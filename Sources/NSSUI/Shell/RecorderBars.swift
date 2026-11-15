import AppKit
import NSSCore
import Observation
import SwiftUI

/// What the floating recording bar shows and does. Owned by `ShellModel`, which keeps `elapsed` current.
@MainActor
@Observable
public final class RecordingControls {
    /// Recorded seconds. Stops advancing while paused.
    public internal(set) var elapsed: TimeInterval = 0
    public internal(set) var isPaused = false
    public internal(set) var canPause = true
    @ObservationIgnored var onStop: @MainActor () -> Void = {}
    @ObservationIgnored var onTogglePause: @MainActor () -> Void = {}
    @ObservationIgnored var onDiscard: @MainActor () -> Void = {}
    public init() {}
}

// MARK: - Shared look

/// Vibrant dark material behind both bars.
private struct BarBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .hudWindow
        v.blendingMode = .behindWindow
        v.state = .active
        v.appearance = NSAppearance(named: .darkAqua)
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

private struct BarChrome: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(BarBackground().clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous)))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(.white.opacity(0.14), lineWidth: 1))
            .environment(\.colorScheme, .dark)
            .fixedSize()
            .padding(10) // room for the panel shadow
    }
}

private struct RoundIconButton: View {
    let symbol: String
    let help: String
    var tint: Color = .white
    let action: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(Circle().fill(.white.opacity(hovering ? 0.22 : 0.10)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

// MARK: - Setup bar (before recording)

extension ShellModel {
    /// SF Symbol for the picked source.
    public var sourceSymbol: String {
        switch Self.resolve(settings.source, in: listing, fallbackDisplay: CGMainDisplayID()).source {
        case .display: return "display"
        case .window: return "macwindow"
        case .area: return "rectangle.dashed"
        }
    }
}

/// Camera or microphone: a toggle button with a device menu beside it.
private struct DeviceToggle: View {
    let symbolOn: String
    let symbolOff: String
    let label: String
    let enabled: Bool
    let devices: [DeviceItem]
    let selection: String?
    let onToggle: (Bool) -> Void
    let onSelect: (String?) -> Void

    private var selectedName: String {
        guard let id = ShellModel.pickDevice(preferred: selection, from: devices) else { return "None found" }
        return devices.first { $0.id == id }?.name ?? "None found"
    }

    var body: some View {
        HStack(spacing: 2) {
            Button { onToggle(!enabled) } label: {
                Image(systemName: enabled ? symbolOn : symbolOff)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(enabled ? Color.white : Color.white.opacity(0.55))
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(enabled ? Color.accentColor.opacity(0.85) : Color.white.opacity(0.10)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(enabled ? "Turn \(label) off" : "Turn \(label) on")

            Menu {
                if devices.isEmpty {
                    Text("No \(label) found")
                } else {
                    let current = ShellModel.pickDevice(preferred: selection, from: devices)
                    ForEach(devices) { device in
                        Button {
                            onSelect(device.id)
                            if !enabled { onToggle(true) }
                        } label: {
                            if device.id == current { Label(device.name, systemImage: "checkmark") } else { Text(device.name) }
                        }
                    }
                }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 14, height: 34)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("\(label.capitalized): \(selectedName)")
        }
    }
}

/// The control bar shown after a source is picked and before recording starts.
struct RecorderSetupBar: View {
    var model: ShellModel

    var body: some View {
        HStack(spacing: 16) {
            RoundIconButton(symbol: "xmark", help: "Close (Esc)") { model.cancelSetup() }
                .keyboardShortcut(.cancelAction)

            HStack(spacing: 8) {
                Image(systemName: model.sourceSymbol).foregroundStyle(.white.opacity(0.75))
                Text(model.sourceTitle)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 190, alignment: .leading)
            }

            Rectangle().fill(.white.opacity(0.15)).frame(width: 1, height: 28)

            DeviceToggle(
                symbolOn: "video.fill", symbolOff: "video.slash.fill", label: "camera",
                enabled: model.settings.cameraEnabled, devices: model.cameras, selection: model.settings.cameraDeviceID,
                onToggle: { model.setCameraEnabled($0) }, onSelect: { model.selectCamera($0) })
            DeviceToggle(
                symbolOn: "mic.fill", symbolOff: "mic.slash.fill", label: "microphone",
                enabled: model.settings.micEnabled, devices: model.microphones, selection: model.settings.micDeviceID,
                onToggle: { model.setMicEnabled($0) }, onSelect: { model.selectMicrophone($0) })

            Button { Task { await model.confirmRecord() } } label: {
                ZStack {
                    Circle().strokeBorder(.white.opacity(0.9), lineWidth: 3)
                    Circle().fill(Color.red).padding(5)
                }
                .frame(width: 52, height: 52)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
            .help("Start recording (Return)")
        }
        .modifier(BarChrome())
    }
}

// MARK: - Recording bar

/// The small bar shown while recording: red dot, elapsed time, pause or resume, stop.
struct RecordingBar: View {
    var controls: RecordingControls
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(controls.isPaused ? Color.orange : Color.red)
                .frame(width: 10, height: 10)
                .opacity(controls.isPaused ? 1 : (pulse ? 0.35 : 1))
                .animation(controls.isPaused ? .default : .easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulse)
                .animation(.default, value: controls.isPaused)
            Text(ElapsedFormat.string(controls.elapsed))
                .font(.system(size: 15, weight: .semibold).monospacedDigit())
                .foregroundStyle(controls.isPaused ? Color.white.opacity(0.6) : Color.white)
                .frame(minWidth: 48, alignment: .leading)
            if controls.canPause {
                RoundIconButton(
                    symbol: controls.isPaused ? "play.fill" : "pause.fill",
                    help: controls.isPaused ? "Resume recording" : "Pause recording"
                ) { controls.onTogglePause() }
            }
            Button { controls.onStop() } label: {
                Image(systemName: "stop.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.red))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Stop recording (\(StopShortcut.display))")
        }
        .modifier(BarChrome())
        .onAppear { pulse = true }
    }
}

// MARK: - Panels

/// Borderless panel that can take keys (Return, Esc) without activating the app being recorded.
private final class BarPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Hosts one bar at the bottom centre of the screen that holds the picked source. Above every window, on every
/// Space, and kept out of the recording.
@MainActor
final class FloatingBarWindow {
    private var panel: NSPanel?

    var isShown: Bool { panel != nil }

    func show<Content: View>(_ content: Content, over source: CGRect?, makeKey: Bool) {
        hide()
        let host = NSHostingView(rootView: content)
        let size = host.fittingSize
        let panel = BarPanel(
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
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.excludeFromCapture()
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        let screens = NSScreen.screens
        if !screens.isEmpty {
            let i = BarPlacement.screenIndex(for: source, screens: screens.map(\.frame))
            panel.setFrame(BarPlacement.frame(size: size, in: screens[i].visibleFrame), display: false)
        }
        panel.alphaValue = 0
        if makeKey { panel.makeKeyAndOrderFront(nil) } else { panel.orderFrontRegardless() }
        NSAnimationContext.runAnimationGroup { $0.duration = 0.18; panel.animator().alphaValue = 1 }
        self.panel = panel
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
    }
}
