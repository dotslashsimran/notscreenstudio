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
        // Default (deferredToDate) keeps full Double precision, so load(save(p)) == p.
        return e
    }
    private static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        return d
    }

    public func createProject(named name: String) async throws -> ProjectReference {
        let fm = FileManager.default
        try fm.createDirectory(at: libraryURL, withIntermediateDirectories: true)
        let base = Self.sanitize(name)
        var n = 1
        while true {
            let leaf = n == 1 ? base : "\(base) \(n)"
            let url = libraryURL.appendingPathComponent("\(leaf).\(ProjectReference.fileExtension)", isDirectory: true)
            do {
                // Non-intermediate create fails if it exists, so an existing bundle is never reused.
                try fm.createDirectory(at: url, withIntermediateDirectories: false)
                return ProjectReference(url: url)
            } catch let e as CocoaError where e.code == .fileWriteFileExists {
                n += 1
            }
        }
    }

    /// Makes `name` safe as one path component: no separators, no leading dots, never empty.
    static func sanitize(_ name: String) -> String {
        var s = String(name.map { "/:\\\0".contains($0) ? "-" : $0 })
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasPrefix(".") { s.removeFirst() }
        return s.isEmpty ? "Untitled" : s
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
