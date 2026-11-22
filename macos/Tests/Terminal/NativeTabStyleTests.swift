import AppKit
import Testing
@testable import Ghostty

@MainActor
struct NativeTabStyleTests {
    @Test func colorResolutionTruthTable() {
        for hasBar in [false, true] {
            for hasActive in [false, true] {
                for hasInactive in [false, true] {
                    let colors = NativeTabStyle.Colors(
                        bar: hasBar ? .black : nil,
                        active: hasActive ? .red : nil,
                        inactive: hasInactive ? .blue : nil
                    )
                    #expect(colors.isEmpty == !(hasBar || hasActive || hasInactive))
                    #expect(colors.background(selected: true) == (hasActive ? .red : nil))
                    #expect(colors.background(selected: false) == (hasInactive ? .blue : nil))
                }
            }
        }
    }

    @Test(arguments: [0.0, 0.5, 1.0])
    func colorResolutionPreservesOpacity(opacity: Double) {
        let color = NSColor.red.withAlphaComponent(opacity)
        let colors = NativeTabStyle.Colors(bar: color, active: color, inactive: color)
        #expect(!colors.isEmpty)
        #expect(colors.bar?.alphaComponent == CGFloat(opacity))
        #expect(colors.background(selected: true)?.alphaComponent == CGFloat(opacity))
        #expect(colors.background(selected: false)?.alphaComponent == CGFloat(opacity))
    }

    @Test func hiddenWindowReceivesReloadedColorsAndReset() throws {
        let window = TerminalWindow(
            contentRect: .zero, styleMask: [], backing: .buffered, defer: false
        )
        #expect(!window.isVisible)
        let config = try TemporaryConfig("""
        macos-tab-bar-background = #123456
        macos-tab-bar-opacity = 0.5
        macos-tab-active-background = red
        macos-tab-inactive-background = blue
        """)
        window.syncAppearance(.init(config))
        #expect(window.tabColors.bar?.alphaComponent == 0.5)
        #expect(window.tabColors.active != nil)
        #expect(window.tabColors.inactive != nil)
        try config.reload("macos-tab-active-background = green")
        window.syncAppearance(.init(config))
        #expect(window.tabColors.bar == nil)
        #expect(window.tabColors.active != nil)
        #expect(window.tabColors.inactive == nil)
        try config.reload("")
        window.syncAppearance(.init(config))
        #expect(window.tabColors.isEmpty)
        #expect(!window.isVisible)
    }

    @Test func unsetColorsLeaveNativeViewsUntouched() {
        let style = NativeTabStyle()
        let bar = NSView()
        let tab = NSView()
        bar.addSubview(tab)
        style.apply(bar: bar, tabs: [tab], selectedIndex: 0, colors: .init())
        #expect(bar.subviews == [tab])
        #expect(tab.subviews.isEmpty)
        #expect(!bar.wantsLayer)
    }

    @Test func backgroundsAreIdempotentAndDoNotInterceptInput() {
        let style = NativeTabStyle()
        let bar = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 30))
        let tab = NSView(frame: bar.bounds)
        let title = NSTextField(labelWithString: "Native title")
        tab.addSubview(title)
        bar.addSubview(tab)
        let colors = NativeTabStyle.Colors(bar: .black, active: .red)
        style.apply(bar: bar, tabs: [tab], selectedIndex: 0, colors: colors)
        let barBackground = bar.subviews[0]
        let tabBackground = tab.subviews[0]
        style.apply(bar: bar, tabs: [tab], selectedIndex: 0, colors: colors)
        #expect(bar.subviews.count == 2)
        #expect(tab.subviews.count == 2)
        #expect(bar.subviews[0] === barBackground)
        #expect(tab.subviews[0] === tabBackground)
        #expect(tab.subviews[1] === title)
        #expect(barBackground.hitTest(.zero) == nil)
        #expect(tabBackground.hitTest(.zero) == nil)
        #expect(tabBackground.frame == tab.bounds)

        style.apply(bar: bar, tabs: [tab], selectedIndex: 0, colors: .init())
        #expect(bar.subviews == [tab])
        #expect(tab.subviews == [title])
        #expect(barBackground.superview == nil)
        #expect(tabBackground.superview == nil)
    }

    @Test func backgroundsFollowNativeLayoutWithoutAutoresizing() {
        let style = NativeTabStyle()
        let bar = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 30))
        let tab = NSView()
        tab.autoresizesSubviews = false
        bar.addSubview(tab)
        let colors = NativeTabStyle.Colors(active: .red)
        style.apply(bar: bar, tabs: [tab], selectedIndex: 0, colors: colors)
        let background = tab.subviews[0]
        tab.setFrameSize(NSSize(width: 300, height: 24))
        tab.layoutSubtreeIfNeeded()
        #expect(background.frame == tab.bounds)
        tab.setFrameSize(NSSize(width: 400, height: 28))
        style.apply(bar: bar, tabs: [tab], selectedIndex: 0, colors: colors)
        #expect(background.frame == tab.bounds)
        #expect(tab.subviews.count == 1)
        style.reset()
        #expect(tab.subviews.isEmpty)
        #expect(tab.constraints.isEmpty)
    }

    @Test func selectionMovesActiveOnlyOverride() {
        let style = NativeTabStyle()
        let bar = NSView()
        let tabs = [NSView(), NSView()]
        for tab in tabs { bar.addSubview(tab) }
        let colors = NativeTabStyle.Colors(active: .red)
        style.apply(bar: bar, tabs: tabs, selectedIndex: 0, colors: colors)
        #expect(tabs[0].subviews.count == 1)
        #expect(tabs[1].subviews.isEmpty)
        style.apply(bar: bar, tabs: tabs, selectedIndex: 1, colors: colors)
        #expect(tabs[0].subviews.isEmpty)
        #expect(tabs[1].subviews.count == 1)
    }

    @Test func rebuiltAndMissingTabBarsRemoveOldBackgrounds() {
        let style = NativeTabStyle()
        let oldBar = NSView()
        let newBar = NSView()
        let colors = NativeTabStyle.Colors(bar: .black)
        style.apply(bar: oldBar, tabs: [], selectedIndex: nil, colors: colors)
        #expect(oldBar.subviews.count == 1)
        style.apply(bar: newBar, tabs: [], selectedIndex: nil, colors: colors)
        #expect(oldBar.subviews.isEmpty)
        #expect(newBar.subviews.count == 1)
        style.apply(bar: nil, tabs: [], selectedIndex: nil, colors: colors)
        #expect(newBar.subviews.isEmpty)
    }

    @Test func selectedTabForegroundBranchRemainsVisible() {
        let style = NativeTabStyle()
        let bar = NSView()
        let effect = TabStyleNSSubduedGlassEffectView()
        let material = NSView()
        let content = NSView()
        let foreground = NSView()
        let tabs = [NSView(), NSView()]
        let title = NSTextField(labelWithString: "Selected native tab")
        tabs[1].addSubview(title)
        tabs.forEach { content.addSubview($0) }
        [material, content, foreground].forEach { effect.addSubview($0) }
        bar.addSubview(effect)
        let colors = NativeTabStyle.Colors(bar: .black, active: .red)
        style.apply(bar: bar, tabs: tabs, selectedIndex: 0, colors: colors)
        #expect(material.isHidden)
        #expect(foreground.isHidden)

        for _ in 0..<3 {
            foreground.addSubview(tabs[1])
            style.apply(bar: bar, tabs: tabs, selectedIndex: 1, colors: colors)
            #expect(!foreground.isHidden)
            #expect(!title.isHiddenOrHasHiddenAncestor)
            #expect(!tabs[0].isHiddenOrHasHiddenAncestor)
            #expect(material.isHidden)

            content.addSubview(tabs[1])
            style.apply(bar: bar, tabs: tabs, selectedIndex: 0, colors: colors)
            #expect(!title.isHiddenOrHasHiddenAncestor)
        }
        style.reset()
        #expect(!material.isHidden)
        #expect(!foreground.isHidden)
        #expect(!title.isHiddenOrHasHiddenAncestor)
    }

    /// Builds the Tahoe track hierarchy, where the track's regular glass view draws its
    /// material with a backdrop layer beside the portal that renders the tabs.
    @available(macOS 26.0, *)
    private func makeGlassTrack() -> GlassTrack {
        let bar = NSView()
        let track = TabStyleNSTabBarTrackView()
        let glass = NSGlassEffectView()
        let content = NSView()
        let tabs = [NSView(), NSView()]
        tabs.forEach { content.addSubview($0) }
        glass.contentView = content
        glass.wantsLayer = true
        track.addSubview(glass)
        bar.addSubview(track)
        // AppKit may wrap the content view in a holder, which is where the fill goes.
        let holder = glass.subviews.first { tabs[0].isDescendant(of: $0) } ?? content

        // The glass view routes added subviews into its content, so the render branch is
        // attached beside the content at the layer level, like AppKit's own root view.
        let renderBranch = CALayer()
        let backdropClass = NSClassFromString("CABackdropLayer") as? CALayer.Type ?? CALayer.self
        let backdrop = backdropClass.init()
        let portal = CALayer()
        renderBranch.addSublayer(backdrop)
        renderBranch.addSublayer(portal)
        glass.layer?.addSublayer(renderBranch)

        // Each tab's own glass sits inside the content branch and must stay native.
        let tabBackdrop = backdropClass.init()
        tabs[1].wantsLayer = true
        tabs[1].layer?.addSublayer(tabBackdrop)
        return GlassTrack(
            bar: bar, holder: holder, holderSubviews: holder.subviews, tabs: tabs,
            renderBranch: renderBranch, backdrop: backdrop, portal: portal,
            tabBackdrop: tabBackdrop
        )
    }

    @Test func glassTrackHidesOnlyItsBackdropAndRestores() {
        guard #available(macOS 26.0, *) else { return }
        #expect(NSStringFromClass(type(of: makeGlassTrack().backdrop)) == "CABackdropLayer")
        let style = NativeTabStyle()
        let track = makeGlassTrack()
        let colors = NativeTabStyle.Colors(bar: NSColor.red.withAlphaComponent(0))
        for _ in 0..<2 {
            style.apply(bar: track.bar, tabs: track.tabs, selectedIndex: 0, colors: colors)
            #expect(track.backdrop.isHidden)
            #expect(!track.portal.isHidden)
            #expect(!track.renderBranch.isHidden)
            #expect(!track.tabBackdrop.isHidden)
            #expect(!track.tabs.contains { $0.isHiddenOrHasHiddenAncestor })
            #expect(track.holder.subviews.count == track.holderSubviews.count + 1)
        }

        // Changing the color keeps the material hidden without stacking backgrounds.
        style.apply(
            bar: track.bar, tabs: track.tabs, selectedIndex: 1,
            colors: .init(bar: NSColor.blue.withAlphaComponent(0.5))
        )
        #expect(track.backdrop.isHidden)
        #expect(track.holder.subviews.count == track.holderSubviews.count + 1)

        // Tab-only colors leave the track's native material alone.
        style.apply(bar: track.bar, tabs: track.tabs, selectedIndex: 0, colors: .init(active: .red))
        #expect(!track.backdrop.isHidden)

        style.apply(bar: track.bar, tabs: track.tabs, selectedIndex: 0, colors: colors)
        #expect(track.backdrop.isHidden)
        style.apply(bar: track.bar, tabs: track.tabs, selectedIndex: 0, colors: .init())
        #expect(!track.backdrop.isHidden)
        #expect(track.holder.subviews == track.holderSubviews)
    }

    @Test func glassTrackPreservesBackdropsHiddenByAppKit() {
        guard #available(macOS 26.0, *) else { return }
        let style = NativeTabStyle()
        let track = makeGlassTrack()
        track.backdrop.isHidden = true
        style.apply(bar: track.bar, tabs: track.tabs, selectedIndex: 0, colors: .init(bar: .black))
        style.reset()
        #expect(track.backdrop.isHidden)
    }

    @Test func glassTabPreservesNativeRenderingBranches() {
        guard #available(macOS 26.0, *) else { return }
        let style = NativeTabStyle()
        let bar = NSView()
        let tab = NSView()
        let glass = NSGlassEffectView()
        let content = NSView()
        let title = NSTextField(labelWithString: "Native glass title")
        content.addSubview(title)
        glass.contentView = content
        tab.addSubview(glass)
        bar.addSubview(tab)
        let renderingBranch = NSView()
        let renderedTitle = NSTextField(labelWithString: "Native rendered foreground")
        renderingBranch.addSubview(renderedTitle)
        glass.addSubview(renderingBranch)
        let nativeVisibility = glass.subviews.map { ($0, $0.isHidden) }

        for selectedIndex in [0, 1, 0] {
            style.apply(
                bar: bar, tabs: [tab], selectedIndex: selectedIndex,
                colors: .init(active: .red.withAlphaComponent(0.5), inactive: .blue)
            )
            #expect(glass.contentView === content)
            #expect(title.stringValue == "Native glass title")
            #expect(content.subviews.count == 2)
            #expect(content.subviews[1] === title)
            #expect(!renderedTitle.isHiddenOrHasHiddenAncestor)
            for (branch, wasHidden) in nativeVisibility {
                #expect(branch.isHidden == wasHidden)
            }
        }
        style.reset()
        #expect(content.subviews == [title])
        #expect(glass.contentView === content)
        #expect(!renderedTitle.isHiddenOrHasHiddenAncestor)
    }
}

private final class TabStyleNSSubduedGlassEffectView: NSView {}
private final class TabStyleNSTabBarTrackView: NSView {}

private struct GlassTrack {
    let bar: NSView
    let holder: NSView
    let holderSubviews: [NSView]
    let tabs: [NSView]
    let renderBranch: CALayer
    let backdrop: CALayer
    let portal: CALayer
    let tabBackdrop: CALayer
}
