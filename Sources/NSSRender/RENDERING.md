# NSSRender: how a frame is drawn

`MetalRenderer` implements `FrameRenderer`. The preview and the export both use it, so a frame looks the same in both.

## Using it

```swift
// Falls back to PassthroughRenderer only when there is no Metal device; any other setup error is thrown.
let renderer = try MetalRenderer.makeDefault(assetBaseURL: projectBundleURL)
try renderer.render(screen: screenPB, camera: cameraPB, state: motion.frameState(at: t), style: project.style, into: outputPB)
```

- All three pixel buffers must be IOSurface-backed `kCVPixelFormatType_32BGRA` buffers. Use `PixelBuffers.make(width:height:)`, a `CVPixelBufferPool` with `kCVPixelBufferIOSurfacePropertiesKey` and `kCVPixelBufferMetalCompatibilityKey`, or the `AVAssetWriterInputPixelBufferAdaptor` pool. Any other format throws `NSSError.unsupported`.
- The output size comes from the output buffer. For export, size it with `style.aspectRatio.outputSize(for: preset.resolution)` (16:9 gives 1920x1080 or 3840x2160, 1:1 gives 1080x1080 or 2160x2160, 9:16 gives 1080x1920 or 2160x3840). For the preview, any size works, but keep the same aspect ratio.
- `render` is synchronous. It returns once the GPU has finished writing `output`. Calls on one renderer are serialized by a lock, so the preview and the export should each create their own renderer. The compiled shader is shared between renderers.
- Pass `camera: nil` when there is no camera track. The bubble is skipped.
- Relative `Background.image(file:)` names are resolved against `assetBaseURL` (the `.nssproj` bundle). The image is decoded once (at most 4096 px on its longer side, with mipmaps) and cached. The cache key is the path plus the file's modification time and size, which the renderer reads with one `stat` per frame. So a file that is replaced at the same path, or that appears after a frame drew the grey fallback, is picked up automatically. A missing image draws mid-grey and does not throw.
- **Editor:** when the user picks a new background image, call `renderer.preload(style:)` on a background queue, not the main thread. Decoding a large image takes tens of milliseconds, and without the preload the first preview frame pays that cost. If you rewrite a file in place with exactly the same size within one timestamp tick, call `invalidateBackgroundImage()`.
- `Background.wallpaper(name:)` accepts the names in `MetalRenderer.wallpaperNames` (`aurora`, `sunset`, `ocean`, `forest`, `midnight`, `peach`). These are procedural, so there are no assets. An unknown name draws `aurora`.
- `CursorState.opacity` (0...1) multiplies with `visible`. The motion model ramps it to fade the cursor in and out.

## Geometry (`RenderLayout`)

`RenderLayout` is the pure-Swift geometry that every shader uniform comes from. The editor can use it for hit testing and overlays:

- `contentRect`: the screen content, fitted inside the output minus `padding * outputHeight` on every side. It keeps the source aspect and is centered.
- `outputPoint(forSource:)` and `sourcePoint(forOutput:)`: the camera transform. `CameraState.center` lands at the middle of `contentRect`, and `scale` magnifies.
- `cameraBubbleRect(_:cameraSize:)`: the bubble frame in output pixels. Circle and squircle bubbles are square. Rounded-rect and rectangle bubbles follow the camera aspect.
- `cursorHeight(style:)`, `rippleRadius(progress:)` and `cursorBlurVector(velocity:style:)`: the cursor and ripple sizes. They scale with the content size, the zoom and `CursorStyle.size`.

## The pass

Each frame is one render pass with one full-screen triangle. A single fragment shader does all the work below for each output pixel. There are no intermediate textures and no extra passes.

1. **Background.** This is a solid colour, a linear gradient (up to 8 stops, interpolated in OKLab so the midpoints stay vivid, with `angleDegrees` 0 meaning left to right and 90 meaning top to bottom), an aspect-filled image (sampled trilinearly from mipmaps), or a procedural wallpaper (colour control points blended in OKLab with a gentle warp).
2. **Screen shadow.** This is an analytic Gaussian: `erf` of the rounded-rect signed distance, with sigma = `shadow.radius * H / 2`, offset by `offsetX/Y * H` and scaled by `opacity`. It needs no blur pass.
3. **Screen content.** The source is cropped and zoomed by the camera. To downscale (for example a 4K source to a 1080p output), a footprint filter takes `ceil(texelsPerPixel)` by `ceil(texelsPerPixel)` bilinear taps (at most 6x6) spread across the output pixel. This is a box filter with no mipmap copy, so the input stays zero-copy. The corners are a rounded-rect SDF with 1 px anti-aliasing.
4. **Click ripples** (at most 8, only when `clickRipples` is on). Each is an anti-aliased ring with a faint fill and a soft dark halo, so it shows on both light and dark interfaces. The radius eases out and the opacity is `(1 - progress)^1.5`. Ripples are clipped to the content.
5. **Cursor.** This is a procedural macOS-style arrow: a polygon SDF with a black fill, a white outline and a soft shadow. Its tip is at `CursorState.position`, mapped through the camera. Motion blur averages up to 16 SDF samples along the velocity vector, centred on the position. The shutter is `motionBlur / 30` s and the blur is capped at 3x the cursor height. A still cursor gets one sample, so it stays crisp. The cursor is evaluated only inside its bounding box and is clipped to the content.
6. **Camera bubble.** The bubble has its own analytic shadow (the same `Style.shadow` values), an SDF mask (circle, rounded rect, squircle as a superellipse with n = 5, or rectangle), an aspect-fill crop of the webcam frame with the same footprint filter, an optional horizontal mirror, and a border drawn inside the edge (`border.width * H`).
7. **Output.** All blending above is in linear light. Inputs are read through `bgra8Unorm_srgb` views, so the GPU decodes them. The result is sRGB-encoded in the shader, and a triangular ±1 LSB dither is added to background pixels only, to prevent gradient banding. The screen and the camera pixels are never dithered, so text stays exact. Then the result is written to a `bgra8Unorm` view of the output buffer.

## Performance

The renderer allocates nothing per frame except the unavoidable `CVMetalTexture` wrappers and the command buffer. The library is compiled once per device (`PipelineCache`). The uniform buffer, the placeholder texture and the render pass descriptor are created once. Uniforms are a flat array of `float4` slots (`Slot` in `Shaders.swift`). The shader receives `#define U_<SLOT>` indices generated from the Swift enum, so the two layouts can never drift apart. The `benchmark4KFrame` test renders a full 4K frame (4K source, zoom, gradient, shadow, a blurred cursor, 3 ripples and a bordered bubble) and prints the best and median times. It asserts the 8 ms budget only when `NSS_BENCH=1` is set (`NSS_BENCH=1 swift test --filter benchmark4KFrame`), because wall-clock budgets are unreliable on loaded machines and CI VMs. Measured on an M-series MacBook Air under heavy load: about 2.5 ms best and 3.2 ms median.

## Shader source

The shaders are Swift strings in `Shaders.swift`, compiled at runtime with `MTLDevice.makeLibrary(source:options:)`. There are no `.metal` files because this toolchain has no Metal compiler.
