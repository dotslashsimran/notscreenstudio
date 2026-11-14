import Foundation
import NSSCore
import NSSMotion
import NSSRender

/// Export entry point contract. STUB (Export worker replaces): reports a failure.
public protocol Exporter: Sendable {
    func export(
        project: Project,
        projectURL: URL,
        track: CursorTrack,
        preset: ExportPreset,
        to outputURL: URL,
        progress: @escaping @Sendable (ExportProgress) -> Void
    ) async throws
}

public struct StubExporter: Exporter {
    public let motionFactory: MotionModelFactory
    public let renderer: any FrameRenderer
    public init(motionFactory: @escaping MotionModelFactory = LinearMotionModel.factory, renderer: any FrameRenderer = PassthroughRenderer()) {
        self.motionFactory = motionFactory
        self.renderer = renderer
    }
    public func export(project: Project, projectURL: URL, track: CursorTrack, preset: ExportPreset, to outputURL: URL, progress: @escaping @Sendable (ExportProgress) -> Void) async throws {
        progress(.failed(message: "Export not implemented yet"))
        throw NSSError.notImplemented("export")
    }
}
