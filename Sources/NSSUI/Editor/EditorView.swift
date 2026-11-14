import SwiftUI
import NSSCore
import NSSExport
import NSSMotion
import NSSProject
import NSSRender

extension EditorDependencies {
    /// Production wiring: the on-disk project store plus whichever motion/render/export implementations are linked in.
    public static func live() -> EditorDependencies {
        let renderer: any FrameRenderer = PassthroughRenderer()
        return EditorDependencies(
            store: FileProjectStore(),
            motionFactory: SpringMotionModel.factory,
            renderer: renderer,
            exporter: MP4Exporter(motionFactory: SpringMotionModel.factory, renderer: renderer),
            motionFactoryForAspect: { SpringMotionModel.factory(sourceAspect: $0) }
        )
    }
}

/// Everything alive while one project is open in the editor.
@MainActor
final class EditorSession {
    let model: EditorModel
    let engine: PreviewEngine
    let thumbnails = ThumbnailStore()

    init(model: EditorModel) {
        self.model = model
        engine = PreviewEngine(model: model)
        model.changeHandler = { [engine] change in engine.modelChanged(change) }
        thumbnails.load(url: model.reference.url.appendingPathComponent(model.project.assets.screenFile), duration: model.duration)
    }

    func close() {
        engine.teardown()
        thumbnails.cancel()
        model.changeHandler = nil
    }
}

/// Editor window for one project. `EditorView()` without arguments shows an empty state (used until the shell wires it up).
public struct EditorView: View {
    private let reference: ProjectReference?
    private let dependencies: EditorDependencies?
    @State private var session: EditorSession?
    @State private var loadError: String?

    public init() {
        reference = nil
        dependencies = nil
    }

    public init(reference: ProjectReference, dependencies: EditorDependencies) {
        self.reference = reference
        self.dependencies = dependencies
    }

    public var body: some View {
        Group {
            if let session {
                EditorContent(session: session).id(ObjectIdentifier(session))
            } else if let loadError {
                ContentUnavailableView("Couldn't open project", systemImage: "exclamationmark.triangle", description: Text(loadError))
            } else if reference == nil {
                ContentUnavailableView("No project open", systemImage: "film", description: Text("Record something or open a project to edit it."))
            } else {
                ProgressView("Opening…")
            }
        }
        .frame(minWidth: 960, minHeight: 600)
        .task(id: reference) { await load() }
        .onDisappear { session?.close() }
    }

    private func load() async {
        guard let reference, let dependencies else { return }
        do {
            let project = try await dependencies.store.load(reference)
            let track = try await dependencies.store.loadCursorTrack(for: reference, assets: project.assets)
            session?.close()
            session = EditorSession(model: EditorModel(project: project, reference: reference, track: track, dependencies: dependencies))
        } catch {
            loadError = error.localizedDescription
        }
    }
}

struct EditorContent: View {
    let session: EditorSession
    @State private var exportModel: ExportModel?

    private var model: EditorModel { session.model }
    private var engine: PreviewEngine { session.engine }

    var body: some View {
        HSplitView {
            VStack(spacing: 8) {
                ZStack(alignment: .top) {
                    PreviewView(model: model, engine: engine)
                    if model.pickingFocusFor != nil {
                        Text("Click the preview to set the zoom focus")
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(.regularMaterial, in: Capsule()).padding(8)
                    }
                }
                .frame(minHeight: 260)
                transport
                EditorTimelineView(model: model, thumbnails: session.thumbnails, seek: { engine.seek(to: $0) })
                    .padding(.horizontal, 12)
            }
            .padding(.bottom, 8)
            InspectorView(model: model)
        }
        .toolbar { toolbar }
        .sheet(item: $exportModel) { m in
            ExportSheet(export: m, close: { exportModel = nil })
        }
    }

    private var transport: some View {
        HStack(spacing: 14) {
            Button { engine.step(frames: -1) } label: { Image(systemName: "backward.frame.fill") }
                .keyboardShortcut(.leftArrow, modifiers: []).help("Previous frame")
            Button { model.isPlaying ? engine.pause() : engine.play() } label: {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill").frame(width: 20)
            }
            .keyboardShortcut(.space, modifiers: []).help("Play / pause")
            Button { engine.step(frames: 1) } label: { Image(systemName: "forward.frame.fill") }
                .keyboardShortcut(.rightArrow, modifiers: []).help("Next frame")
            Text("\(TimelineGeometry.label(for: model.playhead)) / \(TimelineGeometry.label(for: model.duration))")
                .font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            Button { model.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                .disabled(!model.canUndo).keyboardShortcut("z", modifiers: .command).help("Undo")
            Button { model.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                .disabled(!model.canRedo).keyboardShortcut("z", modifiers: [.command, .shift]).help("Redo")
            Button("Export…") { exportModel = ExportModel(editor: model) }
        }
    }
}

extension ExportModel: Identifiable {
    public nonisolated var id: ObjectIdentifier { ObjectIdentifier(self) }
}
