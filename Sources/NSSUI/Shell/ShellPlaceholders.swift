import Foundation
import NSSCore

/// Inert services for previews and the default `MenuBarContent`. Nothing here touches the system.
public struct StubPermissions: PermissionsProviding {
    public var states: [PermissionKind: PermissionState]
    /// What `request` answers for a kind. Kinds not listed answer with their current state.
    public var requestResults: [PermissionKind: PermissionState]
    public init(
        states: [PermissionKind: PermissionState] = [.screenRecording: .granted, .camera: .granted, .microphone: .granted],
        requestResults: [PermissionKind: PermissionState] = [:]
    ) {
        self.states = states
        self.requestResults = requestResults
    }
    public func status(of kind: PermissionKind) -> PermissionState { states[kind] ?? .notDetermined }
    public func request(_ kind: PermissionKind) async -> PermissionState { requestResults[kind] ?? status(of: kind) }
    public func openSettings(for kind: PermissionKind) {}
}

struct PlaceholderSession: RecordingSession {
    var stateUpdates: AsyncStream<RecordingState> { AsyncStream { $0.yield(.idle) } }
    var state: RecordingState { .idle }
    func start(options: RecordingOptions, into bundleURL: URL) async throws { throw NSSError.notImplemented("placeholder") }
    func stop() async throws -> RecordingAssets { throw NSSError.notImplemented("placeholder") }
}

struct PlaceholderLogger: InputLogger {
    func start(source: CaptureSource) async throws {}
    func stop(recordingStartHostTime: Double) async -> CursorTrack { .empty }
}

struct PlaceholderStore: ProjectStore {
    var libraryURL: URL { FileManager.default.temporaryDirectory.appendingPathComponent("notscreenstudio-placeholder") }
    func createProject(named name: String) async throws -> ProjectReference { throw NSSError.notImplemented("placeholder") }
    func load(_ ref: ProjectReference) async throws -> Project { throw NSSError.notImplemented("placeholder") }
    func save(_ project: Project, to ref: ProjectReference) async throws {}
    func loadCursorTrack(for ref: ProjectReference, assets: RecordingAssets) async throws -> CursorTrack { .empty }
    func saveCursorTrack(_ track: CursorTrack, for ref: ProjectReference, assets: RecordingAssets) async throws {}
    func scheduleAutosave(_ project: Project, to ref: ProjectReference) {}
    func listProjects() async throws -> [ProjectReference] { [] }
}
