import CoreGraphics
import Foundation

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

public protocol ClipboardWriting: AnyObject {
    func writeText(_ text: String) throws
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
                timings: ScreenOCRStageTimings(
                    captureElapsedMs: captureElapsedMs,
                    ocrElapsedMs: ocrElapsedMs,
                    clipboardElapsedMs: clipboardElapsedMs,
                    totalElapsedMs: elapsedMilliseconds(since: totalStarted)
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
                timings: ScreenOCRStageTimings(
                    captureElapsedMs: captureElapsedMs,
                    ocrElapsedMs: ocrElapsedMs,
                    clipboardElapsedMs: clipboardElapsedMs,
                    totalElapsedMs: elapsedMilliseconds(since: totalStarted),
                    selectionElapsedMs: image.diagnostics["selection_elapsed_ms"],
                    screenCaptureElapsedMs: image.diagnostics["screen_capture_elapsed_ms"],
                    pngWriteElapsedMs: image.diagnostics["png_write_elapsed_ms"],
                    imageCaptureElapsedMs: image.diagnostics["image_capture_elapsed_ms"],
                    postSelectionToClipboardElapsedMs: image.diagnostics["image_capture_elapsed_ms"].map {
                        $0 + ocrElapsedMs
                    }
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
                timings: ScreenOCRStageTimings(
                    captureElapsedMs: captureElapsedMs,
                    ocrElapsedMs: ocrElapsedMs,
                    clipboardElapsedMs: clipboardElapsedMs,
                    totalElapsedMs: elapsedMilliseconds(since: totalStarted),
                    selectionElapsedMs: image.diagnostics["selection_elapsed_ms"],
                    screenCaptureElapsedMs: image.diagnostics["screen_capture_elapsed_ms"],
                    pngWriteElapsedMs: image.diagnostics["png_write_elapsed_ms"],
                    imageCaptureElapsedMs: image.diagnostics["image_capture_elapsed_ms"],
                    postSelectionToClipboardElapsedMs: image.diagnostics["image_capture_elapsed_ms"].map {
                        $0 + ocrElapsedMs + clipboardElapsedMs
                    }
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
            timings: ScreenOCRStageTimings(
                captureElapsedMs: captureElapsedMs,
                ocrElapsedMs: ocrElapsedMs,
                clipboardElapsedMs: clipboardElapsedMs,
                totalElapsedMs: elapsedMilliseconds(since: totalStarted),
                selectionElapsedMs: image.diagnostics["selection_elapsed_ms"],
                screenCaptureElapsedMs: image.diagnostics["screen_capture_elapsed_ms"],
                pngWriteElapsedMs: image.diagnostics["png_write_elapsed_ms"],
                imageCaptureElapsedMs: image.diagnostics["image_capture_elapsed_ms"],
                postSelectionToClipboardElapsedMs: image.diagnostics["image_capture_elapsed_ms"].map {
                    $0 + ocrElapsedMs + clipboardElapsedMs
                }
            ),
            ocrDiagnostics: document.diagnostics,
            ocrMetadata: document.metadata
        )
    }
}

private func elapsedMilliseconds(since started: Date) -> Int {
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
        let imageURL = outputDirectory.appendingPathComponent(runID).appendingPathExtension("png")
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

public actor PersistentPythonSidecarOCR: OCRRecognizing {
    private let pythonExecutablePath: String
    private let sidecarPath: String
    private var process: Process?
    private var stdinHandle: FileHandle?
    private var stdoutHandle: FileHandle?
    private var ready: PersistentOCRWorkerReady?

    public init(pythonExecutablePath: String, sidecarPath: String) {
        self.pythonExecutablePath = pythonExecutablePath
        self.sidecarPath = sidecarPath
    }

    deinit {
        process?.terminate()
    }

    public func prewarm() async throws -> PersistentOCRWorkerReady {
        try startWorkerIfNeeded()
    }

    public func workerProcessIdentifier() -> Int32? {
        process?.isRunning == true ? process?.processIdentifier : nil
    }

    public func recognizeText(in image: CapturedImage) async throws -> OCRDocument {
        guard let filePath = image.filePath else {
            throw PythonSidecarOCRError.missingImagePath(imageID: image.id)
        }

        _ = try startWorkerIfNeeded()
        guard let stdinHandle, let stdoutHandle else {
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

        let responseData: Data
        do {
            responseData = try readLineData(from: stdoutHandle)
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
                message: envelope.error ?? "Unknown OCR worker error"
            )
        }

        do {
            return try JSONDecoder().decode(OCRDocument.self, from: responseData)
        } catch {
            throw PersistentPythonSidecarOCRError.invalidJSON(message: error.localizedDescription)
        }
    }

    private func startWorkerIfNeeded() throws -> PersistentOCRWorkerReady {
        if let process, process.isRunning, let ready {
            return ready
        }

        stopWorker()

        let workerProcess = Process()
        workerProcess.executableURL = URL(fileURLWithPath: pythonExecutablePath)
        workerProcess.arguments = ["-u", "-m", "screen_ocr_sidecar.worker"]

        var environment = ProcessInfo.processInfo.environment
        environment["PYTHONPATH"] = sidecarPath
        environment["PYTHONDONTWRITEBYTECODE"] = "1"
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

        process = workerProcess
        stdinHandle = stdinPipe.fileHandleForWriting
        stdoutHandle = stdoutPipe.fileHandleForReading

        let readyData: Data
        do {
            readyData = try readLineData(from: stdoutPipe.fileHandleForReading)
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
        stdoutHandle = nil
        ready = nil
        if let process, process.isRunning {
            process.terminate()
        }
        process = nil
    }

    private func readLineData(from fileHandle: FileHandle) throws -> Data {
        var data = Data()
        while true {
            let chunk = try fileHandle.read(upToCount: 1)
            guard let chunk, !chunk.isEmpty else {
                throw PersistentPythonSidecarOCRError.unexpectedEOF
            }
            if chunk.first == 0x0A {
                return data
            }
            data.append(chunk)
        }
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
}

public enum PersistentPythonSidecarOCRError: Error, LocalizedError, Sendable {
    case startFailed(message: String)
    case workerUnavailable
    case writeFailed(message: String)
    case workerReturnedError(message: String)
    case unexpectedEOF
    case invalidJSON(message: String)

    public var errorDescription: String? {
        switch self {
        case .startFailed(let message):
            return "Persistent OCR worker failed to start: \(message)"
        case .workerUnavailable:
            return "Persistent OCR worker is unavailable"
        case .writeFailed(let message):
            return "Persistent OCR worker request write failed: \(message)"
        case .workerReturnedError(let message):
            return "Persistent OCR worker returned an error: \(message)"
        case .unexpectedEOF:
            return "Persistent OCR worker closed its output unexpectedly"
        case .invalidJSON(let message):
            return "Persistent OCR worker returned invalid JSON: \(message)"
        }
    }
}
