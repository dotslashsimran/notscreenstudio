import AppKit
import NSSCore

/// The real `ShellEffects`: HUD panel, camera bubble panel, global stop shortcut and area overlay.
@MainActor
public final class AppKitShellEffects: ShellEffects {
    private let hud = RecordingHUDPanel()
    private let hotKey = GlobalHotKey()
    private let overlay = AreaSelectionOverlay()
    private var bubble: CameraBubblePanel?

    public init() {}

    public var primaryScreenHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

    public func showHUD(startedAt: Date, onStop: @escaping @MainActor () -> Void, onDiscard: @escaping @MainActor () -> Void) {
        hud.show(startedAt: startedAt, onStop: { onStop() }, onDiscard: { onDiscard() })
    }

    public func hideHUD() { hud.hide() }

    public func showBubble(deviceID: String?, shape: CameraShape, frame: CGRect, sourceRect: CGRect) {
        hideBubble()
        let screens = NSScreen.screens.map(\.frame)
        let union = screens.dropFirst().reduce(screens.first ?? sourceRect) { $0.union($1) }
        let placed = BubbleGeometry.keepReachable(frame, in: union)
        let panel = CameraBubblePanel(deviceID: deviceID, shape: shape, frame: placed, sourceRect: sourceRect)
        panel.orderFrontRegardless()
        bubble = panel
    }

    public func bubbleFrame() -> CGRect? { bubble?.frame }
    public func updateBubbleShape(_ shape: CameraShape) { bubble?.apply(shape: shape) }

    public func hideBubble() {
        bubble?.close(stopping: true)
        bubble = nil
    }

    public func registerStopShortcut(_ handler: @escaping @MainActor () -> Void) {
        hotKey.register(keyCode: StopShortcut.keyCode, modifiers: StopShortcut.modifiers, handler: handler)
    }

    public func unregisterStopShortcut() { hotKey.unregister() }

    public func selectArea() async -> AreaSelection? { await overlay.run() }
}
