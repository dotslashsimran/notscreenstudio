import Foundation
import NSSCore

/// STUB (Recording worker replaces): does nothing, reports state transitions.
public actor NoopRecordingSession: RecordingSession {
    private var current: RecordingState = .idle
    private var continuations: [UUID: AsyncStream<RecordingState>.Continuation] = [:]
    private var pendingSize = PixelSize(width: 1920, height: 1080)

    public init() {}

    public nonisolated var stateUpdates: AsyncStream<RecordingState> {
        AsyncStream { continuation in
            let id = UUID()
            Task { await self.register(id, continuation) }
            continuation.onTermination = { _ in Task { await self.unregister(id) } }
        }
    }

    public var state: RecordingState { current }

    private func register(_ id: UUID, _ c: AsyncStream<RecordingState>.Continuation) {
        continuations[id] = c
        c.yield(current)
    }
    private func unregister(_ id: UUID) { continuations[id] = nil }
    private func set(_ s: RecordingState) {
        current = s
        for c in continuations.values { c.yield(s) }
    }

    public func start(options: RecordingOptions, into bundleURL: URL) async throws {
        set(.recording(startedAt: Date()))
    }

    public func stop() async throws -> RecordingAssets {
        set(.finished)
        return RecordingAssets(sourcePixelSize: pendingSize, frameRate: 60, duration: 0)
    }
}
