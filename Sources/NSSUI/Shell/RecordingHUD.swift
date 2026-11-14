import AppKit
import SwiftUI

/// Small floating control while recording: elapsed time, stop, discard.
struct RecordingHUDView: View {
    var startedAt: Date
    var onStop: () -> Void
    var onDiscard: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(.red).frame(width: 9, height: 9)
            TimelineView(.periodic(from: startedAt, by: 0.5)) { context in
                Text(ElapsedFormat.string(context.date.timeIntervalSince(startedAt)))
                    .font(.system(.body, design: .monospaced).weight(.medium))
                    .monospacedDigit()
            }
            Button(action: onStop) { Image(systemName: "stop.fill") }
                .help("Stop recording (\(StopShortcut.display))")
                .keyboardShortcut(.escape, modifiers: [])
            Button(action: onDiscard) { Image(systemName: "trash") }
                .help("Discard this recording")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.15)))
        .fixedSize()
    }
}

/// Borderless, always-on-top, non-activating panel hosting the HUD. Draggable by its background.
@MainActor
final class RecordingHUDPanel {
    private var panel: NSPanel?

    func show(startedAt: Date, onStop: @escaping () -> Void, onDiscard: @escaping () -> Void) {
        hide()
        let host = NSHostingView(rootView: RecordingHUDView(startedAt: startedAt, onStop: onStop, onDiscard: onDiscard))
        let size = host.fittingSize
        let panel = NSPanel(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.contentView = host
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        if let screen = NSScreen.main ?? NSScreen.screens.first {
            let vf = screen.visibleFrame
            panel.setFrameOrigin(CGPoint(x: vf.midX - size.width / 2, y: vf.maxY - size.height - 12))
        }
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
    }
}
