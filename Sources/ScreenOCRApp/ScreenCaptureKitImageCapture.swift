import CoreGraphics
import Foundation
import ImageIO
import ScreenCaptureKit
import ScreenOCRCore
import UniformTypeIdentifiers

struct ScreenCaptureKitImageCapture: ImageCapturing {
    let outputDirectory: URL
    let selectRegion: @MainActor () async throws -> ScreenRegionSelection

    func captureRegion() async throws -> CapturedImage {
        let selectionStarted = Date()
        let selection = try await selectRegion()
        let selectionElapsedMs = elapsedMilliseconds(since: selectionStarted)

        let imageCaptureStarted = Date()
        let screenCaptureStarted = Date()
        let image = try await captureImage(for: selection)
        let screenCaptureElapsedMs = elapsedMilliseconds(since: screenCaptureStarted)

        let pngWriteStarted = Date()
        let fileURL = try writeCaptureImage(image)
        let pngWriteElapsedMs = elapsedMilliseconds(since: pngWriteStarted)
        let imageCaptureElapsedMs = elapsedMilliseconds(since: imageCaptureStarted)

        return CapturedImage(
            id: "screen://\(selection.displayID)/\(Int(Date().timeIntervalSince1970 * 1000))",
            width: image.width,
            height: image.height,
            filePath: fileURL.path,
            diagnostics: [
                "selection_elapsed_ms": selectionElapsedMs,
                "screen_capture_elapsed_ms": screenCaptureElapsedMs,
                "png_write_elapsed_ms": pngWriteElapsedMs,
                "image_capture_elapsed_ms": imageCaptureElapsedMs
            ]
        )
    }

    private func captureImage(for selection: ScreenRegionSelection) async throws -> CGImage {
        let forceLegacy = ProcessInfo.processInfo.environment["SCREEN_OCR_FORCE_LEGACY_CAPTURE"] == "1"

        if #available(macOS 15.2, *), !forceLegacy {
            return try await captureDisplayAgnosticImage(for: selection)
        }

        return try await captureDisplayFilteredImage(for: selection)
    }

    @available(macOS 15.2, *)
    private func captureDisplayAgnosticImage(for selection: ScreenRegionSelection) async throws -> CGImage {
        let captureRect = DisplayCoordinateMapper.appKitRectToCaptureGlobalRect(
            selection.rect,
            appKitDisplayFrame: selection.displayFrame,
            captureDisplayBounds: CGDisplayBounds(selection.displayID)
        )

        return try await withCheckedThrowingContinuation { continuation in
            SCScreenshotManager.captureImage(in: captureRect) { image, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let image else {
                    continuation.resume(throwing: ScreenCaptureKitCaptureError.emptyImage)
                    return
                }

                continuation.resume(returning: image)
            }
        }
    }

    private func captureDisplayFilteredImage(for selection: ScreenRegionSelection) async throws -> CGImage {
        return try await withCheckedThrowingContinuation { continuation in
            SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true) { content, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let content else {
                    continuation.resume(throwing: ScreenCaptureKitCaptureError.emptyShareableContent)
                    return
                }

                guard let display = content.displays.first(where: { $0.displayID == selection.displayID }) else {
                    continuation.resume(throwing: ScreenCaptureKitCaptureError.displayNotFound(selection.displayID))
                    return
                }

                let filter = SCContentFilter(display: display, excludingWindows: [])
                let scale = CGFloat(filter.pointPixelScale)
                let sourceRect = DisplayCoordinateMapper.appKitRectToDisplayLocalCaptureRect(
                    selection.rect,
                    appKitDisplayFrame: selection.displayFrame
                )

                let configuration = SCStreamConfiguration()
                configuration.sourceRect = sourceRect
                configuration.width = max(1, Int(sourceRect.width * scale))
                configuration.height = max(1, Int(sourceRect.height * scale))
                configuration.showsCursor = false

                SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration) { image, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }

                    guard let image else {
                        continuation.resume(throwing: ScreenCaptureKitCaptureError.emptyImage)
                        return
                    }

                    continuation.resume(returning: image)
                }
            }
        }
    }

    /// Writes the capture as *uncompressed* TIFF. The file is a lossless transport to the OCR
    /// sidecar, not a user-facing artifact, so encode speed beats size: PNG (zlib) takes ~89ms
    /// for a 2560x1440 capture where uncompressed TIFF takes ~8.5ms, and the sidecar decodes
    /// it ~5x faster as well (PIL 16.7 -> 3.2ms, cv2 25.6 -> 3.6ms). The capture is deleted
    /// after a successful run, and user-saved screenshots are transcoded back to PNG.
    private func writeCaptureImage(_ image: CGImage) throws -> URL {
        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )

        let fileURL = outputDirectory
            .appendingPathComponent("screen-ocr-\(UUID().uuidString)")
            .appendingPathExtension("tiff")

        guard let destination = CGImageDestinationCreateWithURL(
            fileURL as CFURL,
            UTType.tiff.identifier as CFString,
            1,
            nil
        ) else {
            throw ScreenCaptureKitCaptureError.cannotCreateImageDestination
        }

        let properties = [
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFCompression: 1] // 1 = none
        ] as CFDictionary
        CGImageDestinationAddImage(destination, image, properties)
        guard CGImageDestinationFinalize(destination) else {
            throw ScreenCaptureKitCaptureError.cannotWriteImage
        }

        return fileURL
    }
}

enum ScreenCaptureKitCaptureError: Error, LocalizedError {
    case unsupportedOS
    case emptyImage
    case emptyShareableContent
    case displayNotFound(UInt32)
    case cannotCreateImageDestination
    case cannotWriteImage

    var errorDescription: String? {
        switch self {
        case .unsupportedOS:
            return "ScreenCaptureKit region capture requires macOS 15.2 or newer"
        case .emptyImage:
            return "ScreenCaptureKit returned no image"
        case .emptyShareableContent:
            return "ScreenCaptureKit returned no shareable display content"
        case .displayNotFound(let displayID):
            return "ScreenCaptureKit could not find display \(displayID)"
        case .cannotCreateImageDestination:
            return "Could not create PNG destination"
        case .cannotWriteImage:
            return "Could not write captured PNG"
        }
    }
}
