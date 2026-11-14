import AVFoundation
import CoreMedia
import Foundation
import NSSCore
@preconcurrency import ScreenCaptureKit

/// Everything needed to build the stream, computed without touching hardware.
struct ScreenStreamPlan: Sendable, Equatable {
    var pixelSize: PixelSize
    var sourceRect: CGRect?
    var frameRate: Int
    var capturesSystemAudio: Bool
    var isWindow: Bool

    var bitrate: Int { CaptureMath.videoBitrate(width: pixelSize.width, height: pixelSize.height, frameRate: Double(frameRate)) }

    static func make(contentPoints: CGSize, scale: Double, area: CGRect?, isWindow: Bool, systemAudio: Bool) throws -> ScreenStreamPlan {
        var rect: CGRect?
        var points = contentPoints
        if let area {
            guard let clamped = CaptureMath.clampedArea(area, displaySize: contentPoints) else {
                throw NSSError.unsupported("The selected area is outside the display.")
            }
            rect = clamped
            points = clamped.size
        }
        return ScreenStreamPlan(
            pixelSize: CaptureMath.pixelSize(points: points, scale: scale),
            sourceRect: rect, frameRate: CaptureMath.frameRate,
            capturesSystemAudio: systemAudio, isWindow: isWindow)
    }

    func configuration() -> SCStreamConfiguration {
        let c = SCStreamConfiguration()
        c.width = pixelSize.width
        c.height = pixelSize.height
        c.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(frameRate))
        c.queueDepth = 8
        c.showsCursor = false // the app renders its own smooth cursor
        c.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        c.colorSpaceName = CGColorSpace.sRGB
        c.captureResolution = .best
        c.scalesToFit = false
        if let sourceRect { c.sourceRect = sourceRect }
        if isWindow { c.ignoreShadowsSingleWindow = true }
        if capturesSystemAudio {
            c.capturesAudio = true
            c.sampleRate = 48_000
            c.channelCount = 2
            c.excludesCurrentProcessAudio = true
        }
        return c
    }

    func videoSettings(codec: AVVideoCodecType) -> [String: Any] {
        var compression: [String: Any] = [
            AVVideoAverageBitRateKey: bitrate,
            AVVideoExpectedSourceFrameRateKey: frameRate,
            AVVideoMaxKeyFrameIntervalKey: frameRate * 2,
            AVVideoAllowFrameReorderingKey: false,
        ]
        if codec == .h264 { compression[AVVideoProfileLevelKey] = AVVideoProfileLevelH264HighAutoLevel }
        return [
            AVVideoCodecKey: codec,
            AVVideoWidthKey: pixelSize.width,
            AVVideoHeightKey: pixelSize.height,
            AVVideoCompressionPropertiesKey: compression,
        ]
    }

    static var systemAudioSettings: [String: Any] { [
        AVFormatIDKey: kAudioFormatMPEG4AAC,
        AVSampleRateKey: 48_000,
        AVNumberOfChannelsKey: 2,
        AVEncoderBitRateKey: 160_000,
    ] }
}

struct ScreenResult: Sendable {
    var frames: Int
    /// Host time at which video stopped (stream end, or `stop` time).
    var endHost: Double
}

/// SCStream -> screen.mov. The first complete frame defines the shared origin.
final class ScreenRecorder: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let filter: SCContentFilter
    private var stream: SCStream?
    private let plan: ScreenStreamPlan
    private let writer: SampleFileWriter
    private let origin: SharedOrigin
    private let onFailure: @Sendable (NSSError) -> Void
    private let videoQueue = DispatchQueue(label: "nss.capture.screen.video", qos: .userInteractive)
    private let audioQueue = DispatchQueue(label: "nss.capture.screen.audio", qos: .userInitiated)
    private let lock = NSLock()
    private var stopping = false
    private var endedHost: Double?

    init(filter: SCContentFilter, plan: ScreenStreamPlan, url: URL, origin: SharedOrigin,
         onFailure: @escaping @Sendable (NSSError) -> Void) throws {
        self.filter = filter
        self.plan = plan
        self.origin = origin
        self.onFailure = onFailure
        self.writer = try SampleFileWriter(url: url, fileType: .mov, context: .writer, onFailure: onFailure)

        // Hardware HEVC when the writer accepts it, H.264 otherwise.
        do {
            try writer.addInput("video", mediaType: .video, settings: plan.videoSettings(codec: .hevc))
        } catch {
            try writer.addInput("video", mediaType: .video, settings: plan.videoSettings(codec: .h264))
        }
        if plan.capturesSystemAudio {
            try writer.addInput("audio", mediaType: .audio, settings: ScreenStreamPlan.systemAudioSettings)
        }
        super.init()
    }

    func start() async throws {
        let stream = SCStream(filter: filter, configuration: plan.configuration(), delegate: self)
        lock.withLock { self.stream = stream }
        do {
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: videoQueue)
            if plan.capturesSystemAudio {
                try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: audioQueue)
            }
            try await stream.startCapture()
        } catch {
            throw CaptureErrorMapper.map(error, context: plan.isWindow ? .window : .screen)
        }
    }

    var hasFirstFrame: Bool { writer.isStarted }

    func stop(endHost: Double) async throws -> ScreenResult {
        let already: Double? = lock.withLock {
            stopping = true
            return endedHost
        }
        if already == nil, let stream = lock.withLock({ self.stream }) { try? await stream.stopCapture() }
        let end = already ?? endHost
        let hadMedia = try await writer.finish(endHost: end)
        return ScreenResult(frames: hadMedia ? writer.sampleCount : 0, endHost: end)
    }

    // MARK: SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard sampleBuffer.isValid else { return }
        switch type {
        case .screen:
            guard Self.isCompleteFrame(sampleBuffer) else { return }
            let pts = sampleBuffer.presentationTimeStamp.seconds
            if origin.setIfUnset(pts) {
                do { try writer.start(atOrigin: pts) } catch { onFailure(CaptureErrorMapper.map(error, context: .writer)); return }
            }
            guard let o = origin.current, pts >= o.hostTime else { return }
            writer.append(sampleBuffer, to: "video")
        case .audio:
            guard let o = origin.current, writer.isStarted else { return }
            let start = sampleBuffer.presentationTimeStamp.seconds
            if o.isEntirelyBefore(start: start, duration: sampleBuffer.duration.validOrZero.seconds) { return }
            writer.append(sampleBuffer, to: "audio")
        default:
            break
        }
    }

    static func isCompleteFrame(_ sb: CMSampleBuffer) -> Bool {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int,
              SCFrameStatus(rawValue: raw) == .complete
        else { return false }
        return sb.imageBuffer != nil
    }

    // MARK: SCStreamDelegate

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        let first: Bool = lock.withLock {
            if stopping || endedHost != nil { return false }
            endedHost = CaptureMath.hostNow()
            return true
        }
        if first { onFailure(CaptureErrorMapper.map(error, context: plan.isWindow ? .window : .screen)) }
    }
}
