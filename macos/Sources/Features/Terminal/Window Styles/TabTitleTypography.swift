import AppKit
import CoreText

enum TabTitleTypography {
    private static let symbolFontDescriptor: CTFontDescriptor? = {
        guard let url = Bundle.main.url(forResource: "Gridfit Symbols", withExtension: "ttf"),
              let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor] else {
            return nil
        }
        return descriptors.first
    }()

    static func attributedTitle(_ title: String, font: NSFont?, color: NSColor) -> NSAttributedString? {
        // Squared dot, white medium square, and black medium square are status
        // indicators. Match whole characters to respect explicit emoji presentation.
        let symbolRanges = title.indices.compactMap { index -> NSRange? in
            switch title[index] {
            case "⊡", "◻", "◼", "⊡\u{FE0E}", "◻\u{FE0E}", "◼\u{FE0E}":
                return NSRange(index..<title.index(after: index), in: title)
            default:
                return nil
            }
        }
        let descriptor = symbolRanges.isEmpty ? nil : symbolFontDescriptor
        guard font != nil || descriptor != nil else { return nil }

        let baseFont = font ?? .titleBarFont(ofSize: NSFont.systemFontSize)
        let result = NSMutableAttributedString(string: title, attributes: [
            .font: baseFont,
            .foregroundColor: color,
        ])
        if let descriptor {
            let symbolFont = CTFontCreateWithFontDescriptor(descriptor, baseFont.pointSize, nil) as NSFont
            for range in symbolRanges {
                result.addAttribute(.font, value: symbolFont, range: range)
            }
        }
        return result
    }
}
