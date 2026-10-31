import AppKit

/// Quick Chat: a global shortcut (default ⌥Space, changeable) toggles a floating
/// panel running chatgpt.com, in the spirit of ChatGPT Classic's companion chat.
///
/// If the shortcut is the same as ChatGPT's Show Mini shortcut, Show Mini is unbound
/// (through `ShowMiniController`) while this feature is on, so the two don't fight.
@MainActor
final class QuickChatFeature: Feature {
    let id = "miniChat" // pre-rename id; persisted, keep
    var title: String { "Quick Chat" }
    private(set) var isEnabled = false

    private let log = Log.make("QuickChat")
    private let showMini: ShowMiniController
    private var shortcut = Shortcut.load()
    private var hotKey: GlobalHotKey?
    private lazy var chat = QuickChatController()
    private let recorder = ShortcutRecorderWindow()

    init(showMini: ShowMiniController) {
        self.showMini = showMini
    }

    func enable() throws {
        guard !isEnabled else { return }
        try showMini.set(.quickChatShortcut, active: showMini.conflicts(with: shortcut))
        do {
            try registerHotKey()
        } catch {
            try? showMini.set(.quickChatShortcut, active: false)
            throw error
        }
        isEnabled = true
        log.info("Enabled with shortcut \(self.shortcut.displayString, privacy: .public)")
    }

    func disable() {
        isEnabled = false // first: closing the recorder below must not re-register the hotkey
        hotKey?.unregister()
        hotKey = nil
        recorder.close()
        chat.tearDown()
        try? showMini.set(.quickChatShortcut, active: false)
        log.info("Disabled")
    }

    /// Resizes the Quick Chat panel back to its default size (same as the Reset Window Size shortcut).
    func resetSize() { chat.resetSize() }

    private func registerHotKey() throws {
        hotKey?.unregister()
        hotKey = try GlobalHotKey(shortcut) { [weak self] in self?.chat.toggle() }
    }

    // MARK: Menu

    private var takesMiniShortcut: Bool { showMini.reasons.contains(.quickChatShortcut) }

    func menuItems() -> [NSMenuItem] {
        guard isEnabled else { return [] }
        var items: [NSMenuItem] = [
            ActionMenuItem("Change Shortcut… (\(shortcut.displayString))") { [weak self] in self?.editShortcut() },
            ActionMenuItem("Sign Out of Quick Chat") { [weak self] in self?.chat.signOut() },
        ]
        if takesMiniShortcut, let restart = showMini.restartMenuItem() { items.insert(restart, at: 0) }
        return items
    }

    private func editShortcut() {
        hotKey?.unregister() // so the current shortcut can be pressed in the recorder
        hotKey = nil
        let previous = shortcut
        let previousResetSize = chat.resetSizeShortcut
        let previousMaximize = chat.maximizeShortcut
        recorder.show(current: shortcut, resetSize: chat.resetSizeShortcut, maximize: chat.maximizeShortcut,
                      miniShortcut: showMini.userShortcutDescription, onChange: { [weak self] new in
            self?.shortcut = new
        }, onResetSizeChange: { [weak self] new in
            self?.chat.resetSizeShortcut = new
            new.saveAsResetSize()
        }, onMaximizeChange: { [weak self] new in
            self?.chat.maximizeShortcut = new
            new.saveAsMaximize()
        }, onClose: { [weak self] in
            guard let self else { return }
            guard self.isEnabled else {
                // Turned off while recording: keep the choice; the next enable() registers it.
                self.shortcut.save()
                return
            }
            do {
                try self.registerHotKey()
                try self.showMini.set(.quickChatShortcut, active: self.showMini.conflicts(with: self.shortcut))
                self.shortcut.save()
                self.log.info("Shortcut changed to \(self.shortcut.displayString, privacy: .public)")
                self.showMini.offerRestartIfNeeded()
            } catch {
                self.log.error("Shortcut rejected: \(error.localizedDescription, privacy: .public)")
                self.shortcut = previous
                // Keep the shortcuts distinct after reverting.
                if self.chat.resetSizeShortcut == previous {
                    self.chat.resetSizeShortcut = previousResetSize
                    previousResetSize.saveAsResetSize()
                }
                if self.chat.maximizeShortcut == previous {
                    self.chat.maximizeShortcut = previousMaximize
                    previousMaximize.saveAsMaximize()
                }
                try? self.registerHotKey()
                NSApp.activate()
                NSAlert(error: error).runModal()
            }
        })
    }
}
