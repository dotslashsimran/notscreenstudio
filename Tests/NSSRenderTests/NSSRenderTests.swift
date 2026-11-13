import CoreVideo
import Testing
import NSSCore
@testable import NSSRender

@Suite struct NSSRenderTests {
    @Test func passthroughClearsToBackgroundColor() throws {
        let screen = try PixelBuffers.make(width: 16, height: 16)
        let out = try PixelBuffers.make(width: 32, height: 18)
        var style = Style()
        style.background = .solid(RGBAColor(r: 1, g: 0, b: 0))
        try PassthroughRenderer().render(screen: screen, camera: nil, state: FrameState(time: 0), style: style, into: out)
        CVPixelBufferLockBaseAddress(out, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(out, .readOnly) }
        let p = CVPixelBufferGetBaseAddress(out)!.assumingMemoryBound(to: UInt8.self)
        #expect(p[2] == 255 && p[1] == 0 && p[0] == 0)  // BGRA: red
    }
}
