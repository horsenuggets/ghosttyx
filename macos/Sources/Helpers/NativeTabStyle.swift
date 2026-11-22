import AppKit

/// Styles backgrounds below native tab content without replacing its controls.
@MainActor
final class NativeTabStyle {
    struct Colors {
        var bar: NSColor?
        var active: NSColor?
        var inactive: NSColor?

        var isEmpty: Bool { bar == nil && active == nil && inactive == nil }

        func background(selected: Bool) -> NSColor? {
            selected ? active : inactive
        }
    }

    private var backgrounds: [ObjectIdentifier: BackgroundView] = [:]
    private var hiddenMaterials: [ObjectIdentifier: HiddenMaterial] = [:]

    func reset() {
        apply(bar: nil, tabs: [], selectedIndex: nil, colors: .init())
    }

    func apply(to window: NSWindow, colors: Colors) {
        guard !colors.isEmpty || !backgrounds.isEmpty else { return }
        let windows = window.tabbedWindows ?? []
        let selectedIndex = window.tabGroup?.selectedWindow.flatMap { windows.firstIndex(of: $0) }
        apply(
            bar: window.tabBarView,
            tabs: window.tabButtonsInVisualOrder(),
            selectedIndex: selectedIndex,
            colors: colors
        )
    }

    func apply(bar: NSView?, tabs: [NSView], selectedIndex: Int?, colors: Colors) {
        var retained: Set<ObjectIdentifier> = []
        var retainedMaterials: Set<ObjectIdentifier> = []
        if let bar, !colors.isEmpty {
            if let color = colors.bar {
                // Tahoe puts the track's glass behind a separate content branch. The
                // outer fill excludes that branch so opacity is not applied twice.
                var trackContent: NSView?
                if let effect = subduedGlass(in: bar),
                   let content = effect.subviews.first(where: { branch in
                       tabs.contains { $0.isDescendant(of: branch) }
                   }) {
                    trackContent = content
                    hideMaterial(in: effect, keeping: tabs, retained: &retainedMaterials)
                    addBackground(to: content, color: color, rounded: true, retained: &retained)
                }
                addBackground(
                    to: bar, color: color, rounded: false,
                    excluding: trackContent, retained: &retained
                )
            }

            for (index, tab) in tabs.enumerated() {
                guard let color = colors.background(selected: index == selectedIndex) else { continue }
                let content: NSView
                if #available(macOS 26.0, *),
                   let glass = tab.firstDescendant(withClassName: "NSGlassEffectView") as? NSGlassEffectView,
                   let glassContent = glass.contentView {
                    // The glass renderer also composites the selected tab's foreground.
                    // Keep its native render branches and inversion layers untouched.
                    content = glassContent
                } else {
                    content = tab
                }
                addBackground(to: content, color: color, rounded: true, retained: &retained)
            }
        }

        for key in Set(backgrounds.keys).subtracting(retained) {
            backgrounds.removeValue(forKey: key)?.removeFromSuperview()
        }
        for key in Set(hiddenMaterials.keys).subtracting(retainedMaterials) {
            hiddenMaterials.removeValue(forKey: key)?.restore()
        }
    }

    private func hideMaterial(in effect: NSView, keeping content: [NSView], retained: inout Set<ObjectIdentifier>) {
        // AppKit can move the selected tab into a separate foreground branch. Every
        // branch containing native tab content must remain visible.
        for child in effect.subviews where !content.contains(where: {
            $0 === child || $0.isDescendant(of: child)
        }) {
            let key = ObjectIdentifier(child)
            retained.insert(key)
            if hiddenMaterials[key]?.view !== child {
                hiddenMaterials[key] = HiddenMaterial(view: child)
            }
            child.isHidden = true
        }
    }

    @MainActor
    private struct HiddenMaterial {
        weak var view: NSView?
        let wasHidden: Bool

        init(view: NSView) {
            self.view = view
            self.wasHidden = view.isHidden
        }

        func restore() {
            view?.isHidden = wasHidden
        }
    }

    private func addBackground(
        to host: NSView,
        color: NSColor,
        rounded: Bool,
        excluding excludedView: NSView? = nil,
        retained: inout Set<ObjectIdentifier>
    ) {
        let key = ObjectIdentifier(host)
        retained.insert(key)
        let background: BackgroundView
        if let existing = backgrounds[key], existing.superview === host {
            background = existing
        } else {
            backgrounds[key]?.removeFromSuperview()
            background = BackgroundView(frame: host.bounds)
            background.translatesAutoresizingMaskIntoConstraints = false
            background.setAccessibilityElement(false)
            host.addSubview(background, positioned: .below, relativeTo: nil)
            NSLayoutConstraint.activate([
                background.leadingAnchor.constraint(equalTo: host.leadingAnchor),
                background.trailingAnchor.constraint(equalTo: host.trailingAnchor),
                background.topAnchor.constraint(equalTo: host.topAnchor),
                background.bottomAnchor.constraint(equalTo: host.bottomAnchor),
            ])
            backgrounds[key] = background
        }
        if background.frame != host.bounds {
            background.frame = host.bounds
            background.needsDisplay = true
        }
        background.excludedView = excludedView
        let excludedFrame = excludedView.map { host.convert($0.bounds, from: $0) }
        if background.color != color || background.rounded != rounded || background.excludedFrame != excludedFrame {
            background.color = color
            background.rounded = rounded
            background.excludedFrame = excludedFrame
            background.needsDisplay = true
        }
    }

    private func subduedGlass(in view: NSView) -> NSView? {
        for child in view.subviews {
            if child.className.contains("NSSubduedGlassEffectView") { return child }
            if let found = subduedGlass(in: child) { return found }
        }
        return nil
    }

    private final class BackgroundView: NSView {
        var color: NSColor = .clear
        var rounded = false
        var excludedFrame: NSRect?
        weak var excludedView: NSView?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func draw(_ dirtyRect: NSRect) {
            color.setFill()
            let radius = rounded ? bounds.height / 2 : 0
            let path = NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius)
            if let excludedView {
                let excludedFrame = convert(excludedView.bounds, from: excludedView)
                let excludedRadius = excludedFrame.height / 2
                path.append(NSBezierPath(
                    roundedRect: excludedFrame, xRadius: excludedRadius, yRadius: excludedRadius
                ))
                path.windingRule = .evenOdd
            }
            path.fill()
        }
    }
}
