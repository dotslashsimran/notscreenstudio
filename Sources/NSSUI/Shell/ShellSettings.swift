import CoreGraphics
import Foundation
import NSSCore

/// Everything the shell remembers between launches. Persisted as JSON in `UserDefaults`.
/// Decodes with defaults for every field, so adding a field never invalidates old preferences.
public struct ShellSettings: Codable, Sendable, Equatable {
    /// Last-used source. nil means the main display (the default, and the fallback when a window is gone).
    public var source: CaptureSource?
    public var micEnabled: Bool
    /// nil = the system default microphone.
    public var micDeviceID: String?
    public var cameraEnabled: Bool
    /// nil = the system default camera.
    public var cameraDeviceID: String?
    public var cameraShape: CameraShape
    /// Bubble width as a fraction of the capture source's width.
    public var bubbleSize: Double
    /// Bubble center, normalized to the capture source (0...1, origin top-left).
    public var bubbleCenter: NormalizedPoint

    public static let defaultBubbleSize = 0.18
    public static let defaultBubbleCenter = NormalizedPoint(x: 0.88, y: 0.80)

    public init(
        source: CaptureSource? = nil,
        micEnabled: Bool = false,
        micDeviceID: String? = nil,
        cameraEnabled: Bool = false,
        cameraDeviceID: String? = nil,
        cameraShape: CameraShape = .circle,
        bubbleSize: Double = ShellSettings.defaultBubbleSize,
        bubbleCenter: NormalizedPoint = ShellSettings.defaultBubbleCenter
    ) {
        self.source = source
        self.micEnabled = micEnabled
        self.micDeviceID = micDeviceID
        self.cameraEnabled = cameraEnabled
        self.cameraDeviceID = cameraDeviceID
        self.cameraShape = cameraShape
        self.bubbleSize = bubbleSize
        self.bubbleCenter = bubbleCenter
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        source = try c.decodeIfPresent(CaptureSource.self, forKey: .source)
        micEnabled = try c.decodeIfPresent(Bool.self, forKey: .micEnabled) ?? false
        micDeviceID = try c.decodeIfPresent(String.self, forKey: .micDeviceID)
        cameraEnabled = try c.decodeIfPresent(Bool.self, forKey: .cameraEnabled) ?? false
        cameraDeviceID = try c.decodeIfPresent(String.self, forKey: .cameraDeviceID)
        cameraShape = try c.decodeIfPresent(CameraShape.self, forKey: .cameraShape) ?? .circle
        bubbleSize = try c.decodeIfPresent(Double.self, forKey: .bubbleSize) ?? Self.defaultBubbleSize
        bubbleCenter = try c.decodeIfPresent(NormalizedPoint.self, forKey: .bubbleCenter) ?? Self.defaultBubbleCenter
    }
}

/// Reads and writes `ShellSettings` in a `UserDefaults` suite. Not shared across threads: use from the main actor.
public struct ShellSettingsStore {
    public static let key = "notscreenstudio.shell.settings.v1"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public func load() -> ShellSettings {
        guard let data = defaults.data(forKey: Self.key),
              let settings = try? JSONDecoder().decode(ShellSettings.self, from: data)
        else { return ShellSettings() }
        return settings
    }

    public func save(_ settings: ShellSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
