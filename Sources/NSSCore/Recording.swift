import CoreGraphics
import Foundation

/// What to record.
public enum CaptureSource: Codable, Sendable, Equatable, Hashable {
    /// A whole display (CGDirectDisplayID).
    case display(id: UInt32)
    /// A single window (CGWindowID).
    case window(id: UInt32)
    /// A rectangle on a display. `rect` is in that display's points, origin top-left.
    case area(displayID: UInt32, rect: CGRect)
}

public struct RecordingOptions: Codable, Sendable, Equatable {
    public var source: CaptureSource
    /// AVCaptureDevice uniqueID of the microphone, nil = no mic.
    public var micDeviceID: String?
    /// AVCaptureDevice uniqueID of the camera, nil = no camera.
    public var cameraDeviceID: String?
    public var captureSystemAudio: Bool

    public init(
        source: CaptureSource,
        micDeviceID: String? = nil,
        cameraDeviceID: String? = nil,
        captureSystemAudio: Bool = false
    ) {
        self.source = source
        self.micDeviceID = micDeviceID
        self.cameraDeviceID = cameraDeviceID
        self.captureSystemAudio = captureSystemAudio
    }
}

/// Files inside a `.nssproj` bundle. Names are relative to the bundle root.
public struct RecordingAssets: Codable, Sendable, Equatable {
    public var screenFile: String
    public var cameraFile: String?
    public var micFile: String?
    public var cursorFile: String
    /// Pixel size of the recorded screen video.
    public var sourcePixelSize: PixelSize
    /// Frame rate of the screen video.
    public var frameRate: Double
    /// Duration in seconds of the recording.
    public var duration: MediaTime
    /// Shared time origin (t = 0) of the recording: the host-clock time, in seconds on the
    /// `CACurrentMediaTime()` / `CMClockGetHostTimeClock()` clock, of the presentation timestamp
    /// of the FIRST screen frame written to `screenFile`. `RecordingSession.stop()` fills it.
    /// Cursor/click timestamps are rebased to this origin by `InputLogger.stop(recordingStartHostTime:)`.
    public var startHostTime: Double

    public static let defaultScreenFile = "screen.mov"
    public static let defaultCameraFile = "camera.mov"
    public static let defaultMicFile = "mic.m4a"
    public static let defaultCursorFile = "cursor.json"

    public init(
        screenFile: String = RecordingAssets.defaultScreenFile,
        cameraFile: String? = nil,
        micFile: String? = nil,
        cursorFile: String = RecordingAssets.defaultCursorFile,
        sourcePixelSize: PixelSize,
        frameRate: Double,
        duration: MediaTime,
        startHostTime: Double = 0
    ) {
        self.screenFile = screenFile
        self.cameraFile = cameraFile
        self.micFile = micFile
        self.cursorFile = cursorFile
        self.sourcePixelSize = sourcePixelSize
        self.frameRate = frameRate
        self.duration = duration
        self.startHostTime = startHostTime
    }
}

public enum RecordingState: Codable, Sendable, Equatable {
    case idle
    case preparing
    case recording(startedAt: Date)
    case stopping
    case finished
    case failed(message: String)
}
