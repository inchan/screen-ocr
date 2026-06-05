import AppKit
import CoreGraphics
import ScreenOCRCore

@MainActor
final class SelectionOverlayController {
    private var windows: [NSWindow] = []
    private var continuation: CheckedContinuation<ScreenRegionSelection, Error>?

    func selectRegion() async throws -> ScreenRegionSelection {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            self.showOverlayWindows()
        }
    }

    private func showOverlayWindows() {
        windows = NSScreen.screens.map { screen in
            let view = SelectionOverlayView(screen: screen) { [weak self] result in
                self?.finish(result)
            }

            let window = NSWindow(
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

private final class SelectionOverlayView: NSView {
    private let screen: NSScreen
    private let completion: (Result<ScreenRegionSelection, Error>) -> Void
    private var dragStart: CGPoint?
    private var dragCurrent: CGPoint?

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

    var errorDescription: String? {
        "Selection cancelled"
    }
}

