import Foundation
import Testing
import NSSCore
@testable import NSSUI

@Suite struct PlayheadEasingTests {
    @Test func startsSettled() {
        let e = PlayheadEasing(at: 3)
        #expect(e.value == 3 && e.target == 3 && !e.isAnimating)
    }

    @Test func glideReachesTargetWithinDuration() {
        var e = PlayheadEasing(at: 0)
        e.glide(to: 10)
        #expect(e.isAnimating)
        e.advance(by: PlayheadEasing.defaultDuration / 2)
        #expect(e.value > 5 && e.value < 10)          // ease-out: past half way at half the time
        e.advance(by: PlayheadEasing.defaultDuration)
        #expect(e.value == 10 && !e.isAnimating)
    }

    @Test func monotonicAndNeverOvershoots() {
        var e = PlayheadEasing(at: 2)
        e.glide(to: 7)
        var last = e.value
        for _ in 0..<30 {
            e.advance(by: 1.0 / 120)
            #expect(e.value >= last && e.value <= 7)
            last = e.value
        }
        var b = PlayheadEasing(at: 7)
        b.glide(to: 2)
        last = b.value
        for _ in 0..<30 {
            b.advance(by: 1.0 / 120)
            #expect(b.value <= last && b.value >= 2)
            last = b.value
        }
    }

    @Test func durationIsInRequestedWindow() {
        #expect(PlayheadEasing.defaultDuration >= 0.15 && PlayheadEasing.defaultDuration <= 0.25)
    }

    @Test func retargetStartsFromCurrentValue() {
        var e = PlayheadEasing(at: 0)
        e.glide(to: 10)
        e.advance(by: 0.05)
        let mid = e.value
        e.glide(to: 0)
        #expect(e.value == mid)                         // no jump when retargeting
        e.advance(by: 1)
        #expect(e.value == 0)
    }

    @Test func snapIsExactAndSameTargetDoesNotRestart() {
        var e = PlayheadEasing(at: 0)
        e.glide(to: 4)
        e.advance(by: 0.05)
        let v = e.value
        e.glide(to: 4)                                  // same target: keep going, don't restart
        e.advance(by: 0.0)
        #expect(e.value == v)
        e.snap(to: 9)
        #expect(e.value == 9 && !e.isAnimating)
    }

    @Test func deterministic() {
        func run() -> [Double] {
            var e = PlayheadEasing(at: 1)
            e.glide(to: 6)
            return (0..<20).map { _ in e.advance(by: 1.0 / 60); return e.value }
        }
        #expect(run() == run())
    }
}

@MainActor @Suite struct DisplayPlayheadTests {
    @Test func jumpGlidesButRealPlayheadMovesAtOnce() {
        let m = makeModel()
        m.seek(to: 10)
        #expect(m.playhead == 10)
        m.advanceDisplayPlayhead(dt: 1.0 / 60)
        #expect(m.displayPlayhead > 0 && m.displayPlayhead < 10)
        for _ in 0..<30 { m.advanceDisplayPlayhead(dt: 1.0 / 60) }
        #expect(m.displayPlayhead == 10)
    }

    @Test func scrubbingFollowsExactly() {
        let m = makeModel()
        m.isScrubbing = true
        m.seek(to: 7.3)
        m.advanceDisplayPlayhead(dt: 1.0 / 60)
        #expect(m.displayPlayhead == 7.3)
        m.seek(to: 2.1)
        m.advanceDisplayPlayhead(dt: 1.0 / 60)
        #expect(m.displayPlayhead == 2.1)
    }

    @Test func playbackFollowsExactly() {
        let m = makeModel()
        m.isPlaying = true
        for i in 1...5 {
            m.playhead = Double(i) / 60
            m.advanceDisplayPlayhead(dt: 1.0 / 60)
            #expect(m.displayPlayhead == m.playhead)
        }
    }

    @Test func undoThatMovesTimeGlides() {
        let m = makeModel()
        m.setTrimEnd(5)                                 // clamps nothing yet
        m.seek(to: 4)
        m.advanceDisplayPlayhead(dt: 1)
        m.undo()                                        // trim restored; playhead unchanged
        m.seek(to: 15)
        m.advanceDisplayPlayhead(dt: 1.0 / 60)
        #expect(m.displayPlayhead < 15)
    }
}

@MainActor @Suite struct BubbleInspectorEditTests {
    @Test func shapeChangeIsOneUndoStep() {
        let m = makeModel()
        m.setStyle(\.camera.shape, .tall, name: "Camera Shape")
        #expect(m.project.style.camera.shape == .tall)
        m.undo()
        #expect(m.project.style.camera.shape == CameraBubble().shape)
        m.redo()
        #expect(m.project.style.camera.shape == .tall)
    }

    @Test func roundnessAndZoomedScaleDragsCoalesce() {
        let m = makeModel()
        let r0 = m.project.style.camera.roundness, z0 = m.project.style.camera.zoomedScale
        let binding = m.styleBinding(\.camera.roundness, name: "Camera Roundness")
        m.beginGesture("Roundness")
        for i in 1...10 { binding.wrappedValue = Double(i) / 10 }
        m.endGesture()
        let zb = m.styleBinding(\.camera.zoomedScale, name: "Camera Zoomed Size")
        m.beginGesture("Shrink when zoomed")
        for i in 1...10 { zb.wrappedValue = 1 - Double(i) / 20 }
        m.endGesture()
        #expect(m.project.style.camera.roundness == 1)
        #expect(m.project.style.camera.zoomedScale == 0.5)
        m.undo()
        #expect(m.project.style.camera.zoomedScale == z0)
        #expect(m.project.style.camera.roundness == 1)
        m.undo()
        #expect(m.project.style.camera.roundness == r0)
        #expect(!m.canUndo)
    }

    @Test func zoomedScaleRangeIsSane() {
        #expect(InspectorBindings.zoomedScaleRange.upperBound == 1)
        #expect(InspectorBindings.zoomedScaleRange.lowerBound > 0)
    }
}
