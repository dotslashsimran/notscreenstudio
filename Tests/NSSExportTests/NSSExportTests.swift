import Foundation
import Testing
import NSSCore
@testable import NSSExport

@Suite struct NSSExportTests {
    @Test func stubExporterReportsNotImplemented() async {
        let project = Project(name: "t", assets: RecordingAssets(sourcePixelSize: PixelSize(width: 10, height: 10), frameRate: 60, duration: 1))
        await #expect(throws: NSSError.self) {
            try await StubExporter().export(project: project, projectURL: URL(fileURLWithPath: "/tmp"), track: .empty, preset: ExportPreset(), to: URL(fileURLWithPath: "/tmp/x.mp4"), progress: { _ in })
        }
    }
}
