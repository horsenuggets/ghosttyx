import AppKit
import CoreText

enum TabTitleTypography {
    static let tabFont: NSFont = {
        let descriptor = CTFontDescriptorCreateCopyWithAttributes(
            CTFontCopyFontDescriptor(windowFont),
            [kCTFontVariationAttribute: [NSNumber(value: 0x77676874): 300]] as CFDictionary
        )
        return CTFontCreateWithFontDescriptor(descriptor, windowFont.pointSize - 1, nil) as NSFont
    }()

    static let windowFont: NSFont = {
        func descriptor(_ resource: String, name: String) -> CTFontDescriptor {
            guard let url = Bundle.main.url(forResource: resource, withExtension: "ttf"),
                  let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
                  let descriptor = descriptors.first(where: {
                      CTFontDescriptorCopyAttribute($0, kCTFontNameAttribute) as? String == name
                  }) else {
                preconditionFailure("The bundled title font \"\(resource)\" is missing.")
            }
            return descriptor
        }
        let primary = descriptor("Lexend-VariableFont_wght", name: "Lexend-Regular")
        return CTFontCreateWithFontDescriptor(primary, NSFont.systemFontSize, nil) as NSFont
    }()

    private static let bundledSymbolFont: CTFont? = {
        guard let url = Bundle.main.url(forResource: "Gridfit Mono Regular", withExtension: "ttf"),
              let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
              let descriptor = descriptors.first else {
            return nil
        }
        return CTFontCreateWithFontDescriptor(descriptor, NSFont.systemFontSize, nil)
    }()

    private static let symbolCharacters = bundledSymbolFont.map {
        (CTFontCopyCharacterSet($0) as CharacterSet)
            .intersection(CharacterSet.symbols.union(.punctuationCharacters))
    }

    static func tabFont(forWindowFont font: NSFont?) -> NSFont? {
        font == windowFont ? tabFont : font
    }

    static func editorFont(_ font: NSFont, windowFont: NSFont?) -> NSFont {
        guard isSymbolFont(font) else { return font }
        return tabFont(forWindowFont: windowFont) ?? .titleBarFont(ofSize: font.pointSize)
    }

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
                [.font: font, .foregroundColor: color, .kern: 0.3],
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

    static func nativeTitle(_ title: String, original: NSAttributedString, font: NSFont?) -> NSAttributedString {
        let font = font ?? NSFont.titleBarFont(ofSize: NSFont.systemFontSize)
        var attributes = original.length > 0 ? original.attributes(at: 0, effectiveRange: nil) : [:]
        attributes[.font] = font
        let result = NSMutableAttributedString(string: title, attributes: attributes)
        applySymbolFont(to: result, pointSize: font.pointSize)
        return result
    }

    @discardableResult
    static func applySymbolFont(to title: NSMutableAttributedString, pointSize: CGFloat) -> Bool {
        guard let bundledSymbolFont, let symbolCharacters else { return false }
        let string = title.string
        // Style standalone glyphs and their text variants. Leave emoji variants
        // and other multi-scalar characters intact.
        let symbolRanges = string.indices.compactMap { index -> NSRange? in
            var scalars = string[index].unicodeScalars.makeIterator()
            guard let scalar = scalars.next(), scalar.value > 0x7F, symbolCharacters.contains(scalar) else {
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
