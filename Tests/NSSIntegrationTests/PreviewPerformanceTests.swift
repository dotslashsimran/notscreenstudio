import CoreVideo
import Foundation
import Testing
import NSSCore
import NSSExport
import NSSMotion
import NSSRender
@testable import NSSUI

/// Renderer wrapper that records how long each `render` call takes (on the preview's render queue).
final class TimingRenderer: FrameRenderer, @unchecked Sendable {
    private let inner: any FrameRenderer
    private let lock = NSLock()
    private var _times: [Double] = []
    init(_ inner: any FrameRenderer) { self.inner = inner }
    var times: [Double] { lock.lock(); defer { lock.unlock() }; return _times }
    func render(screen: CVPixelBuffer, camera: CVPixelBuffer?, state: FrameState, style: Style, into output: CVPixelBuffer) throws {
        let t0 = ContinuousClock.now
        try inner.render(screen: screen, camera: camera, state: state, style: style, into: output)
        let d = (ContinuousClock.now - t0).seconds
        lock.lock(); _times.append(d); lock.unlock()
    }
}

extension Duration {
    var seconds: Double { Double(components.seconds) + Double(components.attoseconds) / 1e18 }
}

func percentile(_ values: [Double], _ p: Double) -> Double {
    guard !values.isEmpty else { return .nan }
    let s = values.sorted()
    return s[min(s.count - 1, Int((Double(s.count - 1) * p).rounded()))]
}

/// Drives the real `PreviewEngine` (AVPlayer decode + real motion model + Metal at preview size) without a window,
/// ticking at 60 Hz like the display link. Budgets are asserted only with `NSS_BENCH=1`.
@MainActor
@Suite(.serialized) struct PreviewPerformanceTests {
    @Test(.enabled(if: e2eAvailable))
    func previewFrameTimes() async throws {
        let bundle = try await makeE2EBundle(mic: false, camera: true, duration: 8, trim: TrimRange())
        defer { try? FileManager.default.removeItem(at: bundle.store.libraryURL) }
        let timing = TimingRenderer(try MetalRenderer.makeDefault())
        let deps = EditorDependencies(
            store: bundle.store, motionFactory: SpringMotionModel.factory, renderer: timing,
            exporter: MP4Exporter(motionFactory: SpringMotionModel.factory, renderer: timing),
            motionFactoryForAspect: { SpringMotionModel.factory(sourceAspect: $0) })
        let model = EditorModel(project: bundle.project, reference: bundle.ref, track: bundle.track, dependencies: deps)
        let engine = PreviewEngine(model: model)
        model.changeHandler = { [engine] in engine.modelChanged($0) }
        var presentTimes: [ContinuousClock.Instant] = []
        engine.present = { _ in presentTimes.append(.now) }

        // Warm up: first frame, motion model built, pipelines compiled.
        for _ in 0..<300 where presentTimes.isEmpty {
            engine.tick()
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(!presentTimes.isEmpty, "the preview never produced a frame")
        try await Task.sleep(for: .milliseconds(300))
        engine.tick()

        let warmRenders = timing.times.count
        presentTimes.removeAll()
        engine.play()
        var tickTimes: [Double] = []
        let frames = 360
        let interval = Duration.nanoseconds(16_666_667)
        var deadline = ContinuousClock.now + interval
        for _ in 0..<frames {
            let t0 = ContinuousClock.now
            engine.tick()
            tickTimes.append((ContinuousClock.now - t0).seconds)
            try await Task.sleep(until: deadline)
            deadline += interval
        }
        let playhead = model.playhead
        engine.pause()
        engine.teardown()

        let renders = Array(timing.times.dropFirst(warmRenders))
        let gaps = zip(presentTimes, presentTimes.dropFirst()).map { ($1 - $0).seconds }
        let ms = { (v: Double) in String(format: "%.2f", v * 1000) }
        print("""
        preview bench (\(PreviewEngine.previewSize(for: .r16x9).width)x\(PreviewEngine.previewSize(for: .r16x9).height), \(frames) ticks at 60 Hz, playhead reached \(String(format: "%.1f", playhead)) s):
          Metal render per frame   p50 \(ms(percentile(renders, 0.5))) ms   p95 \(ms(percentile(renders, 0.95))) ms   max \(ms(renders.max() ?? .nan)) ms   (\(renders.count) frames)
          main-thread tick()       p50 \(ms(percentile(tickTimes, 0.5))) ms   p95 \(ms(percentile(tickTimes, 0.95))) ms   max \(ms(tickTimes.max() ?? .nan)) ms
          interval between frames  p50 \(ms(percentile(gaps, 0.5))) ms   p95 \(ms(percentile(gaps, 0.95))) ms   dropped by engine: \(engine.droppedFrames)
        """)
        #expect(playhead > 4, "playback did not advance (playhead \(playhead))")
        #expect(renders.count > frames / 2)
        if runBench {
            #expect(percentile(renders, 0.95) < 0.0166, "render p95 over the 16.6 ms budget")
            #expect(percentile(tickTimes, 0.95) < 0.0166, "main-thread tick p95 over the 16.6 ms budget")
        }
    }
}
