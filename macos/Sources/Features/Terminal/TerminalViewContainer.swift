import AppKit
import SwiftUI

/// Use this container to achieve a glass effect at the window level.
/// Modifying `NSThemeFrame` can sometimes be unpredictable.
class TerminalViewContainer: NSView {
    private let terminalView: NSView

    /// Combined glass effect and inactive tint overlay view
    private(set) var glassEffectView: NSView?
    private var derivedConfig: DerivedConfig?

    var windowThemeFrameView: NSView? {
        window?.contentView?.superview
    }

    var windowCornerRadius: CGFloat? {
        guard let window, window.responds(to: Selector(("_cornerRadius"))) else {
            return nil
        }

        return window.value(forKey: "_cornerRadius") as? CGFloat
    }

    init<Root: View>(@ViewBuilder rootView: () -> Root) {
        self.terminalView = NSHostingView(rootView: rootView())
        super.init(frame: .zero)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// The initial content size to use as a fallback before the SwiftUI
    /// view hierarchy has completed layout (i.e. before @FocusedValue
    /// propagates `lastFocusedSurface`). Once the hosting view reports
    /// a valid intrinsic size, this fallback is no longer used.
    var initialContentSize: NSSize?

    override var intrinsicContentSize: NSSize {
        let hostingSize = terminalView.intrinsicContentSize
        // The hosting view returns a valid size once SwiftUI has laid out
        // with the correct idealWidth/idealHeight. Before that (when
        // @FocusedValue hasn't propagated), it returns a tiny default.
        // Fall back to initialContentSize in that case.
        if let initialContentSize,
           hostingSize.width < initialContentSize.width || hostingSize.height < initialContentSize.height {
            return initialContentSize
        }
        return hostingSize
    }

    private func setup() {
        addSubview(terminalView)
        terminalView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            terminalView.topAnchor.constraint(equalTo: topAnchor),
            terminalView.leadingAnchor.constraint(equalTo: leadingAnchor),
            terminalView.bottomAnchor.constraint(equalTo: bottomAnchor),
            terminalView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateGlassEffectIfNeeded()
        updateGlassEffectTopInsetIfNeeded()
    }

    override func layout() {
        super.layout()
        updateGlassEffectTopInsetIfNeeded()
    }

    func ghosttyConfigDidChange(_ config: Ghostty.Config, preferredBackgroundColor: NSColor?) {
        let newValue = DerivedConfig(config: config, preferredBackgroundColor: preferredBackgroundColor, cornerRadius: windowCornerRadius)
        guard newValue != derivedConfig else { return }
        derivedConfig = newValue
        DispatchQueue.main.async(execute: updateGlassEffectIfNeeded)
    }
}

// MARK: - BaseTerminalController + terminalViewContainer

extension BaseTerminalController {
    var terminalViewContainer: TerminalViewContainer? {
        window?.contentView as? TerminalViewContainer
    }
}

// MARK: Glass

/// An `NSView` that contains a liquid glass background effect and
/// an inactive-window tint overlay.
#if compiler(>=6.2)
@available(macOS 26.0, *)
private class TerminalGlassView: NSView {
    private let glassEffectView: NSGlassEffectView
    private var topConstraint: NSLayoutConstraint!
    private let tintOverlay: NSView
    private let nativeOptics = NativeGlassOptics { Ghostty.logger.warning("\($0)") }
    private var optics = GlassOptics()
    private var inactiveOpacity: CGFloat = 0

    init(topOffset: CGFloat) {
        self.glassEffectView = NSGlassEffectView()
        self.tintOverlay = NSView()
        super.init(frame: .zero)

        translatesAutoresizingMaskIntoConstraints = false

        // Glass effect view fills this view.
        glassEffectView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(glassEffectView)
        topConstraint = glassEffectView.topAnchor.constraint(
            equalTo: topAnchor,
            constant: topOffset
        )
        NSLayoutConstraint.activate([
            topConstraint,
            glassEffectView.leadingAnchor.constraint(equalTo: leadingAnchor),
            glassEffectView.bottomAnchor.constraint(equalTo: bottomAnchor),
            glassEffectView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        // Tint overlay sits above the glass effect.
        tintOverlay.translatesAutoresizingMaskIntoConstraints = false
        tintOverlay.wantsLayer = true
        tintOverlay.alphaValue = 0
        addSubview(tintOverlay, positioned: .above, relativeTo: glassEffectView)

        NSLayoutConstraint.activate([
            tintOverlay.topAnchor.constraint(equalTo: glassEffectView.topAnchor),
            tintOverlay.leadingAnchor.constraint(equalTo: glassEffectView.leadingAnchor),
            tintOverlay.bottomAnchor.constraint(equalTo: glassEffectView.bottomAnchor),
            tintOverlay.trailingAnchor.constraint(equalTo: glassEffectView.trailingAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        nativeOptics.update(root: glassEffectView.layer, optics: optics)
    }

    /// Configures native glass and the independent inactive-window overlay.
    func configure(
        style: NSGlassEffectView.Style,
        appearance: TerminalViewContainer.GlassAppearance,
        cornerRadius: CGFloat?,
        optics: GlassOptics,
        isKeyWindow: Bool
    ) {
        self.optics = optics
        glassEffectView.style = style
        glassEffectView.tintColor = appearance.tintColor
        glassEffectView.cornerRadius = cornerRadius ?? 0
        tintOverlay.layer?.backgroundColor = appearance.inactiveColor.cgColor
        inactiveOpacity = appearance.inactiveOpacity
        updateKeyStatus(isKeyWindow)
        nativeOptics.update(root: glassEffectView.layer, optics: optics)
    }

    /// Updates the top inset offset for both the glass effect and tint overlay.
    /// Call this when the safe area insets change (e.g., during layout).
    func updateTopInset(_ offset: CGFloat) {
        topConstraint.constant = offset
    }

    /// Updates the tint overlay visibility based on window key status.
    func updateKeyStatus(_ isKeyWindow: Bool) {
        tintOverlay.alphaValue = isKeyWindow ? 0 : inactiveOpacity
    }
}
#endif // compiler(>=6.2)

extension TerminalViewContainer {
#if compiler(>=6.2)
    @available(macOS 26.0, *)
    private func addGlassEffectViewIfNeeded() -> TerminalGlassView? {
        if let existed = glassEffectView as? TerminalGlassView {
            updateGlassEffectTopInsetIfNeeded()
            return existed
        }
        guard let themeFrameView = windowThemeFrameView else {
            return nil
        }
        let effectView = TerminalGlassView(topOffset: -themeFrameView.safeAreaInsets.top)
        addSubview(effectView, positioned: .below, relativeTo: terminalView)
        NSLayoutConstraint.activate([
            effectView.topAnchor.constraint(equalTo: topAnchor),
            effectView.leadingAnchor.constraint(equalTo: leadingAnchor),
            effectView.bottomAnchor.constraint(equalTo: bottomAnchor),
            effectView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        glassEffectView = effectView
        return effectView
    }
#endif // compiler(>=6.2)

    private func updateGlassEffectIfNeeded() {
#if compiler(>=6.2)
        guard #available(macOS 26.0, *), let derivedConfig else {
            glassEffectView?.removeFromSuperview()
            glassEffectView = nil
            return
        }
        guard let effectView = addGlassEffectViewIfNeeded() else {
            return
        }

        effectView.configure(
            style: derivedConfig.style.official,
            appearance: derivedConfig.appearance,
            cornerRadius: derivedConfig.cornerRadius,
            optics: derivedConfig.optics,
            isKeyWindow: window?.isKeyWindow ?? true
        )
#endif // compiler(>=6.2)
    }

    private func updateGlassEffectTopInsetIfNeeded() {
#if compiler(>=6.2)
        guard
            #available(macOS 26.0, *),
            let effectView = glassEffectView as? TerminalGlassView,
            let themeFrameView = windowThemeFrameView
        else {
            return
        }
        effectView.updateTopInset(-themeFrameView.safeAreaInsets.top)
#endif // compiler(>=6.2)
    }

    func updateGlassTintOverlay(isKeyWindow: Bool) {
#if compiler(>=6.2)
        guard
            #available(macOS 26.0, *),
            let effectView = glassEffectView as? TerminalGlassView
        else {
            return
        }
        effectView.updateKeyStatus(isKeyWindow)
#endif // compiler(>=6.2)
    }

    struct GlassAppearance: Equatable {
        let tintColor: NSColor
        let inactiveColor: NSColor
        let inactiveOpacity: CGFloat

        init(
            backgroundColor: NSColor,
            backgroundOpacity: Double,
            tintColor: NSColor? = nil,
            tintOpacity: Double? = nil,
            inactiveTintOpacity: Double? = nil,
            inactiveTintSaturation: Double? = nil
        ) {
            self.tintColor = (tintColor ?? backgroundColor)
                .withAlphaComponent(tintOpacity ?? backgroundOpacity)
            inactiveColor = backgroundColor.adjustingSaturation(by: inactiveTintSaturation ?? 1.2)
            inactiveOpacity = inactiveTintOpacity.map { CGFloat($0) } ??
                (backgroundColor.isLightColor ? 0.35 : 0.85)
        }
    }

    struct DerivedConfig: Equatable {
        let appearance: GlassAppearance
        let cornerRadius: CGFloat?
        let optics: GlassOptics
        let style: BackportNSGlassStyle

        init?(config: Ghostty.Config, preferredBackgroundColor: NSColor?, cornerRadius: CGFloat?) {
            switch config.backgroundBlur {
            case .macosGlassRegular:
                style = .regular
            case .macosGlassClear:
                style = .clear
            default:
                return nil
            }
            self.appearance = GlassAppearance(
                backgroundColor: preferredBackgroundColor ?? NSColor(config.backgroundColor),
                backgroundOpacity: config.backgroundOpacity,
                tintColor: config.macosGlassTintColor.map { NSColor($0) },
                tintOpacity: config.macosGlassTintOpacity,
                inactiveTintOpacity: config.macosGlassInactiveTintOpacity,
                inactiveTintSaturation: config.macosGlassInactiveTintSaturation
            )
            self.cornerRadius = cornerRadius
            self.optics = config.macosGlassOptics
        }
    }
}
