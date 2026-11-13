import Foundation

/// A `.nssproj` bundle's `project.json`.
public struct Project: Codable, Sendable, Equatable, Identifiable {
    public static let currentSchemaVersion = 1

    public var id: UUID
    public var name: String
    public var createdAt: Date
    public var modifiedAt: Date
    public var assets: RecordingAssets
    public var timeline: Timeline
    public var style: Style
    public var schemaVersion: Int

    public init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        modifiedAt: Date = Date(),
        assets: RecordingAssets,
        timeline: Timeline = Timeline(),
        style: Style = Style(),
        schemaVersion: Int = Project.currentSchemaVersion
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.assets = assets
        self.timeline = timeline
        self.style = style
        self.schemaVersion = schemaVersion
    }
}

/// Reference to a project bundle on disk (a `.nssproj` directory).
public struct ProjectReference: Sendable, Equatable, Hashable {
    public var url: URL
    public init(url: URL) { self.url = url }
    public static let fileExtension = "nssproj"
    public static let projectFileName = "project.json"
}

public enum ExportResolution: String, Codable, Sendable, Equatable, CaseIterable {
    case p1080, p2160
    /// Shorter side in pixels (1080 or 2160).
    public var shortSide: Int { self == .p1080 ? 1080 : 2160 }
}

public enum VideoCodec: String, Codable, Sendable, Equatable, CaseIterable {
    case h264, hevc
}

public struct ExportPreset: Codable, Sendable, Equatable {
    public var resolution: ExportResolution
    public var fps: Int
    public var codec: VideoCodec
    public init(resolution: ExportResolution = .p1080, fps: Int = 60, codec: VideoCodec = .h264) {
        self.resolution = resolution
        self.fps = fps
        self.codec = codec
    }
    public func outputSize(for aspect: AspectRatio) -> PixelSize { aspect.outputSize(for: resolution) }
}

public enum ExportProgress: Sendable, Equatable {
    case idle
    case running(fraction: Double, framesWritten: Int, totalFrames: Int)
    case finished(URL)
    case failed(message: String)
    case cancelled
}
