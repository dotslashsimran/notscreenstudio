import AVFoundation
import CoreMedia
import CoreVideo
import NSSCore

/// Real-time `FrameSource` for the preview: wraps an `AVPlayer` + `AVPlayerItemVideoOutput` for one video file.
/// Frame selection is "at or before `t`" (what `AVPlayerItemVideoOutput` returns for an item time).
/// Main-actor only: AVFoundation objects are driven from the preview's display link.
@MainActor
public final class PlayerVideoTrack {
    public let player: AVPlayer
    public let output: AVPlayerItemVideoOutput
    public private(set) var lastFrame: CVPixelBuffer?

    public init(url: URL, muted: Bool) {
        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
            kCVPixelBufferMetalCompatibilityKey as String: true,
        ]
        output = AVPlayerItemVideoOutput(pixelBufferAttributes: attrs)
        output.suppressesPlayerRendering = true
        let item = AVPlayerItem(url: url)
        item.add(output)
        player = AVPlayer(playerItem: item)
        player.isMuted = muted
        player.automaticallyWaitsToMinimizeStalling = false
        player.actionAtItemEnd = .pause
    }

    /// Newest frame at or before `time`. Returns true when a new buffer arrived since the last call.
    @discardableResult
    public func pull(at time: MediaTime) -> Bool {
        let t = CMTime(seconds: max(time, 0), preferredTimescale: 600)
        guard output.hasNewPixelBuffer(forItemTime: t),
              let pb = output.copyPixelBuffer(forItemTime: t, itemTimeForDisplay: nil) else { return false }
        lastFrame = pb
        return true
    }
}

/// Async `FrameSource` adapter over live players (the contract shape; the preview itself uses the sync path).
public final class PlayerFrameSource: FrameSource, @unchecked Sendable {
    private let screen: PlayerVideoTrack
    private let camera: PlayerVideoTrack?

    @MainActor public init(screen: PlayerVideoTrack, camera: PlayerVideoTrack?) {
        self.screen = screen
        self.camera = camera
    }

    public func screenFrame(at t: MediaTime) async -> CVPixelBuffer? {
        let box = await MainActor.run { _ = screen.pull(at: t); return Unchecked(value: screen.lastFrame) }
        return box.value
    }

    public func cameraFrame(at t: MediaTime) async -> CVPixelBuffer? {
        let box = await MainActor.run { _ = camera?.pull(at: t); return Unchecked(value: camera?.lastFrame) }
        return box.value
    }
}
