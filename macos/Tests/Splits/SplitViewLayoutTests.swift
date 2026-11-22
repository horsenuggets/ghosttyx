import SwiftUI
import Testing
@testable import Ghostty

@Suite
struct SplitViewLayoutTests {
    private func splitView(_ direction: SplitViewDirection, ratio: CGFloat) -> SplitView<EmptyView, EmptyView> {
        SplitView(
            direction,
            .constant(ratio),
            dividerColor: .clear,
            left: { EmptyView() },
            right: { EmptyView() },
            onEqualize: {}
        )
    }

    @Test(arguments: [SplitViewDirection.horizontal, .vertical], [0.1, 0.3, 0.5, 0.77])
    func dividerOccupiesItsOwnGapBetweenThePanes(direction: SplitViewDirection, ratio: CGFloat) {
        let size = CGSize(width: 801, height: 603)
        let view = splitView(direction, ratio: ratio)
        let left = view.leftRect(for: size)
        let right = view.rightRect(for: size, leftRect: left)
        let point = view.splitterPoint(for: size, leftRect: left)

        // The 1pt divider band, measured along the split axis.
        let (leftEnd, rightStart, total, center) = switch direction {
        case .horizontal: (left.maxX, right.minX, size.width, point.x)
        case .vertical: (left.maxY, right.minY, size.height, point.y)
        }

        #expect(rightStart - leftEnd == 1)
        #expect(center - 0.5 == leftEnd)
        #expect(center + 0.5 == rightStart)
        #expect(leftEnd + 1 + (total - rightStart) == total)
        #expect(!left.intersects(right))
    }

    @MainActor
    @Test(arguments: [SplitViewDirection.horizontal, .vertical])
    func translucentDividerBlendsOnlyWithTheBackground(direction: SplitViewDirection) throws {
        let pane = Color(red: 0, green: 0, blue: 1)
        let view = SplitView(
            direction,
            .constant(0.5),
            dividerColor: Color(red: 1, green: 0, blue: 0).opacity(0.5),
            left: { pane },
            right: { pane },
            onEqualize: {}
        )
        .frame(width: 200, height: 200)
        .background(Color(red: 0, green: 1, blue: 0))

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let image = try #require(renderer.cgImage)
        let pixels = try RGBAPixels(image)

        // At 2x the 1pt divider covers pixels 198 and 199 along the split axis.
        for offset in [198, 199] {
            let (x, y) = direction == .horizontal ? (offset, 200) : (200, offset)
            let pixel = pixels[x, y]
            #expect(abs(pixel.red - 0.5) < 0.05, "Pixel \(offset) red is \(pixel.red).")
            #expect(abs(pixel.green - 0.5) < 0.05, "Pixel \(offset) green is \(pixel.green).")
            #expect(pixel.blue < 0.05, "Pixel \(offset) shows the pane behind the divider.")
        }
    }
}

/// Reads an image as 8-bit sRGB pixels so tests can sample rendered colors.
private struct RGBAPixels {
    private let width: Int
    private let bytes: [UInt8]

    init(_ image: CGImage) throws {
        width = image.width
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: image.width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        try #require(drawn)
        self.bytes = bytes
    }

    /// Returns the color at a pixel, measured from the top left of the image.
    subscript(x: Int, y: Int) -> (red: Double, green: Double, blue: Double) {
        let index = (y * width + x) * 4
        return (Double(bytes[index]) / 255, Double(bytes[index + 1]) / 255, Double(bytes[index + 2]) / 255)
    }
}
