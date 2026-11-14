import CoreGraphics
import Foundation
import Observation
import NSSCore

/// The modules the shell talks to, all through NSSCore protocols so any can be swapped for the real one.
public struct ShellServices: Sendable {
    public var session: any RecordingSession
    public var inputLogger: any InputLogger
    public var store: any ProjectStore
    public var sources: any CaptureSourceProviding
    public var permissions: any PermissionsProviding

    public init(
        session: any RecordingSession,
        inputLogger: any InputLogger,
        store: any ProjectStore,
        sources: any CaptureSourceProviding,
        permissions: any PermissionsProviding
    ) {
        self.session = session
        self.inputLogger = inputLogger
        self.store = store
        self.sources = sources
        self.permissions = permissions
    }
}

/// A recording that was just saved, ready for the editor.
public struct SavedRecording: Sendable, Equatable {
    public var reference: ProjectReference
    public var project: Project
    public var cursorTrack: CursorTrack
}

/// View model for the whole shell: settings, the idle → recording → saving → editing cycle, sources and permissions.
@MainActor
@Observable
public final class ShellModel {
    // MARK: Observable state
    public private(set) var phase: ShellPhase = .idle
    public private(set) var settings: ShellSettings
    public private(set) var listing = SourceListing()
    public private(set) var microphones: [DeviceItem] = []
    public private(set) var cameras: [DeviceItem] = []
    public private(set) var permissionStates: [PermissionKind: PermissionState] = [:]
    /// Set when the source list could not be loaded (usually missing screen recording permission).
    public private(set) var sourceError: String?
    /// A non-fatal remark about the last start, for example "Camera skipped: permission denied".
    public private(set) var notice: String?
    public private(set) var lastSaved: SavedRecording?
    /// Increments each time the editor should open. Views watch it and call `openWindow`.
    public private(set) var editorRequestID = 0
    /// Increments each time the permissions window should open.
    public private(set) var onboardingRequestID = 0

    // MARK: Dependencies
    @ObservationIgnored private let services: ShellServices
    @ObservationIgnored private let effects: any ShellEffects
    @ObservationIgnored private let settingsStore: ShellSettingsStore
    @ObservationIgnored private let now: @MainActor () -> Date
    @ObservationIgnored private var active: ActiveRecording?
    @ObservationIgnored private var watchTask: Task<Void, Never>?
    @ObservationIgnored private var discarding = false

    struct ActiveRecording {
        var reference: ProjectReference
        var source: CaptureSource
        var sourceRect: CGRect?
        var cameraDeviceID: String?
        /// Chosen once at start, so the bundle name, recents entry and project name always agree.
        var name: String
    }

    public init(
        services: ShellServices,
        effects: any ShellEffects,
        settingsStore: ShellSettingsStore = ShellSettingsStore(),
        now: @escaping @MainActor () -> Date = { Date() }
    ) {
        self.services = services
        self.effects = effects
        self.settingsStore = settingsStore
        self.now = now
        self.settings = settingsStore.load()
    }

    // MARK: Derived

    public var isRecording: Bool { phase.isRecording }
    public var canStart: Bool { phase.canStart && !discarding }

    public var missingRequiredPermissions: [PermissionKind] {
        PermissionKind.allCases.filter { PermissionInfo.isRequired($0) && permissionStates[$0] != .granted }
    }

    /// SF Symbol for the menu bar icon in the current phase.
    public var menuBarSymbol: String {
        switch phase {
        case .idle, .editing: return "record.circle"
        case .preparing: return "record.circle"
        case .recording: return "record.circle.fill"
        case .saving: return "ellipsis.circle"
        case .failed: return "exclamationmark.triangle"
        }
    }

    // MARK: Settings

    public func updateSettings(_ change: (inout ShellSettings) -> Void) {
        var s = settings
        change(&s)
        guard s != settings else { return }
        settings = s
        settingsStore.save(s)
    }

    public func selectSource(_ source: CaptureSource?) { updateSettings { $0.source = source } }
    public func setMicEnabled(_ on: Bool) { updateSettings { $0.micEnabled = on } }
    public func selectMicrophone(_ id: String?) { updateSettings { $0.micDeviceID = id } }
    public func setCameraEnabled(_ on: Bool) { updateSettings { $0.cameraEnabled = on } }
    public func selectCamera(_ id: String?) { updateSettings { $0.cameraDeviceID = id } }
    public func selectShape(_ shape: CameraShape) {
        updateSettings { $0.cameraShape = shape }
        effects.updateBubbleShape(shape)
    }

    /// Lets the user drag a rectangle on screen, then remembers it as the source.
    public func chooseArea() async {
        guard canStart, let area = await effects.selectArea() else { return }
        selectSource(area.source)
    }

    // MARK: Sources and permissions

    public func refreshPermissions() {
        for kind in PermissionKind.allCases { permissionStates[kind] = services.permissions.status(of: kind) }
    }

    public func requestPermission(_ kind: PermissionKind) async {
        permissionStates[kind] = await services.permissions.request(kind)
        refreshPermissions()
        if kind == .screenRecording { await refreshSources() }
    }

    public func openSystemSettings(for kind: PermissionKind) { services.permissions.openSettings(for: kind) }

    public func refreshSources() async {
        refreshPermissions()
        microphones = services.sources.microphones()
        cameras = services.sources.cameras()
        do {
            listing = try await services.sources.loadSources()
            sourceError = nil
        } catch {
            sourceError = Self.describe(error)
        }
    }

    /// Call once at launch: reads permissions and asks to show onboarding if screen recording is missing.
    public func launch() async {
        await refreshSources()
        if !missingRequiredPermissions.isEmpty { requestOnboarding() }
    }

    public func requestOnboarding() { onboardingRequestID += 1 }
    public func requestEditor() { if lastSaved != nil { editorRequestID += 1 } }
    public func dismissError() { apply(.dismissError) }
    public func dismissNotice() { notice = nil }

    // MARK: Recording

    /// The one-click action: starts with the last-used source and devices, no dialogs.
    public func startRecording() async {
        guard canStart else { return }
        refreshPermissions()
        guard permissionStates[.screenRecording] == .granted else {
            requestOnboarding()
            return
        }
        guard apply(.startRequested) else { return }
        notice = nil
        var createdRef: ProjectReference?
        var loggerStarted = false
        do {
            if let fresh = try? await services.sources.loadSources() { listing = fresh }
            microphones = services.sources.microphones()
            cameras = services.sources.cameras()

            let (source, fellBack) = Self.resolve(settings.source, in: listing, fallbackDisplay: CGMainDisplayID())
            var notes: [String] = []
            if fellBack { notes.append("The saved source is gone, recording the main display.") }

            var micID: String?
            if settings.micEnabled {
                if !(await deviceAllowed(.microphone)) { notes.append("Microphone skipped: permission denied.") }
                else if let id = Self.pickDevice(preferred: settings.micDeviceID, from: microphones) { micID = id }
                else { notes.append("Microphone skipped: none found.") }
            }
            var camID: String?
            if settings.cameraEnabled {
                if !(await deviceAllowed(.camera)) { notes.append("Camera skipped: permission denied.") }
                else if let id = Self.pickDevice(preferred: settings.cameraDeviceID, from: cameras) { camID = id }
                else { notes.append("Camera skipped: none found.") }
            }
            notice = notes.isEmpty ? nil : notes.joined(separator: " ")

            let name = Self.projectName(for: now())
            let ref = try await services.store.createProject(named: name)
            createdRef = ref
            // The logger starts first so no early movement is lost. `stop` rebases to the session's origin.
            try await services.inputLogger.start(source: source)
            loggerStarted = true
            let options = RecordingOptions(source: source, micDeviceID: micID, cameraDeviceID: camID)
            try await services.session.start(options: options, into: ref.url)

            let startedAt = now()
            let sourceRect = SourceLocator.appKitRect(
                for: source, displays: listing.displays, windows: listing.windows, primaryHeight: effects.primaryScreenHeight)
            active = ActiveRecording(reference: ref, source: source, sourceRect: sourceRect, cameraDeviceID: camID, name: name)
            apply(.started(startedAt))
            showOverlays(startedAt: startedAt)
            watchSession()
        } catch {
            if loggerStarted { _ = await services.inputLogger.stop(recordingStartHostTime: 0) }
            if let createdRef { Self.removeBundle(createdRef, library: services.store.libraryURL) }
            active = nil
            apply(.startFailed(Self.describe(error)))
            if case NSSError.permissionDenied = error { requestOnboarding() }
        }
    }

    public func stopRecording() async {
        guard case .recording = phase, let active, apply(.stopRequested) else { return }
        watchTask?.cancel()
        let bubble = captureBubble(for: active)
        hideOverlays()
        self.active = nil
        do {
            let saved = try await finish(active, bubble: bubble)
            apply(.saved(saved.reference))
            editorRequestID += 1
        } catch {
            // `finish` already cleaned up for a failed stop (bundle removed) and kept the bundle for a failed save.
            apply(.saveFailed(Self.describe(error)))
        }
    }

    /// True if the device's permission is granted. An undecided permission is asked for here, before the
    /// session starts, so the system prompt never interrupts `session.start`. Declined or denied means skip the device.
    private func deviceAllowed(_ kind: PermissionKind) async -> Bool {
        var state = services.permissions.status(of: kind)
        if state == .notDetermined { state = await services.permissions.request(kind) }
        permissionStates[kind] = state
        return state == .granted
    }

    /// Stops the session (finalizing every file), stops the logger, and saves the project and cursor track.
    private func finish(_ active: ActiveRecording, bubble: (center: NormalizedPoint, size: Double)?) async throws -> SavedRecording {
        let assets: RecordingAssets
        do {
            assets = try await services.session.stop()
        } catch {
            // The session deleted its own files, so the bundle is an empty shell. Do not leave a broken project behind.
            _ = await services.inputLogger.stop(recordingStartHostTime: 0)
            Self.removeBundle(active.reference, library: services.store.libraryURL)
            throw error
        }
        // From here the finished recording exists: a failed save keeps the bundle.
        let track = await services.inputLogger.stop(recordingStartHostTime: assets.startHostTime)
        var style = Style()
        style.camera = Self.cameraBubble(
            hasCamera: assets.cameraFile != nil, shape: settings.cameraShape,
            geometry: bubble ?? (settings.bubbleCenter, settings.bubbleSize))
        let project = Project(name: active.name, assets: assets, style: style)
        try await services.store.saveCursorTrack(track, for: active.reference, assets: assets)
        try await services.store.save(project, to: active.reference)
        let saved = SavedRecording(reference: active.reference, project: project, cursorTrack: track)
        lastSaved = saved
        return saved
    }

    /// Stops and throws the recording away, deleting its bundle.
    public func discardRecording() async {
        guard case .recording = phase, let active else { return }
        discarding = true
        defer { discarding = false }
        watchTask?.cancel()
        hideOverlays()
        self.active = nil
        apply(.discardRequested)
        _ = try? await services.session.stop()
        _ = await services.inputLogger.stop(recordingStartHostTime: 0)
        Self.removeBundle(active.reference, library: services.store.libraryURL)
    }

    public func toggleRecording() async {
        if phase.isRecording { await stopRecording() } else { await startRecording() }
    }

    // MARK: Internals

    @discardableResult
    private func apply(_ event: ShellEvent) -> Bool {
        guard let next = ShellStateMachine.reduce(phase, event) else { return false }
        phase = next
        return true
    }

    private func showOverlays(startedAt: Date) {
        effects.showHUD(
            startedAt: startedAt,
            onStop: { [weak self] in Task { await self?.stopRecording() } },
            onDiscard: { [weak self] in Task { await self?.discardRecording() } })
        effects.registerStopShortcut { [weak self] in Task { await self?.stopRecording() } }
        if let active, let camID = active.cameraDeviceID {
            let source = active.sourceRect ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
            let frame = BubbleGeometry.panelFrame(
                center: settings.bubbleCenter, size: settings.bubbleSize, shape: settings.cameraShape, in: source)
            effects.showBubble(deviceID: camID, shape: settings.cameraShape, frame: frame, sourceRect: source)
        }
    }

    private func hideOverlays() {
        effects.hideHUD()
        effects.hideBubble()
        effects.unregisterStopShortcut()
    }

    /// Reads where the user left the bubble, saves it as the new default, and returns it.
    private func captureBubble(for active: ActiveRecording) -> (center: NormalizedPoint, size: Double)? {
        guard active.cameraDeviceID != nil, let frame = effects.bubbleFrame(), let rect = active.sourceRect,
              let result = BubbleGeometry.normalize(panelFrame: frame, in: rect)
        else { return nil }
        updateSettings { $0.bubbleCenter = result.center; $0.bubbleSize = result.size }
        return result
    }

    /// The screen stream can end on its own (window closed, display unplugged).
    private func watchSession() {
        watchTask?.cancel()
        let stream = services.session.stateUpdates
        watchTask = Task { [weak self] in
            for await state in stream {
                guard let self, !Task.isCancelled else { return }
                if case .failed(let message) = state, self.phase.isRecording {
                    await self.captureEnded(message)
                    return
                }
            }
        }
    }

    /// The screen stream ended on its own. Stop the session so the mic and camera stop and every file is
    /// finalized, then keep whatever was recorded (or remove the bundle if nothing usable exists).
    private func captureEnded(_ message: String) async {
        guard let active else { return }
        watchTask = nil
        let bubble = captureBubble(for: active)
        hideOverlays()
        self.active = nil
        apply(.captureFailed(message))
        do {
            let saved = try await finish(active, bubble: bubble)
            notice = "Recording stopped early. The partial recording was saved as \(saved.project.name)."
        } catch {
            // `finish` removes the bundle only when the session produced nothing. If saving the project failed,
            // the finished recording stays on disk, so say where.
            if FileManager.default.fileExists(atPath: active.reference.url.path) {
                notice = "Recording stopped early. The files are kept in \(active.reference.url.lastPathComponent), but the project could not be saved."
            }
        }
    }

    // MARK: Pure helpers (tested)

    /// Picks the source to record, falling back to the main display when the saved one no longer exists.
    static func resolve(
        _ saved: CaptureSource?, in listing: SourceListing, fallbackDisplay: UInt32
    ) -> (source: CaptureSource, fellBack: Bool) {
        let mainID = listing.displays.first(where: \.isMain)?.id ?? listing.displays.first?.id ?? fallbackDisplay
        guard let saved else { return (.display(id: mainID), false) }
        switch saved {
        case .display(let id):
            return listing.displays.contains { $0.id == id } || listing.displays.isEmpty
                ? (saved, false) : (.display(id: mainID), true)
        case .window(let id):
            return listing.windows.contains { $0.id == id } ? (saved, false) : (.display(id: mainID), true)
        case .area(let displayID, _):
            return listing.displays.contains { $0.id == displayID } ? (saved, false) : (.display(id: mainID), true)
        }
    }

    /// The preferred device if it still exists, else the system default, else the first one. nil if there are none.
    static func pickDevice(preferred: String?, from devices: [DeviceItem]) -> String? {
        if let preferred, devices.contains(where: { $0.id == preferred }) { return preferred }
        return (devices.first(where: \.isDefault) ?? devices.first)?.id
    }

    static func cameraBubble(
        hasCamera: Bool, shape: CameraShape, geometry: (center: NormalizedPoint, size: Double)
    ) -> CameraBubble {
        CameraBubble(visible: hasCamera, shape: shape, position: geometry.center, size: geometry.size)
    }

    static func projectName(for date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "Recording \(f.string(from: date))"
    }

    /// Deletes a bundle this app created. Refuses anything that is not a `.nssproj` directly inside the library.
    @discardableResult
    static func removeBundle(_ ref: ProjectReference, library: URL) -> Bool {
        let url = ref.url.standardizedFileURL
        guard url.pathExtension == ProjectReference.fileExtension,
              url.deletingLastPathComponent().standardizedFileURL == library.standardizedFileURL
        else { return false }
        return (try? FileManager.default.removeItem(at: url)) != nil
    }

    static func describe(_ error: Error) -> String {
        switch error {
        case NSSError.permissionDenied(let m), NSSError.unsupported(let m), NSSError.invalidProject(let m),
             NSSError.renderFailed(let m), NSSError.io(let m), NSSError.notImplemented(let m):
            return m
        default: return error.localizedDescription
        }
    }
}

public enum ElapsedFormat {
    /// "0:07", "12:03", "1:02:03".
    public static func string(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}
