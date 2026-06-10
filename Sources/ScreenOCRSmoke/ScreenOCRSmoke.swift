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
        let args = CommandLine.arguments.dropFirst() // drop executable name
        if let firstArg = args.first, firstArg == "engine-bench" {
            let remainingArgs = Array(args.dropFirst())
            let status = await EngineBenchCommand.run(args: remainingArgs)
            exit(status)
        } else {
            let runner = ScreenSmokeRunner()
            let status = await runner.run()
            exit(status)
        }
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

// MARK: - engine-bench subcommand

private enum BenchEngine: String {
    case vision
    case paddle
    case both
}

private enum EngineBenchError: Error, LocalizedError {
    case missingImagePath
    case unknownEngine(String)
    case invalidRepeats(String)

    var errorDescription: String? {
        switch self {
        case .missingImagePath:
            return "engine-bench requires <image-path> as first argument"
        case .unknownEngine(let s):
            return "Unknown engine '\(s)'. Use: vision, paddle, or both"
        case .invalidRepeats(let s):
            return "Invalid --repeats value '\(s)'. Must be a positive integer"
        }
    }
}

private enum EngineBenchCommand {
    static func run(args: [String]) async -> Int32 {
        do {
            let (imagePath, engine, repeats) = try parseArgs(args)
            let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            let result = try await runBench(imagePath: imagePath, engine: engine, repeats: repeats, root: root)
            let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
            print(String(data: data, encoding: .utf8) ?? "")
            return 0
        } catch {
            fputs("engine-bench error: \(error.localizedDescription)\n", stderr)
            fputs("Usage: engine-bench <image-path> [--engine vision|paddle|both] [--repeats N]\n", stderr)
            return 1
        }
    }

    private static func parseArgs(_ args: [String]) throws -> (imagePath: String, engine: BenchEngine, repeats: Int) {
        var imagePath: String?
        var engine = BenchEngine.vision
        var repeats = 3
        var i = 0
        while i < args.count {
            let arg = args[i]
            switch arg {
            case "--engine":
                i += 1
                guard i < args.count else { throw EngineBenchError.unknownEngine("(missing)") }
                guard let e = BenchEngine(rawValue: args[i]) else { throw EngineBenchError.unknownEngine(args[i]) }
                engine = e
            case "--repeats":
                i += 1
                guard i < args.count, let n = Int(args[i]), n > 0 else {
                    throw EngineBenchError.invalidRepeats(i < args.count ? args[i] : "(missing)")
                }
                repeats = n
            default:
                if !arg.hasPrefix("-") {
                    imagePath = arg
                }
            }
            i += 1
        }
        guard let path = imagePath else { throw EngineBenchError.missingImagePath }
        return (path, engine, repeats)
    }

    private static func runBench(
        imagePath: String,
        engine: BenchEngine,
        repeats: Int,
        root: URL
    ) async throws -> [String: Any] {
        let image = CapturedImage(
            id: "bench://\(URL(fileURLWithPath: imagePath).lastPathComponent)",
            width: 0,
            height: 0,
            filePath: imagePath
        )

        switch engine {
        case .vision:
            let result = try await benchVision(image: image, repeats: repeats)
            return ["vision": result]
        case .paddle:
            let result = try await benchPaddle(image: image, repeats: repeats, root: root)
            return ["paddle": result]
        case .both:
            let visionResult = try await benchVision(image: image, repeats: repeats)
            let paddleResult = try await benchPaddle(image: image, repeats: repeats, root: root)
            return ["vision": visionResult, "paddle": paddleResult]
        }
    }

    private static func benchVision(image: CapturedImage, repeats: Int) async throws -> [String: Any] {
        let engine = VisionOCREngine()
        var elapsedAll: [Int] = []
        var lastDocument: OCRDocument?
        for _ in 0..<repeats {
            let start = Date()
            let doc = try await engine.recognizeText(in: image)
            elapsedAll.append(elapsedMilliseconds(since: start))
            lastDocument = doc
        }
        let doc = lastDocument ?? OCRDocument(lines: [])
        return makeResult(elapsedAll: elapsedAll, document: doc)
    }

    private static func benchPaddle(image: CapturedImage, repeats: Int, root: URL) async throws -> [String: Any] {
        let ocr = PersistentPythonSidecarOCR(
            pythonExecutablePath: root.appendingPathComponent(".venv-ocr/bin/python").path,
            sidecarPath: root.appendingPathComponent("sidecar").path
        )
        let prewarmStart = Date()
        let readyInfo = try await ocr.prewarm()
        let initElapsedMs = elapsedMilliseconds(since: prewarmStart)

        var elapsedAll: [Int] = []
        var lastDocument: OCRDocument?
        for _ in 0..<repeats {
            let start = Date()
            let doc = try await ocr.recognizeText(in: image)
            elapsedAll.append(elapsedMilliseconds(since: start))
            lastDocument = doc
        }
        let doc = lastDocument ?? OCRDocument(lines: [])
        var result = makeResult(elapsedAll: elapsedAll, document: doc)
        result["init_elapsed_ms"] = initElapsedMs
        result["worker_init_elapsed_ms"] = readyInfo.initElapsedMs
        return result
    }

    private static func makeResult(elapsedAll: [Int], document: OCRDocument) -> [String: Any] {
        [
            "elapsed_ms_all": elapsedAll,
            "median": medianInt(elapsedAll),
            "line_count": document.lines.count,
            "text": document.normalizedText,
        ]
    }

    private static func medianInt(_ values: [Int]) -> Int {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count % 2 == 0 {
            return (sorted[mid - 1] + sorted[mid]) / 2
        }
        return sorted[mid]
    }
}
