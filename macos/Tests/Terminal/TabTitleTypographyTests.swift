import AppKit
import CoreText
import Testing
@testable import Ghostty

struct TabTitleTypographyTests {
    @Test func missingWindowFontDoesNotSpreadTheLeadingSymbolFont() throws {
        let text = "☑ Session"
        var styled = NSAttributedString(string: text)
        let expected = NSFont.titleBarFont(ofSize: NSFont.systemFontSize)
        for _ in 0..<2 {
            styled = TabTitleTypography.nativeTitle(text, original: styled, font: nil)
            let symbol = try #require(styled.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
            #expect(TabTitleTypography.isSymbolFont(symbol))
            for index in 1..<styled.length {
                #expect(styled.attribute(.font, at: index, effectiveRange: nil) as? NSFont == expected)
            }
        }
    }

    @Test func renameEditorUsesTheDisplayedTabFontAfterALeadingSymbol() throws {
        let text = "☑ Session"
        let custom = NSFont.monospacedSystemFont(ofSize: 16, weight: .medium)
        for windowFont in [TabTitleTypography.windowFont, custom, nil] as [NSFont?] {
            let tabFont = TabTitleTypography.tabFont(forWindowFont: windowFont)
            let styled = try #require(TabTitleTypography.attributedTitle(text, font: tabFont, color: .labelColor))
            let symbol = try #require(styled.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
            let editorFont = TabTitleTypography.editorFont(symbol, windowFont: windowFont)
            #expect(editorFont == (tabFont ?? NSFont.titleBarFont(ofSize: symbol.pointSize)))
            let editorTitle = try #require(TabTitleTypography.attributedTitle(text, font: editorFont, color: .labelColor))
            let editorSymbol = try #require(editorTitle.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
            #expect(editorSymbol.pointSize == symbol.pointSize)
            #expect(TabTitleTypography.editorFont(editorFont, windowFont: windowFont) == editorFont)
        }
    }

    @Test(arguments: ["~/", "project/", "~/Projects/", "/", "Session", ""])
    func nativeWindowTitlePreservesTheSharedTitle(_ title: String) {
        let original = NSAttributedString(string: "Old title", attributes: [
            .foregroundColor: NSColor.secondaryLabelColor
        ])
        let styled = TabTitleTypography.nativeTitle(
            title, original: original, font: TabTitleTypography.windowFont
        )
        #expect(styled.string == title)
        if !title.isEmpty {
            #expect(styled.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor == .secondaryLabelColor)
        }
    }

    @Test func tabTrackingDoesNotChangeWindowTracking() throws {
        let text = "Session ☑"
        let tab = try #require(TabTitleTypography.attributedTitle(
            text, font: TabTitleTypography.tabFont, color: .labelColor
        ))
        for index in 0..<tab.length {
            #expect(tab.attribute(.kern, at: index, effectiveRange: nil) as? Double == 0.3)
        }
        let window = TabTitleTypography.nativeTitle(
            text, original: NSAttributedString(string: text), font: TabTitleTypography.windowFont
        )
        #expect(window.attribute(.kern, at: 0, effectiveRange: nil) == nil)
    }

    @Test func customTitleFontsRemainUnchanged() {
        let custom = NSFont.monospacedSystemFont(ofSize: 16, weight: .medium)
        #expect(TabTitleTypography.tabFont(forWindowFont: custom) == custom)
        #expect(TabTitleTypography.tabFont(forWindowFont: nil) == nil)
        #expect(TabTitleTypography.tabFont(forWindowFont: TabTitleTypography.windowFont) == TabTitleTypography.tabFont)
    }

    @Test func tabTitlesUseTheRegularFaceAtTenPoints() throws {
        let windowFont = TabTitleTypography.windowFont
        let tabFont = TabTitleTypography.tabFont
        let windowTraits = CTFontCopyTraits(windowFont) as NSDictionary
        let tabTraits = CTFontCopyTraits(tabFont) as NSDictionary
        let windowWeight = try #require(windowTraits[kCTFontWeightTrait] as? NSNumber)
        let tabWeight = try #require(tabTraits[kCTFontWeightTrait] as? NSNumber)
        #expect(abs(tabWeight.doubleValue - windowWeight.doubleValue) < 0.001)
        #expect(tabFont.pointSize == 10)
        #expect(windowFont.pointSize == NSFont.systemFontSize)
        #expect(windowFont.fontName == "Lexend-Regular")
        #expect(tabFont.fontName == "Lexend-Regular")
    }

    @Test func titlesUseLexendForASCIIAndGridfitForSymbols() throws {
        let font = TabTitleTypography.windowFont
        #expect(font.fontName == "Lexend-Regular")
        let text = "Session / test-123 + [] ☑"
        let title = try #require(TabTitleTypography.attributedTitle(text, font: font, color: .labelColor))
        for index in 0..<(text as NSString).range(of: "☑").location {
            #expect(title.attribute(.font, at: index, effectiveRange: nil) as? NSFont == font)
        }
        let symbolFont = try #require(title.attribute(.font, at: title.length - 1, effectiveRange: nil) as? NSFont)
        #expect(symbolFont.fontName == "GridfitMono-Regular")
    }

    @Test func statusSquaresUseTheSameGridfitMetrics() throws {
        let baseFont = NSFont.monospacedSystemFont(ofSize: 15, weight: .regular)
        var advances: [CGFloat] = []
        var bounds: [CGRect] = []
        for symbol in ["⊡", "◻", "◼"] {
            let title = "🐟 \(symbol) Session"
            let styled = try #require(TabTitleTypography.attributedTitle(title, font: baseFont, color: .labelColor))
            let range = (title as NSString).range(of: symbol)
            let font = try #require(styled.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont)
            #expect(font.fontName == "GridfitMono-Regular")
            #expect(font.pointSize == baseFont.pointSize)
            #expect(styled.attribute(.font, at: NSMaxRange(range), effectiveRange: nil) as? NSFont == baseFont)
            #expect(styled.string == title)

            let line = CTLineCreateWithAttributedString(styled.attributedSubstring(from: range))
            let runs = try #require(CTLineGetGlyphRuns(line) as? [CTRun])
            let run = try #require(runs.first)
            let shapedFont = try #require((CTRunGetAttributes(run) as NSDictionary)[kCTFontAttributeName] as? NSFont)
            #expect(shapedFont.fontName == font.fontName)
            #expect(CTRunGetGlyphCount(run) == 1)
            var glyph = CGGlyph()
            CTRunGetGlyphs(run, CFRange(location: 0, length: 1), &glyph)
            advances.append(CTFontGetAdvancesForGlyphs(font, .horizontal, &glyph, nil, 1))
            bounds.append(CTFontGetBoundingRectsForGlyphs(font, .horizontal, &glyph, nil, 1))
        }
        #expect(advances.allSatisfy { $0 > 0 && $0 == advances.first })
        #expect(bounds.allSatisfy { !$0.isEmpty && $0 == bounds.first })
    }

    @Test(arguments: ["☑", "☑\u{FE0E}"])
    func ballotBoxUsesGridfit(_ symbol: String) throws {
        let title = try #require(TabTitleTypography.attributedTitle(symbol, font: nil, color: .labelColor))
        let line = CTLineCreateWithAttributedString(title)
        let runs = try #require(CTLineGetGlyphRuns(line) as? [CTRun])
        let run = try #require(runs.first)
        let font = try #require((CTRunGetAttributes(run) as NSDictionary)[kCTFontAttributeName] as? NSFont)
        #expect(font.fontName == "GridfitMono-Regular")
    }

    @Test func titlesWithoutCustomFontUseTheNativeRegularFace() throws {
        let title = "☑ Session"
        let styled = try #require(TabTitleTypography.attributedTitle(title, font: nil, color: .labelColor))
        let asciiRange = (title as NSString).range(of: "Session")
        let font = try #require(styled.attribute(.font, at: asciiRange.location, effectiveRange: nil) as? NSFont)
        #expect(font.fontName == NSFont.systemFont(ofSize: NSFont.systemFontSize).fontName)
        #expect(styled.attribute(.foregroundColor, at: asciiRange.location, effectiveRange: nil) == nil)
    }

    @Test func plainTitlesAndExplicitEmojiKeepSystemStyling() {
        for title in ["Session", "◻\u{FE0F} Session", "◼\u{FE0F} Session", "☑\u{FE0F} Session"] {
            #expect(TabTitleTypography.attributedTitle(title, font: nil, color: .labelColor) == nil)
        }
    }

    @Test func stylingNativeTitlePreservesItsOtherAttributes() throws {
        let font = NSFont.titleBarFont(ofSize: 13)
        let title = NSMutableAttributedString(string: "☑ Session", attributes: [
            .font: font,
            .foregroundColor: NSColor.secondaryLabelColor,
        ])
        #expect(TabTitleTypography.applySymbolFont(to: title, pointSize: font.pointSize))
        let symbolFont = try #require(title.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        #expect(symbolFont.fontName == "GridfitMono-Regular")
        #expect(title.attribute(.font, at: 2, effectiveRange: nil) as? NSFont == font)
        #expect(title.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor == .secondaryLabelColor)
    }
}
