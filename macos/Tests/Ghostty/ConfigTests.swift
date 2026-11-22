import Testing
@testable import Ghostty
import SwiftUI

@Suite
struct ConfigTests {
    @Test func glassOverridesAreUnsetUnlessConfigured() throws {
        let config = try TemporaryConfig("")
        #expect(config.macosGlassOptics == GlassOptics())
        #expect(config.macosGlassInactiveTintOpacity == nil)
        #expect(config.macosGlassInactiveTintSaturation == nil)
        #expect(config.macosGlassTintColor == nil)
        #expect(config.macosGlassTintOpacity == nil)
    }

    @Test func glassOverridesCrossTheConfigBridgeAndResetOnReload() throws {
        let config = try TemporaryConfig("""
        macos-glass-blur-radius = 0
        macos-glass-highlight-angle = -90
        macos-glass-highlight-spread = 120
        macos-glass-highlight-strength = 2
        macos-glass-inactive-tint-opacity = 0
        macos-glass-inactive-tint-saturation = 0.5
        macos-glass-refraction-amount = -60
        macos-glass-refraction-height = 20
        macos-glass-tint-color = #123456
        macos-glass-tint-opacity = 0.25
        """)
        #expect(config.errors.isEmpty)
        #expect(config.macosGlassOptics == GlassOptics(
            blurRadius: 0,
            highlightAngle: -90,
            highlightSpread: 120,
            highlightStrength: 2,
            refractionAmount: -60,
            refractionHeight: 20
        ))
        #expect(config.macosGlassInactiveTintOpacity == 0)
        #expect(config.macosGlassInactiveTintSaturation == 0.5)
        #expect(config.macosGlassTintColor == Color(red: 18.0 / 255, green: 52.0 / 255, blue: 86.0 / 255))
        #expect(config.macosGlassTintOpacity == 0.25)

        try config.reload("")
        #expect(config.macosGlassOptics == GlassOptics())
        #expect(config.macosGlassInactiveTintOpacity == nil)
        #expect(config.macosGlassInactiveTintSaturation == nil)
        #expect(config.macosGlassTintColor == nil)
        #expect(config.macosGlassTintOpacity == nil)
    }

    @Test(arguments: [
        "macos-glass-blur-radius = -1",
        "macos-glass-blur-radius = nan",
        "macos-glass-highlight-angle = inf",
        "macos-glass-highlight-spread = 361",
        "macos-glass-highlight-strength = -1",
        "macos-glass-inactive-tint-opacity = -0.1",
        "macos-glass-inactive-tint-saturation = -1",
        "macos-glass-refraction-amount = -inf",
        "macos-glass-refraction-height = -1",
        "macos-glass-tint-opacity = 1.1",
    ])
    func invalidGlassOverridesProduceDiagnostics(text: String) throws {
        let config = try TemporaryConfig(text)
        #expect(!config.errors.isEmpty)
    }

    // MARK: - Split Divider

    @Test func splitDividerIsOpaqueByDefault() throws {
        let config = try TemporaryConfig("")
        #expect(config.splitDividerOpacity == 1)
        #expect(NSColor(config.splitDividerColor).alphaComponent == 1)
    }

    @Test(arguments: [
        (true, "0", 0.0),
        (true, "0.4", 0.4),
        (true, "2", 1.0),
        (false, "0", 0.0),
        (false, "0.4", 0.4),
        (false, "-1", 0.0),
    ])
    func splitDividerOpacityAppliesToEveryColorSource(
        hasColor: Bool,
        opacity: String,
        expected: Double
    ) throws {
        let color = hasColor ? "split-divider-color = #336699\n" : ""
        let config = try TemporaryConfig(color + "split-divider-opacity = \(opacity)")
        #expect(config.errors.isEmpty)
        #expect(config.splitDividerOpacity == expected)

        let divider = try #require(NSColor(config.splitDividerColor).usingColorSpace(.sRGB))
        #expect(abs(divider.alphaComponent - expected) < 0.001)
        if hasColor {
            #expect(abs(divider.redComponent - 0x33 / 255) < 0.001)
            #expect(abs(divider.greenComponent - 0x66 / 255) < 0.001)
            #expect(abs(divider.blueComponent - 0x99 / 255) < 0.001)
        }
    }

    @Test func splitDividerOpacityResetsOnReload() throws {
        let config = try TemporaryConfig("split-divider-opacity = 0.25")
        #expect(config.splitDividerOpacity == 0.25)

        try config.reload("split-divider-opacity =")
        #expect(config.splitDividerOpacity == 1)
        #expect(NSColor(config.splitDividerColor).alphaComponent == 1)

        try config.reload("split-divider-opacity = 0.5")
        #expect(config.splitDividerOpacity == 0.5)

        try config.reload("")
        #expect(config.splitDividerOpacity == 1)
    }

    // MARK: - Boolean Properties

    @Test func initialWindowDefaultsToTrue() throws {
        let config = try TemporaryConfig("")
        #expect(config.initialWindow == true)
    }

    @Test func initialWindowSetToFalse() throws {
        let config = try TemporaryConfig("initial-window = false")
        #expect(config.initialWindow == false)
    }

    @Test func quitAfterLastWindowClosedDefaultsToFalse() throws {
        let config = try TemporaryConfig("")
        #expect(config.shouldQuitAfterLastWindowClosed == false)
    }

    @Test func quitAfterLastWindowClosedSetToTrue() throws {
        let config = try TemporaryConfig("quit-after-last-window-closed = true")
        #expect(config.shouldQuitAfterLastWindowClosed == true)
    }

    @Test func windowStepResizeDefaultsToFalse() throws {
        let config = try TemporaryConfig("")
        #expect(config.windowStepResize == false)
    }

    @Test func focusFollowsMouseDefaultsToFalse() throws {
        let config = try TemporaryConfig("")
        #expect(config.focusFollowsMouse == false)
    }

    @Test func focusFollowsMouseSetToTrue() throws {
        let config = try TemporaryConfig("focus-follows-mouse = true")
        #expect(config.focusFollowsMouse == true)
    }

    @Test func windowDecorationsDefaultsToTrue() throws {
        let config = try TemporaryConfig("")
        #expect(config.windowDecorations == true)
    }

    @Test func windowDecorationsNone() throws {
        let config = try TemporaryConfig("window-decoration = none")
        #expect(config.windowDecorations == false)
    }

    @Test func macosWindowShadowDefaultsToTrue() throws {
        let config = try TemporaryConfig("")
        #expect(config.macosWindowShadow == true)
    }

    @Test func maximizeDefaultsToFalse() throws {
        let config = try TemporaryConfig("")
        #expect(config.maximize == false)
    }

    @Test func maximizeSetToTrue() throws {
        let config = try TemporaryConfig("maximize = true")
        #expect(config.maximize == true)
    }

    // MARK: - String / Optional String Properties

    @Test func titleDefaultsToNil() throws {
        let config = try TemporaryConfig("")
        #expect(config.title == nil)
    }

    @Test func titleSetToCustomValue() throws {
        let config = try TemporaryConfig("title = My Terminal")
        #expect(config.title == "My Terminal")
    }

    @Test func windowTitleFontFamilyDefaultsToNil() throws {
        let config = try TemporaryConfig("")
        #expect(config.windowTitleFontFamily == nil)
    }

    @Test func windowTitleFontFamilySetToValue() throws {
        let config = try TemporaryConfig("window-title-font-family = Menlo")
        #expect(config.windowTitleFontFamily == "Menlo")
    }

    // MARK: - Enum Properties

    @Test func macosTitlebarStyleDefaultsToTransparent() throws {
        let config = try TemporaryConfig("")
        #expect(config.macosTitlebarStyle == .transparent)
    }

    @Test(arguments: [
        ("native", Ghostty.Config.MacOSTitlebarStyle.native),
        ("transparent", Ghostty.Config.MacOSTitlebarStyle.transparent),
        ("tabs", Ghostty.Config.MacOSTitlebarStyle.tabs),
        ("hidden", Ghostty.Config.MacOSTitlebarStyle.hidden),
    ])
    func macosTitlebarStyleValues(raw: String, expected: Ghostty.Config.MacOSTitlebarStyle) throws {
        let config = try TemporaryConfig("macos-titlebar-style = \(raw)")
        #expect(config.macosTitlebarStyle == expected)
    }

    @Test func resizeOverlayDefaultsToAfterFirst() throws {
        let config = try TemporaryConfig("")
        #expect(config.resizeOverlay == .after_first)
    }

    @Test(arguments: [
        ("always", Ghostty.Config.ResizeOverlay.always),
        ("never", Ghostty.Config.ResizeOverlay.never),
        ("after-first", Ghostty.Config.ResizeOverlay.after_first),
    ])
    func resizeOverlayValues(raw: String, expected: Ghostty.Config.ResizeOverlay) throws {
        let config = try TemporaryConfig("resize-overlay = \(raw)")
        #expect(config.resizeOverlay == expected)
    }

    @Test func resizeOverlayPositionDefaultsToCenter() throws {
        let config = try TemporaryConfig("")
        #expect(config.resizeOverlayPosition == .center)
    }

    @Test func macosIconDefaultsToOfficial() throws {
        let config = try TemporaryConfig("")
        #expect(config.macosIcon == .official)
    }

    @Test func macosIconFrameDefaultsToAluminum() throws {
        let config = try TemporaryConfig("")
        #expect(config.macosIconFrame == .aluminum)
    }

    @Test func macosWindowButtonsDefaultsToVisible() throws {
        let config = try TemporaryConfig("")
        #expect(config.macosWindowButtons == .visible)
    }

    @Test func scrollbarDefaultsToSystem() throws {
        let config = try TemporaryConfig("")
        #expect(config.scrollbar == .system)
    }

    @Test func scrollbarSetToNever() throws {
        let config = try TemporaryConfig("scrollbar = never")
        #expect(config.scrollbar == .never)
    }

    // MARK: - Optional Tab Background Colors

    @Test(arguments: [
        ("macos-tab-bar-background", \Ghostty.Config.macosTabBarBackground),
        ("macos-tab-active-background", \Ghostty.Config.macosTabActiveBackground),
        ("macos-tab-inactive-background", \Ghostty.Config.macosTabInactiveBackground),
    ])
    func macosTabBackgroundColors(key: String, accessor: KeyPath<Ghostty.Config, Color?>) throws {
        let config = try TemporaryConfig("")
        #expect(config[keyPath: accessor] == nil)

        let hex = Color(red: 0x12 / 255.0, green: 0x34 / 255.0, blue: 0x56 / 255.0)
        for value in ["#123456", "123456"] {
            try config.reload("\(key) = \(value)")
            #expect(config.errors.isEmpty)
            #expect(config[keyPath: accessor] == hex)
        }

        try config.reload("\(key) = red")
        #expect(config.errors.isEmpty)
        #expect(config[keyPath: accessor] == Color(red: 1, green: 0, blue: 0))

        // An explicit black color must not be confused with an unset value.
        try config.reload("\(key) = #000000")
        #expect(config.errors.isEmpty)
        #expect(config[keyPath: accessor] == Color(red: 0, green: 0, blue: 0))

        for value in ["not-a-color", "#GGHHII"] {
            try config.reload("\(key) = \(value)")
            #expect(!config.errors.isEmpty)
            #expect(config[keyPath: accessor] == nil)

            // Invalid values leave an earlier valid assignment intact.
            try config.reload("""
            \(key) = #123456
            \(key) = \(value)
            """)
            #expect(!config.errors.isEmpty)
            #expect(config[keyPath: accessor] == hex)
        }

        try config.reload("""
        \(key) = #123456
        \(key) =
        """)
        #expect(config.errors.isEmpty)
        #expect(config[keyPath: accessor] == nil)

        // Removing an override on reload restores the native appearance.
        try config.reload("\(key) = #123456")
        #expect(config[keyPath: accessor] == hex)
        try config.reload("")
        #expect(config.errors.isEmpty)
        #expect(config[keyPath: accessor] == nil)
    }

    @Test(arguments: [
        ("macos-tab-bar-opacity", \Ghostty.Config.macosTabBarOpacity),
        ("macos-tab-active-opacity", \Ghostty.Config.macosTabActiveOpacity),
        ("macos-tab-inactive-opacity", \Ghostty.Config.macosTabInactiveOpacity),
    ])
    func macosTabOpacities(key: String, accessor: KeyPath<Ghostty.Config, Double>) throws {
        let config = try TemporaryConfig("")
        #expect(config[keyPath: accessor] == 1)
        for (value, expected) in [("0", 0.0), ("0.5", 0.5), ("1", 1.0), ("-1", 0.0), ("2", 1.0)] {
            try config.reload("\(key) = \(value)")
            #expect(config.errors.isEmpty)
            #expect(config[keyPath: accessor] == expected)
        }
        try config.reload("\(key) = invalid")
        #expect(!config.errors.isEmpty)
        try config.reload("\(key) = 0.5\n\(key) =")
        #expect(config.errors.isEmpty)
        #expect(config[keyPath: accessor] == 1)
        try config.reload("\(key) = 0.5")
        try config.reload("")
        #expect(config[keyPath: accessor] == 1)
    }

    // MARK: - Numeric Properties

    @Test func backgroundOpacityDefaultsToOne() throws {
        let config = try TemporaryConfig("")
        #expect(config.backgroundOpacity == 1.0)
    }

    @Test func backgroundOpacitySetToCustom() throws {
        let config = try TemporaryConfig("background-opacity = 0.5")
        #expect(config.backgroundOpacity == 0.5)
    }

    @Test func windowPositionDefaultsToNil() throws {
        let config = try TemporaryConfig("")
        #expect(config.windowPositionX == nil)
        #expect(config.windowPositionY == nil)
    }

    // MARK: - Config Loading

    @Test func loadedIsTrueForValidConfig() throws {
        let config = try TemporaryConfig("")
        #expect(config.loaded == true)
    }

    @Test func unfinalizedConfigIsLoaded() throws {
        let config = try TemporaryConfig("", finalize: false)
        #expect(config.loaded == true)
    }

    @Test func reloadConfig() throws {
        let config = try TemporaryConfig("background-opacity = 0.5")
        #expect(config.backgroundOpacity == 0.5)

        try config.reload("background-opacity = 0.7")
        #expect(config.backgroundOpacity == 0.7)
    }

    @Test func defaultConfigIsLoaded() throws {
        let config = try TemporaryConfig("")
        #expect(config.optionalAutoUpdateChannel != nil) // release or tip
        let config1 = try TemporaryConfig("", finalize: false)
        #expect(config1.optionalAutoUpdateChannel == nil)
    }

    @Test func errorsEmptyForValidConfig() throws {
        let config = try TemporaryConfig("")
        #expect(config.errors.isEmpty)
    }

    @Test func errorsReportedForInvalidConfig() throws {
        let config = try TemporaryConfig("not-a-real-key = value")
        #expect(!config.errors.isEmpty)
    }

    // MARK: - Multiple Config Lines

    @Test func multipleConfigValues() throws {
        let config = try TemporaryConfig("""
        initial-window = false
        quit-after-last-window-closed = true
        maximize = true
        focus-follows-mouse = true
        """)
        #expect(config.initialWindow == false)
        #expect(config.shouldQuitAfterLastWindowClosed == true)
        #expect(config.maximize == true)
        #expect(config.focusFollowsMouse == true)
    }

    // MARK: - Keybind

    @Test
    func uppercasedLetterShouldBeNormalized() async throws {
        let config = try TemporaryConfig("""
        keybind=cmd+L=goto_split:left
        """)
        let shortcut = try #require(config.keyboardShortcut(for: "goto_split:left"))
        #expect(shortcut == .init("l", modifiers: [.command]))

        let config2 = try TemporaryConfig("""
        keybind=cmd+Ä=goto_split:left
        """)
        let shortcut2 = try #require(config2.keyboardShortcut(for: "goto_split:left"))
        #expect(shortcut2 == .init("ä", modifiers: [.command]))
    }

    @Test
    func emptyConfigShouldBeHaveDefaultShortcut() async throws {
        let config = try TemporaryConfig("")
        let newWindow = try #require(config.keyboardShortcut(for: "new_window"))
        #expect(newWindow == .init("n", modifiers: [.command]))
        let gotoToNextSplit = try #require(config.keyboardShortcut(for: "goto_split:next"))
        #expect(gotoToNextSplit == .init("]", modifiers: [.command]))
    }
}
