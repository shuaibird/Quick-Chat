#if DEBUG
import Foundation

/// Headless self-test of the keymap overrides. Run a debug build with:
///   QUICKCHAT_SELFTEST=keymap .build/debug/QuickChat
/// Works only on temp directories (CODEX_HOME is pointed at a temp dir); never touches ~/.codex.
@MainActor
enum KeymapSelfTest {
    private static var failures = 0

    private static func check(_ cond: Bool, _ name: String, _ detail: @autoclosure () -> String = "") {
        if cond { print("  ok   \(name)") } else { failures += 1; print("  FAIL \(name) \(detail())") }
    }

    static func run() -> Bool {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("keymap-selftest-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        // Safety net: even a default-resolved keymap path must land in the temp dir.
        let safeCodexHome = root.appendingPathComponent("codex-home", isDirectory: true).path
        setenv("CODEX_HOME", safeCodexHome, 1)
        var n = 0
        func fresh(_ target: KeymapOverride.Target = ShowMiniController.target) -> (KeymapOverride, URL) {
            n += 1
            let codexHome = root.appendingPathComponent("case\(n)/codex", isDirectory: true)
            let km = KeymapOverride(target: target, keymapURL: codexHome.appendingPathComponent("keybindings.json"),
                                    stateURL: root.appendingPathComponent("case\(n)/state/\(target.stateName).json"))
            return (km, codexHome)
        }
        func text(_ url: URL) -> String? { (try? Data(contentsOf: url)).map { String(decoding: $0, as: UTF8.self) } } // keeps a BOM
        func put(_ s: String, _ url: URL) {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? Data(s.utf8).write(to: url, options: .atomic)
        }
        let markerFile = "[\n  {\n    \"command\": \"openAvatarOverlay\",\n    \"key\": null\n  }\n]\n"

        print("1. no file (and no ~/.codex dir)")
        do {
            let (km, home) = fresh()
            try km.apply()
            check(text(km.keymapURL) == markerFile, "file created with marker", text(km.keymapURL) ?? "nil")
            check(km.hasBackup, "backup persisted")
            try km.apply()
            check(text(km.keymapURL) == markerFile, "apply idempotent")
            check(try km.restore() == .deletedFile, "restore deletes created file")
            check(!FileManager.default.fileExists(atPath: home.path), "created directory removed")
            check(try km.restore() == .nothingToRestore, "restore idempotent")
        } catch { check(false, "case 1 threw", "\(error)") }

        print("2. file with other entries + unknown fields")
        do {
            let (km, _) = fresh()
            let original = """
            [
              {"command": "newTask", "key": "Cmd+N", "x-note": {"a": [1, 2.50e3]}},
              {"command": "toggleSidebar", "key": null}
            ]
            """
            put(original, km.keymapURL)
            try km.apply()
            let after = text(km.keymapURL) ?? ""
            let parsed = try OrderedJSON.parse(after)
            guard case .array(let items) = parsed else { throw CocoaError(.fileReadCorruptFile) }
            check(items.count == 3 && km.isOurs(items[2]), "marker appended, others kept", after)
            check(after.contains("\"x-note\": {\n      \"a\": [\n        1,\n        2.50e3"), "unknown field + number lexeme preserved", after)
            check(km.isApplied(items), "effective state disabled")
            try km.restore()
            let restored = try OrderedJSON.parse(text(km.keymapURL) ?? "")
            check(restored == (try OrderedJSON.parse(original)), "restore == original (semantically)")
        } catch { check(false, "case 2 threw", "\(error)") }

        print("3. existing openAvatarOverlay binding (Ctrl+Alt+M) + legacy alias")
        do {
            let (km, _) = fresh()
            let original = """
            [{"command":"focusQuickChat","key":"Cmd+Shift+K"},{"command":"openAvatarOverlay","key":"Ctrl+Alt+M"},{"command":"newTask","key":"Cmd+N"},{"command":"openAvatarOverlay","key":"F5"}]
            """
            put(original, km.keymapURL)
            try km.apply()
            let items = { if case .array(let a) = try OrderedJSON.parse(text(km.keymapURL) ?? "") { return a }; return [] }
            let a1 = try items()
            check(a1.filter { KeymapOverride.command(of: $0) == "openAvatarOverlay" }.count == 1
                  && km.isOurs(a1[1]), "both bindings replaced by marker in place")
            check(a1.contains { KeymapOverride.command(of: $0) == "focusQuickChat" }, "legacy entry left alone")
            try km.restore()
            // Prior entries come back grouped at the first one's position (ChatGPT sorts by command on write anyway).
            let a2 = try items().map(\.compact)
            check(a2 == [#"{"command":"focusQuickChat","key":"Cmd+Shift+K"}"#, #"{"command":"openAvatarOverlay","key":"Ctrl+Alt+M"}"#,
                         #"{"command":"openAvatarOverlay","key":"F5"}"#, #"{"command":"newTask","key":"Cmd+N"}"#],
                  "prior bindings restored (same entries, their relative order kept)", "\(a2)")

            // User edits the entry while enabled → disable must not touch it.
            try km.apply()
            put(#"[{"command":"openAvatarOverlay","key":"Ctrl+Alt+X"}]"#, km.keymapURL)
            check(try km.restore() == .userChangedEntry, "user edit detected")
            check(text(km.keymapURL)?.contains("Ctrl+Alt+X") == true, "user edit preserved")
            check(!km.hasBackup, "backup dropped")
        } catch { check(false, "case 3 threw", "\(error)") }

        print("4. malformed / wrong-schema / blank files")
        do {
            let (km, _) = fresh()
            for bad in ["[{\"command\":\"newTask\",\"key\":\"Cmd+N\"},]", "{\"command\":\"x\"}",
                        "[{\"command\":\"newTask\"}]", "\u{FEFF}[]", "[{\"command\":1,\"key\":null}]"] {
                put(bad, km.keymapURL)
                var threw = false
                do { try km.apply() } catch is KeymapOverride.KeymapError { threw = true }
                check(threw && text(km.keymapURL) == bad && !km.hasBackup, "rejects \(bad.debugDescription)")
            }
            put("  \n", km.keymapURL)
            try km.apply()
            check(text(km.keymapURL) == markerFile, "blank file treated as []")
            try km.restore()
            check(text(km.keymapURL) == "  \n", "blank file restored byte-for-byte")
        } catch { check(false, "case 4 threw", "\(error)") }

        print("5. crash recovery through KeymapOverrideGroup (CODEX_HOME env)")
        do {
            let (km, home) = fresh()
            setenv("CODEX_HOME", home.path, 1)
            defer { setenv("CODEX_HOME", safeCodexHome, 1) }
            check(KeymapOverride.defaultKeymapURL() == km.keymapURL, "CODEX_HOME honoured")
            let original = #"[{"command":"openAvatarOverlay","key":"Ctrl+Alt+M"}]"#
            put(original, km.keymapURL)
            let f1 = KeymapOverrideGroup([km])
            try f1.apply()
            check(text(km.keymapURL) == markerFile, "instance 1 applied")
            // Simulated SIGKILL: f1.restore() never runs. A new instance starts.
            let f2 = KeymapOverrideGroup([km])
            check(text(km.keymapURL)?.contains("Ctrl+Alt+M") == true && !km.hasBackup, "init recovered prior state")
            try f2.apply()
            let backup = km.loadState().backup
            check(backup?.priorEntries == [#"{"command":"openAvatarOverlay","key":"Ctrl+Alt+M"}"#],
                  "re-enable backed up the user's binding, not our marker", "\(String(describing: backup))")
            f2.restore(); f2.restore()
            check(try OrderedJSON.parse(text(km.keymapURL) ?? "") == (try OrderedJSON.parse(original)), "disable restored original")

            // Kill with apply() reused path: marker present + backup → apply reuses backup.
            try km.apply()
            let b1 = km.loadState().backup
            check(try km.apply() == .alreadyApplied && km.loadState().backup == b1, "apply with leftover backup + marker reuses backup")
            try km.restore()
        } catch { check(false, "case 5 threw", "\(error)") }

        print("6. restart-pending logic")
        do {
            var (km, _) = fresh()
            var clock = Date(timeIntervalSince1970: 1_000)
            km.now = { clock }
            let launchedBefore = Date(timeIntervalSince1970: 500)
            check(!km.restartPending(launchDate: launchedBefore), "no writes → not pending")
            try km.apply()
            check(km.restartPending(launchDate: launchedBefore), "enabled after launch → pending")
            check(!km.restartPending(launchDate: Date(timeIntervalSince1970: 1_500)), "launched after write → applied")
            clock = Date(timeIntervalSince1970: 2_000)
            try km.restore()
            check(!km.restartPending(launchDate: launchedBefore), "enable+disable while running → not pending")
            check(km.restartPending(launchDate: Date(timeIntervalSince1970: 1_500)), "disable after launch → pending (still unbound)")
            check(!km.restartPending(launchDate: nil), "unknown launch date → not pending")
        } catch { check(false, "case 6 threw", "\(error)") }


        print("7. a keyed override sharing the file with the Mini unbind")
        do {
            let (mini, _) = fresh()
            let popout = KeymapOverride(target: .init(commandID: "hotkeyWindow", key: "Control+Alt+Shift+F19", displayName: "Popout Window", stateName: "PopoutWindow"), keymapURL: mini.keymapURL,
                                        stateURL: mini.stateURL.deletingLastPathComponent().appendingPathComponent("PopoutWindow.json"))
            let original = #"[{"command":"newTask","key":"Cmd+N"},{"command":"hotkeyWindow","key":"Ctrl+Alt+P"}]"#
            put(original, mini.keymapURL)
            try popout.apply()
            try mini.apply()
            let entries = try mini.read(mini.keymapURL).entries
            check(popout.isApplied(entries) && mini.isApplied(entries), "both overrides applied", "\(entries.map(\.compact))")
            check(entries.contains { $0.compact == #"{"command":"hotkeyWindow","key":"Control+Alt+Shift+F19"}"# }, "popout marker written")
            check(!popout.isApplied([try OrderedJSON.parse(#"{"command":"hotkeyWindow","key":null}"#)]), "unbound ≠ applied for keyed target")
            // Restore in the opposite order to apply.
            check(try popout.restore() == .restored, "popout restored")
            let afterEntries = try mini.read(mini.keymapURL).entries
            let afterPopout = afterEntries.map(\.compact)
            check(afterPopout.contains(#"{"command":"hotkeyWindow","key":"Ctrl+Alt+P"}"#) && mini.isApplied(afterEntries),
                  "user's popout binding back, Mini override untouched", "\(afterPopout)")
            try mini.restore()
            check(try OrderedJSON.parse(text(mini.keymapURL) ?? "") == (try OrderedJSON.parse(original)), "file back to original")
        } catch { check(false, "case 7 threw", "\(error)") }


        print("8. Show Mini controller: reasons + Quick Chat shortcut conflicts")
        do {
            let (km, _) = fresh()
            let mini = ShowMiniController(keymap: km)
            check(Shortcut(accelerator: "Alt+Space") == .optionSpace, "parses Alt+Space")
            check(Shortcut(accelerator: "CmdOrCtrl+Shift+K")?.displayString == "⇧⌘K", "parses CmdOrCtrl+Shift+K")
            check(Shortcut(accelerator: "Control+Alt+Shift+F19")?.displayString == "⌃⌥⇧F19", "parses F19")
            check(Shortcut(accelerator: "Alt+MediaPlayPause") == nil, "unknown key → nil")
            check(mini.conflicts(with: .optionSpace), "no file → Mini on default ⌥Space conflicts")
            try mini.set(.quickChatShortcut, active: true)
            check(text(km.keymapURL) == markerFile, "conflict unbinds Mini")
            check(mini.conflicts(with: .optionSpace), "Mini's shortcut read from backup while unbound")
            try mini.set(.userDisabled, active: true)
            try mini.set(.quickChatShortcut, active: false)
            check(text(km.keymapURL) == markerFile, "still unbound while the user toggle is on")
            try mini.set(.userDisabled, active: false)
            check(!FileManager.default.fileExists(atPath: km.keymapURL.path), "restored once no reason is left")

            put(#"[{"command":"openAvatarOverlay","key":"Control+Alt+M"}]"#, km.keymapURL)
            check(!mini.conflicts(with: .optionSpace), "user rebound Mini → ⌥Space is free")
            check(mini.conflicts(with: Shortcut(accelerator: "Control+Alt+M")!), "same as user's Mini binding conflicts")
            check(mini.userShortcutDescription == "⌃⌥M", "describes Mini's shortcut")
            put(#"[{"command":"openAvatarOverlay","key":null}]"#, km.keymapURL)
            check(!mini.conflicts(with: .optionSpace) && mini.userShortcutDescription == nil, "user unbound Mini → no conflict")
        } catch { check(false, "case 8 threw", "\(error)") }

        print("9. Show Mini bound only through the legacy alias")
        do {
            let (km, _) = fresh()
            let mini = ShowMiniController(keymap: km)
            put(#"[{"command":"focusQuickChat","key":"Cmd+Shift+K"}]"#, km.keymapURL)
            let cmdShiftK = Shortcut(accelerator: "Cmd+Shift+K")!
            check(mini.userShortcutDescription == "⇧⌘K" && !mini.conflicts(with: .optionSpace), "alias read while bound")
            try mini.set(.userDisabled, active: true)
            check(mini.userShortcutDescription == "⇧⌘K", "alias still read while unbound",
                  mini.userShortcutDescription ?? "nil")
            check(!mini.conflicts(with: .optionSpace) && mini.conflicts(with: cmdShiftK), "conflicts follow the alias while unbound")
            try mini.set(.userDisabled, active: false)
        } catch { check(false, "case 9 threw", "\(error)") }

        print("10. group rolls back when a later override fails with a non-keymap error")
        do {
            let (first, _) = fresh(.init(commandID: "hotkeyWindow", key: "Control+Alt+Shift+F19",
                                         displayName: "Popout Window", stateName: "PopoutWindow"))
            // State directory path is a regular file, so saving the second override's backup fails.
            let blocker = first.stateURL.deletingLastPathComponent().appendingPathComponent("blocker")
            put("", blocker)
            let second = KeymapOverride(target: ShowMiniController.target, keymapURL: first.keymapURL,
                                        stateURL: blocker.appendingPathComponent("DisableShowMini.json"))
            let original = #"[{"command":"hotkeyWindow","key":"Ctrl+Alt+P"}]"#
            put(original, first.keymapURL)
            var threw = false
            do { try KeymapOverrideGroup([first, second]).apply() } catch { threw = true }
            check(threw, "apply threw")
            check(try OrderedJSON.parse(text(first.keymapURL) ?? "") == (try OrderedJSON.parse(original)) && !first.hasBackup,
                  "first override rolled back", text(first.keymapURL) ?? "nil")
        } catch { check(false, "case 10 threw", "\(error)") }

        print(failures == 0 ? "keymap self-test: ALL PASSED" : "keymap self-test: \(failures) FAILED")
        return failures == 0
    }
}
#endif
