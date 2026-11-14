import AppKit
import SwiftUI

extension NSWindow {
    /// Keeps this window out of screen recordings and screenshots. The recorder also excludes the whole app
    /// by process in its capture filter; this is the second layer for windows the filter does not know yet.
    @MainActor
    public func excludeFromCapture() { sharingType = .none }
}

/// Marks the hosting window as excluded from capture as soon as the view lands in it.
private struct CaptureExclusionMarker: NSViewRepresentable {
    final class MarkerView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.excludeFromCapture()
        }
    }
    func makeNSView(context: Context) -> MarkerView { MarkerView() }
    func updateNSView(_ nsView: MarkerView, context: Context) { nsView.window?.excludeFromCapture() }
}

extension View {
    /// Keeps the window that shows this view out of recordings (`NSWindow.sharingType = .none`).
    public func excludedFromCapture() -> some View {
        background(CaptureExclusionMarker().frame(width: 0, height: 0))
    }
}
