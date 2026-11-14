import Foundation

/// Visible part of the recording. `end == nil` means "until the end of the recording".
public struct TrimRange: Codable, Sendable, Equatable {
    public var start: MediaTime
    public var end: MediaTime?
    public init(start: MediaTime = 0, end: MediaTime? = nil) {
        self.start = start
        self.end = end
    }
    public func resolvedEnd(duration: MediaTime) -> MediaTime { min(end ?? duration, duration) }
    public func length(duration: MediaTime) -> MediaTime { max(0, resolvedEnd(duration: duration) - start) }
}

public enum ZoomFocus: Codable, Sendable, Equatable {
    /// Follow the cursor / click targets automatically.
    case auto
    /// Fixed focus point (normalized source space).
    case manual(NormalizedPoint)
}

public struct ZoomBlock: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var start: MediaTime
    public var end: MediaTime
    /// 1 = no zoom, 2 = 2x magnification.
    public var scale: Double
    public var focus: ZoomFocus

    public init(id: UUID = UUID(), start: MediaTime, end: MediaTime, scale: Double = 2, focus: ZoomFocus = .auto) {
        self.id = id
        self.start = start
        self.end = end
        self.scale = scale
        self.focus = focus
    }
    public func contains(_ t: MediaTime) -> Bool { t >= start && t < end }
}

public struct Timeline: Codable, Sendable, Equatable {
    public var trim: TrimRange
    public var zoomBlocks: [ZoomBlock]
    /// When true, the motion model adds auto-zoom blocks derived from clicks, in addition to `zoomBlocks`.
    public var autoZoomEnabled: Bool

    public init(trim: TrimRange = TrimRange(), zoomBlocks: [ZoomBlock] = [], autoZoomEnabled: Bool = true) {
        self.trim = trim
        self.zoomBlocks = zoomBlocks
        self.autoZoomEnabled = autoZoomEnabled
    }
}

// Forward compatibility: fields added after v1 decode with defaults when absent (see PLAN.md).
extension Timeline {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Timeline()
        trim = try c.decodeIfPresent(TrimRange.self, forKey: .trim) ?? d.trim
        zoomBlocks = try c.decodeIfPresent([ZoomBlock].self, forKey: .zoomBlocks) ?? d.zoomBlocks
        autoZoomEnabled = try c.decodeIfPresent(Bool.self, forKey: .autoZoomEnabled) ?? d.autoZoomEnabled
    }
}
