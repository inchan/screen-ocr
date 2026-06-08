import AppKit
import CoreGraphics
import Foundation
import ImageIO
import ScreenCaptureKit
import ScreenOCRCore
import UniformTypeIdentifiers

@main
struct ScreenOCRSmoke {
    static func main() async {
        let runner = ScreenSmokeRunner()
        let status = await runner.run()
        exit(status)
    }
}

@MainActor
private final class ScreenSmokeRunner {
    private let expectedText = "OCR 테스트\nHello 123"
    private let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

    func run() async -> Int32 {
        let reportURL = root.appendingPathComponent("artifacts/smoke/latest-screen-smoke.json")
        do {
            guard #available(macOS 15.2, *) else {
                try writeReport(reportURL, report(status: "skipped", reason: "macOS 15.2+ required"))
                return 2
            }

            guard CGPreflightScreenCaptureAccess() else {
                try writeReport(reportURL, report(status: "skipped", reason: "Screen Recording permission not granted"))
                return 2
            }

            let app = NSApplication.shared
            app.setActivationPolicy(.accessory)
            let window = makeFixtureWindow()
            window.makeKeyAndOrderFront(nil)
            try await Task.sleep(for: .milliseconds(500))

            let started = Date()
            let image = try await captureImage(in: window.frame)
            let captureURL = try writePNG(image, to: root.appendingPathComponent("artifacts/smoke/screen-smoke.png"))
            let ocr = PythonSidecarOCR(
                pythonExecutablePath: root.appendingPathComponent(".venv-ocr/bin/python").path,
                sidecarPath: root.appendingPathComponent("sidecar").path
            )
            let document = try await ocr.recognizeText(
                in: CapturedImage(
                    id: "smoke://screen-fixture",
                    width: image.width,
                    height: image.height,
                    filePath: captureURL.path
                )
            )

            let clipboard = PasteboardClipboard()
            try clipboard.writeText(document.normalizedText)
            let elapsedMS = Int(Date().timeIntervalSince(started) * 1000)
            let passed = document.normalizedText.contains("Hello 123")

            try writeReport(
                reportURL,
                report(
                    status: passed ? "passed" : "failed",
                    reason: passed ? nil : "OCR text did not contain expected English anchor",
                    elapsedMS: elapsedMS,
                    actualText: document.normalizedText,
                    expectedText: expectedText,
                    imagePath: captureURL.path,
                    lineCount: document.lines.count
                )
            )

            window.orderOut(nil)
            return passed ? 0 : 1
        } catch {
            try? writeReport(reportURL, report(status: "failed", reason: error.localizedDescription))
            return 1
        }
    }

    private func makeFixtureWindow() -> NSWindow {
        let size = CGSize(width: 640, height: 220)
        let screenFrame = NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let origin = CGPoint(
            x: screenFrame.midX - size.width / 2,
            y: screenFrame.midY - size.height / 2
        )
        let window = NSWindow(
            contentRect: CGRect(origin: origin, size: size),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.backgroundColor = .white
        window.isOpaque = true
        window.level = .floating
        window.contentView = SmokeFixtureView(frame: CGRect(origin: .zero, size: size), text: expectedText)
        return window
    }

    @available(macOS 15.2, *)
    private func captureImage(in rect: CGRect) async throws -> CGImage {
        try await withCheckedThrowingContinuation { continuation in
            SCScreenshotManager.captureImage(in: rect) { image, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let image {
                    continuation.resume(returning: image)
                } else {
                    continuation.resume(throwing: SmokeError.emptyImage)
                }
            }
        }
    }

    private func writePNG(_ image: CGImage, to url: URL) throws -> URL {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw SmokeError.cannotCreateImageDestination
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw SmokeError.cannotWriteImage
        }
        return url
    }

    private func report(
        status: String,
        reason: String?,
        elapsedMS: Int? = nil,
        actualText: String? = nil,
        expectedText: String? = nil,
        imagePath: String? = nil,
        lineCount: Int? = nil
    ) -> [String: Any] {
        [
            "created_at": ISO8601DateFormatter().string(from: Date()),
            "status": status,
            "reason": reason as Any,
            "elapsed_ms": elapsedMS as Any,
            "actual_text": actualText as Any,
            "expected_text": expectedText as Any,
            "image_path": imagePath as Any,
            "line_count": lineCount as Any
        ]
    }

    private func writeReport(_ url: URL, _ report: [String: Any]) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url)
        print(String(data: data, encoding: .utf8) ?? "")
    }
}

private final class SmokeFixtureView: NSView {
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

private enum SmokeError: Error, LocalizedError {
    case emptyImage
    case cannotCreateImageDestination
    case cannotWriteImage

    var errorDescription: String? {
        switch self {
        case .emptyImage:
            return "ScreenCaptureKit returned no image"
        case .cannotCreateImageDestination:
            return "Could not create smoke PNG destination"
        case .cannotWriteImage:
            return "Could not write smoke PNG"
        }
    }
}
