import AppKit
import Foundation

@MainActor
final class FixtureWindowApp: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private let text = "OCR 테스트\nHello 123"
    private let mode = FixtureMode.current

    func applicationDidFinishLaunching(_ notification: Notification) {
        let size = CGSize(width: 640, height: 220)
        let screenFrame = NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let origin = configuredOrigin(defaultOrigin: CGPoint(
            x: screenFrame.midX - size.width / 2,
            y: screenFrame.midY - size.height / 2
        ))
        let window = NSWindow(
            contentRect: CGRect(origin: origin, size: size),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "ScreenOCR Fixture"
        window.backgroundColor = .white
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces]
        window.contentView = mode.makeContentView(frame: CGRect(origin: .zero, size: size), text: text)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
        writeFrameArtifact(frame: window.frame, contentFrame: contentFrame(for: window))
    }

    private func configuredOrigin(defaultOrigin: CGPoint) -> CGPoint {
        let environment = ProcessInfo.processInfo.environment
        let x = environment["SCREEN_OCR_FIXTURE_ORIGIN_X"].flatMap(Double.init) ?? defaultOrigin.x
        let y = environment["SCREEN_OCR_FIXTURE_ORIGIN_Y"].flatMap(Double.init) ?? defaultOrigin.y
        return CGPoint(x: x, y: y)
    }

    private func contentFrame(for window: NSWindow) -> CGRect {
        guard let contentView = window.contentView else {
            return window.frame
        }

        let contentBoundsInWindow = contentView.convert(contentView.bounds, to: nil)
        return window.convertToScreen(contentBoundsInWindow)
    }

    private func writeFrameArtifact(frame: CGRect, contentFrame: CGRect) {
        do {
            let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            let url = root.appendingPathComponent("artifacts/hotkey/fixture-window.json")
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let payload: [String: Any] = [
                "created_at": ISO8601DateFormatter().string(from: Date()),
                "mode": mode.rawValue,
                "text": text,
                "x": frame.origin.x,
                "y": frame.origin.y,
                "width": frame.width,
                "height": frame.height,
                "content_x": contentFrame.origin.x,
                "content_y": contentFrame.origin.y,
                "content_width": contentFrame.width,
                "content_height": contentFrame.height
            ]
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: url)
        } catch {
            fputs("failed to write fixture-window.json: \(error.localizedDescription)\n", stderr)
        }
    }
}

private enum FixtureMode: String {
    case text
    case alignment

    static var current: FixtureMode {
        let rawValue = ProcessInfo.processInfo.environment["SCREEN_OCR_FIXTURE_MODE"] ?? ""
        return FixtureMode(rawValue: rawValue) ?? .text
    }

    @MainActor
    func makeContentView(frame: CGRect, text: String) -> NSView {
        switch self {
        case .text:
            return FixtureView(frame: frame, text: text)
        case .alignment:
            return AlignmentFixtureView(frame: frame)
        }
    }
}

private final class FixtureView: NSView {
    private let text: String

    init(frame: CGRect, text: String) {
        self.text = text
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.white.cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        dirtyRect.fill()

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 44),
            .foregroundColor: NSColor.black
        ]
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        for (index, line) in lines.enumerated() {
            let point = CGPoint(x: 48, y: bounds.height - 78 - CGFloat(index * 62))
            String(line).draw(at: point, withAttributes: attributes)
        }
    }
}

private final class AlignmentFixtureView: NSView {
    private let markerSize: CGFloat = 72

    override init(frame: CGRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.white.cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        dirtyRect.fill()

        drawMarker(
            rect: CGRect(x: 0, y: bounds.height - markerSize, width: markerSize, height: markerSize),
            color: NSColor(calibratedRed: 1, green: 0, blue: 0, alpha: 1),
            label: "TL"
        )
        drawMarker(
            rect: CGRect(x: bounds.width - markerSize, y: bounds.height - markerSize, width: markerSize, height: markerSize),
            color: NSColor(calibratedRed: 0, green: 1, blue: 0, alpha: 1),
            label: "TR"
        )
        drawMarker(
            rect: CGRect(x: 0, y: 0, width: markerSize, height: markerSize),
            color: NSColor(calibratedRed: 0, green: 0, blue: 1, alpha: 1),
            label: "BL"
        )
        drawMarker(
            rect: CGRect(x: bounds.width - markerSize, y: 0, width: markerSize, height: markerSize),
            color: NSColor(calibratedRed: 1, green: 1, blue: 0, alpha: 1),
            label: "BR"
        )

        NSColor.black.setStroke()
        NSBezierPath(rect: bounds.insetBy(dx: 1, dy: 1)).stroke()
    }

    private func drawMarker(rect: CGRect, color: NSColor, label: String) {
        color.setFill()
        rect.fill()

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 20, weight: .bold),
            .foregroundColor: NSColor.black
        ]
        let labelSize = label.size(withAttributes: attributes)
        let point = CGPoint(
            x: rect.midX - labelSize.width / 2,
            y: rect.midY - labelSize.height / 2
        )
        label.draw(at: point, withAttributes: attributes)
    }
}

let app = NSApplication.shared
let delegate = FixtureWindowApp()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
