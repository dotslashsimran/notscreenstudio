import CoreGraphics
import Foundation
import NSSCore
import NSSProject
@testable import NSSUI

/// Scripted `RecordingSession`.
final class ShellFakeSession: RecordingSession, @unchecked Sendable {
    private let lock = NSLock()
    private var _state: RecordingState = .idle
    private var continuation: AsyncStream<RecordingState>.Continuation?
    private var _startedOptions: RecordingOptions?
    private var _startedBundle: URL?
    var failStart: NSSError?
    var stopDuration: MediaTime = 3
    var hostTime: Double = 42

    var startedOptions: RecordingOptions? { lock.withLock { _startedOptions } }
    var startedBundle: URL? { lock.withLock { _startedBundle } }

    var stateUpdates: AsyncStream<RecordingState> {
        AsyncStream { c in
            lock.withLock { continuation = c; c.yield(_state) }
        }
    }
    var state: RecordingState { get async { lock.withLock { _state } } }

    func set(_ s: RecordingState) { lock.withLock { _state = s; continuation?.yield(s) } }

    func start(options: RecordingOptions, into bundleURL: URL) async throws {
        if let failStart { throw failStart }
        lock.withLock { _startedOptions = options; _startedBundle = bundleURL }
        set(.recording(startedAt: Date()))
    }

    func stop() async throws -> RecordingAssets {
        let camera = startedOptions?.cameraDeviceID != nil
        set(.finished)
        return RecordingAssets(
            cameraFile: camera ? "camera.mov" : nil, sourcePixelSize: PixelSize(width: 2880, height: 1800),
            frameRate: 60, duration: stopDuration, startHostTime: hostTime)
    }
}

final class ShellFakeLogger: InputLogger, @unchecked Sendable {
    private let lock = NSLock()
    private var _started: CaptureSource?
    private var _stopOrigin: Double?
    var startedSource: CaptureSource? { lock.withLock { _started } }
    var stopOrigin: Double? { lock.withLock { _stopOrigin } }
    func start(source: CaptureSource) async throws { lock.withLock { _started = source } }
    func stop(recordingStartHostTime: Double) async -> CursorTrack {
        lock.withLock { _stopOrigin = recordingStartHostTime }
        return CursorTrack(samples: [CursorSample(t: 0, x: 0.5, y: 0.5)])
    }
}

@MainActor
final class ShellFakeEffects: ShellEffects {
    var hudShown = false
    var bubbleShown = false
    var bubbleShape: CameraShape?
    var shortcutRegistered = false
    var bubbleFrameValue: CGRect?
    var shownBubbleFrame: CGRect?
    var areaResult: AreaSelection?
    var primaryScreenHeight: CGFloat = 900
    private var stop: (@MainActor () -> Void)?
    private var discard: (@MainActor () -> Void)?

    func showHUD(startedAt: Date, onStop: @escaping @MainActor () -> Void, onDiscard: @escaping @MainActor () -> Void) {
        hudShown = true; stop = onStop; discard = onDiscard
    }
    func hideHUD() { hudShown = false }
    func showBubble(deviceID: String?, shape: CameraShape, frame: CGRect, sourceRect: CGRect) {
        bubbleShown = true; bubbleShape = shape; shownBubbleFrame = frame
        if bubbleFrameValue == nil { bubbleFrameValue = frame }
    }
    func bubbleFrame() -> CGRect? { bubbleShown ? bubbleFrameValue : nil }
    func updateBubbleShape(_ shape: CameraShape) { bubbleShape = shape }
    func hideBubble() { bubbleShown = false }
    func registerStopShortcut(_ handler: @escaping @MainActor () -> Void) { shortcutRegistered = true }
    func unregisterStopShortcut() { shortcutRegistered = false }
    func selectArea() async -> AreaSelection? { areaResult }
}

@MainActor
struct ShellRig {
    let model: ShellModel
    let session: ShellFakeSession
    let logger: ShellFakeLogger
    let effects: ShellFakeEffects
    let store: FileProjectStore
    let library: URL
    let defaults: UserDefaults
    let suite: String

    static let mainDisplay = DisplayItem(id: 7, name: "Built-in", frame: CGRect(x: 0, y: 0, width: 1440, height: 900), isMain: true)
    static let sideDisplay = DisplayItem(id: 8, name: "Side", frame: CGRect(x: 1440, y: 0, width: 1920, height: 1080), isMain: false)

    init(
        permissions: [PermissionKind: PermissionState] = [.screenRecording: .granted, .camera: .granted, .microphone: .granted],
        mics: [DeviceItem] = [DeviceItem(id: "mic1", name: "Mic", isDefault: true)],
        cams: [DeviceItem] = [DeviceItem(id: "cam1", name: "Cam", isDefault: true)],
        windows: [WindowItem] = [WindowItem(id: 55, title: "Doc", appName: "Notes", frame: CGRect(x: 100, y: 100, width: 800, height: 600))],
        initial: ShellSettings? = nil
    ) {
        suite = "shell-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        library = FileManager.default.temporaryDirectory.appendingPathComponent("shell-tests-\(UUID().uuidString)")
        store = FileProjectStore(libraryURL: library)
        session = ShellFakeSession()
        logger = ShellFakeLogger()
        effects = ShellFakeEffects()
        let settingsStore = ShellSettingsStore(defaults: defaults)
        if let initial { settingsStore.save(initial) }
        model = ShellModel(
            services: ShellServices(
                session: session, inputLogger: logger, store: store,
                sources: StubSourceProvider(
                    listing: SourceListing(displays: [Self.mainDisplay, Self.sideDisplay], windows: windows),
                    mics: mics, cams: cams),
                permissions: StubPermissions(states: permissions)),
            effects: effects, settingsStore: settingsStore)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: library)
        defaults.removePersistentDomain(forName: suite)
    }
}
