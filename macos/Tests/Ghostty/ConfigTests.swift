import Testing
@testable import Ghostty
import SwiftUI

@Suite
struct ConfigTests {
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
