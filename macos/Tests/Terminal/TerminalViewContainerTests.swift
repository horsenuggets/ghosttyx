import CoreImage
import SwiftUI
import Testing
@testable import Ghostty

class MockTerminalViewContainer: TerminalViewContainer {
    var _windowCornerRadius: CGFloat?

    override var windowThemeFrameView: NSView? {
        NSView()
    }

    override var windowCornerRadius: CGFloat? {
        _windowCornerRadius
    }
}

class MockConfig: Ghostty.Config {
    init(backgroundBlur: Ghostty.Config.BackgroundBlur, backgroundColor: Color, backgroundOpacity: Double) {
        self._backgroundBlur = backgroundBlur
        self._backgroundColor = backgroundColor
        self._backgroundOpacity = backgroundOpacity
        super.init(config: nil)
    }

    var _backgroundBlur: Ghostty.Config.BackgroundBlur
    var _backgroundColor: Color
    var _backgroundOpacity: Double

    override var backgroundBlur: Ghostty.Config.BackgroundBlur { _backgroundBlur }
    override var backgroundColor: Color { _backgroundColor }
    override var backgroundOpacity: Double { _backgroundOpacity }
}

@MainActor
private func nextMainQueueTurn() async {
    await withCheckedContinuation { continuation in
        DispatchQueue.main.async { continuation.resume() }
    }
}

@MainActor
private func apply(
    _ config: Ghostty.Config,
    to view: TerminalViewContainer,
    preferredBackgroundColor: NSColor? = nil
) async {
    view.ghosttyConfigDidChange(config, preferredBackgroundColor: preferredBackgroundColor)
    await nextMainQueueTurn()
}

@MainActor
struct TerminalViewContainerTests {
    @Test func glassAvailability() async {
        let view = MockTerminalViewContainer { EmptyView() }
        let config = MockConfig(backgroundBlur: .macosGlassRegular, backgroundColor: .clear, backgroundOpacity: 1)
        await apply(config, to: view)
#if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            #expect(view.glassEffectView != nil)
        } else {
            #expect(view.glassEffectView == nil)
        }
#else
        #expect(view.glassEffectView == nil)
#endif
    }

    @Test func appearanceOverridesAreIndependentAndPure() {
        for light in [false, true] {
            let background: NSColor = light ? .white : .black
            for mask in 0..<16 {
                let color: NSColor? = mask & 1 != 0 ? .red : nil
                let opacity: Double? = mask & 2 != 0 ? 0.25 : nil
                let inactiveOpacity: Double? = mask & 4 != 0 ? 0 : nil
                let saturation: Double? = mask & 8 != 0 ? 0.5 : nil
                let first = TerminalViewContainer.GlassAppearance(
                    backgroundColor: background,
                    backgroundOpacity: 0.6,
                    tintColor: color,
                    tintOpacity: opacity,
                    inactiveTintOpacity: inactiveOpacity,
                    inactiveTintSaturation: saturation
                )
                let second = TerminalViewContainer.GlassAppearance(
                    backgroundColor: background,
                    backgroundOpacity: 0.6,
                    tintColor: color,
                    tintOpacity: opacity,
                    inactiveTintOpacity: inactiveOpacity,
                    inactiveTintSaturation: saturation
                )
                #expect(first == second)
                #expect(first.tintColor == (color ?? background).withAlphaComponent(opacity ?? 0.6))
                #expect(first.inactiveOpacity == CGFloat(inactiveOpacity ?? (light ? 0.35 : 0.85)))
                #expect(first.inactiveColor == background.adjustingSaturation(by: CGFloat(saturation ?? 1.2)))
            }
        }
    }

    @Test func inactiveSaturationDoesNotChangeGlassTint() {
        let background = NSColor(srgbRed: 0.8, green: 0.4, blue: 0.2, alpha: 1)
        let appearance = TerminalViewContainer.GlassAppearance(
            backgroundColor: background,
            backgroundOpacity: 0.7,
            inactiveTintSaturation: 0.5
        )
        #expect(abs(appearance.inactiveColor.saturationComponent - 0.375) < 0.000001)
        #expect(appearance.tintColor == background.withAlphaComponent(0.7))
    }

#if compiler(>=6.2)
    @Test func configChangeUpdatesGlass() async throws {
        guard #available(macOS 26.0, *) else { return }
        let view = MockTerminalViewContainer { EmptyView() }
        let config = MockConfig(backgroundBlur: .macosGlassRegular, backgroundColor: .clear, backgroundOpacity: 1)
        await apply(config, to: view)
        let effect = try #require(view.descendants(withClassName: "NSGlassEffectView").first as? NSGlassEffectView)
        #expect(effect.tintColor?.hexString == NSColor.clear.hexString)

        await apply(config, to: view, preferredBackgroundColor: .red)
        #expect(effect.tintColor?.hexString == NSColor.red.hexString)
        #expect(effect.cornerRadius == 0)
        view._windowCornerRadius = 10
        #expect(effect.cornerRadius == 0)
        await apply(config, to: view, preferredBackgroundColor: .red)
        #expect(effect.cornerRadius == 10)
        #expect(effect.style == .regular)

        config._backgroundBlur = .macosGlassClear
        await apply(config, to: view, preferredBackgroundColor: .red)
        #expect(effect.style == .clear)
        config._backgroundBlur = .disabled
        await apply(config, to: view)
        #expect(view.glassEffectView == nil)
    }

    @Test func tintOverridesReloadAndRespectFocus() async throws {
        guard #available(macOS 26.0, *) else { return }
        let config = try TemporaryConfig("""
        background-blur = macos-glass-clear
        background-opacity = 0.7
        macos-glass-tint-color = #ff0000
        macos-glass-tint-opacity = 0.25
        macos-glass-inactive-tint-opacity = 0.1
        macos-glass-inactive-tint-saturation = 0.5
        """)
        let view = MockTerminalViewContainer { EmptyView() }
        await apply(config, to: view, preferredBackgroundColor: .blue)
        let effect = try #require(view.descendants(withClassName: "NSGlassEffectView").first as? NSGlassEffectView)
        let overlay = try #require(view.glassEffectView?.subviews.first { $0 !== effect })
        #expect(effect.tintColor?.hexString == NSColor.red.hexString)
        #expect(effect.tintColor?.alphaComponent == 0.25)
        #expect(config.backgroundOpacity == 0.7)

        view.updateGlassTintOverlay(isKeyWindow: false)
        #expect(overlay.alphaValue == 0.1)
        view.updateGlassTintOverlay(isKeyWindow: true)
        #expect(overlay.alphaValue == 0)

        try config.reload("""
        background = #0000ff
        background-blur = macos-glass-clear
        background-opacity = 0.6
        """)
        await apply(config, to: view)
        #expect(effect.tintColor?.hexString == NSColor.blue.hexString)
        #expect(effect.tintColor?.alphaComponent == 0.6)
        view.updateGlassTintOverlay(isKeyWindow: false)
        #expect(overlay.alphaValue == 0.85)
    }
#endif
}

private final class TestGlassFilter: CIFilter {
    let values: [String: Double]

    init(_ values: [String: Double]) {
        self.values = values
        super.init()
    }

    required init?(coder: NSCoder) {
        return nil
    }

    // CIFilter otherwise considers these undeclared inputs equal, causing Core Animation
    // to discard replacements even when the boundary values differ.
    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? TestGlassFilter else { return false }
        return values == other.values
    }

    override var hash: Int { values.hashValue }
}

private struct TestGlassFilterAccess: GlassFilterAccess {
    var copyError: Error?

    func inputKeys(of filter: Any, keys: [String]) throws -> Set<String>? {
        (filter as? TestGlassFilter).map { Set($0.values.keys).intersection(keys) }
    }

    func copy(_ filter: Any, overriding inputs: [String: Double]) throws -> Any {
        if let copyError { throw copyError }
        let original = try #require(filter as? TestGlassFilter)
        return TestGlassFilter(original.values.merging(inputs) { _, replacement in replacement })
    }
}

enum CompanionFilterChange: CaseIterable {
    case insert
    case remove
    case reorder
    case replace
}

@MainActor
struct NativeGlassOpticsTests {
    @Test func mapsOnlyExplicitOverridesAndConvertsDegrees() {
        #expect(GlassOptics().inputs.isEmpty)
        let optics = GlassOptics(
            blurRadius: 0,
            highlightAngle: -90,
            highlightSpread: 180,
            highlightStrength: 2,
            refractionAmount: -60,
            refractionHeight: 20
        )
        #expect(optics.inputs == [
            "inputBlurRadius": 0,
            "inputInnerRefractionAmount": -60,
            "inputInnerRefractionHeight": 20,
            "inputKeyFillHighlightAmount": 2,
            "inputKeyFillHighlightAngle": -.pi / 2,
            "inputKeyFillHighlightSpread": .pi,
            "inputKeyFillHighlightSpreadSDR": .pi,
        ])
        #expect(optics.inputs == optics.inputs)
    }

    @Test func copiesFiltersAndRestoresRemovedOverrides() throws {
        let original = TestGlassFilter(["inputBlurRadius": 5, "inputInnerRefractionAmount": -60])
        let unrelated = CIFilter(name: "CIColorControls")
        let layer = CALayer()
        layer.filters = [original] + (unrelated.map { [$0] } ?? [])
        var diagnostics: [String] = []
        let adapter = NativeGlassOptics(access: TestGlassFilterAccess()) { diagnostics.append($0) }
        adapter.update(root: layer, optics: GlassOptics(blurRadius: 24, refractionAmount: -80))
        let applied = try #require(layer.filters?.first as? TestGlassFilter)
        #expect(applied !== original)
        #expect(original.values["inputBlurRadius"] == 5)
        #expect(applied.values["inputBlurRadius"] == 24)
        #expect(applied.values["inputInnerRefractionAmount"] == -80)
        #expect(layer.filters?.last as? CIFilter === unrelated)

        adapter.update(root: layer, optics: GlassOptics(refractionAmount: -20))
        let partial = try #require(layer.filters?.first as? TestGlassFilter)
        #expect(partial.values["inputBlurRadius"] == 5)
        #expect(partial.values["inputInnerRefractionAmount"] == -20)
        adapter.update(root: layer, optics: GlassOptics())
        #expect(layer.filters?.first as? TestGlassFilter === original)
        #expect(diagnostics.isEmpty)
    }

    @Test func reappliesAfterNativeFilterAndLayerReplacement() async throws {
        let root = CALayer()
        let child = CALayer()
        child.filters = [TestGlassFilter(["inputBlurRadius": 5])]
        root.addSublayer(child)
        var diagnostics: [String] = []
        let adapter = NativeGlassOptics(access: TestGlassFilterAccess()) { diagnostics.append($0) }
        adapter.update(root: root, optics: GlassOptics(blurRadius: 37))

        let newNative = TestGlassFilter(["inputBlurRadius": 10])
        child.filters = [newNative]
        await nextMainQueueTurn()
        await nextMainQueueTurn()
        #expect((child.filters?.first as? TestGlassFilter)?.values["inputBlurRadius"] == 37)

        let replacement = CALayer()
        let replacementNative = TestGlassFilter(["inputBlurRadius": 12])
        replacement.filters = [replacementNative]
        root.sublayers = [replacement]
        await nextMainQueueTurn()
        await nextMainQueueTurn()
        #expect((replacement.filters?.first as? TestGlassFilter)?.values["inputBlurRadius"] == 37)
        #expect(child.filters?.first as? TestGlassFilter === newNative)
        adapter.update(root: root, optics: GlassOptics())
        #expect(replacement.filters?.first as? TestGlassFilter === replacementNative)
        #expect(diagnostics.isEmpty)
    }

    @Test(arguments: CompanionFilterChange.allCases, [false, true])
    func companionFilterChangesPreserveTheNativeBaseline(
        change: CompanionFilterChange,
        afterRefresh: Bool
    ) async throws {
        let original = TestGlassFilter(["inputBlurRadius": 5])
        let companion = try #require(CIFilter(name: "CIColorControls"))
        let replacement = try #require(CIFilter(name: "CIColorControls"))
        replacement.setValue(0.5, forKey: kCIInputSaturationKey)
        let layer = CALayer()
        layer.filters = [original, companion]
        var diagnostics: [String] = []
        let adapter = NativeGlassOptics(access: TestGlassFilterAccess()) { diagnostics.append($0) }
        adapter.update(root: layer, optics: GlassOptics(blurRadius: 37))
        let owned = try #require(layer.filters?.first as? TestGlassFilter)

        let changed: [CIFilter]
        switch change {
        case .insert: changed = [replacement, owned, companion]
        case .remove: changed = [owned]
        case .reorder: changed = [companion, owned]
        case .replace: changed = [owned, replacement]
        }
        layer.filters = changed
        if afterRefresh {
            await nextMainQueueTurn()
            await nextMainQueueTurn()
        }
        adapter.update(root: layer, optics: GlassOptics())

        let restored = layer.filters ?? []
        let expected = changed.map { $0 === owned ? original : $0 }
        #expect(restored.count == expected.count)
        #expect(zip(restored, expected).allSatisfy { ($0 as AnyObject) === $1 })
        #expect((restored.compactMap { $0 as? TestGlassFilter }.first)?.values["inputBlurRadius"] == 5)
        #expect(diagnostics.isEmpty)
    }

    @Test(arguments: [false, true])
    func otherRestorationPathsPreserveCompanionChanges(detach: Bool) throws {
        let original = TestGlassFilter(["inputBlurRadius": 5])
        let companion = try #require(CIFilter(name: "CIColorControls"))
        let child = CALayer()
        child.filters = [original]
        let root = CALayer()
        root.addSublayer(child)
        let adapter = NativeGlassOptics(access: TestGlassFilterAccess()) { _ in }
        adapter.update(root: root, optics: GlassOptics(blurRadius: 37))
        let owned = try #require(child.filters?.first as? TestGlassFilter)
        child.filters = [owned, companion]

        if detach {
            root.sublayers = []
            adapter.update(root: root, optics: GlassOptics(blurRadius: 37))
        } else {
            adapter.update(root: CALayer(), optics: GlassOptics(blurRadius: 37))
        }
        #expect(child.filters?.first as? TestGlassFilter === original)
        #expect(child.filters?.last as? CIFilter === companion)
        #expect(child.filters?.count == 2)
        adapter.restore()
    }

    @Test func overridesEqualToNativeValuesSurviveLaterNativeChanges() async {
        let original = TestGlassFilter(["inputBlurRadius": 5])
        let layer = CALayer()
        layer.filters = [original]
        var diagnostics: [String] = []
        let adapter = NativeGlassOptics(access: TestGlassFilterAccess()) { diagnostics.append($0) }
        adapter.update(root: layer, optics: GlassOptics(blurRadius: 5))
        await nextMainQueueTurn()
        await nextMainQueueTurn()
        #expect(layer.filters?.first as? TestGlassFilter === original)

        let newNative = TestGlassFilter(["inputBlurRadius": 10])
        layer.filters = [newNative]
        await nextMainQueueTurn()
        await nextMainQueueTurn()
        #expect((layer.filters?.first as? TestGlassFilter)?.values["inputBlurRadius"] == 5)
        adapter.update(root: layer, optics: GlassOptics())
        #expect(layer.filters?.first as? TestGlassFilter === newNative)
        #expect(diagnostics.isEmpty)
    }

    @Test func diagnosesUnsupportedInputsWithoutChangingOtherFilters() {
        let filter = TestGlassFilter(["inputBlurRadius": 5])
        let layer = CALayer()
        layer.filters = [filter]
        var diagnostics: [String] = []
        let adapter = NativeGlassOptics(access: TestGlassFilterAccess()) { diagnostics.append($0) }
        let optics = GlassOptics(refractionHeight: 20)
        adapter.update(root: layer, optics: optics)
        adapter.update(root: layer, optics: optics)
        #expect(layer.filters?.first as? TestGlassFilter === filter)
        #expect(diagnostics == ["Native glass does not support \"macos-glass-refraction-height\" on this macOS version."])
    }

    @Test func diagnosesATreeWithoutNativeFilters() async {
        let layer = CALayer()
        var diagnostics: [String] = []
        let adapter = NativeGlassOptics(access: TestGlassFilterAccess()) { diagnostics.append($0) }
        adapter.update(root: layer, optics: GlassOptics(blurRadius: 20))
        #expect(diagnostics.isEmpty)
        await nextMainQueueTurn()
        #expect(diagnostics == ["Native glass does not support \"macos-glass-blur-radius\" on this macOS version."])
    }

    @Test func rootReplacementRestoresThePreviousTree() async {
        let original = TestGlassFilter(["inputBlurRadius": 5])
        let first = CALayer()
        first.filters = [original]
        let second = CALayer()
        second.filters = [TestGlassFilter(["inputBlurRadius": 10])]
        let adapter = NativeGlassOptics(access: TestGlassFilterAccess()) { _ in }
        adapter.update(root: first, optics: GlassOptics(blurRadius: 30))
        adapter.update(root: second, optics: GlassOptics(blurRadius: 30))
        #expect(first.filters?.first as? TestGlassFilter === original)
        #expect((second.filters?.first as? TestGlassFilter)?.values["inputBlurRadius"] == 30)
        adapter.restore()
        await nextMainQueueTurn()
        await nextMainQueueTurn()
        #expect((second.filters?.first as? TestGlassFilter)?.values["inputBlurRadius"] == 10)
    }

    @Test func nativeFailureLeavesTheOriginalFilterIntact() {
        let filter = TestGlassFilter(["inputBlurRadius": 5])
        let layer = CALayer()
        layer.filters = [filter]
        let error = NSError(domain: "GlassTest", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "The filter rejected an input.",
        ])
        var diagnostics: [String] = []
        let adapter = NativeGlassOptics(access: TestGlassFilterAccess(copyError: error)) {
            diagnostics.append($0)
        }
        adapter.update(root: layer, optics: GlassOptics(blurRadius: 20))
        #expect(layer.filters?.first as? TestGlassFilter === filter)
        #expect(diagnostics == ["The filter rejected an input."])
    }

    @Test func observationsDoNotKeepTheAdapterAlive() {
        let layer = CALayer()
        layer.filters = [TestGlassFilter(["inputBlurRadius": 5])]
        var adapter: NativeGlassOptics? = NativeGlassOptics(access: TestGlassFilterAccess()) { _ in }
        let reference = { [weak adapter] in adapter }
        adapter?.update(root: layer, optics: GlassOptics(blurRadius: 20))
        adapter = nil
        #expect(reference() == nil)
    }

    @Test func nativeBoundaryIgnoresNonNativeFilters() throws {
        let access = NativeGlassFilterAccess()
        #expect(try access.inputKeys(of: NSObject(), keys: ["inputBlurRadius"]) == nil)
        #expect(throws: (any Error).self) {
            try access.copy(NSObject(), overriding: ["inputBlurRadius": 5])
        }
    }
}
