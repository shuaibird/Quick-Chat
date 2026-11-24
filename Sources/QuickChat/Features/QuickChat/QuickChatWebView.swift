import AppKit
import Carbon.HIToolbox
import WebKit

enum PageZoomCommand: String {
    case increase = "Zoom In"
    case decrease = "Zoom Out"

    init?(shortcut: Shortcut) {
        let command = UInt32(cmdKey)
        let modifiers = shortcut.carbonModifiers
        guard modifiers == command || modifiers == UInt32(cmdKey | shiftKey) else { return nil }

        let key = shortcut.keyLabel
        let code = Int(shortcut.keyCode)
        if key == "+" || code == kVK_ANSI_KeypadPlus {
            self = .increase
        } else if modifiers == command && (key == "-" || code == kVK_ANSI_KeypadMinus) {
            self = .decrease
        } else if key == "=" || code == kVK_ANSI_Equal {
            self = .increase
        } else if modifiers == command && code == kVK_ANSI_Minus {
            self = .decrease
        } else {
            return nil
        }
    }

    func scale(from zoom: CGFloat) -> CGFloat {
        let percent = Int((zoom * 100).rounded())
        let step = self == .increase ? 10 : -10
        return CGFloat(min(200, max(50, percent + step))) / 100
    }
}

final class QuickChatWebView: WKWebView {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard let shortcut = Shortcut(event: event),
              let command = PageZoomCommand(shortcut: shortcut) else {
            return super.performKeyEquivalent(with: event)
        }
        pageZoom = command.scale(from: pageZoom)
        return true
    }
}
