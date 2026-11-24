#if DEBUG
import Carbon.HIToolbox

enum WindowCommandSelfTest {
    static func run() -> Bool {
        let cases: [(Int, Int, String, WindowCommand?)] = [
            (kVK_ANSI_N, cmdKey, "N", .newWindow),
            (kVK_ANSI_N, cmdKey, "Т", .newWindow),
            (kVK_ANSI_W, cmdKey, "Ц", .close),
            (kVK_ANSI_L, cmdKey, "N", .newWindow), // Latin layout with N on a different key
            (kVK_ANSI_N, cmdKey, "B", nil),
            (kVK_ANSI_N, cmdKey | shiftKey, "Т", nil),
            (kVK_ANSI_N, cmdKey | optionKey, "N", nil),
            (kVK_ANSI_Equal, cmdKey, "=", .zoomIn),
            (kVK_ANSI_Equal, cmdKey | shiftKey, "+", .zoomIn),
            (kVK_ANSI_KeypadPlus, cmdKey, "", .zoomIn),
            (kVK_ANSI_KeypadMinus, cmdKey, "", .zoomOut),
            (kVK_ANSI_Equal, cmdKey, "-", .zoomOut),
            (kVK_ANSI_Minus, cmdKey | shiftKey, "_", nil),
        ]
        var failures = 0
        for (code, modifiers, label, expected) in cases {
            let shortcut = Shortcut(keyCode: UInt32(code), carbonModifiers: UInt32(modifiers), keyLabel: label)
            let actual = WindowCommand(shortcut: shortcut)
            if actual != expected {
                failures += 1
                print("FAIL: key \(code) with modifiers \(modifiers) and label \(label): expected \(String(describing: expected)), got \(String(describing: actual))")
            }
        }
        print("Window shortcuts: \(cases.count - failures)/\(cases.count) passed")
        return failures == 0
    }
}
#endif
