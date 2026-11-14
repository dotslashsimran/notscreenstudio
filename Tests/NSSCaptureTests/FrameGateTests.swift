import Testing
@testable import NSSCapture

@Suite struct FrameGateTests {
    @Test func framesBeforeArmAreNeverWritten() {
        var g = FrameGate<Int>(armed: false)
        let early = g.accept(pts: 1)
        #expect(!early)
        g.hold(1); g.hold(2)
        #expect(g.held == 2) // only the newest is kept
    }

    @Test func armReturnsHeldFrameAndMakesItTheOrigin() {
        var g = FrameGate<Int>(armed: false)
        g.hold(7)
        let held = g.arm(at: 10)
        #expect(held == 7)
        #expect(g.held == nil)
        let written = g.accept(pts: 10) // the held frame is written at the end of the countdown
        #expect(written)
    }

    @Test func staleFramesQueuedBeforeArmAreDropped() {
        var g = FrameGate<Int>(armed: false)
        _ = g.arm(at: 10)
        let stale = g.accept(pts: 9.99)
        let live = g.accept(pts: 10.016)
        #expect(!stale)
        #expect(live)
    }

    @Test func timestampsStrictlyIncrease() {
        var g = FrameGate<Int>(armed: false)
        g.hold(1)
        _ = g.arm(at: 10)
        let first = g.accept(pts: 10)
        let duplicate = g.accept(pts: 10)
        let next = g.accept(pts: 10.02)
        let older = g.accept(pts: 10.01)
        #expect(first)
        #expect(!duplicate)
        #expect(next)
        #expect(!older)
    }

    @Test func alreadyArmedGateAcceptsIncreasingFrames() {
        var g = FrameGate<Int>(armed: true)
        let a = g.accept(pts: 0.5)
        let b = g.accept(pts: 0.6)
        #expect(a && b)
    }

    @Test func armWithoutHeldFrameWaitsForLiveFrames() {
        var g = FrameGate<Int>(armed: false)
        let held = g.arm(at: 5)
        let stale = g.accept(pts: 4)
        let live = g.accept(pts: 5.01)
        #expect(held == nil)
        #expect(!stale)
        #expect(live)
    }
}
