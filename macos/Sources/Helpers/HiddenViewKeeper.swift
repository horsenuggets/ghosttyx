import AppKit

/// Keeps a view hidden even when AppKit tries to show it again.
///
/// AppKit owns some private titlebar views and can unhide them on its own schedule. On
/// macOS 27, for example, removing the native tab bar shows `NSTitlebarBackgroundView`
/// again after the window has already synced its appearance, which brings back its
/// backdrop and separator line.
final class HiddenViewKeeper {
    private weak var view: NSView?
    private var observation: NSKeyValueObservation?

    /// Hides the given view and keeps it hidden until another view is kept or
    /// `release()` is called.
    func keep(_ view: NSView) {
        view.isHidden = true
        guard self.view !== view else { return }
        self.view = view
        observation = view.observe(\.isHidden, options: [.new]) { view, _ in
            guard !view.isHidden else { return }
            view.isHidden = true
        }
    }

    /// Stops keeping the current view hidden without changing its visibility.
    func release() {
        observation?.invalidate()
        observation = nil
        view = nil
    }

    deinit {
        observation?.invalidate()
    }
}
