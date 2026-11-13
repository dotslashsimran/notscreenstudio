import Foundation
import Testing
import NSSCore
@testable import NSSProject

@Suite struct NSSProjectTests {
    @Test func saveAndLoadRoundTrip() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("nss-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = FileProjectStore(libraryURL: dir)
        let ref = try await store.createProject(named: "t")
        let project = Project(name: "t", assets: RecordingAssets(sourcePixelSize: PixelSize(width: 100, height: 100), frameRate: 60, duration: 1))
        try await store.save(project, to: ref)
        let loaded = try await store.load(ref)
        #expect(loaded.id == project.id)
        #expect(loaded.assets == project.assets)
        let track = CursorTrack(samples: [CursorSample(t: 0, x: 0.1, y: 0.2)])
        try await store.saveCursorTrack(track, for: ref, assets: project.assets)
        #expect(try await store.loadCursorTrack(for: ref, assets: project.assets) == track)
        #expect(try await store.listProjects().count == 1)
    }
}
