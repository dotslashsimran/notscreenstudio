import Foundation
import NSSCore

/// STUB (Projects worker replaces): real JSON round-trip of project.json / cursor.json, no autosave debounce.
public actor FileProjectStore: ProjectStore {
    public nonisolated let libraryURL: URL

    public init(libraryURL: URL = FileProjectStore.defaultLibraryURL) {
        self.libraryURL = libraryURL
    }

    public static var defaultLibraryURL: URL {
        FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("notscreenstudio", isDirectory: true)
    }

    private static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }
    private static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    public func createProject(named name: String) async throws -> ProjectReference {
        let url = libraryURL.appendingPathComponent("\(name).\(ProjectReference.fileExtension)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return ProjectReference(url: url)
    }

    public func load(_ ref: ProjectReference) async throws -> Project {
        let data = try Data(contentsOf: ref.url.appendingPathComponent(ProjectReference.projectFileName))
        return try Self.decoder().decode(Project.self, from: data)
    }

    public func save(_ project: Project, to ref: ProjectReference) async throws {
        try FileManager.default.createDirectory(at: ref.url, withIntermediateDirectories: true)
        let data = try Self.encoder().encode(project)
        try data.write(to: ref.url.appendingPathComponent(ProjectReference.projectFileName), options: .atomic)
    }

    public func loadCursorTrack(for ref: ProjectReference, assets: RecordingAssets) async throws -> CursorTrack {
        let data = try Data(contentsOf: ref.url.appendingPathComponent(assets.cursorFile))
        return try Self.decoder().decode(CursorTrack.self, from: data)
    }

    public func saveCursorTrack(_ track: CursorTrack, for ref: ProjectReference, assets: RecordingAssets) async throws {
        let data = try Self.encoder().encode(track)
        try data.write(to: ref.url.appendingPathComponent(assets.cursorFile), options: .atomic)
    }

    public nonisolated func scheduleAutosave(_ project: Project, to ref: ProjectReference) {
        // STUB: autosave is implemented by the Projects worker.
    }

    public func listProjects() async throws -> [ProjectReference] {
        let items = (try? FileManager.default.contentsOfDirectory(at: libraryURL, includingPropertiesForKeys: nil)) ?? []
        return items.filter { $0.pathExtension == ProjectReference.fileExtension }.map(ProjectReference.init)
    }
}
