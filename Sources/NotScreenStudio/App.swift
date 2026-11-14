import AppKit
import NSSCore
import NSSUI
import SwiftUI

@main
struct NotScreenStudioApp: App {
    @State private var app: AppModel
    @Environment(\.openWindow) private var openWindow

    init() {
        // `--smoke-test`: build every dependency, render one frame, exit. Used by scripts/bundle.sh and CI.
        if CommandLine.arguments.contains("--smoke-test") { SmokeTest.runAndExit() }
        _app = State(initialValue: AppModel())
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(
                model: app.shell,
                openEditor: { show("editor") },
                openPermissions: { show("permissions") })
        } label: {
            MenuBarLabel(model: app.shell, openEditor: { show("editor") }, openPermissions: { show("permissions") })
        }
        .menuBarExtraStyle(.window)

        Window("notscreenstudio", id: "editor") {
            EditorWindowContent(model: app.shell, dependencies: app.editorDependencies)
        }

        Window("Permissions", id: "permissions") {
            PermissionsView(model: app.shell)
        }
        .windowResizability(.contentSize)
    }

    private func show(_ id: String) {
        openWindow(id: id)
        NSApplication.shared.activate()
    }
}

/// The menu bar icon. It lives as long as the app, so it also launches the shell and opens windows on request.
struct MenuBarLabel: View {
    var model: ShellModel
    var openEditor: () -> Void
    var openPermissions: () -> Void

    var body: some View {
        Image(systemName: model.menuBarSymbol)
            .accessibilityLabel(model.isRecording ? "notscreenstudio, recording" : "notscreenstudio")
            .task { await model.launch() }
            .onChange(of: model.editorRequestID) { openEditor() }
            .onChange(of: model.onboardingRequestID) { openPermissions() }
    }
}

/// Editor window: opens the project that was just recorded, or an empty state before any recording.
struct EditorWindowContent: View {
    var model: ShellModel
    var dependencies: EditorDependencies

    var body: some View {
        if let reference = model.lastSaved?.reference ?? model.latestProject {
            EditorView(reference: reference, dependencies: dependencies)
        } else {
            EditorView()
        }
    }
}
