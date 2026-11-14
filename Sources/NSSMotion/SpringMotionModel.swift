import Foundation
import NSSCore

/// The real `MotionModel`: spring camera with auto-zoom, spring-smoothed cursor, idle fade and
/// click ripples.
///
/// Determinism: everything stateful (springs, dead zone, idle fade) is simulated ONCE at init with
/// a fixed step (`MotionTuning.simulationRate`, 240 Hz) from the trim start, where all springs
/// start settled, to the trim end. `frameState(at:)` then reads that table: a direct index on the
/// uniform grid plus linear interpolation, O(1), no allocation (except the ripple array when a
/// ripple is visible). Same `t` gives the same `FrameState`, in any order, from any thread, so the
/// preview, scrubbing and export match exactly. Times outside the trim range are clamped to it.
public struct SpringMotionModel: MotionModel {
    public let tuning: MotionTuning
    public let cursorStyle: CursorStyle
    public let sourceAspect: Double
    /// Resolved zoom segments (auto + manual), sorted and non-overlapping. Useful for timeline UI.
    public let zoomSegments: [ZoomSegment]
    /// First and last simulated source time (the trim range).
    public let startTime: MediaTime
    public let endTime: MediaTime

    private let track: CursorTrack
    private let rate: Double
    private let frames: [SimFrame]
    private let rawCursor: Bool
    private let rippleTimes: [MediaTime]
    private let ripplePoints: [NormalizedPoint]

    /// Compact per-step state: 32 bytes. 10 minutes at 240 Hz is ~4.6 MB.
    struct SimFrame {
        var logScale: Float
        var focusX: Float
        var focusY: Float
        var cursorX: Float
        var cursorY: Float
        var cursorVX: Float
        var cursorVY: Float
        var opacity: Float
    }

    /// - Parameters:
    ///   - duration: recording duration; if not positive, derived from the last sample/click.
    ///   - sourceAspect: width / height of the recorded source (e.g. `sourcePixelSize.aspect`).
    public init(
        track: CursorTrack,
        timeline: Timeline,
        cursorStyle: CursorStyle,
        duration: MediaTime,
        sourceAspect: Double = 16.0 / 9.0,
        tuning: MotionTuning = .standard
    ) {
        let samples = track.samples.filter { $0.t.isFinite && $0.x.isFinite && $0.y.isFinite }
        let track = CursorTrack(
            samples: samples.isSorted ? samples : samples.sorted { $0.t < $1.t },
            clicks: track.clicks,
            sampleRate: track.sampleRate
        )
        var duration = duration.isFinite ? duration : 0
        if duration <= 0 {
            duration = max(track.samples.last?.t ?? 0, track.clicks.map(\.t).filter(\.isFinite).max() ?? 0)
        }
        let start = min(max(0, timeline.trim.start.isFinite ? timeline.trim.start : 0), duration)
        let end = max(start, timeline.trim.resolvedEnd(duration: duration))
        let rate = tuning.simulationRate.isFinite && tuning.simulationRate > 0 ? tuning.simulationRate : 240

        self.tuning = tuning
        self.cursorStyle = cursorStyle
        self.sourceAspect = sourceAspect
        self.track = track
        self.rate = rate
        self.startTime = start
        self.endTime = end
        self.rawCursor = tuning.cursorSpring(smoothing: cursorStyle.smoothing) == nil

        let segments = ZoomPlanner.segments(track: track, timeline: timeline, duration: duration, sourceAspect: sourceAspect, tuning: tuning)
        self.zoomSegments = segments

        let downs = track.clicks.filter { $0.kind == .down && $0.t.isFinite }.sorted { $0.t < $1.t }
        self.rippleTimes = downs.map(\.t)
        self.ripplePoints = downs.map(\.point)

        self.frames = Self.simulate(track: track, segments: segments, cursorStyle: cursorStyle, start: start, end: end, rate: rate, tuning: tuning)
    }

    /// Factory with a known source aspect (width / height).
    public static func factory(sourceAspect: Double, tuning: MotionTuning = .standard) -> MotionModelFactory {
        { track, timeline, style, duration in
            SpringMotionModel(track: track, timeline: timeline, cursorStyle: style, duration: duration, sourceAspect: sourceAspect, tuning: tuning)
        }
    }

    /// Factory assuming a 16:9 source. Prefer `factory(sourceAspect:)` when the source size is known.
    public static let factory: MotionModelFactory = SpringMotionModel.factory(sourceAspect: 16.0 / 9.0, tuning: .standard)

    // MARK: Lookup

    public func frameState(at t: MediaTime) -> FrameState {
        let tc = t.isFinite ? min(max(t, startTime), endTime) : startTime
        let u = (tc - startTime) * rate
        var i = Int(u)
        if i >= frames.count - 1 { i = frames.count - 2 }
        if i < 0 { i = 0 }
        let f = Float(min(max(u - Double(i), 0), 1))
        let a = frames[i], b = frames[i + 1]
        @inline(__always) func mix(_ x: Float, _ y: Float) -> Double { Double(x + (y - x) * f) }

        // Camera: interpolated spring state, then clamp the viewport inside the source.
        let scale = max(1, exp(mix(a.logScale, b.logScale)))
        let half = 0.5 / scale
        let center = NormalizedPoint(
            x: min(max(mix(a.focusX, b.focusX), half), 1 - half),
            y: min(max(mix(a.focusY, b.focusY), half), 1 - half)
        )
        let camera = CameraState(scale: scale, center: center)

        // Cursor.
        let hasCursor = !track.samples.isEmpty
        var position = NormalizedPoint(x: mix(a.cursorX, b.cursorX), y: mix(a.cursorY, b.cursorY))
        if rawCursor, let raw = track.rawPosition(at: tc) { position = raw }
        let velocity = NormalizedPoint(x: mix(a.cursorVX, b.cursorVX), y: mix(a.cursorVY, b.cursorVY))
        let opacity = hasCursor ? min(max(mix(a.opacity, b.opacity), 0), 1) : 0
        let cursor = CursorState(
            position: hasCursor ? position : .center,
            velocity: hasCursor ? velocity : .zero,
            visible: hasCursor && opacity > 0,
            ripples: ripples(at: t),
            opacity: opacity
        )
        return FrameState(time: t, camera: camera, cursor: cursor)
    }

    /// Ripples for every mouse-down in (t - rippleDuration, t].
    func ripples(at t: MediaTime) -> [RippleState] {
        guard cursorStyle.clickRipples, !rippleTimes.isEmpty, t.isFinite else { return [] }
        let d = max(tuning.rippleDuration, 1e-6)
        // first click with time > t - d
        var lo = 0, hi = rippleTimes.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if rippleTimes[mid] <= t - d { lo = mid + 1 } else { hi = mid }
        }
        guard lo < rippleTimes.count, rippleTimes[lo] <= t else { return [] }
        var out: [RippleState] = []
        var k = lo
        while k < rippleTimes.count, rippleTimes[k] <= t {
            out.append(RippleState(position: ripplePoints[k], progress: min(max((t - rippleTimes[k]) / d, 0), 1)))
            k += 1
        }
        return out
    }

    // MARK: Simulation

    private static func simulate(
        track: CursorTrack,
        segments: [ZoomSegment],
        cursorStyle: CursorStyle,
        start: MediaTime,
        end: MediaTime,
        rate: Double,
        tuning: MotionTuning
    ) -> [SimFrame] {
        let dt = 1 / rate
        let steps = max(1, Int(((end - start) * rate).rounded(.up)))
        var frames: [SimFrame] = []
        frames.reserveCapacity(steps + 1)

        let zoomStep = tuning.zoomSpring.stepper(dt: dt)
        let panStep = tuning.panSpring.stepper(dt: dt)
        let cursorSpring = tuning.cursorSpring(smoothing: cursorStyle.smoothing)
        let cursorStep = cursorSpring?.stepper(dt: dt)

        var cursor = RawCursor(samples: track.samples)
        var planner = CameraPlanner(segments: segments, tuning: tuning)
        var activity = ActivityTracker(track: track, tuning: tuning, hideWhenIdle: cursorStyle.hideWhenIdle)

        // Settled initial state at the trim start.
        let raw0 = cursor.position(at: start)
        let target0 = planner.target(at: start, cursor: raw0)
        var logScale = log(target0.scale), logScaleV = 0.0
        var fx = target0.focus.x, fxV = 0.0
        var fy = target0.focus.y, fyV = 0.0
        var cx = raw0?.x ?? 0.5, cxV = 0.0
        var cy = raw0?.y ?? 0.5, cyV = 0.0
        var opacity = activity.settledOpacity(at: start)

        func record() {
            frames.append(SimFrame(
                logScale: Float(logScale), focusX: Float(fx), focusY: Float(fy),
                cursorX: Float(cx), cursorY: Float(cy), cursorVX: Float(cxV), cursorVY: Float(cyV),
                opacity: Float(opacity)
            ))
        }
        // Raw-cursor velocity: slope of the raw track (finite difference over one step).
        func rawVelocity(_ p: NormalizedPoint?, _ prev: NormalizedPoint?) -> (Double, Double) {
            guard let p, let prev else { return (0, 0) }
            return ((p.x - prev.x) * rate, (p.y - prev.y) * rate)
        }

        record()
        var prevRaw = raw0
        for k in 1...steps {
            let t = start + Double(k) * dt
            let raw = cursor.position(at: t)
            let target = planner.target(at: t, cursor: raw)
            zoomStep.step(&logScale, &logScaleV, target: log(target.scale))
            panStep.step(&fx, &fxV, target: target.focus.x)
            panStep.step(&fy, &fyV, target: target.focus.y)
            if let raw {
                if let cursorStep {
                    cursorStep.step(&cx, &cxV, target: raw.x)
                    cursorStep.step(&cy, &cyV, target: raw.y)
                } else {
                    (cxV, cyV) = rawVelocity(raw, prevRaw)
                    cx = raw.x
                    cy = raw.y
                }
            }
            opacity = activity.opacity(after: opacity, at: t, dt: dt)
            prevRaw = raw
            record()
        }
        return frames
    }
}

// MARK: - Simulation helpers (sequential cursors over sorted input; used only during the build)

/// Linear interpolation of the raw cursor with a forward-only index (O(1) amortized per step).
struct RawCursor {
    let samples: [CursorSample]
    var i = 0
    init(samples: [CursorSample]) { self.samples = samples }

    mutating func position(at t: MediaTime) -> NormalizedPoint? {
        guard let first = samples.first, let last = samples.last else { return nil }
        if t <= first.t { return first.point }
        if t >= last.t { return last.point }
        while i + 1 < samples.count, samples[i + 1].t <= t { i += 1 }
        let a = samples[i], b = samples[i + 1]
        let span = b.t - a.t
        let f = span > 0 ? (t - a.t) / span : 0
        return NormalizedPoint(x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f)
    }
}

/// Camera target (scale + focus) over time, including the dead-zone follow state.
struct CameraPlanner {
    let segments: [ZoomSegment]
    let tuning: MotionTuning
    var index = 0
    var active: Int? = nil
    var focus = NormalizedPoint.center

    init(segments: [ZoomSegment], tuning: MotionTuning) {
        self.segments = segments
        self.tuning = tuning
    }

    static func clampFocus(_ p: NormalizedPoint, scale: Double) -> NormalizedPoint {
        let h = 0.5 / max(scale, 1)
        return NormalizedPoint(x: min(max(p.x, h), 1 - h), y: min(max(p.y, h), 1 - h))
    }

    mutating func target(at t: MediaTime, cursor: NormalizedPoint?) -> (scale: Double, focus: NormalizedPoint) {
        while index < segments.count, segments[index].end <= t { index += 1 }
        guard index < segments.count else {
            active = nil
            return (1, focus)
        }
        let seg = segments[index]
        guard seg.start <= t else {
            // Between segments: zoomed out; quietly pre-aim the focus at the next segment so the
            // zoom-in heads straight for it (invisible at scale 1, where the center is clamped).
            active = nil
            focus = Self.clampFocus(seg.initialFocus, scale: seg.scale)
            return (1, focus)
        }
        if active != index {
            active = index
            focus = Self.clampFocus(seg.initialFocus, scale: seg.scale)
        }
        if let from = seg.followFrom, t >= from, let p = cursor {
            // Dead zone: pan only when the cursor leaves the central part of the viewport.
            let dz = max(0, tuning.deadZone) * 0.5 / seg.scale
            var f = focus
            if p.x > f.x + dz { f.x = p.x - dz } else if p.x < f.x - dz { f.x = p.x + dz }
            if p.y > f.y + dz { f.y = p.y - dz } else if p.y < f.y - dz { f.y = p.y + dz }
            focus = Self.clampFocus(f, scale: seg.scale)
        }
        return (seg.scale, focus)
    }
}

/// Idle detection and the cursor fade (only when `hideWhenIdle`).
struct ActivityTracker {
    let samples: [CursorSample]
    let clicks: [MediaTime]
    let tuning: MotionTuning
    let enabled: Bool
    var si = 0
    var ci = 0
    var lastActivity: MediaTime = 0

    init(track: CursorTrack, tuning: MotionTuning, hideWhenIdle: Bool) {
        samples = track.samples
        clicks = track.clicks.filter { $0.t.isFinite }.map(\.t).sorted()
        self.tuning = tuning
        enabled = hideWhenIdle
    }

    /// Advance to `t` and return the time of the last movement or click at or before `t`.
    mutating func advance(to t: MediaTime) -> MediaTime {
        while si < samples.count, samples[si].t <= t {
            if si > 0 {
                let a = samples[si - 1], b = samples[si]
                if abs(b.x - a.x) + abs(b.y - a.y) > tuning.activityEpsilon { lastActivity = max(lastActivity, b.t) }
            }
            si += 1
        }
        while ci < clicks.count, clicks[ci] <= t {
            lastActivity = max(lastActivity, clicks[ci])
            ci += 1
        }
        return lastActivity
    }

    private func targetOpacity(at t: MediaTime) -> Double {
        t - lastActivity >= tuning.idleHideDelay ? 0 : 1
    }

    mutating func settledOpacity(at t: MediaTime) -> Double {
        guard enabled else { return 1 }
        _ = advance(to: t)
        return targetOpacity(at: t)
    }

    mutating func opacity(after current: Double, at t: MediaTime, dt: Double) -> Double {
        guard enabled else { return 1 }
        _ = advance(to: t)
        let target = targetOpacity(at: t)
        if target > current {
            return min(target, current + dt / max(tuning.idleFadeInDuration, 1e-6))
        } else {
            return max(target, current - dt / max(tuning.idleFadeOutDuration, 1e-6))
        }
    }
}

extension Array where Element == CursorSample {
    var isSorted: Bool {
        var prev = -Double.infinity
        for s in self {
            if s.t < prev { return false }
            prev = s.t
        }
        return true
    }
}
