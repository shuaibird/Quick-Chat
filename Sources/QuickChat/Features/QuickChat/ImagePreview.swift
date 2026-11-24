import AppKit
import ImageIO
import QuickLookUI
import UniformTypeIdentifiers
import WebKit

@MainActor
final class ImagePreview: NSObject, WKScriptMessageHandlerWithReply, WKDownloadDelegate, NSWindowDelegate {
    static let shared = ImagePreview()
    private let log = Log.make("ImagePreview")
    private static let messageName = "quickChatImagePreview"
    private static let sizeLimit = 50 * 1024 * 1024
    private static let pixelLimit = 100_000_000
    private var newestRequest: UUID?
    private struct Download {
        let request: UUID
        let screen: NSScreen?
        let reply: @MainActor (Any?, String?) -> Void
        var file: URL?
    }
    private var downloads: [ObjectIdentifier: Download] = [:]
    private var window: ImagePreviewWindow?
    private var file: URL?

    func install(in controller: WKUserContentController) {
        controller.addScriptMessageHandler(self, contentWorld: .defaultClient, name: Self.messageName)
        controller.addUserScript(WKUserScript(source: Self.clickScript, injectionTime: .atDocumentStart,
                                              forMainFrameOnly: true, in: .defaultClient))
    }

    private static let clickScript = """
    let previewClick = 0;
    const validImage = image => image instanceof HTMLImageElement && image.complete &&
      Math.min(image.naturalWidth, image.naturalHeight) >= 32;
    const visible = image => {
      const rect = image.getBoundingClientRect();
      return rect.width >= 32 && rect.height >= 32 && image.checkVisibility?.() !== false;
    };
    const load = async (source, click) => {
      if (source.startsWith('blob:')) {
        try {
          const blob = await (await fetch(source)).blob();
          if (blob.size > 50 * 1024 * 1024 || !blob.type.startsWith('image/')) return false;
          source = await new Promise((resolve, reject) => {
            const reader = new FileReader();
            reader.onload = () => resolve(reader.result);
            reader.onerror = reject;
            reader.readAsDataURL(blob);
          });
        } catch {
          // Give WebKit's download delegate a chance to load the original URL.
        }
      }
      return click !== previewClick ||
        window.webkit.messageHandlers.quickChatImagePreview.postMessage(source);
    };
    window.addEventListener('click', async event => {
      if (!event.isTrusted || event.button !== 0 || event.metaKey || event.ctrlKey ||
          event.altKey || event.shiftKey) return;
      const target = event.target;
      if (!(target instanceof Element) || target.closest('a[download], button[disabled]')) return;
      const control = target.closest('button, a[href], [role="button"], [role="menuitem"]');
      const image = document.elementsFromPoint(event.clientX, event.clientY).find(candidate =>
        validImage(candidate) && visible(candidate) &&
        candidate.closest('main, [data-message-author-role], [role="dialog"]') &&
        !candidate.closest('nav, aside, [role="menu"], a[download]'));
      // A toolbar button can lie over an image. Only a control that wraps the
      // clicked image is an image opener; let Edit, Share, etc. handle their own clicks.
      if (!image || (control && !control.contains(image))) return;
      const source = image.currentSrc || image.src;
      if (!/^(https:|blob:|data:image[/])/i.test(source)) return;
      const link = target.closest('a[href]');
      if (link && link.href !== source && link.href !== image.src) return;
      event.preventDefault();
      event.stopImmediatePropagation();
      const click = ++previewClick;
      try {
        if (await load(source, click)) return;
      } catch {
        // Fall through to the site's own viewer when the native preview fails.
      }
      if (click === previewClick && target.isConnected && target instanceof HTMLElement) target.click();
    }, true);
    """

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage,
                               replyHandler: @escaping @MainActor (Any?, String?) -> Void) {
        guard message.name == Self.messageName, message.frameInfo.isMainFrame,
              message.frameInfo.securityOrigin.protocol == "https",
              ["chatgpt.com", "www.chatgpt.com"].contains(message.frameInfo.securityOrigin.host),
              let webView = message.webView, let source = message.body as? String,
              source.utf8.count <= Self.sizeLimit * 4 / 3 + 256 else {
            replyHandler(false, nil)
            return
        }
        let request = UUID()
        newestRequest = request
        let screen = webView.window?.screen
        if source.prefix(5).lowercased() == "data:" {
            guard let comma = source.firstIndex(of: ","),
                  source[..<comma].lowercased().hasPrefix("data:image/"),
                  source[..<comma].lowercased().hasSuffix(";base64"),
                  let data = Data(base64Encoded: String(source[source.index(after: comma)...])) else {
                replyHandler(false, nil)
                return
            }
            let temporary = previewURL(for: request)
            do {
                try data.write(to: temporary)
                let opened = present(file: temporary, on: screen)
                if !opened { try? FileManager.default.removeItem(at: temporary) }
                replyHandler(opened, nil)
            } catch {
                try? FileManager.default.removeItem(at: temporary)
                replyHandler(false, nil)
                log.error("Could not write image preview: \(error.localizedDescription, privacy: .private)")
            }
            return
        }
        guard let url = URL(string: source), ["https", "blob"].contains(url.scheme ?? "") else {
            replyHandler(false, nil)
            return
        }
        webView.startDownload(using: URLRequest(url: url, timeoutInterval: 15)) { [self] download in
            downloads[ObjectIdentifier(download)] = Download(request: request, screen: screen, reply: replyHandler)
            download.delegate = self
        }
    }

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse,
                  suggestedFilename: String, completionHandler: @escaping @MainActor (URL?) -> Void) {
        let id = ObjectIdentifier(download)
        let successfulResponse = (response as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? true
        guard var entry = downloads[id], entry.request == newestRequest,
              successfulResponse, response.expectedContentLength <= Self.sizeLimit else {
            if let canceled = downloads.removeValue(forKey: id) {
                canceled.reply(canceled.request != newestRequest, nil)
            }
            completionHandler(nil)
            return
        }
        let destination = previewURL(for: entry.request)
        entry.file = destination
        downloads[id] = entry
        completionHandler(destination)
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let entry = downloads.removeValue(forKey: ObjectIdentifier(download)) else { return }
        guard let file = entry.file else {
            entry.reply(false, nil)
            return
        }
        let superseded = entry.request != newestRequest
        let opened = !superseded && present(file: file, on: entry.screen)
        if !opened { try? FileManager.default.removeItem(at: file) }
        entry.reply(opened || superseded, nil)
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        log.error("Image preview download failed: \(error.localizedDescription, privacy: .private)")
        guard let entry = downloads.removeValue(forKey: ObjectIdentifier(download)) else { return }
        if let file = entry.file { try? FileManager.default.removeItem(at: file) }
        entry.reply(entry.request != newestRequest, nil)
    }

    private func previewURL(for request: UUID) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("QuickChat-preview-\(request.uuidString)")
    }

    private func present(file: URL, on screen: NSScreen?) -> Bool {
        guard let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= Self.sizeLimit,
              let source = CGImageSourceCreateWithURL(file as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int, width > 0,
              let height = properties[kCGImagePropertyPixelHeight] as? Int, height > 0,
              width <= Self.pixelLimit / height,
              let identifier = CGImageSourceGetType(source) as String?,
              let ext = UTType(identifier)?.preferredFilenameExtension else {
            log.error("Image preview resource could not be decoded")
            return false
        }
        let typedFile = file.appendingPathExtension(ext)
        guard (try? FileManager.default.moveItem(at: file, to: typedFile)) != nil else { return false }
        guard let image = NSImage(contentsOf: typedFile) else {
            try? FileManager.default.removeItem(at: typedFile)
            return false
        }
        window?.close()
        let preview = ImagePreviewWindow(file: typedFile, image: image, screen: screen)
        preview.delegate = self
        self.file = typedFile
        window = preview
        NSApp.activate()
        preview.makeKeyAndOrderFront(nil)
        preview.showQuickLook()
        log.info("Native image preview opened")
        return true
    }

    func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? ImagePreviewWindow, closing === window else { return }
        closing.releaseQuickLook()
        window = nil
        if let file { try? FileManager.default.removeItem(at: file) }
        file = nil
    }
}

@MainActor
final class ImagePreviewWindow: NSWindow {
    private let file: URL
    private var quickLook: QLPreviewView?

    init(file: URL, image: NSImage, screen: NSScreen?) {
        self.file = file
        let imageView = NSImageView(image: image)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        let visible = (screen ?? NSScreen.main)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1024, height: 768)
        let size = NSSize(width: visible.width * 0.8, height: visible.height * 0.8)
        super.init(contentRect: NSRect(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2,
                                       width: size.width, height: size.height),
                   styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        title = "Image Preview — Space to close"
        isReleasedWhenClosed = false
        level = .floating
        collectionBehavior = [.fullScreenPrimary]
        contentView = imageView
    }

    func showQuickLook() {
        guard let view = QLPreviewView(frame: .zero, style: .normal) else { return }
        view.autostarts = true
        view.previewItem = file as NSURL
        quickLook = view
        contentView = view
        title = "Quick Look — Space to close"
        if let visible = screen?.visibleFrame { setFrame(visible, display: true) }
    }

    func releaseQuickLook() {
        quickLook?.close()
        quickLook = nil
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty {
            switch event.charactersIgnoringModifiers {
            case " ", "\u{1b}":
                if !event.isARepeat { close() }
                return
            default:
                break
            }
        }
        super.sendEvent(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection([.command, .option, .control, .shift]) == .command,
           event.charactersIgnoringModifiers?.lowercased() == "w" {
            close()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
