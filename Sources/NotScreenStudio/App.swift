import AppKit
import NSSUI
import SwiftUI

@main
struct NotScreenStudioApp: App {
    @State private var app = AppModel()
    @Environment(\.openWindow) private var openWindow

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
            EditorWindowContent(model: app.shell)
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

/// Editor window. The real `EditorView` takes no project yet, so the saved recording's name is shown above it.
struct EditorWindowContent: View {
    var model: ShellModel

    var body: some View {
        VStack(spacing: 0) {
            if let saved = model.lastSaved {
                Text(saved.project.name).font(.headline).padding(.top, 8)
                Text(saved.reference.url.path).font(.caption).foregroundStyle(.secondary).padding(.bottom, 8)
            }
            EditorView()
        }
    }
}
