import AppKit
import WebKit

/// Floating Quick Chat in the spirit of ChatGPT Classic's companion chat: chatgpt.com in a
/// web view, which uses its compact layout at this width.
@MainActor
final class QuickChatController: NSObject {
    private static let chatURL = URL(string: "https://chatgpt.com/")!
    /// OpenAI's sign-in hosts (and their subdomains): where sign-in starts from a chatgpt.com page.
    private static let openAISignInHosts = ["auth.openai.com", "auth0.openai.com"]
    /// Hidden longer than this while off ChatGPT (e.g. a help page reached from a sign-in page),
    /// the panel goes back to the chat when shown. Shorter keeps a sign-in in progress, such as
    /// while copying a code from another app.
    private static let returnToChatAfter: TimeInterval = 5 * 60
    private static let safariUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15"

    private let log = Log.make("QuickChat")
    private var panel: QuickChatPanel?
    private var webView: WKWebView?
    private var previousApp: NSRunningApplication?
    /// When the panel was last shown / last lost key, and until when a Space switch may not
    /// take its focus (see `spaceDidChange()`).
    private var shownAt: Date?
    private var lostKeyAt: Date?
    private var keepFocusUntil: Date?
    /// When the panel was last hidden (see `returnToChatAfter`).
    private var hiddenAt: Date?
    private var workspaceObservers: [NSObjectProtocol] = []
    /// Where each in-flight download is being written, for "reveal in Finder" when it finishes.
    private var downloadDestinations: [ObjectIdentifier: URL] = [:]
    /// Recent automatic reloads after the web content process died, to stop a crash loop.
    private var crashReloads: [Date] = []
    /// Set when crash reloads were given up; the page reloads the next time the panel shows.
    private var reloadOnShow = false

    /// Local shortcut (only while the panel is key) that triggers the panel's `resetSize()`.
    var resetSizeShortcut = Shortcut.loadResetSize() {
        didSet { panel?.resetSizeShortcut = resetSizeShortcut }
    }

    /// Local shortcut (only while the panel is key) that toggles maximize, like the green button.
    var maximizeShortcut = Shortcut.loadMaximize() {
        didSet { panel?.maximizeShortcut = maximizeShortcut }
    }

    /// Hides the panel whenever it's visible on the current Space (focused or not), otherwise
    /// shows it here. Focus goes back to the previous app only if the panel had it.
    func toggle() {
        if let panel, panel.isVisible, panel.isOnActiveSpace {
            hide(restoreFocus: panel.isKeyWindow && NSApp.isActive)
        } else {
            show()
        }
    }

    func show() {
        let panel = self.panel ?? makePanel()
        let front = NSWorkspace.shared.frontmostApplication
        if front?.processIdentifier != ProcessInfo.processInfo.processIdentifier { previousApp = front }
        if let webView {
            // Off ChatGPT after a long hide: back to the chat, which also stands in for a crash retry.
            let returnToChat = webView.url?.host.map { !Self.isChatGPTHost($0) } == true
                && hiddenAt.map { Date.now.timeIntervalSince($0) > Self.returnToChatAfter } == true
            if returnToChat {
                log.info("Off ChatGPT since the panel was hidden; going back to the chat")
                webView.load(URLRequest(url: Self.chatURL))
            } else if reloadOnShow {
                reload(webView)
            }
            if returnToChat || reloadOnShow {
                reloadOnShow = false
                crashReloads = []
            }
        }
        hiddenAt = nil
        // Don't activate the app: activation is only a request since macOS 14, and after a
        // Space switch macOS hands focus on to another app (Finder, the full-screen app) and the
        // panel loses the keyboard. A non-activating panel takes key without it, like Spotlight.
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(webView)
        focusComposer()
        shownAt = .now
    }

    /// A Space switch makes macOS activate an app on the new Space (Finder on the desktop, the
    /// full-screen app), which takes the keyboard from the panel; that includes a switch still
    /// landing just after ⌥Space. If the panel had focus (or was just shown), take it back.
    private func observeSpaceChanges() {
        guard workspaceObservers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers = [
            center.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil,
                               queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.spaceDidChange() }
            },
            // The new Space's app can activate just after the Space-change notification.
            center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil,
                               queue: .main) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                MainActor.assumeIsolated {
                    self?.otherAppActivated(app)
                    self?.reclaimFocusIfKept()
                }
            },
        ]
    }

    /// Keeps `previousApp` current while the panel is open, so hiding returns focus to the app
    /// you're in now; not the one from when the panel opened, which may sit on another Space
    /// (activating it would switch back there).
    private func otherAppActivated(_ app: NSRunningApplication?) {
        guard let app, app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              panel?.isVisible == true else { return }
        previousApp = app
    }

    private func spaceDidChange() {
        guard let panel, panel.isVisible else { return }
        let recent = { (date: Date?) in date.map { Date.now.timeIntervalSince($0) < 1 } ?? false }
        guard panel.isKeyWindow || recent(lostKeyAt) || recent(shownAt) else { return }
        keepFocusUntil = .now.addingTimeInterval(1)
        reclaimFocusIfKept()
    }

    private func reclaimFocusIfKept() {
        guard let until = keepFocusUntil, Date.now < until,
              let panel, panel.isVisible, panel.isOnActiveSpace else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, let panel = self.panel, panel.isVisible, !panel.isKeyWindow else { return }
            panel.makeKeyAndOrderFront(nil)
            panel.makeFirstResponder(self.webView)
        }
    }

    /// `restoreFocus`: give focus back to the app that was frontmost before showing.
    func hide(restoreFocus: Bool) {
        guard let panel, panel.isVisible else { return }
        keepFocusUntil = nil
        panel.orderOut(nil)
        hiddenAt = .now
        if restoreFocus { previousApp?.activate() }
    }

    /// Closes the panel and releases the web view (the sign-in session stays in the data store).
    func tearDown() {
        panel?.orderOut(nil)
        webView?.stopLoading()
        panel?.contentView = nil
        panel = nil
        webView = nil
        crashReloads = []
        reloadOnShow = false
    }

    /// Signs out by clearing the panel's website data (cookies, storage).
    func signOut() {
        let store = WKWebsiteDataStore.default()
        store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) { [weak self] in
            MainActor.assumeIsolated {
                self?.log.info("Cleared Quick Chat website data")
                self?.webView?.load(URLRequest(url: Self.chatURL))
            }
        }
    }

    // MARK: Building

    private func makePanel() -> QuickChatPanel {
        let panel = QuickChatPanel(contentRect: NSRect(origin: .zero, size: QuickChatPanel.defaultSize))
        panel.onCancel = { [weak self] in self?.hide(restoreFocus: true) }
        panel.onGoBack = { [weak self] in self?.webView?.goBack() }
        panel.onGoForward = { [weak self] in self?.webView?.goForward() }
        panel.onResignKey = { [weak self] in
            self?.lostKeyAt = .now
            self?.reclaimFocusIfKept()
        }
        observeSpaceChanges()
        panel.resetSizeShortcut = resetSizeShortcut
        panel.maximizeShortcut = maximizeShortcut

        let header = DraggableView() // drag strip under the transparent title bar
        let webView = makeWebView()
        let stack = NSStackView(views: [header, webView])
        stack.orientation = .vertical
        stack.spacing = 0
        stack.edgeInsets = NSEdgeInsets()
        header.heightAnchor.constraint(equalToConstant: 28).isActive = true
        panel.contentView = stack

        if !panel.setFrameUsingName(QuickChatPanel.autosaveName) {
            center(panel)
        }
        panel.setFrameAutosaveName(QuickChatPanel.autosaveName)

        self.panel = panel
        self.webView = webView
        webView.load(URLRequest(url: Self.chatURL))
        return panel
    }

    private func center(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2,
                                     y: visible.minY + (visible.height - size.height) * 0.6))
    }

    private func makeWebView() -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.mediaTypesRequiringUserActionForPlayback = []
        config.userContentController.addUserScript(WKUserScript(
            source: Self.noAutocorrectScript, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.customUserAgent = Self.safariUserAgent
        webView.uiDelegate = self
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.underPageBackgroundColor = .windowBackgroundColor
        return webView
    }

    /// Turns off macOS autocorrect / auto-capitalization (and inline predictions) in chatgpt.com's
    /// composer. Their suggestion bubble swallows keys while it's up, ⌥Space included, so the
    /// toggle shortcut stops working. Spell-check underlines stay. Re-applied on DOM changes,
    /// since the page re-renders the composer.
    private static let noAutocorrectScript = """
    (() => {
      const apply = () => document.querySelectorAll('#prompt-textarea, [contenteditable="true"], textarea')
        .forEach(el => {
          if (el.getAttribute('autocorrect') === 'off') return;
          el.setAttribute('autocorrect', 'off');
          el.setAttribute('autocapitalize', 'off');
          el.setAttribute('writingsuggestions', 'false');
        });
      new MutationObserver(apply).observe(document, { childList: true, subtree: true });
      apply();
    })();
    """

    private func focusComposer() {
        // Best effort: chatgpt.com's composer is a contenteditable #prompt-textarea.
        webView?.evaluateJavaScript("document.querySelector('#prompt-textarea')?.focus()")
    }

    /// chatgpt.com or a subdomain of it (not e.g. "notchatgpt.com").
    private static func isChatGPTHost(_ host: String) -> Bool {
        let host = host.lowercased()
        return host == "chatgpt.com" || host.hasSuffix(".chatgpt.com")
    }

    /// blob: and data: URLs are page-generated files (exports, images); they're saved, never shown.
    private static func isGeneratedFile(_ url: URL?) -> Bool {
        url?.scheme == "blob" || url?.scheme == "data"
    }

    /// ~/Downloads/<name>, or "<name> 2", "<name> 3", … if that already exists (Finder-style).
    private static func uniqueDownloadURL(suggestedFilename: String) -> URL {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        var name = (suggestedFilename as NSString).lastPathComponent
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty || name.hasPrefix(".") { name = "download" + name }
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var candidate = downloads.appendingPathComponent(name)
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            let numbered = "\(base) \(n)" + (ext.isEmpty ? "" : ".\(ext)")
            candidate = downloads.appendingPathComponent(numbered)
            n += 1
        }
        return candidate
    }

    /// Whether a link to `url`, clicked on the page `source`, opens in the browser. Decided by
    /// where the link was clicked, not by a list of destinations: answers only appear on
    /// chatgpt.com, so a link from there that leaves ChatGPT (and isn't its sign-in) goes to the
    /// browser. Any other page in the panel is part of a sign-in flow (Google, Apple, Microsoft,
    /// SSO), whose links stay in the panel whatever host they use.
    private static func opensInBrowser(_ url: URL?, from source: URL?) -> Bool {
        guard let host = url?.host?.lowercased() else { return false } // about:blank, data:, etc.
        guard let sourceHost = source?.host, isChatGPTHost(sourceHost) else { return false }
        let isOpenAISignIn = openAISignInHosts.contains { host == $0 || host.hasSuffix("." + $0) }
        return !isChatGPTHost(host) && !isOpenAISignIn
    }
}

// MARK: - WebKit delegates

extension QuickChatController: WKUIDelegate, WKNavigationDelegate, WKDownloadDelegate {
    /// `window.open` / target=_blank: opens in the panel, unless `opensInBrowser` sends it to the browser.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard let url = navigationAction.request.url else { return nil }
        if Self.isGeneratedFile(url) {
            // window.open(blob:/data:) would otherwise replace the chat in the panel.
            webView.startDownload(using: navigationAction.request) { $0.delegate = self }
        } else if Self.opensInBrowser(url, from: webView.url) {
            NSWorkspace.shared.open(url)
        } else {
            webView.load(navigationAction.request)
        }
        return nil
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        let url = navigationAction.request.url
        // <a download>, blob:/data: links: save the file instead of navigating (checked first, as
        // download links often point at file hosts that would otherwise open in the browser).
        if navigationAction.shouldPerformDownload || (navigationAction.targetFrame?.isMainFrame == true && Self.isGeneratedFile(url)) {
            decisionHandler(.download)
            return
        }
        if navigationAction.targetFrame?.isMainFrame == true, navigationAction.navigationType == .linkActivated,
           Self.opensInBrowser(url, from: webView.url), let url {
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    /// Responses the web view can't display, or that the server marks as attachments, are saved.
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping @MainActor (WKNavigationResponsePolicy) -> Void) {
        let disposition = (navigationResponse.response as? HTTPURLResponse)?
            .value(forHTTPHeaderField: "Content-Disposition")?.lowercased()
        let isAttachment = disposition?.hasPrefix("attachment") == true
        decisionHandler(!navigationResponse.canShowMIMEType || isAttachment ? .download : .allow)
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        focusComposer()
    }

    /// macOS may kill the web content process (often while hidden, under memory pressure), which
    /// leaves the view blank; reload right away so it's ready before the panel is shown again.
    /// A page that keeps crashing it (3 times in a minute) is left until the panel is next shown.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        let now = Date()
        crashReloads.removeAll { now.timeIntervalSince($0) > 60 }
        guard crashReloads.count < 3 else {
            log.error("Web content process keeps terminating; reloading when the panel is next shown")
            reloadOnShow = true
            return
        }
        crashReloads.append(now)
        log.info("Web content process terminated; reloading")
        reload(webView)
    }

    private func reload(_ webView: WKWebView) {
        if webView.url != nil { webView.reload() } else { webView.load(URLRequest(url: Self.chatURL)) }
    }

    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping @MainActor ([URL]?) -> Void) {
        guard let panel else { return completionHandler(nil) }
        let open = NSOpenPanel()
        open.allowsMultipleSelection = parameters.allowsMultipleSelection
        open.canChooseDirectories = parameters.allowsDirectories
        open.beginSheetModal(for: panel) { response in
            completionHandler(response == .OK ? open.urls : nil)
        }
    }

    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                 decisionHandler: @escaping @MainActor (WKPermissionDecision) -> Void) {
        // Camera and microphone alike: WebKit asks the user (per page load) on chatgpt.com only.
        // macOS's own TCC prompt also appears once per app (NSCamera/NSMicrophoneUsageDescription).
        decisionHandler(origin.protocol == "https" && Self.isChatGPTHost(origin.host) ? .prompt : .deny)
    }

    // MARK: Downloads (WKDownloadDelegate)

    /// Saves straight to ~/Downloads under a unique name (like Safari): no modal sheet on the
    /// floating panel, which may be hidden by the time a slow download asks for a destination.
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse,
                  suggestedFilename: String, completionHandler: @escaping @MainActor (URL?) -> Void) {
        let destination = Self.uniqueDownloadURL(suggestedFilename: suggestedFilename)
        downloadDestinations[ObjectIdentifier(download)] = destination
        log.info("Downloading to \(destination.path, privacy: .public)")
        completionHandler(destination)
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let destination = downloadDestinations.removeValue(forKey: ObjectIdentifier(download)) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([destination])
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        downloadDestinations.removeValue(forKey: ObjectIdentifier(download))
        log.error("Download failed: \(error.localizedDescription, privacy: .public)")
        NSSound.beep()
    }
}

// MARK: - Panel

final class QuickChatPanel: NSPanel {
    static let autosaveName = "MiniChat.Panel" // pre-rename name; keeps the saved frame
    /// Default content size (also the "reset size" target): a 3:4 portrait panel. Anything under
    /// 640 wide gets chatgpt.com's compact (mobile) layout; 420 sits between Classic's 440-wide
    /// companion chat and `minSize` (400), so the thread reads as a narrow column without the
    /// squat look of the new app's 470-wide window cut down to 560 tall.
    static let defaultSize = NSSize(width: 420, height: 560)
    var onCancel: (() -> Void)?
    var onResignKey: (() -> Void)?
    /// ⌘[ / ⌘] while the panel is key: the browsers' Back and Forward.
    var onGoBack: (() -> Void)?
    var onGoForward: (() -> Void)?

    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }

    /// Local key combo that calls `resetSize()` while the panel is key (default ⌘O).
    var resetSizeShortcut: Shortcut? = .commandO
    /// Local key combo that calls `toggleMaximize()` while the panel is key (default ⌘F).
    var maximizeShortcut: Shortcut? = .commandF {
        didSet { updateZoomTooltip() }
    }

    /// System traffic-light buttons shown in the title bar's top-left cluster (the rest stay
    /// hidden). Red close goes through `close()` below, so it hides rather than destroys; green
    /// zoom is rerouted to `toggleMaximize()` (see `configureZoomButton()`).
    static let trafficLights: [NSWindow.ButtonType] = [.closeButton, .zoomButton]

    /// Where the green button sits when minimize is hidden: minimize's slot, so there's no gap.
    private var zoomButtonOrigin: NSPoint?

    /// The user's frame from before maximizing; non-nil while maximized. Hiding and showing
    /// keep the panel maximized; a relaunch doesn't, as the maximized frame is never autosaved.
    private var restoreFrame: NSRect?
    var isMaximized: Bool { restoreFrame != nil }
    /// Set while the panel changes its own frame, so only user moves/resizes end the maximize.
    private var isSettingFrame = false

    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        title = "ChatGPT"
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        // .fullScreenAuxiliary lets the panel show over another app's full-screen Space. Don't add
        // .fullScreenNone: the full-screen behaviors are mutually exclusive and it cancels
        // .fullScreenAuxiliary (issue #7). As an auxiliary window it can't go full screen itself,
        // so the green button still only maximizes.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .fullScreenDisallowsTiling]
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            standardWindowButton(button)?.isHidden = !Self.trafficLights.contains(button)
        }
        configureZoomButton()
        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovableByWindowBackground = false
        minSize = NSSize(width: 400, height: 400)
        backgroundColor = .windowBackgroundColor
        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(frameDidChange),
                                                   name: name, object: self)
        }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    /// Points the green button at `toggleMaximize()` and, if minimize is hidden, slides it into
    /// minimize's slot next to close. AppKit re-lays out the title bar buttons (resize, key
    /// changes), so the button's frame changes are watched and the slot re-applied.
    private func configureZoomButton() {
        guard let zoom = standardWindowButton(.zoomButton), !zoom.isHidden else { return }
        zoom.target = self
        zoom.action = #selector(maximizeButtonClicked(_:))
        updateZoomTooltip()

        guard !Self.trafficLights.contains(.miniaturizeButton),
              let mini = standardWindowButton(.miniaturizeButton) else { return }
        zoomButtonOrigin = mini.frame.origin
        pinZoomButton()
        zoom.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(pinZoomButton),
                                               name: NSView.frameDidChangeNotification, object: zoom)
    }

    /// Deferred a turn: moving the button synchronously inside AppKit's title bar layout pass
    /// gets overwritten by the rest of that pass.
    @objc private func pinZoomButton() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let zoomButtonOrigin = self.zoomButtonOrigin,
                  let zoom = self.standardWindowButton(.zoomButton),
                  zoom.frame.origin != zoomButtonOrigin else { return }
            zoom.setFrameOrigin(zoomButtonOrigin)
        }
    }

    private func updateZoomTooltip() {
        var tip = isMaximized ? "Restore Size" : "Maximize"
        if let maximizeShortcut { tip += " (\(maximizeShortcut.displayString))" }
        standardWindowButton(.zoomButton)?.toolTip = tip
    }

    @objc private func maximizeButtonClicked(_ sender: Any?) { toggleMaximize() }

    /// Title bar double-click / Window ▸ Zoom toggle maximize too, instead of AppKit's own zoom.
    override func zoom(_ sender: Any?) { toggleMaximize() }

    /// Esc (when the page doesn't handle it) hides the panel.
    override func cancelOperation(_ sender: Any?) { onCancel?() }

    /// Fills the screen's visible frame (menu bar and Dock stay visible), or goes back to the
    /// user's frame from before. The panel stays resizable while maximized.
    func toggleMaximize() {
        if let restoreFrame {
            setOwnFrame(restoreFrame)
            endMaximize()
        } else {
            guard let visible = (screen ?? NSScreen.main)?.visibleFrame else { return }
            restoreFrame = frame
            setFrameAutosaveName("") // keep the user's frame as the one restored on relaunch
            setOwnFrame(visible)
            updateZoomTooltip()
        }
    }

    /// Resizes to `defaultSize`, keeping the top-left corner put (the pre-maximize one if
    /// maximized) but staying on the visible part of the screen. The frame autosave then
    /// persists the new size.
    func resetSize() {
        let anchor = restoreFrame ?? frame
        let size = frameRect(forContentRect: NSRect(origin: .zero, size: Self.defaultSize)).size
        var frame = NSRect(x: anchor.minX, y: anchor.maxY - size.height,
                           width: size.width, height: size.height)
        if let visible = (screen ?? NSScreen.main)?.visibleFrame {
            frame.size.width = min(frame.width, visible.width)
            frame.size.height = min(frame.height, visible.height)
            frame.origin.x = min(max(frame.minX, visible.minX), visible.maxX - frame.width)
            frame.origin.y = min(max(frame.minY, visible.minY), visible.maxY - frame.height)
        }
        setOwnFrame(frame)
        if isMaximized { endMaximize() }
    }

    /// Animated frame change that doesn't count as the user moving or resizing the panel.
    private func setOwnFrame(_ frame: NSRect) {
        isSettingFrame = true
        defer { isSettingFrame = false }
        setFrame(frame, display: true, animate: true)
    }

    /// Leaves the maximized state as is (frame-wise) and resumes autosaving the current frame.
    private func endMaximize() {
        restoreFrame = nil
        setFrameAutosaveName(Self.autosaveName)
        saveFrame(usingName: Self.autosaveName)
        updateZoomTooltip()
    }

    /// The user moved or resized the maximized panel: that frame becomes their own.
    @objc private func frameDidChange() {
        if isMaximized, !isSettingFrame { endMaximize() }
    }

    /// Runs the Reset Window Size or Maximize action if `event` is its shortcut. Key repeats
    /// are swallowed, so holding the shortcut doesn't toggle maximize over and over.
    private func handleLocalShortcut(_ event: NSEvent) -> Bool {
        guard let pressed = Shortcut(event: event) else { return false }
        guard pressed == resetSizeShortcut || pressed == maximizeShortcut else { return false }
        if event.isARepeat { return true }
        if pressed == resetSizeShortcut {
            resetSize()
        } else if pressed == maximizeShortcut {
            toggleMaximize()
        } else {
            return false
        }
        return true
    }

    /// Catches the panel's local shortcuts before the web view sees them. Done here rather
    /// than in `performKeyEquivalent` so combos without ⌘ (e.g. ⌥R, F5) work too.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, handleLocalShortcut(event) { return }
        super.sendEvent(event)
    }

    override func close() { onCancel?() }

    /// ⌘W hides and ⌘[ / ⌘] go back / forward; the local shortcuts are caught here too, ahead
    /// of the web view (which otherwise claims ⌘ combos). A local shortcut the user set to one
    /// of these combos wins, as it's checked first. Matched by character, like menu key
    /// equivalents, so they work on any keyboard layout.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if handleLocalShortcut(event) { return true }
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command {
            switch event.charactersIgnoringModifiers {
            case "w": onCancel?(); return true
            case "[": onGoBack?(); return true
            case "]": onGoForward?(); return true
            default: break
            }
        }
        return super.performKeyEquivalent(with: event)
    }
}

/// Header strip that drags the window.
private final class DraggableView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }
}
