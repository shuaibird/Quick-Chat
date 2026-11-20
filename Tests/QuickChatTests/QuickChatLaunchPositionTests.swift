import Foundation
import Testing
@testable import QuickChat

struct QuickChatLaunchPositionTests {
    private typealias Position = QuickChatLaunchPosition
    private typealias Display = Position.Display
    private typealias SavedPosition = Position.SavedPosition

    private let primary = Display(id: "primary", frame: CGRect(x: 0, y: 0, width: 1200, height: 900),
                                  visibleFrame: CGRect(x: 80, y: 0, width: 1120, height: 876))
    private let side = Display(id: "side", frame: CGRect(x: -1000, y: -200, width: 1000, height: 800),
                               visibleFrame: CGRect(x: -1000, y: -160, width: 1000, height: 736))
    private let size = CGSize(width: 400, height: 500)

    @Test func fixedPositionsUseVisibleAreaOfDisplayUnderPointer() {
        let mouse = CGPoint(x: -100, y: 0)
        let displays = [primary, side]
        #expect(Position.center.frame(for: size, displays: displays, mouse: mouse, last: nil)
                == CGRect(x: -700, y: -42, width: 400, height: 500))
        #expect(Position.top.frame(for: size, displays: displays, mouse: mouse, last: nil)
                == CGRect(x: -700, y: 60, width: 400, height: 500))
        #expect(Position.bottom.frame(for: size, displays: displays, mouse: mouse, last: nil)
                == CGRect(x: -700, y: -144, width: 400, height: 500))
    }

    @Test func lastPositionFollowsOriginalDisplayEvenIfItWasRearranged() throws {
        let frame = CGRect(x: -110, y: -85, width: size.width, height: size.height)
        let saved = try #require(SavedPosition(frame: frame, displays: [primary, side]))
        #expect(saved.displayID == "primary") // most of the window is on primary
        let moved = Display(id: primary.id, frame: primary.frame.offsetBy(dx: 500, dy: -240),
                            visibleFrame: primary.visibleFrame.offsetBy(dx: 500, dy: -240))
        let mouse = CGPoint(x: -100, y: 0)
        #expect(Position.last.frame(for: size, displays: [side, moved], mouse: mouse, last: saved)
                == CGRect(x: 580, y: -240, width: 400, height: 500))
    }

    @Test func lastPositionCentersWhenTheDisplayIsGoneOrNoPositionWasSaved() throws {
        let frame = CGRect(origin: CGPoint(x: -850, y: 0), size: size)
        let saved = try #require(SavedPosition(frame: frame, displays: [primary, side]))
        let mouse = CGPoint(x: 500, y: 500)
        #expect(Position.last.frame(for: size, displays: [primary, side], mouse: mouse, last: saved) == frame)
        let centered = CGRect(x: 440, y: 188, width: 400, height: 500)
        #expect(Position.last.frame(for: size, displays: [primary], mouse: mouse, last: saved) == centered)
        #expect(Position.last.frame(for: size, displays: [primary, side], mouse: mouse, last: nil) == centered)
    }

    @Test func anOversizedWindowFitsInTheVisibleArea() {
        let size = CGSize(width: 1400, height: 1000)
        for position in Position.allCases {
            #expect(position.frame(for: size, displays: [primary], mouse: .zero, last: nil) == primary.visibleFrame)
        }
    }

    @Test func preferencesPersistAndDefaultToCenter() throws {
        let domain = "QuickChatLaunchPositionTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }

        #expect(Position.load(from: defaults) == .center)
        #expect(SavedPosition.load(from: defaults) == nil)
        for position in Position.allCases {
            position.save(to: defaults)
            #expect(Position.load(from: defaults) == position)
        }
        defaults.set("unknown", forKey: "quickChat.launchPosition")
        #expect(Position.load(from: defaults) == .center)

        let frame = CGRect(origin: CGPoint(x: 300, y: 200), size: size)
        let saved = try #require(SavedPosition(frame: frame, displays: [primary]))
        saved.save(to: defaults)
        #expect(SavedPosition.load(from: defaults) == saved)
    }
}
