import AppKit

/// Single owner of ChatGPT's Show Mini keymap entry (`openAvatarOverlay`, default ⌥Space).
///
/// Several features can ask for Mini to be unbound: the user's "Disable Show Mini" toggle,
/// and Quick Chat when its shortcut is the same as Mini's. Mini is unbound while at least
/// one reason is active and restored once none are (see research/02-show-mini.md).
/// ChatGPT reads the keymap only at launch, so changes need a ChatGPT restart, which is
/// offered from the menu but never done automatically.
@MainActor
final class ShowMiniController {
    enum Reason: Hashable { case userDisabled, quickChatShortcut }

    static let target = KeymapOverride.Target(
        commandID: "openAvatarOverlay",
        legacyCommandID: "focusQuickChat",
        key: nil,
        displayName: "Show Mini",
        stateName: "DisableShowMini"
    )

    /// ChatGPT's macOS default for Show Mini.
    static let defaultAccelerator = "Alt+Space"

    private let keymap: KeymapOverrideGroup
    private let log = Log.make("ShowMini")
    private(set) var reasons: Set<Reason> = []
    private(set) var restarting = false

    init(keymap: KeymapOverride? = nil) {
        self.keymap = KeymapOverrideGroup([keymap ?? KeymapOverride(target: Self.target)])
    }

    var isUnbound: Bool { !reasons.isEmpty }

    /// Adds or removes a reason. Throws (leaving the reasons unchanged) if the keymap
    /// can't be written.
    func set(_ reason: Reason, active: Bool) throws {
        let wasUnbound = isUnbound
        var updated = reasons
        if active { updated.insert(reason) } else { updated.remove(reason) }
        let nowUnbound = !updated.isEmpty
        if nowUnbound, !wasUnbound {
            try keymap.apply()
            log.info("Unbound Show Mini (\(String(describing: updated), privacy: .public))")
        } else if !nowUnbound, wasUnbound {
            keymap.restore()
            log.info("Restored Show Mini")
        }
        if nowUnbound != wasUnbound { changedSinceOffer = true }
        reasons = updated
    }

    // MARK: Mini's shortcut

    /// The accelerators Show Mini uses when it isn't unbound by us: the user's own entries
    /// (or the legacy alias's), else ChatGPT's default. Empty means the user unbound it themselves.
    var userAccelerators: [String] {
        let override = keymap.overrides[0]
        var entries = override.currentEntries() ?? []
        if let backup = override.loadState().backup {
            // While we hold the override, our marker stands in for the backed-up entries.
            // Legacy alias entries stay in the file, so they still count once those are back.
            entries = entries.filter { !override.isOurs($0) }
                + backup.priorEntries.compactMap { try? OrderedJSON.parse($0) }
        }
        let relevant = KeymapOverride.effectiveEntries(for: Self.target.commandID,
                                                       legacy: Self.target.legacyCommandID, in: entries)
        if relevant.isEmpty { return [Self.defaultAccelerator] }
        return Self.accelerators(in: relevant)
    }

    private static func accelerators(in entries: [OrderedJSON]) -> [String] {
        if entries.contains(where: { $0["key"] == .null }) { return [] }
        return entries.compactMap { if case .string(let key)? = $0["key"] { key } else { nil } }
    }

    /// Whether `shortcut` is one of Show Mini's shortcuts.
    func conflicts(with shortcut: Shortcut) -> Bool {
        userAccelerators.contains { Shortcut(accelerator: $0) == shortcut }
    }

    /// Mini's shortcut for display, e.g. "⌥Space".
    var userShortcutDescription: String? {
        userAccelerators.first.map { Shortcut(accelerator: $0)?.displayString ?? $0 }
    }

    // MARK: Restart

    var restartPending: Bool { keymap.restartPending }

    /// "Restart ChatGPT to …" item, when ChatGPT still runs with an outdated keymap.
    func restartMenuItem() -> NSMenuItem? {
        guard restartPending, !restarting else { return nil }
        let title = isUnbound ? "Restart ChatGPT to Apply" : "Restart ChatGPT to Restore Show Mini"
        return ActionMenuItem(title) { [weak self] in self?.restartChatGPT() }
    }

    /// Set when Mini's binding flips; cleared by `offerRestartIfNeeded()` / `clearRestartOffer()`,
    /// so only a user change made since then can prompt.
    private var changedSinceOffer = false

    /// Forgets binding changes made so far without prompting (e.g. features restored at launch).
    func clearRestartOffer() { changedSinceOffer = false }

    /// Call after a user action that may have changed Mini's binding. Asks to restart
    /// ChatGPT only if that action flipped the binding and the running ChatGPT now
    /// disagrees with the keymap it launched with (`restartPending`; false when ChatGPT
    /// isn't running, or when the user flipped back to what it launched with).
    /// "Later" leaves the "Restart ChatGPT to …" menu item as the reminder.
    func offerRestartIfNeeded() {
        guard changedSinceOffer else { return }
        changedSinceOffer = false
        guard restartPending, !restarting else { return }
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Restart ChatGPT now?"
        let state = isUnbound ? "stays active" : "stays off"
        alert.informativeText = "ChatGPT reads keyboard shortcuts only when it launches, so the Show Mini "
            + "shortcut \(state) until it restarts.\n\nYou can also restart later from the menu."
        alert.addButton(withTitle: "Restart ChatGPT")
        alert.addButton(withTitle: "Later")
        guard alert.runModal() == .alertFirstButtonReturn else {
            log.info("User postponed ChatGPT restart")
            return
        }
        guard restartPending else { return } // state may have changed while the alert was up
        restartChatGPT()
    }

    private func restartChatGPT() {
        restarting = true
        log.info("User requested ChatGPT restart to apply keymap")
        Task { @MainActor [weak self] in
            defer { self?.restarting = false }
            do {
                try await ChatGPTApp.restart()
            } catch {
                self?.log.error("Restart failed: \(error.localizedDescription, privacy: .public)")
                NSApp.activate()
                NSAlert(error: error).runModal()
            }
        }
    }
}
