import Carbon.HIToolbox

enum WindowCommand: String, Equatable {
    case newWindow = "New Window"
    case close = "Close"
    case zoomIn = "Zoom In"
    case zoomOut = "Zoom Out"

    init?(shortcut: Shortcut) {
        let command = UInt32(cmdKey)
        let commandShift = UInt32(cmdKey | shiftKey)
        guard shortcut.carbonModifiers == command || shortcut.carbonModifiers == commandShift else { return nil }

        let key = shortcut.keyLabel?.lowercased() ?? ""
        let code = Int(shortcut.keyCode)
        let shifted = shortcut.carbonModifiers == commandShift
        if key == "+" || code == kVK_ANSI_KeypadPlus {
            self = .zoomIn
        } else if !shifted && (key == "-" || code == kVK_ANSI_KeypadMinus) {
            self = .zoomOut
        } else if key == "=" || code == kVK_ANSI_Equal {
            self = .zoomIn
        } else if !shifted && code == kVK_ANSI_Minus {
            self = .zoomOut
        } else if !shifted {
            // Letter shortcuts follow Latin layouts, with a physical key fallback for other scripts.
            let isASCIILetter = key.utf8.count == 1 && key.utf8.contains { (97...122).contains($0) }
            if key == "n" || (!isASCIILetter && code == kVK_ANSI_N) {
                self = .newWindow
            } else if key == "w" || (!isASCIILetter && code == kVK_ANSI_W) {
                self = .close
            } else {
                return nil
            }
        } else {
            return nil
        }
    }
}
