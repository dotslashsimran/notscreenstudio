import Testing
import NSSCore
@testable import NSSInput

@Suite struct NSSInputTests {
    @Test func noopLoggerReturnsEmptyTrack() async throws {
        let l = NoopInputLogger()
        try await l.start(source: .display(id: 1))
        #expect(await l.stop(recordingStartHostTime: 0) == .empty)
    }
}
