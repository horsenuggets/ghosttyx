import AppKit
import CoreText

enum TabTitleTypography {
    private static let bundledSymbolFont: CTFont? = {
        guard let url = Bundle.main.url(forResource: "Gridfit Symbols", withExtension: "ttf"),
              let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
              let descriptor = descriptors.first else {
            return nil
        }
        return CTFontCreateWithFontDescriptor(descriptor, NSFont.systemFontSize, nil)
    }()

    private static let symbolCharacters = bundledSymbolFont.map { CTFontCopyCharacterSet($0) as CharacterSet }

    static func isSymbolFont(_ font: NSFont) -> Bool {
        bundledSymbolFont.map { ($0 as NSFont).fontName == font.fontName } ?? false
    }

    static func attributedTitle(_ title: String, font: NSFont?, color: NSColor) -> NSAttributedString? {
        let result = NSMutableAttributedString(string: title)
        let fullRange = NSRange(location: 0, length: result.length)
        let baseFont: NSFont
        if let font {
            baseFont = font
            result.addAttributes(
                [.font: font, .foregroundColor: color],
                range: fullRange
            )
        } else {
            // The title bar face is the headline cut, which is bolder than the tab
            // title's native regular face. Start from the system font so titles
            // without a custom font keep their original weight.
            baseFont = .systemFont(ofSize: NSFont.systemFontSize)
            result.addAttribute(.font, value: baseFont, range: fullRange)
        }
        let styledSymbols = applySymbolFont(to: result, pointSize: baseFont.pointSize)
        return font != nil || styledSymbols ? result : nil
    }

    @discardableResult
    static func applySymbolFont(to title: NSMutableAttributedString, pointSize: CGFloat) -> Bool {
        guard let bundledSymbolFont, let symbolCharacters else { return false }
        let string = title.string
        // Style standalone glyphs and their text variants. Leave emoji variants
        // and other multi-scalar characters intact.
        let symbolRanges = string.indices.compactMap { index -> NSRange? in
            var scalars = string[index].unicodeScalars.makeIterator()
            guard let scalar = scalars.next(), symbolCharacters.contains(scalar) else {
                return nil
            }
            if let selector = scalars.next(), selector.value != 0xFE0E || scalars.next() != nil {
                return nil
            }
            return NSRange(index..<string.index(after: index), in: string)
        }
        guard !symbolRanges.isEmpty else { return false }
        let symbolFont = CTFontCreateCopyWithAttributes(bundledSymbolFont, pointSize, nil, nil) as NSFont
        for range in symbolRanges {
            title.addAttribute(.font, value: symbolFont, range: range)
        }
        return true
    }
}
