import SwiftUI
import NSSCore

/// Shell worker owns this folder: menu bar, source picker, recording HUD, camera bubble overlay.
public struct MenuBarContent: View {
    public var openEditor: () -> Void
    public init(openEditor: @escaping () -> Void = {}) { self.openEditor = openEditor }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button("Record Screen (stub)") {}
            Button("Open Editor", action: openEditor)
            Divider()
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
        .padding(8)
    }
}
