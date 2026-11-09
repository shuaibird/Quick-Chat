import AppKit

/// Shared helpers for talking to the new ChatGPT app (Electron, bundle id com.openai.codex).
/// Shared file: feature implementers should not edit it; put feature-specific helpers
/// in their own Features/<Name>/ folder.
@MainActor
enum ChatGPTApp {
    nonisolated static let bundleIdentifier = "com.openai.codex"
    private static let log = Log.make("ChatGPTApp")

    static var runningApp: NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .first { !$0.isTerminated }
    }

    /// Location of the installed app, if any.
    static var appURL: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
    }

    /// Gracefully quits ChatGPT (if running), waits for it to exit, then relaunches it.
    /// If ChatGPT was not running it is simply launched.
    static func restart(timeout: TimeInterval = 15) async throws {
        if let app = runningApp {
            log.info("Terminating ChatGPT (pid \(app.processIdentifier))")
            app.terminate()
            let deadline = Date().addingTimeInterval(timeout)
            while !app.isTerminated {
                if Date() > deadline {
                    throw FeatureError("ChatGPT did not quit within \(Int(timeout)) seconds.",
                                       recoverySuggestion: "Quit ChatGPT manually and reopen it.")
                }
                try await Task.sleep(for: .milliseconds(200))
            }
        }
        try await launch()
    }

    /// Launches (or activates) ChatGPT.
    @discardableResult
    static func launch(activate: Bool = true) async throws -> NSRunningApplication {
        guard let url = appURL else {
            throw FeatureError("ChatGPT (\(bundleIdentifier)) is not installed.")
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = activate
        log.info("Launching ChatGPT at \(url.path, privacy: .public)")
        return try await NSWorkspace.shared.openApplication(at: url, configuration: config)
    }
}
