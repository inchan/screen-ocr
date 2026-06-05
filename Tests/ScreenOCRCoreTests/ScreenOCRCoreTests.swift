import XCTest
@testable import ScreenOCRCore

final class ScreenOCRCoreTests: XCTestCase {
    func testSuccessfulOCRRunCopiesRecognizedTextToClipboard() async throws {
        let capture = FakeCapture(
            image: CapturedImage(
                id: "fixture://mixed-ko-en",
                width: 320,
                height: 120,
                diagnostics: [
                    "selection_elapsed_ms": 8,
                    "screen_capture_elapsed_ms": 5,
                    "png_write_elapsed_ms": 2,
                    "image_capture_elapsed_ms": 7
                ]
            )
        )
        let ocr = FakeOCR(
            result: OCRDocument(
                lines: [
                    OCRLine(text: "OCR 테스트", score: 0.97),
                    OCRLine(text: "Hello 123", score: 0.95)
                ],
                diagnostics: [
                    "preprocess_elapsed_ms": 4,
                    "preprocess_applied": 1
                ],
                metadata: [
                    "preprocess_status": "applied",
                    "ocr_image_path": "/tmp/preprocessed.png"
                ]
            )
        )
        let clipboard = FakeClipboard()
        let pipeline = ScreenOCRPipeline(capture: capture, ocr: ocr, clipboard: clipboard)

        let report = try await pipeline.run()

        XCTAssertEqual(report.status, .copiedText)
        XCTAssertEqual(report.capturedImageID, "fixture://mixed-ko-en")
        XCTAssertNil(report.capturedImagePath)
        XCTAssertEqual(report.recognizedText, "OCR 테스트\nHello 123")
        XCTAssertEqual(clipboard.text, "OCR 테스트\nHello 123")
        XCTAssertEqual(report.lineCount, 2)
        XCTAssertNotNil(report.timings)
        XCTAssertGreaterThanOrEqual(report.timings?.captureElapsedMs ?? -1, 0)
        XCTAssertGreaterThanOrEqual(report.timings?.ocrElapsedMs ?? -1, 0)
        XCTAssertGreaterThanOrEqual(report.timings?.clipboardElapsedMs ?? -1, 0)
        XCTAssertGreaterThanOrEqual(report.timings?.totalElapsedMs ?? -1, 0)
        XCTAssertEqual(report.timings?.selectionElapsedMs, 8)
        XCTAssertEqual(report.timings?.screenCaptureElapsedMs, 5)
        XCTAssertEqual(report.timings?.pngWriteElapsedMs, 2)
        XCTAssertEqual(report.timings?.imageCaptureElapsedMs, 7)
        XCTAssertGreaterThanOrEqual(report.timings?.postSelectionToClipboardElapsedMs ?? -1, 7)
        XCTAssertEqual(report.ocrDiagnostics["preprocess_elapsed_ms"], 4)
        XCTAssertEqual(report.ocrDiagnostics["preprocess_applied"], 1)
        XCTAssertEqual(report.ocrMetadata["preprocess_status"], "applied")
        XCTAssertEqual(report.ocrMetadata["ocr_image_path"], "/tmp/preprocessed.png")
    }

    func testOCRFailureDoesNotOverwriteClipboardAndReportsCapturedImage() async throws {
        let capture = FakeCapture(
            image: CapturedImage(id: "fixture://failed-ocr", width: 240, height: 80)
        )
        let ocr = FailingOCR(error: TestError.message("model unavailable"))
        let clipboard = FakeClipboard()
        let pipeline = ScreenOCRPipeline(capture: capture, ocr: ocr, clipboard: clipboard)

        let report = try await pipeline.run()

        XCTAssertEqual(report.status, .failed(.ocr))
        XCTAssertEqual(report.capturedImageID, "fixture://failed-ocr")
        XCTAssertNil(report.capturedImagePath)
        XCTAssertEqual(report.recognizedText, "")
        XCTAssertNil(clipboard.text)
        XCTAssertEqual(report.lineCount, 0)
        XCTAssertEqual(report.errorMessage, "model unavailable")
    }

    func testCaptureFailureReturnsReportWithoutRunningOCR() async throws {
        let capture = FailingCapture(error: TestError.message("screen recording denied"))
        let ocr = FakeOCR(result: OCRDocument(lines: [OCRLine(text: "Should not run", score: 1)]))
        let clipboard = FakeClipboard()
        let pipeline = ScreenOCRPipeline(capture: capture, ocr: ocr, clipboard: clipboard)

        let report = try await pipeline.run()

        XCTAssertEqual(report.status, .failed(.capture))
        XCTAssertEqual(report.capturedImageID, "")
        XCTAssertNil(report.capturedImagePath)
        XCTAssertEqual(report.recognizedText, "")
        XCTAssertEqual(report.lineCount, 0)
        XCTAssertNil(clipboard.text)
        XCTAssertEqual(report.errorMessage, "screen recording denied")
    }

    func testClipboardFailureReturnsReportWithRecognizedTextButDoesNotClaimCopy() async throws {
        let capture = FakeCapture(
            image: CapturedImage(id: "fixture://clipboard-failure", width: 320, height: 120)
        )
        let ocr = FakeOCR(result: OCRDocument(lines: [OCRLine(text: "OCR 테스트", score: 0.97)]))
        let clipboard = FailingClipboard(error: TestError.message("pasteboard locked"))
        let pipeline = ScreenOCRPipeline(capture: capture, ocr: ocr, clipboard: clipboard)

        let report = try await pipeline.run()

        XCTAssertEqual(report.status, .failed(.clipboard))
        XCTAssertEqual(report.capturedImageID, "fixture://clipboard-failure")
        XCTAssertNil(report.capturedImagePath)
        XCTAssertEqual(report.recognizedText, "OCR 테스트")
        XCTAssertEqual(report.lineCount, 1)
        XCTAssertEqual(report.errorMessage, "pasteboard locked")
    }

    func testClipboardToastMessageStartsWithEmoji() {
        XCTAssertEqual(ClipboardCopyToast.message, "📋 Copied to clipboard")
    }

    func testClipboardToastFrameIsBelowMenuBarAnchorAndClampedToVisibleScreen() {
        let visibleFrame = CGRect(x: 0, y: 0, width: 320, height: 240)
        let anchorFrame = CGRect(x: 280, y: 220, width: 32, height: 20)

        let frame = ClipboardCopyToast.frame(
            below: anchorFrame,
            preferredSize: CGSize(width: 180, height: 44),
            visibleFrame: visibleFrame
        )

        XCTAssertEqual(frame.maxX, 312)
        XCTAssertEqual(frame.minY, 168)
        XCTAssertEqual(frame.width, 180)
        XCTAssertEqual(frame.height, 44)
    }

    func testPythonSidecarOCRParsesSidecarJSON() async throws {
        let executable = try makeExecutableScript(
            name: "fake-ocr-success",
            body: """
            #!/bin/sh
            echo '{"text":"OCR 테스트\\nHello 123","line_count":2,"lines":[{"text":"OCR 테스트","score":0.97,"box":[[0,0],[1,0],[1,1],[0,1]]},{"text":"Hello 123","score":0.95,"box":[[0,2],[1,2],[1,3],[0,3]]}]}'
            """
        )
        let ocr = PythonSidecarOCR(pythonExecutablePath: executable.path, sidecarPath: "/tmp/sidecar")
        let image = CapturedImage(
            id: "fixture://bridge",
            width: 320,
            height: 120,
            filePath: "/tmp/input.png"
        )

        let document = try await ocr.recognizeText(in: image)

        XCTAssertEqual(document.normalizedText, "OCR 테스트\nHello 123")
        XCTAssertEqual(document.lines.map(\.score), [0.97, 0.95])
    }

    func testPythonSidecarOCRReportsProcessFailure() async throws {
        let executable = try makeExecutableScript(
            name: "fake-ocr-failure",
            body: """
            #!/bin/sh
            echo 'model unavailable' >&2
            exit 42
            """
        )
        let ocr = PythonSidecarOCR(pythonExecutablePath: executable.path, sidecarPath: "/tmp/sidecar")
        let image = CapturedImage(
            id: "fixture://bridge-failure",
            width: 320,
            height: 120,
            filePath: "/tmp/input.png"
        )

        do {
            _ = try await ocr.recognizeText(in: image)
            XCTFail("Expected Python sidecar failure")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("exit 42"))
            XCTAssertTrue(error.localizedDescription.contains("model unavailable"))
        }
    }

    func testPersistentPythonSidecarOCRParsesWorkerJSONL() async throws {
        let executable = try makeExecutableScript(
            name: "fake-worker-success",
            body: """
            #!/bin/sh
            printf '%s\\n' '{"event":"ready","ok":true,"init_elapsed_ms":1.5}'
            while IFS= read -r line; do
              printf '%s\\n' '{"ok":true,"text":"OCR 테스트\\nHello 123","line_count":2,"lines":[{"text":"OCR 테스트","score":0.97},{"text":"Hello 123","score":0.95}],"diagnostics":{"preprocess_elapsed_ms":3,"preprocess_applied":1},"metadata":{"preprocess_status":"applied","ocr_image_path":"/tmp/input.preprocessed.png"}}'
            done
            """
        )
        let ocr = PersistentPythonSidecarOCR(
            pythonExecutablePath: executable.path,
            sidecarPath: "/tmp/sidecar"
        )
        let ready = try await ocr.prewarm()
        let image = CapturedImage(
            id: "fixture://persistent-bridge",
            width: 320,
            height: 120,
            filePath: "/tmp/input.png"
        )

        let document = try await ocr.recognizeText(in: image)

        XCTAssertEqual(ready.initElapsedMs, 1.5)
        XCTAssertEqual(document.normalizedText, "OCR 테스트\nHello 123")
        XCTAssertEqual(document.lines.map(\.score), [0.97, 0.95])
        XCTAssertEqual(document.diagnostics["preprocess_elapsed_ms"], 3)
        XCTAssertEqual(document.metadata["preprocess_status"], "applied")
    }

    func testPersistentPythonSidecarOCRReportsWorkerError() async throws {
        let executable = try makeExecutableScript(
            name: "fake-worker-error",
            body: """
            #!/bin/sh
            printf '%s\\n' '{"event":"ready","ok":true,"init_elapsed_ms":1}'
            while IFS= read -r line; do
              printf '%s\\n' '{"ok":false,"error":"model unavailable"}'
            done
            """
        )
        let ocr = PersistentPythonSidecarOCR(
            pythonExecutablePath: executable.path,
            sidecarPath: "/tmp/sidecar"
        )
        let image = CapturedImage(
            id: "fixture://persistent-bridge-error",
            width: 320,
            height: 120,
            filePath: "/tmp/input.png"
        )

        do {
            _ = try await ocr.recognizeText(in: image)
            XCTFail("Expected persistent worker failure")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("model unavailable"))
        }
    }

    func testDebugArtifactWriterSavesImageTextAndManifestAsPair() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("screen-ocr-debug-tests-\(UUID().uuidString)", isDirectory: true)
        let sourceImageURL = directory.appendingPathComponent("captures/screen-ocr-debug-source.png")
        try FileManager.default.createDirectory(
            at: sourceImageURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let imageData = Data([0x89, 0x50, 0x4E, 0x47])
        try imageData.write(to: sourceImageURL)

        let report = ScreenOCRRunReport(
            status: .copiedText,
            capturedImageID: "screen://1/1234",
            capturedImagePath: sourceImageURL.path,
            recognizedText: "OCR 테스트\nHello 123",
            lineCount: 2,
            errorMessage: nil,
            timings: ScreenOCRStageTimings(
                captureElapsedMs: 11,
                ocrElapsedMs: 22,
                clipboardElapsedMs: 3,
                totalElapsedMs: 36
            ),
            ocrDiagnostics: [
                "preprocess_elapsed_ms": 4,
                "preprocess_applied": 1
            ],
            ocrMetadata: [
                "preprocess_status": "applied"
            ]
        )
        let outputDirectory = directory.appendingPathComponent("debug-runs", isDirectory: true)
        let pair = try OCRDebugArtifactWriter(outputDirectory: outputDirectory)
            .savePair(from: report, createdAt: Date(timeIntervalSince1970: 0))

        XCTAssertEqual(pair.runID, "screen-ocr-debug-source")
        XCTAssertTrue(FileManager.default.fileExists(atPath: pair.imagePath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: pair.textPath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: pair.manifestPath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: pair.latestManifestPath))
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: pair.imagePath)), imageData)
        XCTAssertEqual(try String(contentsOf: URL(fileURLWithPath: pair.textPath), encoding: .utf8), "OCR 테스트\nHello 123")

        let manifest = try JSONSerialization.jsonObject(
            with: Data(contentsOf: URL(fileURLWithPath: pair.manifestPath))
        ) as? [String: Any]
        XCTAssertEqual(manifest?["run_id"] as? String, "screen-ocr-debug-source")
        XCTAssertEqual(manifest?["status"] as? String, "copied_text")
        XCTAssertEqual(manifest?["debug_image_path"] as? String, pair.imagePath)
        XCTAssertEqual(manifest?["debug_text_path"] as? String, pair.textPath)
        let timings = manifest?["timings"] as? [String: Any]
        XCTAssertEqual(timings?["capture_elapsed_ms"] as? Int, 11)
        XCTAssertEqual(timings?["ocr_elapsed_ms"] as? Int, 22)
        XCTAssertEqual(timings?["clipboard_elapsed_ms"] as? Int, 3)
        XCTAssertEqual(timings?["total_elapsed_ms"] as? Int, 36)
        let ocrDiagnostics = manifest?["ocr_diagnostics"] as? [String: Any]
        XCTAssertEqual(ocrDiagnostics?["preprocess_elapsed_ms"] as? Int, 4)
        XCTAssertEqual(ocrDiagnostics?["preprocess_applied"] as? Int, 1)
        let ocrMetadata = manifest?["ocr_metadata"] as? [String: Any]
        XCTAssertEqual(ocrMetadata?["preprocess_status"] as? String, "applied")
    }
}

private struct FakeCapture: ImageCapturing {
    let image: CapturedImage

    func captureRegion() async throws -> CapturedImage {
        image
    }
}

private struct FailingCapture: ImageCapturing {
    let error: Error

    func captureRegion() async throws -> CapturedImage {
        throw error
    }
}

private struct FakeOCR: OCRRecognizing {
    let result: OCRDocument

    func recognizeText(in image: CapturedImage) async throws -> OCRDocument {
        result
    }
}

private struct FailingOCR: OCRRecognizing {
    let error: Error

    func recognizeText(in image: CapturedImage) async throws -> OCRDocument {
        throw error
    }
}

private final class FakeClipboard: ClipboardWriting {
    private(set) var text: String?

    func writeText(_ text: String) throws {
        self.text = text
    }
}

private final class FailingClipboard: ClipboardWriting {
    let error: Error

    init(error: Error) {
        self.error = error
    }

    func writeText(_ text: String) throws {
        throw error
    }
}

private enum TestError: Error, LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let message):
            return message
        }
    }
}

private func makeExecutableScript(name: String, body: String) throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("screen-ocr-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent(name)
    try body.write(to: url, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    return url
}
