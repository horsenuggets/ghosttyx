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
}
