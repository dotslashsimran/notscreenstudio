import Testing
@testable import NSSCapture

@Suite struct FrameGateTests {
    @Test func framesBeforeArmAreNeverWritten() {
        var g = FrameGate<Int>(armed: false)
        #expect(!g.accept(pts: 1))
        g.hold(1); g.hold(2)
        #expect(g.held == 2) // only the newest is kept
    }

    @Test func armReturnsHeldFrameAndMakesItTheOrigin() {
        var g = FrameGate<Int>(armed: false)
        g.hold(7)
        #expect(g.arm(at: 10) == 7)
        #expect(g.held == nil)
        #expect(g.accept(pts: 10)) // the held frame is written at the end of the countdown
    }

    @Test func staleFramesQueuedBeforeArmAreDropped() {
        var g = FrameGate<Int>(armed: false)
        _ = g.arm(at: 10)
        #expect(!g.accept(pts: 9.99))
        #expect(g.accept(pts: 10.016))
    }

    @Test func timestampsStrictlyIncrease() {
        var g = FrameGate<Int>(armed: false)
        g.hold(1)
        _ = g.arm(at: 10)
        #expect(g.accept(pts: 10))
        #expect(!g.accept(pts: 10)) // duplicate
        #expect(!g.accept(pts: 10.0)) 
        #expect(g.accept(pts: 10.02))
        #expect(!g.accept(pts: 10.01)) // out of order
    }

    @Test func unarmedStartAcceptsEverythingIncreasing() {
        var g = FrameGate<Int>(armed: true)
        #expect(g.accept(pts: 0.5))
        #expect(g.accept(pts: 0.6))
    }

    @Test func armWithoutHeldFrameWaitsForLiveFrames() {
        var g = FrameGate<Int>(armed: false)
        #expect(g.arm(at: 5) == nil)
        #expect(!g.accept(pts: 4))
        #expect(g.accept(pts: 5.01))
    }
}
