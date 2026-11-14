import SwiftUI
import NSSCore

/// Editor worker owns this folder: preview, timeline, inspector.
public struct EditorView: View {
    public init() {}
    public var body: some View {
        VStack {
            Text("notscreenstudio editor").font(.title2)
            Text("Preview, timeline and inspector go here.").foregroundStyle(.secondary)
        }
        .frame(minWidth: 800, minHeight: 500)
    }
}
