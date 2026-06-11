import CoreGraphics
import Foundation
#if canImport(AppKit)
import AppKit
#endif

public struct CapturedImage: Equatable, Sendable {
    public let id: String
    public let width: Int
    public let height: Int
    public let filePath: String?
    public let diagnostics: [String: Int]

    public init(
        id: String,
        width: Int,
        height: Int,
        filePath: String? = nil,
        diagnostics: [String: Int] = [:]
    ) {
        self.id = id
        self.width = width
        self.height = height
        self.filePath = filePath
        self.diagnostics = diagnostics
    }
}

public struct OCRLine: Codable, Equatable, Sendable {
    public let text: String
    public let score: Double

    public init(text: String, score: Double) {
        self.text = text
        self.score = score
    }
}

public struct OCRDocument: Codable, Equatable, Sendable {
    public let lines: [OCRLine]
    public let diagnostics: [String: Int]
    public let metadata: [String: String]

    public init(
        lines: [OCRLine],
        diagnostics: [String: Int] = [:],
        metadata: [String: String] = [:]
    ) {
        self.lines = lines
        self.diagnostics = diagnostics
        self.metadata = metadata
    }

    public var normalizedText: String {
        lines
            .map(\.text)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private enum CodingKeys: String, CodingKey {
        case lines
        case diagnostics
        case metadata
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        lines = try container.decode([OCRLine].self, forKey: .lines)
        diagnostics = try container.decodeIfPresent([String: Int].self, forKey: .diagnostics) ?? [:]
        metadata = try container.decodeIfPresent([String: String].self, forKey: .metadata) ?? [:]
    }
}

public protocol ImageCapturing {
    func captureRegion() async throws -> CapturedImage
}

public protocol OCRRecognizing {
    func recognizeText(in image: CapturedImage) async throws -> OCRDocument
}

/// Engines backed by an external worker process (prewarm, liveness, stage streaming).
/// In-process engines (e.g. Apple Vision) implement only OCRRecognizing.
public protocol OCRWorkerManaging: OCRRecognizing {
    func prewarm() async throws -> PersistentOCRWorkerReady
    func workerProcessIdentifier() async -> Int32?
    func setStageHandler(_ handler: (@Sendable (OCRStage) -> Void)?) async
}

public protocol ClipboardWriting: AnyObject {
    func writeText(_ text: String) throws
}

#if canImport(AppKit)
public final class PasteboardClipboard: ClipboardWriting {
    public init() {}

    public func writeText(_ text: String) throws {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
#endif

/// Tracks a serial OCR batch — how many jobs are queued and how many have finished — so the
/// UI can show "n/m" while the queue drains. Resets to empty once the batch fully drains, so a
/// later burst of captures starts counting from 1 again.
public struct OCRBatchProgress: Equatable, Sendable {
    public private(set) var total: Int
    public private(set) var completed: Int

    public init(total: Int = 0, completed: Int = 0) {
        self.total = total
        self.completed = completed
    }

    /// True while at least one queued job has not finished.
    public var isActive: Bool { completed < total }

    /// 1-based index of the job currently being processed (clamped to a sane value when idle).
    public var currentIndex: Int { min(completed + 1, max(total, 1)) }

    /// Records a newly captured job waiting for OCR.
    public mutating func enqueue() {
        total += 1
    }

    /// Marks the in-flight job as finished. When the batch fully drains, resets to empty.
    public mutating func complete() {
        completed += 1
        if completed >= total {
            total = 0
            completed = 0
        }
    }
}

/// Formats the live progress toast text. Shows the "n/m" position only when more than one job
/// is in the batch, and renders elapsed time as `0.x초`.
public enum OCRProgressToast {
    public static func processing(index: Int, total: Int, elapsed: TimeInterval) -> String {
        let seconds = formatSeconds(elapsed)
        if total > 1 {
            return "⏳ 처리 중 \(index)/\(total) · \(seconds)초"
        }
        return "⏳ 처리 중 · \(seconds)초"
    }

    public static func copied(index: Int, total: Int, elapsed: TimeInterval) -> String {
        let seconds = formatSeconds(elapsed)
        if total > 1 {
            return "✅ 복사 완료 \(index)/\(total) · \(seconds)초"
        }
        return "✅ 복사 완료 · \(seconds)초"
    }

    public static func failed(reason: String) -> String {
        "⚠️ OCR 실패 · \(reason)"
    }

    static func formatSeconds(_ elapsed: TimeInterval) -> String {
        String(format: "%.1f", max(0, elapsed))
    }
}

/// The pipeline stages shown, in order, in the step-by-step progress toast. Each maps to a
/// measured segment of a single OCR run.
public enum OCRStage: String, CaseIterable, Sendable {
    case screenCapture
    case pngWrite
    case preprocess
    case recognize
    case clipboard

    public var label: String {
        switch self {
        case .screenCapture: return "화면 캡처"
        // The capture file is uncompressed TIFF for speed; the case keeps its historical
        // "pngWrite" wire name so diagnostics/timing keys stay comparable across versions.
        case .pngWrite: return "이미지 저장"
        case .preprocess: return "전처리"
        case .recognize: return "검출+인식"
        case .clipboard: return "클립보드 복사"
        }
    }

    /// Maps a worker progress event name to its stage (worker streams these two).
    public static func fromWorkerEvent(_ name: String) -> OCRStage? {
        switch name {
        case "preprocess": return .preprocess
        case "recognize": return .recognize
        default: return nil
        }
    }
}

/// Pure state for the step-by-step progress toast: which stages have finished (with their
/// frozen duration), which one is currently running, and the batch position. The live elapsed
/// time of the active stage is supplied at render time so this stays free of any clock.
public struct OCRStageProgress: Equatable, Sendable {
    public var completedMs: [OCRStage: Int]
    public var active: OCRStage?
    public var batchIndex: Int
    public var batchTotal: Int

    public init(
        completedMs: [OCRStage: Int] = [:],
        active: OCRStage? = nil,
        batchIndex: Int = 1,
        batchTotal: Int = 1
    ) {
        self.completedMs = completedMs
        self.active = active
        self.batchIndex = batchIndex
        self.batchTotal = batchTotal
    }

    public var isComplete: Bool {
        active == nil && completedMs.count == OCRStage.allCases.count
    }
}

public enum OCRStageToast {
    /// Column separator between a row's label and its duration. The app splits each line on this
    /// tab and draws the label left-aligned and the duration right-aligned, so the columns line up
    /// pixel-for-pixel regardless of how wide each Korean/Latin label renders — no space padding.
    public static let columnSeparator = "\t"

    /// Renders the multi-line toast: a total line followed by one line per stage that has
    /// started — completed stages show their frozen duration, the active stage shows live
    /// elapsed time, and stages that have not begun yet are omitted so the list grows one row
    /// at a time. The total is the sum of all stage times (frozen + the active stage's live
    /// time). The first line is always the total; the app draws a divider beneath it.
    ///
    /// Each line is `"<icon> <label>\t<seconds>"`: the leading `icon label` is the left column,
    /// and the part after the tab is the right (duration) column.
    public static func render(progress: OCRStageProgress, activeElapsedMs: Int) -> String {
        let activeMs = progress.active == nil ? 0 : max(0, activeElapsedMs)
        let totalMs = progress.completedMs.values.reduce(0, +) + activeMs

        let batch = progress.batchTotal > 1 ? " \(progress.batchIndex)/\(progress.batchTotal)" : ""
        let header = progress.isComplete ? "✅" : "⏳"

        var rows: [(icon: String, label: String, secs: String)] = [
            (header, "전체\(batch)", seconds(totalMs))
        ]
        for stage in OCRStage.allCases {
            if let ms = progress.completedMs[stage] {
                rows.append(("✓", stage.label, seconds(ms)))
            } else if progress.active == stage {
                rows.append(("▶", stage.label, seconds(activeMs)))
            }
            // Stages that have not started yet are not shown — the list appears one row at a time.
        }

        return rows
            .map { "\($0.icon) \($0.label)\(columnSeparator)\($0.secs)" }
            .joined(separator: "\n")
    }

    static func seconds(_ milliseconds: Int) -> String {
        String(format: "%.2f초", max(0, Double(milliseconds)) / 1000)
    }
}

public enum ClipboardCopyToast {
    public static let message = "📋 Copied to clipboard"

    public static func frame(
        below anchorFrame: CGRect,
        preferredSize: CGSize,
        visibleFrame: CGRect,
        verticalGap: CGFloat = 8
    ) -> CGRect {
        let x = min(
            max(anchorFrame.midX - preferredSize.width / 2, visibleFrame.minX + verticalGap),
            visibleFrame.maxX - preferredSize.width - verticalGap
        )
        let y = max(
            visibleFrame.minY + verticalGap,
            anchorFrame.minY - preferredSize.height - verticalGap
        )

        return CGRect(origin: CGPoint(x: x, y: y), size: preferredSize)
    }
}

public enum ScreenOCRRunStatus: Equatable, Sendable {
    case copiedText
    case failed(ScreenOCRFailureStage)
}

public enum ScreenOCRFailureStage: Equatable, Sendable {
    case capture
    case ocr
    case clipboard
}

public struct ScreenOCRRunReport: Equatable, Sendable {
    public let status: ScreenOCRRunStatus
    public let capturedImageID: String
    public let capturedImagePath: String?
    public let recognizedText: String
    public let lineCount: Int
    public let errorMessage: String?
    public let timings: ScreenOCRStageTimings?
    public let ocrDiagnostics: [String: Int]
    public let ocrMetadata: [String: String]

    public init(
        status: ScreenOCRRunStatus,
        capturedImageID: String,
        capturedImagePath: String?,
        recognizedText: String,
        lineCount: Int,
        errorMessage: String?,
        timings: ScreenOCRStageTimings? = nil,
        ocrDiagnostics: [String: Int] = [:],
        ocrMetadata: [String: String] = [:]
    ) {
        self.status = status
        self.capturedImageID = capturedImageID
        self.capturedImagePath = capturedImagePath
        self.recognizedText = recognizedText
        self.lineCount = lineCount
        self.errorMessage = errorMessage
        self.timings = timings
        self.ocrDiagnostics = ocrDiagnostics
        self.ocrMetadata = ocrMetadata
    }
}

public struct ScreenOCRStageTimings: Codable, Equatable, Sendable {
    public let captureElapsedMs: Int
    public let ocrElapsedMs: Int
    public let clipboardElapsedMs: Int
    public let totalElapsedMs: Int
    public let selectionElapsedMs: Int?
    public let screenCaptureElapsedMs: Int?
    public let pngWriteElapsedMs: Int?
    public let imageCaptureElapsedMs: Int?
    public let postSelectionToClipboardElapsedMs: Int?

    public init(
        captureElapsedMs: Int,
        ocrElapsedMs: Int,
        clipboardElapsedMs: Int,
        totalElapsedMs: Int,
        selectionElapsedMs: Int? = nil,
        screenCaptureElapsedMs: Int? = nil,
        pngWriteElapsedMs: Int? = nil,
        imageCaptureElapsedMs: Int? = nil,
        postSelectionToClipboardElapsedMs: Int? = nil
    ) {
        self.captureElapsedMs = captureElapsedMs
        self.ocrElapsedMs = ocrElapsedMs
        self.clipboardElapsedMs = clipboardElapsedMs
        self.totalElapsedMs = totalElapsedMs
        self.selectionElapsedMs = selectionElapsedMs
        self.screenCaptureElapsedMs = screenCaptureElapsedMs
        self.pngWriteElapsedMs = pngWriteElapsedMs
        self.imageCaptureElapsedMs = imageCaptureElapsedMs
        self.postSelectionToClipboardElapsedMs = postSelectionToClipboardElapsedMs
    }
}

public extension ScreenOCRStageTimings {
    var diagnosticPayload: [String: Int] {
        var payload = [
            "capture_elapsed_ms": captureElapsedMs,
            "ocr_elapsed_ms": ocrElapsedMs,
            "clipboard_elapsed_ms": clipboardElapsedMs,
            "total_elapsed_ms": totalElapsedMs
        ]
        if let selectionElapsedMs {
            payload["selection_elapsed_ms"] = selectionElapsedMs
        }
        if let screenCaptureElapsedMs {
            payload["screen_capture_elapsed_ms"] = screenCaptureElapsedMs
        }
        if let pngWriteElapsedMs {
            payload["png_write_elapsed_ms"] = pngWriteElapsedMs
        }
        if let imageCaptureElapsedMs {
            payload["image_capture_elapsed_ms"] = imageCaptureElapsedMs
        }
        if let postSelectionToClipboardElapsedMs {
            payload["post_selection_to_clipboard_elapsed_ms"] = postSelectionToClipboardElapsedMs
        }
        return payload
    }
}

public struct ScreenOCRPipeline<Capture: ImageCapturing, OCR: OCRRecognizing, Clipboard: ClipboardWriting> {
    private let capture: Capture
    private let ocr: OCR
    private let clipboard: Clipboard

    public init(capture: Capture, ocr: OCR, clipboard: Clipboard) {
        self.capture = capture
        self.ocr = ocr
        self.clipboard = clipboard
    }

    private func makeTimings(
        capture: Int,
        ocr: Int,
        clipboard: Int,
        total: Int,
        diagnostics: [String: Int]
    ) -> ScreenOCRStageTimings {
        let imageCapture = diagnostics["image_capture_elapsed_ms"]
        return ScreenOCRStageTimings(
            captureElapsedMs: capture,
            ocrElapsedMs: ocr,
            clipboardElapsedMs: clipboard,
            totalElapsedMs: total,
            selectionElapsedMs: diagnostics["selection_elapsed_ms"],
            screenCaptureElapsedMs: diagnostics["screen_capture_elapsed_ms"],
            pngWriteElapsedMs: diagnostics["png_write_elapsed_ms"],
            imageCaptureElapsedMs: imageCapture,
            postSelectionToClipboardElapsedMs: imageCapture.map { $0 + ocr + clipboard }
        )
    }

    public func run() async throws -> ScreenOCRRunReport {
        let totalStarted = Date()
        var captureElapsedMs = 0
        var ocrElapsedMs = 0
        var clipboardElapsedMs = 0
        let image: CapturedImage
        do {
            let started = Date()
            image = try await capture.captureRegion()
            captureElapsedMs = elapsedMilliseconds(since: started)
        } catch {
            captureElapsedMs = elapsedMilliseconds(since: totalStarted)
            return ScreenOCRRunReport(
                status: .failed(.capture),
                capturedImageID: "",
                capturedImagePath: nil,
                recognizedText: "",
                lineCount: 0,
                errorMessage: error.localizedDescription,
                timings: makeTimings(
                    capture: captureElapsedMs,
                    ocr: ocrElapsedMs,
                    clipboard: clipboardElapsedMs,
                    total: elapsedMilliseconds(since: totalStarted),
                    diagnostics: [:]
                )
            )
        }

        let document: OCRDocument

        do {
            let started = Date()
            document = try await ocr.recognizeText(in: image)
            ocrElapsedMs = elapsedMilliseconds(since: started)
        } catch {
            ocrElapsedMs = elapsedMilliseconds(since: totalStarted) - captureElapsedMs
            return ScreenOCRRunReport(
                status: .failed(.ocr),
                capturedImageID: image.id,
                capturedImagePath: image.filePath,
                recognizedText: "",
                lineCount: 0,
                errorMessage: error.localizedDescription,
                timings: makeTimings(
                    capture: captureElapsedMs,
                    ocr: ocrElapsedMs,
                    clipboard: clipboardElapsedMs,
                    total: elapsedMilliseconds(since: totalStarted),
                    diagnostics: image.diagnostics
                )
            )
        }

        let text = document.normalizedText
        do {
            let started = Date()
            try clipboard.writeText(text)
            clipboardElapsedMs = elapsedMilliseconds(since: started)
        } catch {
            clipboardElapsedMs = elapsedMilliseconds(since: totalStarted) - captureElapsedMs - ocrElapsedMs
            return ScreenOCRRunReport(
                status: .failed(.clipboard),
                capturedImageID: image.id,
                capturedImagePath: image.filePath,
                recognizedText: text,
                lineCount: document.lines.count,
                errorMessage: error.localizedDescription,
                timings: makeTimings(
                    capture: captureElapsedMs,
                    ocr: ocrElapsedMs,
                    clipboard: clipboardElapsedMs,
                    total: elapsedMilliseconds(since: totalStarted),
                    diagnostics: image.diagnostics
                ),
                ocrDiagnostics: document.diagnostics,
                ocrMetadata: document.metadata
            )
        }

        return ScreenOCRRunReport(
            status: .copiedText,
            capturedImageID: image.id,
            capturedImagePath: image.filePath,
            recognizedText: text,
            lineCount: document.lines.count,
            errorMessage: nil,
            timings: makeTimings(
                capture: captureElapsedMs,
                ocr: ocrElapsedMs,
                clipboard: clipboardElapsedMs,
                total: elapsedMilliseconds(since: totalStarted),
                diagnostics: image.diagnostics
            ),
            ocrDiagnostics: document.diagnostics,
            ocrMetadata: document.metadata
        )
    }
}

public func elapsedMilliseconds(since started: Date) -> Int {
    max(0, Int((Date().timeIntervalSince(started) * 1000).rounded()))
}

public struct OCRDebugArtifactPair: Equatable, Sendable {
    public let runID: String
    public let imagePath: String
    public let textPath: String
    public let manifestPath: String
    public let latestManifestPath: String
}

public struct OCRDebugArtifactWriter {
    private let outputDirectory: URL
    private let fileManager: FileManager

    public init(outputDirectory: URL, fileManager: FileManager = .default) {
        self.outputDirectory = outputDirectory
        self.fileManager = fileManager
    }

    public func savePair(from report: ScreenOCRRunReport, createdAt: Date = Date()) throws -> OCRDebugArtifactPair {
        guard let capturedImagePath = report.capturedImagePath else {
            throw OCRDebugArtifactError.missingCapturedImagePath
        }

        let sourceImageURL = URL(fileURLWithPath: capturedImagePath)
        let runID = sourceImageURL.deletingPathExtension().lastPathComponent
        // Keep the capture's own container (uncompressed TIFF today) — the copy is an APFS
        // clone on the pre-toast path, so re-encoding here would cost what the fast capture
        // format just saved.
        let imageExtension = sourceImageURL.pathExtension.isEmpty ? "png" : sourceImageURL.pathExtension
        let imageURL = outputDirectory.appendingPathComponent(runID).appendingPathExtension(imageExtension)
        let textURL = outputDirectory.appendingPathComponent(runID).appendingPathExtension("txt")
        let manifestURL = outputDirectory.appendingPathComponent(runID).appendingPathExtension("json")
        let latestManifestURL = outputDirectory.appendingPathComponent("latest-pair.json")

        try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        if sourceImageURL.standardizedFileURL.path != imageURL.standardizedFileURL.path {
            if fileManager.fileExists(atPath: imageURL.path) {
                try fileManager.removeItem(at: imageURL)
            }
            try fileManager.copyItem(at: sourceImageURL, to: imageURL)
        }

        try report.recognizedText.write(to: textURL, atomically: true, encoding: .utf8)

        let manifest: [String: Any] = [
            "created_at": ISO8601DateFormatter().string(from: createdAt),
            "run_id": runID,
            "status": report.status.diagnosticValue,
            "captured_image_id": report.capturedImageID,
            "source_image_path": sourceImageURL.path,
            "debug_image_path": imageURL.path,
            "debug_text_path": textURL.path,
            "line_count": report.lineCount,
            "error_message": report.errorMessage as Any,
            "timings": report.timings?.diagnosticPayload as Any,
            "ocr_diagnostics": report.ocrDiagnostics,
            "ocr_metadata": report.ocrMetadata
        ]
        let data = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: manifestURL)
        try data.write(to: latestManifestURL)

        return OCRDebugArtifactPair(
            runID: runID,
            imagePath: imageURL.path,
            textPath: textURL.path,
            manifestPath: manifestURL.path,
            latestManifestPath: latestManifestURL.path
        )
    }
}

public enum OCRDebugArtifactError: Error, LocalizedError, Equatable {
    case missingCapturedImagePath

    public var errorDescription: String? {
        switch self {
        case .missingCapturedImagePath:
            return "Cannot save OCR debug artifacts because the capture has no image path"
        }
    }
}

public extension ScreenOCRRunStatus {
    var diagnosticValue: String {
        switch self {
        case .copiedText:
            return "copied_text"
        case .failed(let stage):
            return "failed_\(stage.diagnosticValue)"
        }
    }
}

public extension ScreenOCRFailureStage {
    var diagnosticValue: String {
        switch self {
        case .capture:
            return "capture"
        case .ocr:
            return "ocr"
        case .clipboard:
            return "clipboard"
        }
    }
}

public struct PythonSidecarOCR: OCRRecognizing {
    private let pythonExecutablePath: String
    private let sidecarPath: String

    public init(pythonExecutablePath: String, sidecarPath: String) {
        self.pythonExecutablePath = pythonExecutablePath
        self.sidecarPath = sidecarPath
    }

    public func recognizeText(in image: CapturedImage) async throws -> OCRDocument {
        guard let filePath = image.filePath else {
            throw PythonSidecarOCRError.missingImagePath(imageID: image.id)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonExecutablePath)
        process.arguments = ["-m", "screen_ocr_sidecar.ocr", filePath]

        var environment = ProcessInfo.processInfo.environment
        environment["PYTHONPATH"] = sidecarPath
        environment["PYTHONDONTWRITEBYTECODE"] = "1"
        process.environment = environment

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        let errorOutput = stderr.fileHandleForReading.readDataToEndOfFile()

        guard process.terminationStatus == 0 else {
            throw PythonSidecarOCRError.processFailed(
                status: process.terminationStatus,
                stderr: String(data: errorOutput, encoding: .utf8) ?? ""
            )
        }

        do {
            return try JSONDecoder().decode(OCRDocument.self, from: output)
        } catch {
            throw PythonSidecarOCRError.invalidJSON(message: error.localizedDescription)
        }
    }
}

public enum PythonSidecarOCRError: Error, LocalizedError, Equatable {
    case missingImagePath(imageID: String)
    case processFailed(status: Int32, stderr: String)
    case invalidJSON(message: String)

    public var errorDescription: String? {
        switch self {
        case .missingImagePath(let imageID):
            return "Captured image has no file path: \(imageID)"
        case .processFailed(let status, let stderr):
            let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if detail.isEmpty {
                return "Python OCR sidecar failed with exit \(status)"
            }

            return "Python OCR sidecar failed with exit \(status): \(detail)"
        case .invalidJSON(let message):
            return "Python OCR sidecar returned invalid JSON: \(message)"
        }
    }
}

public struct PersistentOCRWorkerReady: Codable, Equatable, Sendable {
    public let initElapsedMs: Double

    public init(initElapsedMs: Double) {
        self.initElapsedMs = initElapsedMs
    }
}

public actor PersistentPythonSidecarOCR: OCRWorkerManaging {
    private let pythonExecutablePath: String
    private let sidecarPath: String
    private let requestTimeoutMs: Int
    private let recognitionWorkerCount: Int?
    private var process: Process?
    private var stdinHandle: FileHandle?
    private var reader: WorkerLineReader?
    private var ready: PersistentOCRWorkerReady?
    private var startTask: Task<PersistentOCRWorkerReady, Error>?
    private var stageHandler: (@Sendable (OCRStage) -> Void)?

    /// Installs a callback invoked as the worker streams per-stage progress events for the next
    /// request (one in-flight request at a time, so a single slot is enough).
    public func setStageHandler(_ handler: (@Sendable (OCRStage) -> Void)?) {
        stageHandler = handler
    }

    public init(pythonExecutablePath: String, sidecarPath: String, recognitionWorkerCount: Int? = nil) {
        self.init(
            pythonExecutablePath: pythonExecutablePath,
            sidecarPath: sidecarPath,
            requestTimeoutMs: Self.configuredTimeoutMs(),
            recognitionWorkerCount: recognitionWorkerCount
        )
    }

    init(
        pythonExecutablePath: String,
        sidecarPath: String,
        requestTimeoutMs: Int,
        recognitionWorkerCount: Int? = nil
    ) {
        self.pythonExecutablePath = pythonExecutablePath
        self.sidecarPath = sidecarPath
        self.requestTimeoutMs = max(1, requestTimeoutMs)
        self.recognitionWorkerCount = Self.normalizedRecognitionWorkerCount(recognitionWorkerCount)
    }

    /// Worker startup (process spawn + model load) is legitimately slower than a single OCR
    /// request, so it gets its own floor rather than inheriting a tight per-request timeout.
    /// A large per-request timeout still applies; only an unusually small one is widened here.
    private var startupTimeoutMs: Int {
        max(requestTimeoutMs, 5000)
    }

    private static func configuredTimeoutMs() -> Int {
        if let raw = ProcessInfo.processInfo.environment["SCREEN_OCR_OCR_TIMEOUT_MS"],
           let value = Int(raw.trimmingCharacters(in: .whitespaces)),
           value > 0 {
            return value
        }
        // A dense, near-full-screen capture (e.g. 3190x1728 with dozens of text lines)
        // legitimately takes ~18s to recognize on CPU. A 15s timeout killed such jobs
        // mid-flight and then forced a cold worker restart on the next request — a death
        // spiral. 30s comfortably covers large captures while still catching a true hang.
        return 30000
    }

    private static func normalizedRecognitionWorkerCount(_ count: Int?) -> Int? {
        guard let count, count > 0 else { return nil }
        return count
    }

    deinit {
        // Same escalation as stopWorker: SIGTERM is ignorable while the worker sits inside a
        // native Paddle kernel (Python only delivers it at the next bytecode), so follow up
        // with SIGKILL — the recognizer children reap themselves via their parent watchdogs.
        if let process, process.isRunning {
            process.terminate()
            DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
                if process.isRunning {
                    kill(process.processIdentifier, SIGKILL)
                }
            }
        }
    }

    public func prewarm() async throws -> PersistentOCRWorkerReady {
        try await startWorkerIfNeeded()
    }

    public func workerProcessIdentifier() -> Int32? {
        process?.isRunning == true ? process?.processIdentifier : nil
    }

    public func recognizeText(in image: CapturedImage) async throws -> OCRDocument {
        guard let filePath = image.filePath else {
            throw PythonSidecarOCRError.missingImagePath(imageID: image.id)
        }

        _ = try await startWorkerIfNeeded()
        guard let stdinHandle, let reader else {
            throw PersistentPythonSidecarOCRError.workerUnavailable
        }

        let request = PersistentOCRWorkerRequest(id: UUID().uuidString, imagePath: filePath)
        var requestData = try JSONEncoder().encode(request)
        requestData.append(0x0A)
        do {
            try stdinHandle.write(contentsOf: requestData)
        } catch {
            stopWorker()
            throw PersistentPythonSidecarOCRError.writeFailed(message: error.localizedDescription)
        }

        // The worker streams progress events ("preprocess", "recognize") ahead of the final
        // result line; consume them, forwarding each stage to the handler, until the result.
        let responseData: Data
        do {
            responseData = try await readResultLine(using: reader, timeoutMs: requestTimeoutMs)
        } catch {
            stopWorker()
            throw error
        }

        let envelope: PersistentOCRWorkerResponseEnvelope
        do {
            envelope = try JSONDecoder().decode(PersistentOCRWorkerResponseEnvelope.self, from: responseData)
        } catch {
            stopWorker()
            throw PersistentPythonSidecarOCRError.invalidJSON(message: error.localizedDescription)
        }

        if envelope.ok == false {
            throw PersistentPythonSidecarOCRError.workerReturnedError(
                message: envelope.error ?? "Unknown OCR worker error",
                stage: envelope.stage,
                traceback: envelope.traceback
            )
        }

        do {
            return try JSONDecoder().decode(OCRDocument.self, from: responseData)
        } catch {
            throw PersistentPythonSidecarOCRError.invalidJSON(message: error.localizedDescription)
        }
    }

    private func startWorkerIfNeeded() async throws -> PersistentOCRWorkerReady {
        if let process, process.isRunning, let ready {
            return ready
        }

        // Dedupe concurrent starts: prewarm and the first request can both reach here while the
        // worker is still loading. Without this, the second caller's `stopWorker()` would kill
        // the worker the first caller is mid-read on ("closed output unexpectedly"). Join the
        // in-flight start instead of spawning a competing one.
        if let startTask {
            return try await startTask.value
        }

        let task = Task { try await self.startWorker() }
        startTask = task
        defer { startTask = nil }
        return try await task.value
    }

    private func startWorker() async throws -> PersistentOCRWorkerReady {
        stopWorker()

        let workerProcess = Process()
        workerProcess.executableURL = URL(fileURLWithPath: pythonExecutablePath)
        workerProcess.arguments = ["-u", "-m", "screen_ocr_sidecar.worker"]

        var environment = ProcessInfo.processInfo.environment
        environment["PYTHONPATH"] = sidecarPath
        environment["PYTHONDONTWRITEBYTECODE"] = "1"
        if let recognitionWorkerCount {
            environment["SCREEN_OCR_REC_WORKERS"] = "\(recognitionWorkerCount)"
        } else {
            environment.removeValue(forKey: "SCREEN_OCR_REC_WORKERS")
        }
        workerProcess.environment = environment

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        workerProcess.standardInput = stdinPipe
        workerProcess.standardOutput = stdoutPipe
        workerProcess.standardError = FileHandle.standardError

        do {
            try workerProcess.run()
        } catch {
            throw PersistentPythonSidecarOCRError.startFailed(message: error.localizedDescription)
        }

        let workerReader = WorkerLineReader(handle: stdoutPipe.fileHandleForReading)
        process = workerProcess
        stdinHandle = stdinPipe.fileHandleForWriting
        reader = workerReader

        let readyData: Data
        do {
            readyData = try await readResponseLine(using: workerReader, timeoutMs: startupTimeoutMs)
        } catch {
            stopWorker()
            throw error
        }

        let readyEnvelope: PersistentOCRWorkerReadyEnvelope
        do {
            readyEnvelope = try JSONDecoder().decode(PersistentOCRWorkerReadyEnvelope.self, from: readyData)
        } catch {
            stopWorker()
            throw PersistentPythonSidecarOCRError.invalidJSON(message: error.localizedDescription)
        }

        guard readyEnvelope.event == "ready", readyEnvelope.ok == true else {
            stopWorker()
            throw PersistentPythonSidecarOCRError.workerReturnedError(
                message: readyEnvelope.error ?? "OCR worker did not become ready"
            )
        }

        let ready = PersistentOCRWorkerReady(initElapsedMs: readyEnvelope.initElapsedMs ?? 0)
        self.ready = ready
        return ready
    }

    private func stopWorker() {
        stdinHandle = nil
        reader = nil
        ready = nil
        if let process, process.isRunning {
            // SIGTERM first so the worker can shut its recognizer pool down (it installs a
            // handler for exactly this); escalate to SIGKILL only if it is still around after
            // a grace period — e.g. wedged inside a native Paddle kernel.
            process.terminate()
            DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
                if process.isRunning {
                    kill(process.processIdentifier, SIGKILL)
                }
            }
        }
        process = nil
    }

    /// Reads one newline-delimited response line, racing the blocking read against a hard
    /// timeout. On timeout the worker process is terminated so the in-flight read unblocks
    /// via EOF; the next request restarts the worker.
    private func readResponseLine(using reader: WorkerLineReader, timeoutMs: Int) async throws -> Data {
        try await withThrowingTaskGroup(of: Data?.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data?, Error>) in
                    DispatchQueue.global().async {
                        do {
                            continuation.resume(returning: try reader.readLine())
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    }
                }
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(max(1, timeoutMs)) * 1_000_000)
                return nil
            }

            defer { group.cancelAll() }

            while let result = try await group.next() {
                if let data = result {
                    return data
                }
                // Timeout fired first: terminate the worker so the blocked read sees EOF,
                // then surface a timeout error to the caller.
                stopWorker()
                throw PersistentPythonSidecarOCRError.requestTimedOut(ms: timeoutMs)
            }

            throw PersistentPythonSidecarOCRError.unexpectedEOF
        }
    }

    /// Reads worker output lines until the final result, forwarding any `event:"progress"`
    /// lines to the stage handler along the way. Each line read is bounded by `timeoutMs`,
    /// which covers the long gap between the "recognize" event and the result.
    private func readResultLine(using reader: WorkerLineReader, timeoutMs: Int) async throws -> Data {
        while true {
            let data = try await readResponseLine(using: reader, timeoutMs: timeoutMs)
            let progress = try? JSONDecoder().decode(PersistentOCRWorkerProgressEnvelope.self, from: data)
            if progress?.event == "progress",
               let stageName = progress?.stage,
               let stage = OCRStage.fromWorkerEvent(stageName) {
                stageHandler?(stage)
                continue
            }
            return data
        }
    }
}

/// Buffered line reader over a worker's stdout. Reads in chunks (vs. one byte at a time) and
/// keeps any bytes past the newline for the next call. Accessed by one in-flight request at a
/// time, but handed to a background read task, hence `@unchecked Sendable`.
final class WorkerLineReader: @unchecked Sendable {
    private let handle: FileHandle
    private var buffer = Data()

    init(handle: FileHandle) {
        self.handle = handle
    }

    func readLine() throws -> Data {
        while true {
            if let newlineIndex = buffer.firstIndex(of: 0x0A) {
                let line = Data(buffer[buffer.startIndex..<newlineIndex])
                let remainderStart = buffer.index(after: newlineIndex)
                buffer = Data(buffer[remainderStart...])
                return line
            }

            let chunk = try readAvailableChunk()
            guard !chunk.isEmpty else {
                throw PersistentPythonSidecarOCRError.unexpectedEOF
            }
            buffer.append(chunk)
        }
    }

    /// Reads whatever is currently available on the pipe via a single `read(2)` syscall.
    /// Unlike `FileHandle.read(upToCount:)` — which blocks until the requested count is
    /// filled or EOF — this returns as soon as one or more bytes arrive, so a line that is
    /// already in the pipe is delivered immediately. Returns empty `Data` on EOF.
    private func readAvailableChunk() throws -> Data {
        let capacity = 4096
        var storage = Data(count: capacity)
        let bytesRead = storage.withUnsafeMutableBytes { raw -> Int in
            guard let base = raw.baseAddress else { return 0 }
            return read(handle.fileDescriptor, base, capacity)
        }
        if bytesRead < 0 {
            throw PersistentPythonSidecarOCRError.unexpectedEOF
        }
        return storage.prefix(bytesRead)
    }
}

private struct PersistentOCRWorkerRequest: Encodable {
    let id: String
    let imagePath: String

    enum CodingKeys: String, CodingKey {
        case id
        case imagePath = "image_path"
    }
}

private struct PersistentOCRWorkerProgressEnvelope: Decodable {
    let event: String?
    let stage: String?
}

private struct PersistentOCRWorkerReadyEnvelope: Decodable {
    let event: String?
    let ok: Bool?
    let error: String?
    let initElapsedMs: Double?

    enum CodingKeys: String, CodingKey {
        case event
        case ok
        case error
        case initElapsedMs = "init_elapsed_ms"
    }
}

private struct PersistentOCRWorkerResponseEnvelope: Decodable {
    let ok: Bool?
    let error: String?
    let stage: String?
    let traceback: String?
}

/// Structured detail carried by an OCR failure so callers can attribute it to a pipeline stage
/// and recover the full diagnostic (e.g. a Python traceback) for logs without surfacing it to
/// the user.
public struct OCRFailureDetail: Sendable, Equatable {
    public let stage: String?
    public let traceback: String?

    public init(stage: String? = nil, traceback: String? = nil) {
        self.stage = stage
        self.traceback = traceback
    }
}

/// A protocol every OCR error conforms to so the app layer can pull stage/traceback off any
/// thrown error uniformly (worker errors, capture errors, …) for error tracking.
public protocol OCRDiagnosable {
    var failureDetail: OCRFailureDetail { get }
}

public enum PersistentPythonSidecarOCRError: Error, LocalizedError, Sendable, OCRDiagnosable {
    case startFailed(message: String)
    case workerUnavailable
    case writeFailed(message: String)
    case workerReturnedError(message: String, stage: String? = nil, traceback: String? = nil)
    case unexpectedEOF
    case invalidJSON(message: String)
    case requestTimedOut(ms: Int)

    public var errorDescription: String? {
        switch self {
        case .startFailed(let message):
            return "Persistent OCR worker failed to start: \(message)"
        case .workerUnavailable:
            return "Persistent OCR worker is unavailable"
        case .writeFailed(let message):
            return "Persistent OCR worker request write failed: \(message)"
        case .workerReturnedError(let message, let stage, _):
            if let stage {
                return "Persistent OCR worker failed at \(stage): \(message)"
            }
            return "Persistent OCR worker returned an error: \(message)"
        case .unexpectedEOF:
            return "Persistent OCR worker closed its output unexpectedly"
        case .invalidJSON(let message):
            return "Persistent OCR worker returned invalid JSON: \(message)"
        case .requestTimedOut(let ms):
            return "Persistent OCR worker timed out after \(ms) ms"
        }
    }

    public var failureDetail: OCRFailureDetail {
        switch self {
        case .workerReturnedError(_, let stage, let traceback):
            return OCRFailureDetail(stage: stage, traceback: traceback)
        case .requestTimedOut:
            return OCRFailureDetail(stage: "recognize")
        case .unexpectedEOF:
            return OCRFailureDetail(stage: "worker")
        case .startFailed:
            return OCRFailureDetail(stage: "worker_start")
        default:
            return OCRFailureDetail()
        }
    }
}
