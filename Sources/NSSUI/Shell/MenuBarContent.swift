import AppKit
import SwiftUI
import NSSCore

/// Camera shapes offered in the menu, with the default radius for the rounded one.
public enum ShapeKind: String, CaseIterable, Identifiable, Sendable {
    case circle, square, tall, wide
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .circle: return "Circle"
        case .square: return "Square"
        case .tall: return "Tall"
        case .wide: return "Wide"
        }
    }

    public var shape: CameraShape {
        switch self {
        case .circle: return .circle
        case .square: return .square
        case .tall: return .tall
        case .wide: return .wide
        }
    }

    public init(_ shape: CameraShape) {
        switch shape {
        case .circle: self = .circle
        case .square: self = .square
        case .tall: self = .tall
        case .wide: self = .wide
        }
    }
}

extension ShellModel {
    /// Short description of what "Record" will capture.
    public var sourceTitle: String {
        let (source, _) = Self.resolve(settings.source, in: listing, fallbackDisplay: CGMainDisplayID())
        switch source {
        case .display(let id): return listing.displays.first { $0.id == id }?.name ?? "Main display"
        case .window(let id): return listing.windows.first { $0.id == id }?.displayName ?? "Window"
        case .area(_, let rect): return "Area \(Int(rect.width)) × \(Int(rect.height))"
        }
    }

    public func isSelected(display: DisplayItem) -> Bool {
        let (source, _) = Self.resolve(settings.source, in: listing, fallbackDisplay: CGMainDisplayID())
        return source == .display(id: display.id)
    }
}

/// The menu bar popover: one big Record button, then source, microphone and camera choices.
@MainActor
public struct MenuBarContent: View {
    @Bindable private var model: ShellModel
    private var openEditor: () -> Void
    private var openPermissions: () -> Void

    public init(
        model: ShellModel,
        openEditor: @escaping () -> Void = {},
        openPermissions: @escaping () -> Void = {}
    ) {
        self.model = model
        self.openEditor = openEditor
        self.openPermissions = openPermissions
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            recordButton
            banners
            Divider()
            sourceSection
            Divider()
            micSection
            cameraSection
            Divider()
            countdownSection
            Divider()
            footer
        }
        .padding(12)
        .frame(width: 300)
        .excludedFromCapture()
        .task { await model.refreshSources() }
    }

    // MARK: Record

    private var recordButton: some View {
        Button {
            if model.isCountingDown { model.cancelCountdown() } else { Task { await model.toggleRecording() } }
        } label: {
            HStack {
                Image(systemName: model.isRecording ? "stop.fill" : model.isCountingDown ? "xmark" : "record.circle.fill")
                Text(recordTitle).fontWeight(.semibold)
                Spacer()
                Text(model.isRecording ? StopShortcut.display : model.sourceTitle)
                    .font(.caption).opacity(0.8).lineLimit(1)
            }
            .padding(.vertical, 6).padding(.horizontal, 8)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(.red)
        .disabled(!model.canStart && !model.isRecording && !model.isCountingDown)
    }

    private var recordTitle: String {
        switch model.phase {
        case .recording: return "Stop Recording"
        case .preparing: return model.isCountingDown ? "Cancel Countdown" : "Starting…"
        case .saving: return "Saving…"
        default: return "Record"
        }
    }

    @ViewBuilder private var banners: some View {
        if case .failed(let message) = model.phase {
            Banner(text: message, systemImage: "exclamationmark.triangle.fill", tint: .orange) { model.dismissError() }
        }
        if let notice = model.notice {
            Banner(text: notice, systemImage: "info.circle.fill", tint: .blue) { model.dismissNotice() }
        }
        if !model.missingRequiredPermissions.isEmpty {
            Button("Screen recording is not allowed yet. Fix…", action: openPermissions)
                .buttonStyle(.link).font(.caption)
        }
    }

    // MARK: Source

    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionTitle("Source")
            ForEach(model.listing.displays) { display in
                SourceRow(title: display.name, systemImage: "display", selected: model.isSelected(display: display)) {
                    model.selectSource(display.isMain ? nil : .display(id: display.id))
                }
            }
            Menu {
                if model.listing.windows.isEmpty { Text("No windows found") }
                ForEach(model.listing.windows) { window in
                    Button(window.displayName) { model.selectSource(.window(id: window.id)) }
                }
            } label: {
                Label(selectedWindowTitle ?? "Window…", systemImage: "macwindow")
            }
            .menuStyle(.borderlessButton)
            Button {
                Task { await model.chooseArea() }
            } label: {
                Label(selectedAreaTitle ?? "Select Area…", systemImage: "rectangle.dashed")
            }
            .buttonStyle(.plain)
            if let error = model.sourceError {
                Text(error).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var selectedWindowTitle: String? {
        if case .window = model.settings.source { return model.sourceTitle }
        return nil
    }

    private var selectedAreaTitle: String? {
        if case .area = model.settings.source { return model.sourceTitle }
        return nil
    }

    // MARK: Devices

    private var micSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle("Microphone", isOn: Binding(get: { model.settings.micEnabled }, set: { model.setMicEnabled($0) }))
            if model.settings.micEnabled {
                DevicePicker(
                    devices: model.microphones,
                    selection: Binding(get: { model.settings.micDeviceID }, set: { model.selectMicrophone($0) }))
            }
        }
    }

    private var cameraSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle("Camera", isOn: Binding(get: { model.settings.cameraEnabled }, set: { model.setCameraEnabled($0) }))
            if model.settings.cameraEnabled {
                DevicePicker(
                    devices: model.cameras,
                    selection: Binding(get: { model.settings.cameraDeviceID }, set: { model.selectCamera($0) }))
                Picker("Shape", selection: Binding(
                    get: { ShapeKind(model.settings.cameraShape) }, set: { model.selectShape($0.shape) })
                ) {
                    ForEach(ShapeKind.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                if model.settings.cameraShape != .circle {
                    HStack {
                        Text("Corners").font(.caption).foregroundStyle(.secondary)
                        Slider(value: Binding(get: { model.settings.bubbleRoundness }, set: { model.selectRoundness($0) }), in: 0...1)
                    }
                }
            }
        }
    }

    private var countdownSection: some View {
        Picker("Countdown", selection: Binding(get: { model.settings.countdownSeconds }, set: { model.setCountdown($0) })) {
            ForEach(ShellSettings.countdownChoices, id: \.self) { Text($0 == 0 ? "Off" : "\($0) s").tag($0) }
        }
        .pickerStyle(.segmented)
    }

    // MARK: Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            if model.lastSaved != nil || model.latestProject != nil { Button("Open Last Recording", action: openEditor).buttonStyle(.plain) }
            Button("Permissions…", action: openPermissions).buttonStyle(.plain)
            Button("Quit notscreenstudio") { NSApplication.shared.terminate(nil) }.buttonStyle(.plain)
        }
    }
}

private struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(text.uppercased()).font(.caption2).foregroundStyle(.secondary) }
}

private struct SourceRow: View {
    let title: String
    let systemImage: String
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack {
                Label(title, systemImage: systemImage)
                Spacer()
                if selected { Image(systemName: "checkmark") }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct DevicePicker: View {
    let devices: [DeviceItem]
    @Binding var selection: String?
    var body: some View {
        Picker("Device", selection: Binding(
            get: { ShellModel.pickDevice(preferred: selection, from: devices) ?? "" },
            set: { selection = $0.isEmpty ? nil : $0 })
        ) {
            if devices.isEmpty { Text("None found").tag("") }
            ForEach(devices) { Text($0.name).tag($0.id) }
        }
        .labelsHidden()
        .disabled(devices.isEmpty)
    }
}

private struct Banner: View {
    let text: String
    let systemImage: String
    let tint: Color
    let dismiss: () -> Void
    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: systemImage).foregroundStyle(tint)
            Text(text).font(.caption).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(action: dismiss) { Image(systemName: "xmark") }.buttonStyle(.plain)
        }
        .padding(8)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }
}
