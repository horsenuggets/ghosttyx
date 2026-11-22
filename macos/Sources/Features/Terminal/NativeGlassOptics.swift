#if os(macOS)
import AppKit
import QuartzCore

struct GlassOptics: Equatable {
    static let inputSettings = [
        "inputBlurRadius": "macos-glass-blur-radius",
        "inputInnerRefractionAmount": "macos-glass-refraction-amount",
        "inputInnerRefractionHeight": "macos-glass-refraction-height",
        "inputKeyFillHighlightAmount": "macos-glass-highlight-strength",
        "inputKeyFillHighlightAngle": "macos-glass-highlight-angle",
        "inputKeyFillHighlightSpread": "macos-glass-highlight-spread",
        "inputKeyFillHighlightSpreadSDR": "macos-glass-highlight-spread",
    ]
    var blurRadius: Double?
    var highlightAngle: Double?
    var highlightSpread: Double?
    var highlightStrength: Double?
    var refractionAmount: Double?
    var refractionHeight: Double?

    var inputs: [String: Double] {
        var result: [String: Double] = [:]
        result["inputBlurRadius"] = blurRadius
        result["inputInnerRefractionAmount"] = refractionAmount
        result["inputInnerRefractionHeight"] = refractionHeight
        result["inputKeyFillHighlightAmount"] = highlightStrength
        result["inputKeyFillHighlightAngle"] = highlightAngle.map { $0 / 180 * .pi }
        result["inputKeyFillHighlightSpread"] = highlightSpread.map { $0 / 180 * .pi }
        result["inputKeyFillHighlightSpreadSDR"] = highlightSpread.map { $0 / 180 * .pi }
        return result
    }
}

protocol GlassFilterAccess {
    func inputKeys(of filter: Any, keys: [String]) throws -> Set<String>?
    func copy(_ filter: Any, overriding inputs: [String: Double]) throws -> Any
}

struct NativeGlassFilterAccess: GlassFilterAccess {
    func inputKeys(of filter: Any, keys: [String]) throws -> Set<String>? {
        var error: NSError?
        let supported = GhosttyGlassFilterInputKeys(filter, keys, &error)
        if let error { throw error }
        return supported.map { Set($0) }
    }

    func copy(_ filter: Any, overriding inputs: [String: Double]) throws -> Any {
        var error: NSError?
        let values = inputs.mapValues(NSNumber.init(value:))
        if let replacement = GhosttyCopyGlassFilterWithInputs(filter, values, &error) {
            return replacement
        }
        throw error ?? NSError(domain: "Ghostty.GlassEffect", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "The native glass filter could not be copied.",
        ])
    }
}

/// Overrides only native glass filters belonging to this view's layer tree.
@MainActor
final class NativeGlassOptics {
    private struct FilterOverride {
        let native: Any
        let applied: Any
    }

    private struct Snapshot {
        weak var layer: CALayer?
        let overrides: [FilterOverride]
        let appliedFilters: [Any]
        let inputs: [String: Double]
        let supported: Set<String>
    }

    private weak var rootLayer: CALayer?
    private var optics = GlassOptics()
    private var snapshots: [ObjectIdentifier: Snapshot] = [:]
    private var observations: [ObjectIdentifier: [NSKeyValueObservation]] = [:]
    private var updateScheduled = false
    private var lastDiagnostic: String?
    private let access: any GlassFilterAccess
    private let report: (String) -> Void

    init(access: any GlassFilterAccess = NativeGlassFilterAccess(), report: @escaping (String) -> Void) {
        self.access = access
        self.report = report
    }

    func update(root: CALayer?, optics: GlassOptics) {
        if rootLayer !== root {
            restore()
            rootLayer = root
        }
        if self.optics != optics {
            lastDiagnostic = nil
            self.optics = optics
        }
        refresh()
        scheduleUpdate()
    }

    func restore() {
        optics = GlassOptics()
        observations.removeAll()
        for snapshot in snapshots.values {
            restoreOwnedFilters(from: snapshot)
        }
        snapshots.removeAll()
    }

    private func scheduleUpdate() {
        guard !updateScheduled, !optics.inputs.isEmpty else { return }
        updateScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.updateScheduled = false
            self.refresh(reportUnavailable: true)
        }
    }

    private func refresh(reportUnavailable: Bool = false) {
        let inputs = optics.inputs
        guard !inputs.isEmpty, let rootLayer else {
            restore()
            return
        }

        let layers = descendants(of: rootLayer)
        let identifiers = Set(layers.map(ObjectIdentifier.init))
        observations = observations.filter { identifiers.contains($0.key) }
        for (identifier, snapshot) in snapshots where !identifiers.contains(identifier) {
            restoreOwnedFilters(from: snapshot)
        }
        snapshots = snapshots.filter { identifiers.contains($0.key) }
        var supported = Set<String>()
        var failure: String?
        var hasFilters = false

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        for layer in layers {
            observe(layer)
            let identifier = ObjectIdentifier(layer)
            let current = layer.filters ?? []
            hasFilters = hasFilters || !current.isEmpty
            let saved = snapshots[identifier]
            let isApplied = saved.map { sameFilters(current, $0.appliedFilters) } ?? false
            if let saved, isApplied, saved.inputs == inputs {
                supported.formUnion(saved.supported)
                continue
            }

            let native = saved.map { restoringOwnedFilters(in: current, from: $0) } ?? current
            var replacements = native
            var layerSupported = Set<String>()
            var overriddenIndices: [Int] = []
            for (index, filter) in native.enumerated() {
                do {
                    guard let keys = try access.inputKeys(of: filter, keys: Array(inputs.keys)) else { continue }
                    let available = inputs.filter { keys.contains($0.key) }
                    guard !available.isEmpty else { continue }
                    replacements[index] = try access.copy(filter, overriding: available)
                    layerSupported.formUnion(available.keys)
                    overriddenIndices.append(index)
                } catch {
                    failure = error.localizedDescription
                }
            }
            supported.formUnion(layerSupported)
            if !overriddenIndices.isEmpty {
                layer.filters = replacements
                // Core Animation can retain a value-equal filter instead of our copy.
                let applied = layer.filters ?? []
                let overrides = overriddenIndices.compactMap { index -> FilterOverride? in
                    guard applied.indices.contains(index) else { return nil }
                    return FilterOverride(native: native[index], applied: applied[index])
                }
                snapshots[identifier] = Snapshot(
                    layer: layer,
                    overrides: overrides,
                    appliedFilters: applied,
                    inputs: inputs,
                    supported: layerSupported
                )
            } else {
                if let saved { restoreOwnedFilters(from: saved) }
                snapshots.removeValue(forKey: identifier)
            }
        }

        // AppKit builds its internal tree asynchronously. Defer diagnostics for an
        // unfiltered tree until the next main-queue turn.
        if hasFilters || reportUnavailable {
            let missing = Set(inputs.keys).subtracting(supported)
            let settings = Set(missing.compactMap { GlassOptics.inputSettings[$0] }).sorted()
            let message = failure ?? (settings.isEmpty ? nil :
                "Native glass does not support \(settings.map { "\"\($0)\"" }.joined(separator: ", ")) on this macOS version.")
            if let message, message != lastDiagnostic {
                lastDiagnostic = message
                report(message)
            } else if message == nil {
                lastDiagnostic = nil
            }
        }
    }

    private func restoringOwnedFilters(in current: [Any], from snapshot: Snapshot) -> [Any] {
        current.map { filter in
            snapshot.overrides.first { ($0.applied as AnyObject) === (filter as AnyObject) }?.native ?? filter
        }
    }

    private func restoreOwnedFilters(from snapshot: Snapshot) {
        guard let layer = snapshot.layer else { return }
        let current = layer.filters ?? []
        let native = restoringOwnedFilters(in: current, from: snapshot)
        if !sameFilters(current, native) { layer.filters = native }
    }

    private func observe(_ layer: CALayer) {
        let identifier = ObjectIdentifier(layer)
        guard observations[identifier] == nil else { return }
        observations[identifier] = [
            layer.observe(\.filters) { [weak self] _, _ in
                DispatchQueue.main.async { self?.scheduleUpdate() }
            },
            layer.observe(\.sublayers) { [weak self] _, _ in
                DispatchQueue.main.async { self?.scheduleUpdate() }
            },
        ]
    }

    private func descendants(of layer: CALayer) -> [CALayer] {
        [layer] + (layer.sublayers ?? []).flatMap { descendants(of: $0) }
    }

    private func sameFilters(_ lhs: [Any], _ rhs: [Any]) -> Bool {
        lhs.count == rhs.count && zip(lhs, rhs).allSatisfy { ($0 as AnyObject) === ($1 as AnyObject) }
    }
}
#endif
