import AppKit
import CoreText
import Testing
@testable import Ghostty

struct TabTitleTypographyTests {
    @Test func statusSquaresUseTheSameGridfitMetrics() throws {
        let baseFont = NSFont.monospacedSystemFont(ofSize: 15, weight: .regular)
        var advances: [CGFloat] = []
        var bounds: [CGRect] = []
        for symbol in ["⊡", "◻", "◼"] {
            let title = "🐟 \(symbol) Session"
            let styled = try #require(TabTitleTypography.attributedTitle(title, font: baseFont, color: .labelColor))
            let range = (title as NSString).range(of: symbol)
            let font = try #require(styled.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont)
            #expect(font.fontName == "GridfitSymbols-Regular")
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
        #expect(font.fontName == "GridfitSymbols-Regular")
    }

    @Test func plainTitlesAndExplicitEmojiKeepSystemStyling() {
        for title in ["Session", "◻\u{FE0F} Session", "◼\u{FE0F} Session", "☑\u{FE0F} Session"] {
            #expect(TabTitleTypography.attributedTitle(title, font: nil, color: .labelColor) == nil)
        }
    }
}
