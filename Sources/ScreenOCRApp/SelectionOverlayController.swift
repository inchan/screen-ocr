import AppKit
import CoreGraphics
import ScreenOCRCore

@MainActor
final class SelectionOverlayController {
    private var windows: [NSWindow] = []
    private var continuation: CheckedContinuation<ScreenRegionSelection, Error>?

    /// Whether a selection session is currently on screen. Callers (the hotkey path) skip new
    /// requests while this is true.
    var isSelecting: Bool { continuation != nil }

    func selectRegion() async throws -> ScreenRegionSelection {
        // A second entry would silently overwrite (and leak) the first continuation and stack
        // duplicate overlay windows — the first capture would then never complete.
        guard !isSelecting else {
            throw SelectionOverlayError.alreadyActive
        }
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            self.showOverlayWindows()
        }
    }

    private func showOverlayWindows() {
        // An accessory (LSUIElement) app is not active by default, so its overlay window can
        // neither become key (no keyDown → Escape can't cancel) nor receive the first click as a
        // selection (it would be swallowed to activate the app). Activate the app first so the
        // borderless key-capable window below can take keyboard + first-mouse input.
        NSApp.activate(ignoringOtherApps: true)

        windows = NSScreen.screens.map { screen in
            let view = SelectionOverlayView(screen: screen) { [weak self] result in
                self?.finish(result)
            }

            let window = OverlayWindow(
                contentRect: screen.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false,
                screen: screen
            )
            window.contentView = view
            window.backgroundColor = .clear
            window.isOpaque = false
            window.level = .screenSaver
            window.ignoresMouseEvents = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.makeKeyAndOrderFront(nil)
            return window
        }

        // Make the first overlay key so Escape and the first selection click are delivered.
        windows.first?.makeKey()
        NSCursor.crosshair.set()
    }

    private func finish(_ result: Result<ScreenRegionSelection, Error>) {
        NSCursor.arrow.set()
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()

        guard let continuation else {
            return
        }

        self.continuation = nil
        switch result {
        case .success(let selection):
            continuation.resume(returning: selection)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }
}

/// A borderless window that can still become key/main. Plain borderless `NSWindow`s return
/// `false` for both, which blocks keyDown (Escape-to-cancel) and first-click delivery.
private final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private final class SelectionOverlayView: NSView {
    private let screen: NSScreen
    private let completion: (Result<ScreenRegionSelection, Error>) -> Void
    private var dragStart: CGPoint?
    private var dragCurrent: CGPoint?

    // Register the first click even when the app was inactive when the overlay appeared
    // (e.g. triggered by the global hotkey while another app was frontmost).
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    init(screen: NSScreen, completion: @escaping (Result<ScreenRegionSelection, Error>) -> Void) {
        self.screen = screen
        self.completion = completion
        super.init(frame: CGRect(origin: .zero, size: screen.frame.size))
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.18).cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func viewDidMoveToWindow() {
        window?.makeFirstResponder(self)
    }

    override func mouseDown(with event: NSEvent) {
        dragStart = event.locationInWindow
        dragCurrent = event.locationInWindow
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        dragCurrent = event.locationInWindow
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let dragStart else {
            completion(.failure(SelectionOverlayError.cancelled))
            return
        }

        let dragEnd = event.locationInWindow
        let globalStart = toGlobalPoint(dragStart)
        let globalEnd = toGlobalPoint(dragEnd)

        do {
            let selection = try ScreenRegionSelection.resolve(
                dragStart: globalStart,
                dragEnd: globalEnd,
                displays: Self.displayFrames()
            )
            completion(.success(selection))
        } catch {
            completion(.failure(error))
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            completion(.failure(SelectionOverlayError.cancelled))
        } else {
            super.keyDown(with: event)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let dragStart, let dragCurrent else {
            return
        }

        let rect = CGRect(
            x: min(dragStart.x, dragCurrent.x),
            y: min(dragStart.y, dragCurrent.y),
            width: abs(dragStart.x - dragCurrent.x),
            height: abs(dragStart.y - dragCurrent.y)
        )

        NSColor.clear.setFill()
        rect.fill(using: .clear)
        NSColor.systemBlue.setStroke()
        let path = NSBezierPath(rect: rect)
        path.lineWidth = 2
        path.stroke()
    }

    private func toGlobalPoint(_ localPoint: CGPoint) -> CGPoint {
        CGPoint(
            x: screen.frame.origin.x + localPoint.x,
            y: screen.frame.origin.y + localPoint.y
        )
    }

    private static func displayFrames() -> [DisplayFrame] {
        NSScreen.screens.map { screen in
            let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            return DisplayFrame(
                id: displayID?.uint32Value ?? 0,
                frame: screen.frame
            )
        }
    }
}

enum SelectionOverlayError: Error, LocalizedError {
    case cancelled
    case alreadyActive

    var errorDescription: String? {
        switch self {
        case .cancelled: "Selection cancelled"
        case .alreadyActive: "Selection already in progress"
        }
    }
}

