import SwiftUI
import NSSUI

@main
struct NotScreenStudioApp: App {
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        MenuBarExtra("notscreenstudio", systemImage: "record.circle") {
            MenuBarContent(openEditor: { openWindow(id: "editor") })
        }
        .menuBarExtraStyle(.window)

        Window("notscreenstudio", id: "editor") {
            EditorView()
        }
    }
}
