import Foundation

/// Applies and restores several `KeymapOverride`s (different commands, same keymap file)
/// as one unit, and handles crash recovery and restart awareness for them.
///
/// ChatGPT reads the keymap only at launch, so changes apply on its next start; callers
/// surface `restartPending` and let the user restart ChatGPT (never automatically).
@MainActor
final class KeymapOverrideGroup {
    private(set) var overrides: [KeymapOverride]
    private let log = Log.make("Keymap")

    init(_ overrides: [KeymapOverride]) {
        self.overrides = overrides
        recoverLeftoverBackups()
    }

    /// Backups left by a run that was killed (SIGKILL/crash) are restored right away, so
    /// the keymap is back to the user's state. If the feature is on, apply() then
    /// re-applies from fresh, correct backups (never backing up our own markers).
    private func recoverLeftoverBackups() {
        for keymap in overrides where keymap.hasBackup {
            keymap.log.notice("Found leftover backup from a previous run; restoring")
            do {
                try keymap.restore()
            } catch {
                keymap.log.error("Crash recovery failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Applies every override, or none: if one fails, all are restored (including the failing
    /// one, which may have written its marker before a later step such as saving state failed).
    func apply() throws {
        overrides = overrides.map { $0.reresolved() } // CODEX_HOME may have changed
        do {
            for keymap in overrides {
                let outcome = try keymap.apply()
                keymap.log.info("Applied (\(String(describing: outcome), privacy: .public)) to \(keymap.keymapURL.path, privacy: .public)")
            }
        } catch {
            let detail = (error as? KeymapOverride.KeymapError)?.detail ?? String(describing: error)
            log.error("Apply failed: \(error.localizedDescription, privacy: .public) [\(detail, privacy: .public)]")
            restore()
            throw (error as? KeymapOverride.KeymapError)?.featureError ?? error
        }
    }

    /// Restores every override (reverse order). Idempotent; a failed restore keeps its
    /// backup for the next launch.
    func restore() {
        for keymap in overrides.reversed() {
            do {
                let outcome = try keymap.restore()
                keymap.log.info("Restored (\(String(describing: outcome), privacy: .public))")
            } catch {
                keymap.log.error("Restore failed; backup kept for next launch: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Whether the running ChatGPT loaded a keymap that differs from the file now.
    var restartPending: Bool {
        guard let app = ChatGPTApp.runningApp else { return false }
        return overrides.contains { $0.restartPending(launchDate: app.launchDate) }
    }
}
