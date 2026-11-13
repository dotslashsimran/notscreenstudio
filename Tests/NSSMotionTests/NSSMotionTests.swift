import Testing
import NSSCore
@testable import NSSMotion

@Suite struct NSSMotionTests {
    @Test func linearModelIsDeterministicAndIdentityCamera() {
        let track = CursorTrack(samples: [CursorSample(t: 0, x: 0.2, y: 0.2), CursorSample(t: 2, x: 0.6, y: 0.4)])
        let m = LinearMotionModel(track: track, timeline: Timeline(), cursorStyle: CursorStyle())
        let a = m.frameState(at: 1)
        #expect(a == m.frameState(at: 1))
        #expect(a.camera == .identity)
        #expect(abs(a.cursor.position.x - 0.4) < 1e-9)
        #expect(abs(a.cursor.position.y - 0.3) < 1e-9)
    }
}
