import AppKit
import WebKit

@MainActor
final class QuickChatWindows {
    /// Least recently focused first, so restoring the group also restores its stacking order.
    private var windows: [QuickChatController] = []
    private var isHiding = false

    var resetSizeShortcut = Shortcut.loadResetSize() {
        didSet { windows.forEach { $0.resetSizeShortcut = resetSizeShortcut } }
    }

    var maximizeShortcut = Shortcut.loadMaximize() {
        didSet { windows.forEach { $0.maximizeShortcut = maximizeShortcut } }
    }

    func toggle() {
        if windows.contains(where: { $0.isVisibleOnActiveSpace }) {
            hideAll()
        } else {
            show()
        }
    }

    func show() {
        guard let front = windows.last else {
            openWindow()
            return
        }
        for window in windows.dropLast() { window.show(focused: false) }
        front.show()
    }

    func openWindow() {
        for window in windows where !window.isVisibleOnActiveSpace { window.show(focused: false) }
        let window = QuickChatController(cascadeFrom: windows.last?.frame)
        window.resetSizeShortcut = resetSizeShortcut
        window.maximizeShortcut = maximizeShortcut
        window.onNewWindow = { [weak self] in self?.openWindow() }
        window.onCancel = { [weak self] in self?.hideAll() }
        window.onClose = { [weak self, weak window] in
            if let window { self?.close(window) }
        }
        window.onFocus = { [weak self, weak window] in
            guard let self, !isHiding, let window,
                  let index = windows.firstIndex(where: { $0 === window }) else { return }
            windows.remove(at: index)
            windows.append(window)
        }
        window.canReclaimFocus = { [weak self, weak window] in
            guard let self, !isHiding, let window else { return false }
            return windows.last === window
        }
        windows.append(window)
        window.show()
    }

    private func hideAll() {
        isHiding = true
        defer { isHiding = false }
        let focused = windows.first { $0.isFocused }
        for window in windows where window !== focused { window.hide(restoreFocus: false) }
        focused?.hide(restoreFocus: true)
    }

    private func close(_ window: QuickChatController) {
        let wasFocused = window.isFocused
        windows.removeAll { $0 === window }
        if wasFocused && windows.isEmpty { window.hide(restoreFocus: true) }
        window.tearDown()
        if wasFocused { windows.last?.focusIfVisible() }
    }

    func tearDown() {
        let closing = windows
        windows.removeAll()
        closing.forEach { $0.tearDown() }
    }

    func signOut() {
        let store = WKWebsiteDataStore.default()
        store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) { [weak self] in
            MainActor.assumeIsolated {
                self?.windows.forEach { $0.returnToChat() }
            }
        }
    }
}
