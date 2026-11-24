import Carbon.HIToolbox

enum WindowCommand: String, Equatable {
    case newWindow = "New Window"
    case close = "Close"

    init?(shortcut: Shortcut) {
        guard shortcut.carbonModifiers == UInt32(cmdKey) else { return nil }
        let key = shortcut.keyLabel?.lowercased() ?? ""
        let code = Int(shortcut.keyCode)
        // Letter shortcuts follow Latin layouts, with a physical key fallback for other scripts.
        let isASCIILetter = key.utf8.count == 1 && key.utf8.contains { (97...122).contains($0) }
        if key == "n" || (!isASCIILetter && code == kVK_ANSI_N) {
            self = .newWindow
        } else if key == "w" || (!isASCIILetter && code == kVK_ANSI_W) {
            self = .close
        } else {
            return nil
        }
    }
}
