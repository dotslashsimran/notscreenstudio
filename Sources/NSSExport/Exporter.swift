import Foundation
import NSSCore

/// Export entry point contract.
///
/// `export` renders the project's trimmed range at `preset` and writes an MP4 to `outputURL`.
/// It reports progress through `progress`, ending with `.finished`, `.failed` or `.cancelled`.
/// Cancel by cancelling the calling `Task`: the call then throws `CancellationError` and leaves nothing
/// behind. Errors are `NSSError` values.
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
