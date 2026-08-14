import AppKit

@main
enum KaiMDMain {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.regular)
        application.run()

        // NSApplication's delegate is weak, so keep it alive for the run loop.
        withExtendedLifetime(delegate) {}
    }
}
