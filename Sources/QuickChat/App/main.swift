import AppKit

MainActor.assumeIsolated {
    #if DEBUG
    if ProcessInfo.processInfo.environment["QUICKCHAT_SELFTEST"] == "keymap" {
        exit(KeymapSelfTest.run() ? 0 : 1)
    }
    // Opens Quick Chat panel without enabling any feature (no keymap changes).
    if ProcessInfo.processInfo.environment["QUICKCHAT_DEBUG"] == "panel" {
        EditMenu.install()
        let chat = QuickChatController()
        DispatchQueue.main.async { chat.show() }
        NSApplication.shared.setActivationPolicy(.accessory)
        withExtendedLifetime(chat) { NSApplication.shared.run() }
    }
    #endif

    LegacyCleanup.run()

    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory) // menu-bar only (LSUIElement is also set in Info.plist)
    EditMenu.install()
    withExtendedLifetime(delegate) { app.run() }
}
