import AppKit
import SwiftUI
import NSSCore

/// Slider that groups a whole drag into a single undo step.
struct EditSlider: View {
    let model: EditorModel
    let title: String
    let value: Binding<Double>
    let range: ClosedRange<Double>
    var format: (Double) -> String = { String(format: "%.2f", $0) }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack { Text(title); Spacer(); Text(format(value.wrappedValue)).foregroundStyle(.secondary).monospacedDigit() }.font(.caption)
            Slider(value: value, in: range) { editing in
                if editing { model.beginGesture(title) } else { model.endGesture() }
            }
        }
    }
}

struct InspectorView: View {
    let model: EditorModel
    @State private var fileError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                zoomSection
                backgroundSection
                frameSection
                cursorSection
                if model.project.assets.cameraFile != nil { cameraSection }
            }
            .padding(12)
        }
        .frame(minWidth: 260, idealWidth: 280, maxWidth: 320)
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content()
        }
    }

    // MARK: Zoom

    private var zoomSection: some View {
        section("Zoom") {
            Toggle("Auto-zoom on clicks", isOn: Binding(get: { model.project.timeline.autoZoomEnabled }, set: { model.setAutoZoom($0) }))
            HStack {
                Button("Add zoom at playhead") { model.addZoomBlock() }
                Spacer()
            }
            if let z = model.selectedZoom {
                Divider()
                EditSlider(model: model, title: "Scale", value: Binding(get: { z.scale }, set: { model.setZoomScale(z.id, $0) }),
                           range: ZoomBlockEditing.scaleRange, format: { String(format: "%.1f×", $0) })
                Picker("Focus", selection: Binding(
                    get: { z.focus == .auto },
                    set: { auto in model.setZoomFocus(z.id, auto ? .auto : .manual(.center)) }
                )) {
                    Text("Auto").tag(true)
                    Text("Manual").tag(false)
                }.pickerStyle(.segmented)
                if case .manual(let p) = z.focus {
                    Text(String(format: "Focus %.0f%%, %.0f%%", p.x * 100, p.y * 100)).font(.caption).foregroundStyle(.secondary)
                    Button(model.pickingFocusFor == z.id ? "Click in the preview…" : "Pick in preview") {
                        model.pickingFocusFor = model.pickingFocusFor == z.id ? nil : z.id
                    }
                }
                Button("Delete zoom", role: .destructive) { model.deleteZoomBlock(z.id) }
            } else {
                Text("Select a zoom block on the timeline to edit it.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Background

    private var backgroundSection: some View {
        let bg = model.project.style.background
        let kind = InspectorBindings.kind(of: bg)
        return section("Background") {
            Picker("Type", selection: Binding(
                get: { kind },
                set: { k in model.setStyle(\.background, InspectorBindings.background(switchingTo: k, from: bg), name: "Background") }
            )) {
                ForEach(InspectorBindings.BackgroundKind.allCases) { Text($0.rawValue).tag($0) }
            }.labelsHidden()
            switch bg {
            case .solid(let c):
                ColorPicker("Color", selection: Binding(
                    get: { InspectorBindings.color(c) },
                    set: { model.setStyle(\.background, .solid(InspectorBindings.rgba($0)), name: "Background Color", coalescingKey: "bgcolor") }
                ))
            case .gradient(let stops, let angle):
                ForEach(Array(stops.enumerated()), id: \.offset) { i, stop in
                    ColorPicker("Stop \(i + 1)", selection: Binding(
                        get: { InspectorBindings.color(stop.color) },
                        set: { new in
                            var s = stops
                            s[i].color = InspectorBindings.rgba(new)
                            model.setStyle(\.background, .gradient(stops: s, angleDegrees: angle), name: "Gradient", coalescingKey: "stop\(i)")
                        }
                    ))
                }
                EditSlider(model: model, title: "Angle", value: Binding(
                    get: { angle },
                    set: { model.setStyle(\.background, .gradient(stops: stops, angleDegrees: $0), name: "Gradient Angle") }
                ), range: 0...360, format: { String(format: "%.0f°", $0) })
            case .image(let file):
                HStack {
                    Text(file.isEmpty ? "No image" : (file as NSString).lastPathComponent).lineLimit(1).foregroundStyle(.secondary)
                    Spacer()
                    Button("Choose…") { chooseImage() }
                }
                if let fileError { Text(fileError).font(.caption).foregroundStyle(.red) }
            case .wallpaper(let name):
                Picker("Wallpaper", selection: Binding(
                    get: { name },
                    set: { model.setStyle(\.background, .wallpaper(name: $0), name: "Wallpaper") }
                )) {
                    ForEach(InspectorBindings.wallpapers, id: \.self) { Text($0).tag($0) }
                }
            }
        }
    }

    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        // Copy into the bundle (off the main thread) so the project stays self-contained.
        let name = "background-" + url.lastPathComponent
        let dest = model.reference.url.appendingPathComponent(name)
        Task {
            let result: Result<Void, Error> = await Task.detached {
                Result {
                    if FileManager.default.fileExists(atPath: dest.path) { try FileManager.default.removeItem(at: dest) }
                    try FileManager.default.copyItem(at: url, to: dest)
                }
            }.value
            switch result {
            case .success:
                fileError = nil
                model.setStyle(\.background, .image(file: name), name: "Background Image")
            case .failure(let error):
                fileError = "Couldn't copy image: \(error.localizedDescription)"
            }
        }
    }

    // MARK: Frame

    private var frameSection: some View {
        section("Frame") {
            EditSlider(model: model, title: "Padding", value: model.styleBinding(\.padding, name: "Padding"), range: 0...0.2, format: pct)
            EditSlider(model: model, title: "Corner radius", value: model.styleBinding(\.cornerRadius, name: "Corner Radius"), range: 0...0.08, format: pct)
            EditSlider(model: model, title: "Shadow blur", value: model.styleBinding(\.shadow.radius, name: "Shadow"), range: 0...0.1, format: pct)
            EditSlider(model: model, title: "Shadow opacity", value: model.styleBinding(\.shadow.opacity, name: "Shadow"), range: 0...1, format: pct)
            Picker("Aspect", selection: model.styleBinding(\.aspectRatio, name: "Aspect Ratio")) {
                ForEach(AspectRatio.allCases, id: \.self) { Text(InspectorBindings.label(for: $0)).tag($0) }
            }.pickerStyle(.segmented)
        }
    }

    // MARK: Cursor

    private var cursorSection: some View {
        section("Cursor") {
            EditSlider(model: model, title: "Size", value: model.styleBinding(\.cursor.size, name: "Cursor Size"), range: 0.5...4, format: { String(format: "%.1f×", $0) })
            EditSlider(model: model, title: "Smoothing", value: model.styleBinding(\.cursor.smoothing, name: "Cursor Smoothing"), range: 0...1, format: pct)
            EditSlider(model: model, title: "Motion blur", value: model.styleBinding(\.cursor.motionBlur, name: "Motion Blur"), range: 0...1, format: pct)
            Toggle("Click ripples", isOn: model.styleBinding(\.cursor.clickRipples, name: "Click Ripples"))
            Toggle("Hide when idle", isOn: model.styleBinding(\.cursor.hideWhenIdle, name: "Hide Cursor When Idle"))
        }
    }

    // MARK: Camera

    private var cameraSection: some View {
        let cam = model.project.style.camera
        return section("Camera") {
            Toggle("Visible", isOn: model.styleBinding(\.camera.visible, name: "Camera Visibility"))
            Picker("Shape", selection: Binding(
                get: { InspectorBindings.kind(of: cam.shape) },
                set: { model.setStyle(\.camera.shape, InspectorBindings.shape($0), name: "Camera Shape") }
            )) {
                ForEach(InspectorBindings.ShapeKind.allCases) { Text($0.rawValue).tag($0) }
            }
            EditSlider(model: model, title: "Size", value: model.styleBinding(\.camera.size, name: "Camera Size"), range: 0.08...0.4, format: pct)
            Toggle("Border", isOn: Binding(
                get: { cam.border != nil },
                set: { model.setStyle(\.camera.border, $0 ? CameraBorder() : nil, name: "Camera Border") }
            ))
            if let b = cam.border {
                EditSlider(model: model, title: "Border width", value: Binding(
                    get: { b.width },
                    set: { model.setStyle(\.camera.border, CameraBorder(width: $0, color: b.color), name: "Camera Border") }
                ), range: 0.001...0.015, format: { String(format: "%.1f%%", $0 * 100) })
                ColorPicker("Border color", selection: Binding(
                    get: { InspectorBindings.color(b.color) },
                    set: { model.setStyle(\.camera.border, CameraBorder(width: b.width, color: InspectorBindings.rgba($0)), name: "Camera Border", coalescingKey: "bordercolor") }
                ))
            }
            Toggle("Mirror", isOn: model.styleBinding(\.camera.mirror, name: "Camera Mirror"))
            Text("Drag the bubble in the preview to move it.").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func pct(_ v: Double) -> String { String(format: "%.0f%%", v * 100) }
}
