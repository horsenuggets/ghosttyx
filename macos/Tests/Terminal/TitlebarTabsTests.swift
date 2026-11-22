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

}
