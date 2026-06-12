import AppKit

@MainActor
enum WindowOrderingPolicy {
    /// Starting the capture overlay activates the LSUIElement app so the overlay can receive
    /// Escape and first-click input. Activation can also pull already-open settings windows to
    /// the front. Keep only inactive, visible, normal-level app windows behind the overlay.
    static func windowsToKeepBehindDuringCapture(
        appWasActive: Bool,
        windows: [NSWindow]
    ) -> [NSWindow] {
        guard !appWasActive else { return [] }
        return windows.filter { window in
            window.isVisible
                && window.level == .normal
                && !(window is NSPanel)
                && !window.isKeyWindow
        }
    }
}
