import AppKit
import Testing
@testable import Ghostty

// Stand-ins for AppKit's private titlebar views. Lookups match on the unqualified class
// name, so these exercise the same paths as the real hierarchy.
private final class NSTitlebarAccessoryClipView: NSView {}
private final class NSTitlebarAccessoryContainerView: NSView {}
private final class NSTabBar: NSView {}

@MainActor
struct TitlebarTabsTests {
    /// Builds `container > accessory > tab bar`, the shape AppKit uses for the tab bar.
    private func tabBar(in container: NSView) -> NSView {
        let accessory = NSView()
        let tabBar = NSTabBar()
        container.addSubview(accessory)
        accessory.addSubview(tabBar)
        return tabBar
    }

    @Test func findsTheMacOS26AccessoryClipView() {
        let clip = NSTitlebarAccessoryClipView()
        #expect(TitlebarTabsTahoeTerminalWindow.accessoryClipView(containing: tabBar(in: clip)) === clip)
    }

    @Test func findsTheMacOS27AccessoryContainerView() {
        let container = NSTitlebarAccessoryContainerView()
        #expect(TitlebarTabsTahoeTerminalWindow.accessoryClipView(containing: tabBar(in: container)) === container)
    }

    @Test func findsNoAccessoryClipViewOutsideTheTitlebar() {
        #expect(TitlebarTabsTahoeTerminalWindow.accessoryClipView(containing: tabBar(in: NSView())) == nil)
    }

    @Test func accessoryClipViewNamesCoverEveryKnownMacOSVersion() {
        #expect(TitlebarTabsTahoeTerminalWindow.accessoryClipViewClassNames == [
            "NSTitlebarAccessoryClipView",
            "NSTitlebarAccessoryContainerView",
        ])
    }

    @Test func keptViewStaysHiddenWhenShownAgain() {
        let keeper = HiddenViewKeeper()
        let view = NSView()
        keeper.keep(view)
        #expect(view.isHidden)

        // AppKit showing the view again must not bring it back.
        for _ in 0..<3 {
            view.isHidden = false
            #expect(view.isHidden)
        }
    }

    @Test func keepingTheSameViewTwiceStillKeepsItHidden() {
        let keeper = HiddenViewKeeper()
        let view = NSView()
        keeper.keep(view)
        keeper.keep(view)
        view.isHidden = false
        #expect(view.isHidden)
    }

    @Test func keepingAReplacementViewReleasesThePreviousOne() {
        let keeper = HiddenViewKeeper()
        let old = NSView()
        let replacement = NSView()
        keeper.keep(old)
        keeper.keep(replacement)

        old.isHidden = false
        replacement.isHidden = false
        #expect(!old.isHidden)
        #expect(replacement.isHidden)
    }

    @Test func releasedViewCanBeShownAgain() {
        let keeper = HiddenViewKeeper()
        let view = NSView()
        keeper.keep(view)
        keeper.release()
        #expect(view.isHidden)

        view.isHidden = false
        #expect(!view.isHidden)
    }

    @Test func releasingWithoutAViewDoesNothing() {
        let keeper = HiddenViewKeeper()
        keeper.release()
        let view = NSView()
        view.isHidden = false
        #expect(!view.isHidden)
    }
}
