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

    static func attributedTitle(_ title: String, font: NSFont?, color: NSColor) -> NSAttributedString? {
        // Style standalone glyphs and their text variants. Leave emoji variants
        // and other multi-scalar characters intact.
        let symbolRanges = title.indices.compactMap { index -> NSRange? in
            var scalars = title[index].unicodeScalars.makeIterator()
            guard let scalar = scalars.next(), symbolCharacters?.contains(scalar) == true else {
                return nil
            }
            if let selector = scalars.next(), selector.value != 0xFE0E || scalars.next() != nil {
                return nil
            }
            return NSRange(index..<title.index(after: index), in: title)
        }
        guard font != nil || !symbolRanges.isEmpty else { return nil }

        let baseFont = font ?? .titleBarFont(ofSize: NSFont.systemFontSize)
        let result = NSMutableAttributedString(string: title, attributes: [
            .font: baseFont,
            .foregroundColor: color,
        ])
        if !symbolRanges.isEmpty, let bundledSymbolFont {
            let symbolFont = CTFontCreateCopyWithAttributes(bundledSymbolFont, baseFont.pointSize, nil, nil) as NSFont
            for range in symbolRanges {
                result.addAttribute(.font, value: symbolFont, range: range)
            }
        }
        return result
    }
}
