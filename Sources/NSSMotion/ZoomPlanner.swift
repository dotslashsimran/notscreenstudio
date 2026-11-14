import Foundation
import NSSCore

/// One resolved zoom interval: an auto-zoom cluster or a manual `ZoomBlock`, after overlap resolution.
/// Segments returned by `ZoomPlanner.segments` are sorted and never overlap.
public struct ZoomSegment: Sendable, Equatable {
    public enum Origin: Sendable, Equatable {
        case auto
        case manual(UUID)
    }

    public var start: MediaTime
    public var end: MediaTime
    /// Target magnification (already clamped to 1...maxZoomScale).
    public var scale: Double
    /// Focus at the start of the segment (the first click for auto segments).
    public var initialFocus: NormalizedPoint
    /// When non-nil, the focus follows the cursor (with a dead zone) from this time on.
    /// nil = fixed focus (`ZoomFocus.manual`).
    public var followFrom: MediaTime?
    public var origin: Origin

    public init(start: MediaTime, end: MediaTime, scale: Double, initialFocus: NormalizedPoint, followFrom: MediaTime?, origin: Origin) {
        self.start = start
        self.end = end
        self.scale = scale
        self.initialFocus = initialFocus
        self.followFrom = followFrom
        self.origin = origin
    }

    public func contains(_ t: MediaTime) -> Bool { t >= start && t < end }
}

/// Turns clicks and manual `ZoomBlock`s into non-overlapping `ZoomSegment`s.
public enum ZoomPlanner {
    /// - Parameters:
    ///   - sourceAspect: width / height of the recorded source, so click distances are isotropic.
    public static func segments(
        track: CursorTrack,
        timeline: Timeline,
        duration: MediaTime,
        sourceAspect: Double,
        tuning: MotionTuning = .standard
    ) -> [ZoomSegment] {
        let manual = manualSegments(track: track, blocks: timeline.zoomBlocks, duration: duration, tuning: tuning)
        guard timeline.autoZoomEnabled else { return manual }
        let auto = autoSegments(track: track, duration: duration, sourceAspect: sourceAspect, tuning: tuning)
        var result = manual
        for seg in auto {
            result.append(contentsOf: subtract(manual, from: seg, track: track, tuning: tuning))
        }
        result.sort { $0.start < $1.start }
        return result
    }

    // MARK: Auto

    static func autoSegments(track: CursorTrack, duration: MediaTime, sourceAspect: Double, tuning: MotionTuning) -> [ZoomSegment] {
        let downs = track.clicks
            .filter { $0.kind == .down && $0.t.isFinite && $0.t >= 0 && $0.t <= duration }
            .sorted { $0.t < $1.t }
        guard !downs.isEmpty else { return [] }
        let aspect = sourceAspect.isFinite && sourceAspect > 0 ? sourceAspect : 16.0 / 9.0

        // 1. Cluster clicks in time and space.
        var clusters: [[ClickEvent]] = []
        for c in downs {
            if let last = clusters.last?.last {
                let dt = c.t - last.t
                let dx = (c.x - last.x) * aspect, dy = c.y - last.y
                let dist = (dx * dx + dy * dy).squareRoot()
                let joins = dt <= tuning.clusterMaxGap && (dist <= tuning.clusterMaxDistance || dt <= tuning.clusterPanGap)
                if joins {
                    clusters[clusters.count - 1].append(c)
                    continue
                }
            }
            clusters.append([c])
        }

        // 2. Each cluster -> interval: lead-in before the first click, hold while activity continues.
        var segs: [ZoomSegment] = []
        for cluster in clusters {
            let first = cluster[0], last = cluster[cluster.count - 1]
            let end = holdEnd(after: last.t, track: track, tuning: tuning)
            segs.append(ZoomSegment(
                start: first.t - tuning.autoZoomLeadIn,
                end: end,
                scale: clampScale(tuning.autoZoomScale, tuning),
                initialFocus: first.point.clamped,
                followFrom: first.t,
                origin: .auto
            ))
        }

        // 3. Merge segments whose gap is too short to zoom out and back in.
        var merged: [ZoomSegment] = []
        for s in segs {
            if var prev = merged.last, s.start - prev.end < tuning.minZoomOutGap {
                prev.end = max(prev.end, s.end)
                merged[merged.count - 1] = prev
            } else {
                merged.append(s)
            }
        }

        // 4. Clamp to the recording.
        return merged.compactMap { s in
            var s = s
            s.start = max(0, s.start)
            s.end = min(duration, s.end)
            return s.end - s.start >= tuning.minSegmentDuration ? s : nil
        }
    }

    /// End of the hold after the last click at `t0`: `autoZoomHold` after the cursor last moved,
    /// capped at `t0 + autoZoomMaxHold`.
    static func holdEnd(after t0: MediaTime, track: CursorTrack, tuning: MotionTuning) -> MediaTime {
        let cap = t0 + max(tuning.autoZoomMaxHold, tuning.autoZoomHold)
        var lastMove = t0
        let samples = track.samples
        var i = firstIndex(in: samples, after: t0)
        if i > 0 { i -= 1 }
        var prev: CursorSample? = nil
        while i < samples.count {
            let s = samples[i]
            if s.t > cap || s.t - lastMove > tuning.autoZoomHold { break }
            if let p = prev, s.t > t0, abs(s.x - p.x) + abs(s.y - p.y) > tuning.activityEpsilon {
                lastMove = s.t
            }
            prev = s
            i += 1
        }
        return min(lastMove + tuning.autoZoomHold, cap)
    }

    // MARK: Manual

    static func manualSegments(track: CursorTrack, blocks: [ZoomBlock], duration: MediaTime, tuning: MotionTuning) -> [ZoomSegment] {
        let sorted = blocks
            .filter { $0.start.isFinite && $0.end.isFinite && $0.end > $0.start }
            .sorted { $0.start < $1.start }
        var segs: [ZoomSegment] = []
        for b in sorted {
            let start = max(0, b.start)
            let end = duration > 0 ? min(b.end, duration) : b.end
            guard end > start else { continue }
            // A later-starting block takes over where blocks overlap.
            if var prev = segs.last, prev.end > start {
                prev.end = start
                if prev.end > prev.start { segs[segs.count - 1] = prev } else { segs.removeLast() }
            }
            switch b.focus {
            case .manual(let p):
                segs.append(ZoomSegment(start: start, end: end, scale: clampScale(b.scale, tuning), initialFocus: p.clamped, followFrom: nil, origin: .manual(b.id)))
            case .auto:
                let p = track.rawPosition(at: start)?.clamped ?? .center
                segs.append(ZoomSegment(start: start, end: end, scale: clampScale(b.scale, tuning), initialFocus: p, followFrom: start, origin: .manual(b.id)))
            }
        }
        return segs
    }

    /// Cut every manual interval out of an auto segment; manual blocks win where they overlap.
    static func subtract(_ manual: [ZoomSegment], from seg: ZoomSegment, track: CursorTrack, tuning: MotionTuning) -> [ZoomSegment] {
        var pieces = [seg]
        for m in manual where m.end > seg.start && m.start < seg.end {
            var next: [ZoomSegment] = []
            for p in pieces {
                if m.end <= p.start || m.start >= p.end { next.append(p); continue }
                if m.start > p.start {
                    var a = p
                    a.end = m.start
                    next.append(a)
                }
                if m.end < p.end {
                    var b = p
                    b.start = m.end
                    if let f = b.followFrom, b.start > f {
                        b.initialFocus = track.rawPosition(at: b.start)?.clamped ?? b.initialFocus
                    }
                    next.append(b)
                }
            }
            pieces = next
        }
        return pieces.filter { $0.end - $0.start >= tuning.minSegmentDuration }
    }

    // MARK: Helpers

    static func clampScale(_ s: Double, _ tuning: MotionTuning) -> Double {
        guard s.isFinite else { return 1 }
        return min(max(s, 1), max(1, tuning.maxZoomScale))
    }

    /// Index of the first sample with `t > time` (samples.count if none).
    static func firstIndex(in samples: [CursorSample], after time: MediaTime) -> Int {
        var lo = 0, hi = samples.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if samples[mid].t <= time { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }
}
