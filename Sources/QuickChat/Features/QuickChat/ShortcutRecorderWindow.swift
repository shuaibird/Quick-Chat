import AppKit
import Carbon.HIToolbox

/// Small window for choosing Quick Chat's shortcuts: the global toggle and the local
/// (panel-focused) Reset Window Size and Maximize. The caller unregisters its global hotkey while this is
/// open (otherwise the current shortcut would be swallowed).
@MainActor
final class ShortcutRecorderWindow: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let recorder = RecorderField()
    private let resetSizeRecorder = RecorderField()
    private let maximizeRecorder = RecorderField()
    private let hint = NSTextField(wrappingLabelWithString: "")
    /// Which shortcuts are accepted (mirrors `Shortcut.init?(event:)`); briefly replaced
    /// by the reason when an ineligible combo is pressed.
    private let rules = NSTextField(wrappingLabelWithString: Shortcut.rulesText)
    private var rulesResetToken = 0
    private var onChange: ((Shortcut) -> Void)?
    private var onResetSizeChange: ((Shortcut) -> Void)?
    private var onMaximizeChange: ((Shortcut) -> Void)?
    private var onClose: (() -> Void)?

    /// `miniShortcut`: Show Mini's current shortcut, shown as a hint (picking it turns Show Mini off).
    /// `resetSize`, `maximize`: the current local shortcuts. All three shortcuts stay distinct.
    func show(current: Shortcut, resetSize: Shortcut, maximize: Shortcut, miniShortcut: String?,
              onChange: @escaping (Shortcut) -> Void,
              onResetSizeChange: @escaping (Shortcut) -> Void,
              onMaximizeChange: @escaping (Shortcut) -> Void,
              onClose: @escaping () -> Void) {
        self.onChange = onChange
        self.onResetSizeChange = onResetSizeChange
        self.onMaximizeChange = onMaximizeChange
        self.onClose = onClose
        recorder.shortcut = current
        resetSizeRecorder.shortcut = resetSize
        maximizeRecorder.shortcut = maximize
        let fields: [(RecorderField, (Shortcut) -> Void)] = [
            (recorder, { [weak self] in self?.onChange?($0) }),
            (resetSizeRecorder, { [weak self] in self?.onResetSizeChange?($0) }),
            (maximizeRecorder, { [weak self] in self?.onMaximizeChange?($0) }),
        ]
        for (field, record) in fields {
            field.validate = { [weak self, unowned field] new in self?.conflict(new, for: field) }
            field.onRecord = { [weak self] shortcut in self?.showRules(); record(shortcut) }
            field.onReject = { [weak self] reason in self?.showRejection(reason) }
        }
        showRules()

        hint.stringValue = miniShortcut.map {
            "ChatGPT's Show Mini uses \($0).\nChoosing the same shortcut turns Show Mini off while Quick Chat is on."
        } ?? "ChatGPT's Show Mini has no shortcut,\nso any shortcut is free."
        let window = self.window ?? makeWindow()
        self.window = window
        // Size to content (the hint text may differ between opens); width stays 424.
        if let content = window.contentView {
            content.layoutSubtreeIfNeeded()
            window.setContentSize(NSSize(width: 424, height: ceil(content.fittingSize.height)))
        }
        NSApp.activate()
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(recorder)
    }

    func close() { window?.close() }

    /// Whether the window is open (a recording session is in progress).
    var isOpen: Bool { window?.isVisible == true }

    /// Brings the open window forward without starting a new session.
    func bringToFront() {
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    /// Standard editing and window combos (see `EditMenu`, `QuickChatPanel`); taking one would
    /// break it in the panel, or everywhere for the global shortcut. Matched by key character,
    /// as menu key equivalents are, so they hold on any keyboard layout.
    private static let reserved: [(key: String, modifiers: Int, name: String)] = [
        ("X", cmdKey, "Cut"), ("C", cmdKey, "Copy"), ("V", cmdKey, "Paste"),
        ("V", cmdKey | optionKey | shiftKey, "Paste and Match Style"), ("A", cmdKey, "Select All"),
        ("Z", cmdKey, "Undo"), ("Z", cmdKey | shiftKey, "Redo"), ("W", cmdKey, "Close"), ("Q", cmdKey, "Quit"),
    ]

    /// Why `new` can't go in `field`: it's a reserved combo, or another of the three fields already has it.
    private func conflict(_ new: Shortcut, for field: RecorderField) -> String? {
        if let combo = Self.reserved.first(where: {
            UInt32($0.modifiers) == new.carbonModifiers && new.keyLabel?.uppercased() == $0.key
        }) {
            return "\(new.displayString) is \(combo.name).\nPick another combo."
        }
        let names: [(RecorderField, String)] = [
            (recorder, "the Quick Chat shortcut"), (resetSizeRecorder, "Reset Window Size"), (maximizeRecorder, "Maximize"),
        ]
        guard let name = names.first(where: { $0.0 !== field && $0.0.shortcut == new })?.1 else { return nil }
        return "\(new.displayString) is already \(name).\nPick another combo, or change that one first."
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 424, height: 292), // refit in show()
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Quick Chat Shortcuts"
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.delegate = self

        let label = Self.sectionLabel("Quick Chat", detail: "Opens Quick Chat from any app.")
        let reset = NSButton(title: "Reset to ⌥Space", target: self, action: #selector(resetToDefault))
        let row = NSStackView(views: [recorder, reset])
        let resetSizeLabel = Self.sectionLabel("Reset Window Size",
                                               detail: "Works only while Quick Chat is focused.")
        let resetSizeReset = NSButton(title: "Reset to ⌘O", target: self, action: #selector(resetResetSizeToDefault))
        let resetSizeRow = NSStackView(views: [resetSizeRecorder, resetSizeReset])
        let maximizeLabel = Self.sectionLabel("Maximize / Restore Size",
                                              detail: "Works only while Quick Chat is focused.")
        let maximizeReset = NSButton(title: "Reset to ⌘F", target: self, action: #selector(resetMaximizeToDefault))
        let maximizeRow = NSStackView(views: [maximizeRecorder, maximizeReset])
        for button in [reset, resetSizeReset, maximizeReset] {
            button.setContentHuggingPriority(.required, for: .horizontal)
            button.widthAnchor.constraint(equalToConstant: 120).isActive = true
        }
        rules.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        hint.textColor = .tertiaryLabelColor
        hint.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        let done = NSButton(title: "Done", target: self, action: #selector(finish))
        done.keyEquivalent = "\r"
        let buttons = NSStackView(views: [NSView(), done])
        let stack = NSStackView(views: [label, row, hint, resetSizeLabel, resetSizeRow,
                                        maximizeLabel, maximizeRow, rules, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.setCustomSpacing(6, after: row)
        stack.setCustomSpacing(18, after: hint)
        stack.setCustomSpacing(18, after: resetSizeRow)
        stack.setCustomSpacing(18, after: maximizeRow)
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 20, bottom: 16, right: 20)
        row.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40).isActive = true
        for view in [resetSizeRow, maximizeRow, rules, hint, buttons] {
            view.widthAnchor.constraint(equalTo: row.widthAnchor).isActive = true
        }
        // Wrap at a fixed width so the fitted height is deterministic.
        for text in [rules, hint] { text.preferredMaxLayoutWidth = 424 - 40 }
        // The rules text and every rejection reason are 2 lines; reserve that so swapping can't jump or clip.
        let twoLines = NSTextField(wrappingLabelWithString: "X\nX")
        twoLines.font = rules.font
        rules.heightAnchor.constraint(greaterThanOrEqualToConstant: ceil(twoLines.fittingSize.height)).isActive = true
        window.contentView = stack
        return window
    }

    private static func sectionLabel(_ title: String, detail: String) -> NSTextField {
        let text = NSMutableAttributedString(string: title, attributes: [
            .font: NSFont.boldSystemFont(ofSize: NSFont.systemFontSize), .foregroundColor: NSColor.labelColor,
        ])
        text.append(NSAttributedString(string: "  " + detail, attributes: [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize), .foregroundColor: NSColor.secondaryLabelColor,
        ]))
        let label = NSTextField(labelWithAttributedString: text)
        return label
    }

    private func showRules() {
        rulesResetToken += 1
        rules.stringValue = Shortcut.rulesText
        rules.textColor = .secondaryLabelColor
    }

    /// Shows why the pressed combo was rejected, then restores the rules text.
    private func showRejection(_ reason: String) {
        rulesResetToken += 1
        let token = rulesResetToken
        rules.stringValue = reason
        rules.textColor = .systemRed
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            guard let self, self.rulesResetToken == token else { return }
            self.showRules()
        }
    }

    @objc private func resetToDefault() {
        if let reason = recorder.validate?(.optionSpace) { return showRejection(reason) }
        showRules()
        recorder.shortcut = .optionSpace
        onChange?(.optionSpace)
    }

    @objc private func resetResetSizeToDefault() {
        if let reason = resetSizeRecorder.validate?(.commandO) { return showRejection(reason) }
        showRules()
        resetSizeRecorder.shortcut = .commandO
        onResetSizeChange?(.commandO)
    }

    @objc private func resetMaximizeToDefault() {
        if let reason = maximizeRecorder.validate?(.commandF) { return showRejection(reason) }
        showRules()
        maximizeRecorder.shortcut = .commandF
        onMaximizeChange?(.commandF)
    }

    @objc private func finish() { window?.close() }

    func windowWillClose(_ notification: Notification) {
        let onClose = self.onClose
        self.onClose = nil
        onClose?()
    }
}

/// Focusable field that captures the next shortcut-worthy key press.
private final class RecorderField: NSView {
    var shortcut: Shortcut = .optionSpace { didSet { needsDisplay = true } }
    var onRecord: ((Shortcut) -> Void)?
    var onReject: ((String) -> Void)?
    /// Extra check after the basic rules; returns why `new` isn't allowed, or nil if it is.
    var validate: ((Shortcut) -> String?)?
    private var recording = false { didSet { needsDisplay = true } }

    override var acceptsFirstResponder: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 32) }

    override func becomeFirstResponder() -> Bool { recording = true; return true }
    override func resignFirstResponder() -> Bool { recording = false; return true }
    override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(self) }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53, event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty {
            window?.makeFirstResponder(nil) // plain Esc stops recording
            return
        }
        guard let new = Shortcut(event: event) else {
            NSSound.beep()
            onReject?(Shortcut.rejectionReason(for: event))
            return
        }
        if let reason = validate?(new) {
            NSSound.beep()
            onReject?(reason)
            return
        }
        shortcut = new
        onRecord?(new)
    }

    /// Shortcuts with ⌘ arrive here first; treat them like any other key.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard recording, window?.firstResponder === self else { return false }
        keyDown(with: event)
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 6, yRadius: 6)
        NSColor.controlBackgroundColor.setFill()
        path.fill()
        (recording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        path.lineWidth = recording ? 2 : 1
        path.stroke()
        let text = recording ? "Press shortcut… (now \(shortcut.displayString))" : shortcut.displayString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .medium),
            .foregroundColor: recording ? NSColor.secondaryLabelColor : NSColor.labelColor,
        ]
        let size = text.size(withAttributes: attrs)
        text.draw(at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2), withAttributes: attrs)
    }
}
