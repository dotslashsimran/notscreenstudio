import AVFoundation
import CoreMedia
import Foundation
import NSSCore
@preconcurrency import ScreenCaptureKit

/// Real `RecordingSession`: screen (SCStream) + optional mic and camera (AVCaptureSession), written
/// into a bundle directory. All files share one time origin: the host-clock PTS of the first screen frame.
public actor ScreenCaptureRecordingSession: RecordingSession {
    private let hub = StateHub()
    private let events = EventHub()

    private var screen: ScreenRecorder?
    private var mic: DeviceRecorder?
    private var camera: DeviceRecorder?
    private var origin = SharedOrigin()
    private var plan: ScreenStreamPlan?
    private var files: CaptureFilePlan?
    private var fatalError: NSSError?
    private var screenEndedEarly = false
    private var bundleURL: URL?
    /// Files created by the current attempt only. Cleanup never touches anything else.
    private var createdFiles: [URL] = []

    public init() {}

    public nonisolated var stateUpdates: AsyncStream<RecordingState> { hub.stream() }
    /// Runtime problems (window closed, device unplugged, disk full).
    public nonisolated var captureEvents: AsyncStream<CaptureEvent> { events.stream() }
    public var state: RecordingState { hub.current }

    public func start(options: RecordingOptions, into bundleURL: URL) async throws {
        switch hub.current {
        case .preparing, .recording, .stopping:
            throw NSSError.unsupported("A recording is already in progress.")
        default: break
        }
        hub.set(.preparing)
        await discardRecorders() // recorders left over from a failed run
        files = nil; plan = nil; self.bundleURL = nil; createdFiles = []
        fatalError = nil
        do {
            try await begin(options: options, bundleURL: bundleURL)
            hub.set(.recording(startedAt: Date()))
        } catch {
            await teardownAfterFailedStart()
            let mapped = CaptureErrorMapper.map(error)
            hub.set(.failed(message: Self.message(mapped)))
            throw mapped
        }
    }

    /// Stops any recorders still held (best effort) without deleting files.
    private func discardRecorders() async {
        let (s, m, c) = (screen, mic, camera)
        screen = nil; mic = nil; camera = nil
        let now = CaptureMath.hostNow()
        if let s { _ = try? await s.stop(endHost: now) }
        if let m { _ = try? await m.stop(endHost: now) }
        if let c { _ = try? await c.stop(endHost: now) }
    }

    private func begin(options: RecordingOptions, bundleURL: URL) async throws {
        try await CapturePermissions.ensure(for: options)
        do {
            try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)
        } catch {
            throw CaptureErrorMapper.map(error, context: .writer)
        }

        self.bundleURL = bundleURL
        origin = SharedOrigin()
        screenEndedEarly = false
        let files = CaptureFilePlan(options: options)
        self.files = files

        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        } catch {
            throw CaptureErrorMapper.map(error)
        }
        let (filter, area, isWindow) = try Self.makeFilter(options.source, content: content)
        let info = SCShareableContent.info(for: filter)
        let plan = try ScreenStreamPlan.make(
            contentPoints: info.contentRect.size, scale: Double(info.pointPixelScale),
            area: area, isWindow: isWindow, systemAudio: options.captureSystemAudio)
        self.plan = plan

        let box = WeakSession(self)
        let report: @Sendable (CaptureEvent.Component, Bool) -> @Sendable (NSSError) -> Void = { component, fatal in
            { error in
                let event = CaptureEvent(component: component, error: error, isFatal: fatal)
                Task { await box.session?.handle(event) }
            }
        }

        // Devices first (they warm up slowly). Their samples are dropped until the origin exists.
        if let id = options.micDeviceID, let name = files.mic {
            createdFiles.append(files.url(name, in: bundleURL))
            let r = try DeviceRecorder(kind: .microphone, deviceID: id, url: files.url(name, in: bundleURL), origin: origin, onFailure: report(.microphone, false))
            try await r.start()
            mic = r
        }
        if let id = options.cameraDeviceID, let name = files.camera {
            createdFiles.append(files.url(name, in: bundleURL))
            let r = try DeviceRecorder(kind: .camera, deviceID: id, url: files.url(name, in: bundleURL), origin: origin, onFailure: report(.camera, false))
            try await r.start()
            camera = r
        }
        createdFiles.append(files.url(files.screen, in: bundleURL))
        let recorder = try ScreenRecorder(
            filter: filter, plan: plan, url: files.url(files.screen, in: bundleURL),
            origin: origin, onFailure: report(.screen, true))
        screen = recorder
        try await recorder.start()

        // Give the first frame a moment so `start` returns with the origin already set.
        for _ in 0..<300 where !recorder.hasFirstFrame {
            try? await Task.sleep(for: .milliseconds(10))
        }
        if !recorder.hasFirstFrame {
            throw NSSError.io("No screen frames arrived. Check that the selected source is visible and try again.")
        }
    }

    private func handle(_ event: CaptureEvent) {
        events.send(event)
        if event.isFatal {
            fatalError = event.error
            screenEndedEarly = true
            if case .recording = hub.current { hub.set(.failed(message: Self.message(event.error))) }
        }
    }

    public func stop() async throws -> RecordingAssets {
        // Serialize against an in-flight start().
        while case .preparing = hub.current { try? await Task.sleep(for: .milliseconds(10)) }
        // Take ownership synchronously (no await before this point) so a second stop() finds nothing.
        guard let screen, let plan, let files else {
            throw NSSError.unsupported("No recording is in progress.")
        }
        let (mic, camera) = (self.mic, self.camera)
        let created = createdFiles
        self.screen = nil; self.mic = nil; self.camera = nil
        hub.set(.stopping)
        let stopHost = CaptureMath.hostNow()

        var screenResult: ScreenResult?
        var screenError: Error?
        do { screenResult = try await screen.stop(endHost: stopHost) } catch { screenError = error }

        var micHas = false, camHas = false
        if let mic { micHas = (try? await mic.stop(endHost: stopHost)) ?? false }
        if let camera { camHas = (try? await camera.stop(endHost: stopHost)) ?? false }
        // A broken mic/camera file never costs the screen recording.

        guard let result = screenResult, result.frames > 0, let o = origin.current else {
            let err = fatalError ?? screenError.map { CaptureErrorMapper.map($0, context: .writer) }
                ?? NSSError.io("No screen frames were captured.")
            for u in created { try? FileManager.default.removeItem(at: u) }
            hub.set(.failed(message: Self.message(err)))
            throw err
        }
        let assets = RecordingAssets(
            screenFile: files.screen,
            cameraFile: camHas ? files.camera : nil,
            micFile: micHas ? files.mic : nil,
            sourcePixelSize: plan.pixelSize,
            frameRate: Double(plan.frameRate),
            duration: o.duration(endingAt: result.endHost),
            startHostTime: o.hostTime)
        if !micHas, let f = files.mic, let d = bundleURL { try? FileManager.default.removeItem(at: files.url(f, in: d)) }
        if !camHas, let f = files.camera, let d = bundleURL { try? FileManager.default.removeItem(at: files.url(f, in: d)) }
        hub.set(.finished)
        return assets
    }

    private func teardownAfterFailedStart() async {
        await discardRecorders()
        for u in createdFiles { try? FileManager.default.removeItem(at: u) }
        createdFiles = []
    }

    static func message(_ e: NSSError) -> String {
        switch e {
        case .notImplemented(let m), .unsupported(let m), .permissionDenied(let m),
             .invalidProject(let m), .renderFailed(let m), .io(let m): return m
        }
    }

    /// Builds the content filter. Excludes this app's own windows (camera bubble, HUD) from display and area captures.
    static func makeFilter(_ source: CaptureSource, content: SCShareableContent) throws -> (SCContentFilter, CGRect?, Bool) {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let ownBundle = Bundle.main.bundleIdentifier
        let own = content.applications.filter {
            CaptureMath.isOwnApp(pid: $0.processID, bundleID: $0.bundleIdentifier, ownPID: ownPID, ownBundleID: ownBundle)
        }
        switch source {
        case .display(let id):
            guard let d = content.displays.first(where: { $0.displayID == id }) else {
                throw NSSError.unsupported("The selected display is no longer available.")
            }
            return (SCContentFilter(display: d, excludingApplications: own, exceptingWindows: []), nil, false)
        case .area(let id, let rect):
            guard let d = content.displays.first(where: { $0.displayID == id }) else {
                throw NSSError.unsupported("The selected display is no longer available.")
            }
            return (SCContentFilter(display: d, excludingApplications: own, exceptingWindows: []), rect, false)
        case .window(let id):
            guard let w = content.windows.first(where: { $0.windowID == id }) else {
                throw NSSError.io("The selected window was closed.")
            }
            return (SCContentFilter(desktopIndependentWindow: w), nil, true)
        }
    }
}

final class WeakSession: @unchecked Sendable {
    weak var session: ScreenCaptureRecordingSession?
    init(_ s: ScreenCaptureRecordingSession) { session = s }
}
