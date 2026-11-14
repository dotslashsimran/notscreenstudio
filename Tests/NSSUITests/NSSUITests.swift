import Testing
@testable import NSSUI

@Suite struct NSSUITests {
    @Test @MainActor func viewsConstruct() {
        _ = EditorView()
        _ = MenuBarContent()
    }
}
