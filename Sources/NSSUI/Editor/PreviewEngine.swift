import AVFoundation
import AppKit
import NSSCore
import NSSRender
import QuartzCore

/// Wraps a non-Sendable value so it can cross to the render queue. Safe because each wrapped value is
/// handed to exactly one queue block at a time.
struct Unchecked<T>: @unchecked Sendable { let value: T }

/// Lock-protected current motion model; swapped when the timeline or cursor style changes.
final class MotionBox: @unchecked Sendable {
    private let lock = NSLock()
    private var model: any MotionModel
    init(_ model: any MotionModel) { self.model = model }
    func get() -> any MotionModel { lock.lock(); defer { lock.unlock() }; return model }
    func set(_ m: any MotionModel) { lock.lock(); model = m; lock.unlock() }
}

struct IdentityMotion: MotionModel {
    func frameState(at t: MediaTime) -> FrameState { FrameState(time: t) }
}

/// Drives playback and preview rendering. `tick(targetTimestamp:)` is called from the view's display link.
/// Per tick: read playhead, pull frames from `AVPlayerItemVideoOutput`, then render on a background queue into
/// a small pool of reused IOSurface-backed buffers. If the renderer is still busy the tick is dropped.
@MainActor
public final class PreviewEngine {
    public static let poolSize = 3

    private let model: EditorModel
    private let screen: PlayerVideoTrack
    private let camera: PlayerVideoTrack?
    private let mic: AVPlayer?
    private let renderer: any FrameRenderer
    private let motion: MotionBox
    private let renderQueue = DispatchQueue(label: "nss.preview.render", qos: .userInteractive)

    private var pool: [CVPixelBuffer] = []
    private var poolIndex = 0
    private var poolSize = PixelSize(width: 0, height: 0)
    private var renderBusy = false
    private var dirty = true
    private var awaitingFrame = 0
    private var motionGeneration = 0
    private var tickCount = 0
    private var syncCheckCount = 0

    /// Called on the main actor with each finished buffer (the view sets it as layer contents).
    public var present: ((CVPixelBuffer) -> Void)?
    /// Camera state used for the frame currently on screen (for click -> source mapping).
    public private(set) var displayedCamera = CameraState.identity
    public private(set) var droppedFrames = 0
    public private(set) var lastRenderError: String?

    public init(model: EditorModel) {
        self.model = model
        let base = model.reference.url
        let assets = model.project.assets
        screen = PlayerVideoTrack(url: base.appendingPathComponent(assets.screenFile), muted: false)
        camera = assets.cameraFile.map { PlayerVideoTrack(url: base.appendingPathComponent($0), muted: true) }
        mic = assets.micFile.map {
            let p = AVPlayer(url: base.appendingPathComponent($0))
            p.automaticallyWaitsToMinimizeStalling = false
            return p
        }
        renderer = model.dependencies.renderer
        motion = MotionBox(IdentityMotion())
        rebuildMotion()
        seek(to: model.trimStart)
    }

    public var frameSource: PlayerFrameSource { PlayerFrameSource(screen: screen, camera: camera) }

    // MARK: Model changes

    public func modelChanged(_ change: EditorChange) {
        if change == .timeline { rebuildMotion() }
        dirty = true
    }

    private func rebuildMotion() {
        motionGeneration += 1
        let gen = motionGeneration
        let factory = model.dependencies.motionFactory
        let track = model.track
        let timeline = model.project.timeline
        let style = model.project.style.cursor
        let duration = model.duration
        let box = motion
        Task { @MainActor [weak self] in
            let built = await Task.detached(priority: .userInitiated) { factory(track, timeline, style, duration) }.value
            guard let self, self.motionGeneration == gen else { return }
            box.set(built)
            self.dirty = true
        }
    }

    // MARK: Transport

    public func play() {
        if model.playhead >= model.trimEnd - 0.01 { seek(to: model.trimStart) }
        let t = CMTime(seconds: model.playhead, preferredTimescale: 600)
        let players = allPlayers
        if screen.player.currentItem?.status == .readyToPlay {
            let host = CMTimeAdd(CMClockGetTime(CMClockGetHostTimeClock()), CMTime(seconds: 0.15, preferredTimescale: 600))
            for p in players where p.currentItem?.status == .readyToPlay { p.setRate(1, time: t, atHostTime: host) }
        } else {
            for p in players { p.seek(to: t, toleranceBefore: .zero, toleranceAfter: .zero); p.play() }
        }
        model.isPlaying = true
    }

    public func pause() {
        for p in allPlayers { p.pause() }
        model.isPlaying = false
        model.playhead = clampedPlayerTime()
        dirty = true
    }

    public func seek(to time: MediaTime) {
        let t = TrimEditing.clamp(time, to: model.trim, duration: model.duration)
        let cm = CMTime(seconds: t, preferredTimescale: 600)
        for p in allPlayers { p.seek(to: cm, toleranceBefore: .zero, toleranceAfter: .zero) }
        model.playhead = t
        awaitingFrame = 30
        dirty = true
    }

    public func step(frames: Int) {
        if model.isPlaying { pause() }
        seek(to: model.playhead + Double(frames) * model.frameDuration)
    }

    public func teardown() {
        for p in allPlayers { p.pause() }
        present = nil
    }

    private var allPlayers: [AVPlayer] {
        var a = [screen.player]
        if let c = camera { a.append(c.player) }
        if let m = mic { a.append(m) }
        return a
    }

    private func clampedPlayerTime() -> MediaTime {
        let s = screen.player.currentTime().seconds
        return s.isFinite ? TrimEditing.clamp(s, to: model.trim, duration: model.duration) : model.playhead
    }

    // MARK: Per-frame

    public func tick() {
        tickCount += 1
        var t = model.playhead
        if model.isPlaying {
            let raw = screen.player.currentTime().seconds
            t = raw.isFinite ? raw : t
            if t >= model.trimEnd {
                t = model.trimEnd
                pause()
                model.playhead = t
            } else {
                if tickCount % 2 == 0 { model.playhead = t }
                correctDrift(master: t)
            }
        }

        var gotNew = screen.pull(at: t)
        if camera?.pull(at: t) == true { gotNew = true }
        if gotNew { awaitingFrame = 0 }
        let needsRender = model.isPlaying || dirty || gotNew || awaitingFrame > 0
        if awaitingFrame > 0 { awaitingFrame -= 1 }
        guard needsRender, let screenFrame = screen.lastFrame else { return }

        ensurePool()
        guard !pool.isEmpty else { return }
        if renderBusy {
            droppedFrames += 1
            dirty = true
            return
        }
        dirty = false
        renderBusy = true
        let out = Unchecked(value: pool[poolIndex])
        poolIndex = (poolIndex + 1) % pool.count
        let frameTime = t
        let job = Unchecked(value: (screenFrame, camera?.lastFrame))
        let style = model.project.style
        let renderer = renderer
        let box = motion
        renderQueue.async { [weak self] in
            let state = box.get().frameState(at: frameTime)
            var failure: String?
            do {
                try renderer.render(screen: job.value.0, camera: style.camera.visible ? job.value.1 : nil, state: state, style: style, into: out.value)
            } catch {
                failure = String(describing: error)
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.renderBusy = false
                    self.lastRenderError = failure
                    if failure == nil {
                        self.displayedCamera = state.camera
                        self.present?(out.value)
                    }
                }
            }
        }
    }

    private func correctDrift(master: MediaTime) {
        syncCheckCount += 1
        guard syncCheckCount % 30 == 0 else { return }
        let target = CMTime(seconds: master, preferredTimescale: 600)
        for p in [camera?.player, mic].compactMap({ $0 }) {
            let d = abs(p.currentTime().seconds - master)
            if d.isFinite, d > 0.08 { p.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) }
        }
    }

    /// (Re)creates the output pool only when the size changes (aspect ratio edit), never per frame.
    private func ensurePool() {
        let size = Self.previewSize(for: model.project.style.aspectRatio)
        guard size != poolSize || pool.isEmpty else { return }
        pool = (0..<Self.poolSize).compactMap { _ in try? PixelBuffers.make(width: size.width, height: size.height) }
        poolSize = size
        poolIndex = 0
    }

    /// 2/3 of 1080p output, keeping the chosen aspect ratio.
    public static func previewSize(for aspect: AspectRatio) -> PixelSize {
        let full = aspect.outputSize(for: .p1080)
        return PixelSize(width: full.width * 2 / 3, height: full.height * 2 / 3)
    }
}
