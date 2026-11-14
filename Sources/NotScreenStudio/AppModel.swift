import AppKit
import NSSCapture
import NSSCore
import NSSExport
import NSSInput
import NSSMotion
import NSSProject
import NSSRender
import NSSUI
import Observation

/// The app's dependency container. Every module is created here and handed out as its NSSCore protocol,
/// so replacing a stub with the real module is a one-line change at its `let`.
@MainActor
@Observable
final class AppModel {
    // Swap implementations here. Each line is the only place its module is named.
    @ObservationIgnored let recordingSession: any RecordingSession = ScreenCaptureRecordingSession()
    @ObservationIgnored let inputLogger: any InputLogger = SystemInputLogger()
    @ObservationIgnored let projectStore: any ProjectStore
    @ObservationIgnored let motionFactory: MotionModelFactory = SpringMotionModel.factory
    @ObservationIgnored let renderer: any FrameRenderer = PassthroughRenderer()
    @ObservationIgnored let exporter: any Exporter

    let shell: ShellModel

    /// What the editor window needs, built from the services above.
    var editorDependencies: EditorDependencies {
        EditorDependencies(
            store: projectStore, motionFactory: motionFactory, renderer: renderer, exporter: exporter,
            motionFactoryForAspect: { SpringMotionModel.factory(sourceAspect: $0) })
    }

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
        let store = FileProjectStore()
        store.installTerminationFlush()
        projectStore = store
        exporter = StubExporter(motionFactory: motionFactory, renderer: renderer)
        shell = ShellModel(
            services: ShellServices(
                session: recordingSession,
                inputLogger: inputLogger,
                store: projectStore,
                sources: SystemSourceProvider(),
                permissions: SystemPermissions()),
            effects: AppKitShellEffects())
    }
}
