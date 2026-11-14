import NSSCore

/// STUB (Motion worker replaces): identity camera, raw interpolated cursor, no ripples.
public struct LinearMotionModel: MotionModel {
    public let track: CursorTrack
    public let timeline: Timeline
    public let cursorStyle: CursorStyle

    public init(track: CursorTrack, timeline: Timeline, cursorStyle: CursorStyle) {
        self.track = track
        self.timeline = timeline
        self.cursorStyle = cursorStyle
    }

    public func frameState(at t: MediaTime) -> FrameState {
        let p = track.rawPosition(at: t)
        let cursor = CursorState(position: p ?? .center, velocity: .zero, visible: p != nil, ripples: [])
        return FrameState(time: t, camera: .identity, cursor: cursor)
    }

    public static let factory: MotionModelFactory = { track, timeline, style, _ in
        LinearMotionModel(track: track, timeline: timeline, cursorStyle: style)
    }
}
