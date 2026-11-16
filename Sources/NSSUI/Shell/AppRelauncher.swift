import AppKit

/// Relaunches this app bundle as a new process, then quits the current one.
@MainActor
public enum AppRelauncher {
    /// True when running from a real `.app` bundle (not `swift run`).
    public static var canRelaunch: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    public static func relaunch() {
        guard canRelaunch else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: config) { _, error in
            Task { @MainActor in
                if error == nil { NSApplication.shared.terminate(nil) }
            }
        }
    }
}
