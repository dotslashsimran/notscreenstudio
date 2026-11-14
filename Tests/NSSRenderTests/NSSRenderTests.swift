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

    @Test func solidColorFrameSourceReturnsFrames() async throws {
        let src = try SolidColorFrameSource(width: 4, height: 4, color: RGBAColor(r: 0, g: 1, b: 0))
        let f = try #require(await src.screenFrame(at: 3.2))
        #expect(CVPixelBufferGetWidth(f) == 4)
        CVPixelBufferLockBaseAddress(f, .readOnly)
        let p = CVPixelBufferGetBaseAddress(f)!.assumingMemoryBound(to: UInt8.self)
        #expect(p[1] == 255 && p[0] == 0 && p[2] == 0)
        CVPixelBufferUnlockBaseAddress(f, .readOnly)
        #expect(await src.cameraFrame(at: 0) == nil)
        let withCam = try SolidColorFrameSource(width: 2, height: 2, color: .white, hasCamera: true)
        #expect(await withCam.cameraFrame(at: 0) != nil)
    }
}
