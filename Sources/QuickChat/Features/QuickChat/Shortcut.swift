import AppKit
import Carbon.HIToolbox

/// A global keyboard shortcut: a Carbon virtual key code plus Carbon modifier flags
/// (`cmdKey`, `optionKey`, ...), as used by `RegisterEventHotKey`.
struct Shortcut: Codable, Equatable {
    var keyCode: UInt32
    var carbonModifiers: UInt32
    /// Key label captured when recorded (for keys not in `Self.keyNames`).
    var keyLabel: String?

    static let optionSpace = Shortcut(keyCode: UInt32(kVK_Space), carbonModifiers: UInt32(optionKey))
    /// Default local shortcut for resetting the Quick Chat panel's size.
    static let commandO = Shortcut(keyCode: UInt32(kVK_ANSI_O), carbonModifiers: UInt32(cmdKey), keyLabel: "O")
    /// Default local shortcut for maximizing / restoring the Quick Chat panel.
    static let commandF = Shortcut(keyCode: UInt32(kVK_ANSI_F), carbonModifiers: UInt32(cmdKey), keyLabel: "F")

    init(keyCode: UInt32, carbonModifiers: UInt32, keyLabel: String? = nil) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
        self.keyLabel = keyLabel
    }

    /// Builds a shortcut from a key-down event, or nil if it isn't usable as a global
    /// shortcut (needs ⌘, ⌃ or ⌥, unless it's a function key).
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
        var carbon: UInt32 = 0
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        if flags.contains(.option) { carbon |= UInt32(optionKey) }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey) }
        let code = UInt32(event.keyCode)
        let isFunctionKey = Self.functionKeys.contains(Int(code))
        guard isFunctionKey || !flags.intersection([.command, .control, .option]).isEmpty else { return nil }
        self.init(keyCode: code, carbonModifiers: carbon,
                  keyLabel: event.charactersIgnoringModifiers?.uppercased())
    }

    /// User-facing summary of what `init?(event:)` accepts.
    static let rulesText = "Hold ⌘, ⌃ or ⌥ (⇧ alone doesn't count) and press a key.\nF1–F20 work with or without modifiers. Esc stops recording."

    /// Why `init?(event:)` rejected this key press (it lacked ⌘, ⌃ and ⌥).
    static func rejectionReason(for event: NSEvent) -> String {
        let key = keyNames[Int(event.keyCode)] ?? event.charactersIgnoringModifiers?.uppercased() ?? "That key"
        let shifted = event.modifierFlags.contains(.shift)
        return shifted
            ? "⇧\(key) isn't allowed: ⇧ alone doesn't count.\nAdd ⌘, ⌃ or ⌥."
            : "\(key) alone isn't allowed.\nAdd ⌘, ⌃ or ⌥ (or use F1–F20)."
    }

    /// Parses an Electron accelerator as ChatGPT stores it (e.g. `Alt+Space`,
    /// `Control+Alt+Shift+4`, `CmdOrCtrl+K`). Nil for keys this type doesn't know.
    /// Character keys resolve to the key that types them in the current keyboard layout, as
    /// Chromium's global shortcuts do (`kLayoutAwareGlobalHotkeys`), else to the US position.
    init?(accelerator: String) {
        var carbon: UInt32 = 0
        var key: String?
        for part in accelerator.split(separator: "+").map({ $0.lowercased() }) {
            switch part {
            case "command", "cmd", "commandorcontrol", "cmdorctrl", "super", "meta": carbon |= UInt32(cmdKey)
            case "control", "ctrl": carbon |= UInt32(controlKey)
            case "alt", "option": carbon |= UInt32(optionKey)
            case "shift": carbon |= UInt32(shiftKey)
            default: key = part
            }
        }
        guard let key, let fixed = Self.keyCodes[key] else { return nil }
        let code = key.count == 1 ? Self.layoutKeyCode(typing: key) ?? fixed : fixed
        self.init(keyCode: UInt32(code), carbonModifiers: carbon, keyLabel: key.uppercased())
    }

    /// The key that types `character` without modifiers in the current keyboard layout
    /// (dead keys skipped), like Chromium's lookup; nil if no key does.
    private static func layoutKeyCode(typing character: String) -> Int? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
        return data.withUnsafeBytes { buffer -> Int? in
            guard let layout = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return nil }
            for code in 0..<128 {
                var deadKeyState: UInt32 = 0
                var chars = [UniChar](repeating: 0, count: 4)
                var length = 0
                let status = UCKeyTranslate(layout, UInt16(code), UInt16(kUCKeyActionDown), 0, UInt32(LMGetKbdType()),
                                            0, &deadKeyState, chars.count, &length, &chars)
                if status == noErr, deadKeyState == 0, String(utf16CodeUnits: chars, count: length) == character {
                    return code
                }
            }
            return nil
        }
    }

    /// Same key and modifiers (the display label doesn't matter).
    static func == (lhs: Shortcut, rhs: Shortcut) -> Bool {
        lhs.keyCode == rhs.keyCode && lhs.carbonModifiers == rhs.carbonModifiers
    }

    var displayString: String {
        var s = ""
        if carbonModifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if carbonModifiers & UInt32(optionKey) != 0 { s += "⌥" }
        if carbonModifiers & UInt32(shiftKey) != 0 { s += "⇧" }
        if carbonModifiers & UInt32(cmdKey) != 0 { s += "⌘" }
        return s + (Self.keyNames[Int(keyCode)] ?? keyLabel ?? "Key \(keyCode)")
    }

    private static let functionKeys: Set<Int> = [
        kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
        kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20,
    ]

    private static let keyNames: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Escape: "⎋", kVK_Delete: "⌫",
        kVK_ForwardDelete: "⌦", kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑",
        kVK_DownArrow: "↓", kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17",
        kVK_F18: "F18", kVK_F19: "F19", kVK_F20: "F20",
    ]

    /// Accelerator key names (lowercased) → virtual key codes.
    private static let keyCodes: [String: Int] = {
        var map: [String: Int] = [
            "space": kVK_Space, "return": kVK_Return, "enter": kVK_Return, "tab": kVK_Tab,
            "escape": kVK_Escape, "esc": kVK_Escape, "backspace": kVK_Delete, "delete": kVK_ForwardDelete,
            "left": kVK_LeftArrow, "right": kVK_RightArrow, "up": kVK_UpArrow, "down": kVK_DownArrow,
            "home": kVK_Home, "end": kVK_End, "pageup": kVK_PageUp, "pagedown": kVK_PageDown,
            "-": kVK_ANSI_Minus, "=": kVK_ANSI_Equal, "[": kVK_ANSI_LeftBracket, "]": kVK_ANSI_RightBracket,
            ";": kVK_ANSI_Semicolon, "'": kVK_ANSI_Quote, ",": kVK_ANSI_Comma, ".": kVK_ANSI_Period,
            "/": kVK_ANSI_Slash, "\\": kVK_ANSI_Backslash, "`": kVK_ANSI_Grave,
        ]
        let letters = [kVK_ANSI_A, kVK_ANSI_B, kVK_ANSI_C, kVK_ANSI_D, kVK_ANSI_E, kVK_ANSI_F, kVK_ANSI_G,
                       kVK_ANSI_H, kVK_ANSI_I, kVK_ANSI_J, kVK_ANSI_K, kVK_ANSI_L, kVK_ANSI_M, kVK_ANSI_N,
                       kVK_ANSI_O, kVK_ANSI_P, kVK_ANSI_Q, kVK_ANSI_R, kVK_ANSI_S, kVK_ANSI_T, kVK_ANSI_U,
                       kVK_ANSI_V, kVK_ANSI_W, kVK_ANSI_X, kVK_ANSI_Y, kVK_ANSI_Z]
        for (i, code) in letters.enumerated() { map[String(UnicodeScalar(UInt8(97 + i)))] = code }
        let digits = [kVK_ANSI_0, kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5, kVK_ANSI_6,
                      kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9]
        for (i, code) in digits.enumerated() { map[String(i)] = code }
        let fkeys = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
                     kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20]
        for (i, code) in fkeys.enumerated() { map["f\(i + 1)"] = code }
        return map
    }()

    // MARK: Persistence

    private static let defaultsKey = "miniChat.shortcut" // pre-rename key; persisted, keep
    /// Local (panel-focused) shortcut for Reset Window Size.
    private static let resetSizeDefaultsKey = "quickChat.resetSizeShortcut"
    /// Local (panel-focused) shortcut for Maximize / Restore Size.
    private static let maximizeDefaultsKey = "quickChat.maximizeShortcut"

    /// The global Quick Chat toggle shortcut.
    static func load() -> Shortcut { load(key: defaultsKey, fallback: .optionSpace) }
    func save() { save(key: Self.defaultsKey) }

    /// The Reset Window Size shortcut (works only while the Quick Chat panel is focused).
    static func loadResetSize() -> Shortcut { load(key: resetSizeDefaultsKey, fallback: .commandO) }
    func saveAsResetSize() { save(key: Self.resetSizeDefaultsKey) }

    /// The Maximize / Restore Size shortcut (works only while the Quick Chat panel is focused).
    static func loadMaximize() -> Shortcut { load(key: maximizeDefaultsKey, fallback: .commandF) }
    func saveAsMaximize() { save(key: Self.maximizeDefaultsKey) }

    private static func load(key: String, fallback: Shortcut) -> Shortcut {
        guard let data = UserDefaults.standard.data(forKey: key),
              let shortcut = try? JSONDecoder().decode(Shortcut.self, from: data) else { return fallback }
        return shortcut
    }

    private func save(key: String) {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
