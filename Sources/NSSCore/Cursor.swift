import Foundation

/// One cursor position. `x`,`y` normalized 0...1, origin top-left (may fall slightly outside for area/window capture).
public struct CursorSample: Codable, Sendable, Equatable {
    public var t: MediaTime
    public var x: Double
    public var y: Double
    public init(t: MediaTime, x: Double, y: Double) {
        self.t = t
        self.x = x
        self.y = y
    }
    public var point: NormalizedPoint { NormalizedPoint(x: x, y: y) }
}

public enum MouseButton: String, Codable, Sendable, Equatable {
    case left, right, other
}

public enum ClickKind: String, Codable, Sendable, Equatable {
    case down, up
}

public struct ClickEvent: Codable, Sendable, Equatable {
    public var t: MediaTime
    public var x: Double
    public var y: Double
    public var button: MouseButton
    public var kind: ClickKind
    public init(t: MediaTime, x: Double, y: Double, button: MouseButton = .left, kind: ClickKind) {
        self.t = t
        self.x = x
        self.y = y
        self.button = button
        self.kind = kind
    }
    public var point: NormalizedPoint { NormalizedPoint(x: x, y: y) }
}

/// Logged input for a recording. Persisted as `cursor.json`.
/// Samples are sorted by `t`, nominally `sampleRate` Hz.
public struct CursorTrack: Codable, Sendable, Equatable {
    public var samples: [CursorSample]
    public var clicks: [ClickEvent]
    public var sampleRate: Double

    public init(samples: [CursorSample] = [], clicks: [ClickEvent] = [], sampleRate: Double = 120) {
        self.samples = samples
        self.clicks = clicks
        self.sampleRate = sampleRate
    }

    public static let empty = CursorTrack()

    /// Linear interpolation of the raw cursor position at `t` (clamped to first/last sample). nil if no samples.
    public func rawPosition(at t: MediaTime) -> NormalizedPoint? {
        guard let first = samples.first, let last = samples.last else { return nil }
        if t <= first.t { return first.point }
        if t >= last.t { return last.point }
        // binary search for the last sample with time <= t
        var lo = 0
        var hi = samples.count - 1
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if samples[mid].t <= t { lo = mid } else { hi = mid }
        }
        let a = samples[lo], b = samples[hi]
        let span = b.t - a.t
        let f = span > 0 ? (t - a.t) / span : 0
        return NormalizedPoint(x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f)
    }
}
