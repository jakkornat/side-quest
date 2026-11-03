import AppKit

@main
enum SideQuestApp {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()

        app.delegate = delegate
        app.setActivationPolicy(.regular)

        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}
