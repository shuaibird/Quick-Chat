import Foundation

enum QuickChatLaunchPosition: String, CaseIterable {
    case center, top, bottom, last

    var title: String {
        switch self {
        case .center: "Center of Screen"
        case .top: "Top of Screen"
        case .bottom: "Bottom of Screen"
        case .last: "Last Position"
        }
    }

    private static let defaultsKey = "quickChat.launchPosition"

    static func load(from defaults: UserDefaults = .standard) -> Self {
        defaults.string(forKey: defaultsKey).flatMap(Self.init(rawValue:)) ?? .center
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.defaultsKey)
    }

    struct Display {
        let id: String?
        let frame: CGRect
        let visibleFrame: CGRect
    }

    struct SavedPosition: Codable, Equatable {
        private static let defaultsKey = "quickChat.lastPanelPosition"

        let displayID: String
        /// Relative to the display so rearranging displays doesn't move the panel on that display.
        let offset: CGPoint

        init?(frame: CGRect, displays: [Display]) {
            func overlap(_ display: Display) -> CGFloat {
                let intersection = display.frame.intersection(frame)
                return intersection.isEmpty ? 0 : intersection.width * intersection.height
            }
            guard let display = displays.max(by: { overlap($0) < overlap($1) }),
                  overlap(display) > 0, let id = display.id else { return nil }
            displayID = id
            offset = CGPoint(x: frame.minX - display.frame.minX, y: frame.minY - display.frame.minY)
        }

        static func load(from defaults: UserDefaults = .standard) -> Self? {
            guard let data = defaults.data(forKey: defaultsKey) else { return nil }
            return try? JSONDecoder().decode(Self.self, from: data)
        }

        func save(to defaults: UserDefaults = .standard) {
            if let data = try? JSONEncoder().encode(self) {
                defaults.set(data, forKey: Self.defaultsKey)
            }
        }
    }

    /// `displays` is ordered with the primary display first, like `NSScreen.screens`.
    func frame(for size: CGSize, displays: [Display], mouse: CGPoint, last: SavedPosition?) -> CGRect? {
        let restoredDisplay = self == .last ? last.flatMap { position in
            displays.first { $0.id == position.displayID }
        } : nil
        guard let display = restoredDisplay ?? displays.first(where: { $0.frame.contains(mouse) }) ?? displays.first,
              !display.visibleFrame.isEmpty else { return nil }

        let visible = display.visibleFrame
        let width = min(size.width, visible.width)
        let height = min(size.height, visible.height)
        let center = CGPoint(x: visible.midX - width / 2, y: visible.midY - height / 2)
        // Leave a gap at the top/bottom unless the window nearly fills the available height.
        let inset = min(16, (visible.height - height) / 4)
        let origin: CGPoint
        switch self {
        case .center:
            origin = center
        case .top:
            origin = CGPoint(x: center.x, y: visible.maxY - height - inset)
        case .bottom:
            origin = CGPoint(x: center.x, y: visible.minY + inset)
        case .last:
            if let restoredDisplay, let last {
                origin = CGPoint(x: restoredDisplay.frame.minX + last.offset.x,
                                 y: restoredDisplay.frame.minY + last.offset.y)
            } else {
                origin = center
            }
        }
        return CGRect(x: min(max(origin.x, visible.minX), visible.maxX - width),
                      y: min(max(origin.y, visible.minY), visible.maxY - height),
                      width: width, height: height)
    }
}
