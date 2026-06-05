import AppKit
import Carbon.HIToolbox
import CoreGraphics
import Foundation
import ScreenOCRCore

@MainActor
final class ScreenOCRApp: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var statusMenuItem: NSMenuItem?
    private var hotKeyRef: EventHotKeyRef?
    private var hotKeyEventHandler: EventHandlerRef?
    private var lastScreenRecordingAlertDate: Date?
    private let selectionOverlay = SelectionOverlayController()
    private var persistentOCR: PersistentPythonSidecarOCR?
    private let copyToastPresenter = CopyToastPresenter()

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureStatusItem()
        registerHotKey()
        prewarmOCRWorkerAtLaunch()
        if ProcessInfo.processInfo.environment["SCREEN_OCR_RUN_FIXTURE_ON_LAUNCH"] == "1" {
            Task {
                await runFixtureOCRFlow()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let hotKeyEventHandler {
            RemoveEventHandler(hotKeyEventHandler)
        }
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "OCR"

        let menu = NSMenu()
        let status = NSMenuItem(title: "Starting...", action: nil, keyEquivalent: "")
        status.isEnabled = false
        statusMenuItem = status
        menu.addItem(status)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(makeMenuItem(title: "Capture OCR", action: #selector(runScreenOCR)))
        menu.addItem(makeMenuItem(title: "OCR Fixture", action: #selector(runFixtureOCR)))
        menu.addItem(makeMenuItem(title: "Open Screen Recording Settings", action: #selector(openScreenRecordingSettings)))
        menu.addItem(makeMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))

        item.menu = menu
        statusItem = item
        updateStatus("Ready")
    }

    private func makeMenuItem(title: String, action: Selector, keyEquivalent: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        return item
    }

    private func registerHotKey() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else {
                    return noErr
                }
                let app = Unmanaged<ScreenOCRApp>.fromOpaque(userData).takeUnretainedValue()
                Task { @MainActor in
                    app.handleHotKey()
                }
                return noErr
            },
            1,
            &eventType,
            selfPointer,
            &hotKeyEventHandler
        )

        guard installStatus == noErr else {
            updateStatus("Hotkey handler unavailable: \(installStatus)")
            writeAppStatus(
                status: "hotkey_handler_unavailable",
                details: ["install_status": "\(installStatus)"]
            )
            return
        }

        let hotKeyID = EventHotKeyID(signature: OSType(0x534F4352), id: 1)
        let registerStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_0),
            UInt32(cmdKey | shiftKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if registerStatus == noErr {
            updateStatus("Ready - Cmd+Shift+0")
            writeAppStatus(status: "hotkey_registered", details: ["shortcut": "Cmd+Shift+0"])
        } else {
            updateStatus("Cmd+Shift+0 unavailable: \(registerStatus)")
            writeAppStatus(
                status: "hotkey_unavailable",
                details: ["register_status": "\(registerStatus)", "shortcut": "Cmd+Shift+0"]
            )
        }
    }

    private func handleHotKey() {
        Task {
            await runScreenOCRFromHotKey()
        }
    }

    @objc private func runScreenOCR() {
        Task {
            await runScreenOCRFromHotKey()
        }
    }

    @objc private func runFixtureOCR() {
        Task {
            await runFixtureOCRFlow()
        }
    }

    private func runScreenOCRFromHotKey() async {
        do {
            writeAppStatus(
                status: "capture_hotkey_received",
                details: ["shortcut": "Cmd+Shift+0"]
            )
            updateStatus("Capture requested")

            guard ensureScreenCapturePermission() else {
                return
            }

            updateStatus("Select a region...")
            let paths = runtimePaths()
            let ocr = ocrRecognizer(paths: paths)

            let pipeline = ScreenOCRPipeline(
                capture: ScreenCaptureKitImageCapture(
                    outputDirectory: paths.captureOutputDirectory,
                    selectRegion: { [self] in
                        try await self.selectionOverlay.selectRegion()
                    }
                ),
                ocr: ocr,
                clipboard: PasteboardClipboard()
            )

            let report = try await pipeline.run()
            let debugResult = saveDebugArtifacts(for: report, paths: paths)

            switch report.status {
            case .copiedText:
                updateStatus("Copied \(report.lineCount) OCR lines")
                showCopiedToast()
            case .failed(let stage):
                updateStatus("OCR \(stage.diagnosticValue) failed")
            }

            var details: [String: String] = [
                "run_status": report.status.diagnosticValue,
                "line_count": "\(report.lineCount)",
                "captured_image_id": report.capturedImageID
            ]
            if let capturedImagePath = report.capturedImagePath {
                details["captured_image_path"] = capturedImagePath
            }
            if let errorMessage = report.errorMessage {
                details["error_message"] = errorMessage
            }
            if let timings = report.timings {
                details.merge(timings.diagnosticStringPayload) { _, new in new }
            }
            details.merge(report.ocrDiagnostics.mapValues(String.init)) { _, new in new }
            details.merge(report.ocrMetadata) { _, new in new }
            if let debugPair = debugResult.pair {
                details["debug_image_path"] = debugPair.imagePath
                details["debug_text_path"] = debugPair.textPath
                details["debug_manifest_path"] = debugPair.manifestPath
                details["debug_latest_manifest_path"] = debugPair.latestManifestPath
            }
            if let debugError = debugResult.errorMessage {
                details["debug_artifact_error"] = debugError
            }

            writeAppStatus(
                status: report.status == .copiedText ? "capture_ocr_finished" : "capture_ocr_failed",
                details: details
            )
        } catch {
            updateStatus("OCR failed: \(error.localizedDescription)")
            writeAppStatus(status: "capture_ocr_error", details: ["error": error.localizedDescription])
        }
    }

    private func runFixtureOCRFlow() async {
        do {
            updateStatus("Running fixture OCR...")
            let paths = runtimePaths()
            let ocr = ocrRecognizer(paths: paths)

            let pipeline = ScreenOCRPipeline(
                capture: StaticImageCapture(
                    image: CapturedImage(
                        id: "fixture://mixed-ko-en-simple",
                        width: 640,
                        height: 220,
                        filePath: paths.fixtureImage.path
                    )
                ),
                ocr: ocr,
                clipboard: PasteboardClipboard()
            )

            let report = try await pipeline.run()
            updateStatus("Copied \(report.lineCount) fixture OCR lines")
            if report.status == .copiedText {
                showCopiedToast()
            }
            writeAppStatus(
                status: "fixture_ocr_finished",
                details: [
                    "run_status": "\(report.status)",
                    "line_count": "\(report.lineCount)"
                ].merging(report.timings?.diagnosticStringPayload ?? [:]) { _, new in new }
                    .merging(report.ocrDiagnostics.mapValues(String.init)) { _, new in new }
                    .merging(report.ocrMetadata) { _, new in new }
            )
        } catch {
            updateStatus("Fixture OCR failed: \(error.localizedDescription)")
            writeAppStatus(status: "fixture_ocr_error", details: ["error": error.localizedDescription])
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    @objc private func openScreenRecordingSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ScreenCapture"
        ]
        for rawURL in urls {
            guard let url = URL(string: rawURL) else {
                continue
            }
            if NSWorkspace.shared.open(url) {
                return
            }
        }
    }

    private func updateStatus(_ text: String) {
        statusMenuItem?.title = text
    }

    private func showCopiedToast() {
        guard let button = statusItem?.button,
              let window = button.window,
              let screen = window.screen ?? NSScreen.main else {
            copyToastPresenter.show(message: ClipboardCopyToast.message, anchorFrame: nil, visibleFrame: nil)
            return
        }

        let anchorFrame = button.convert(button.bounds, to: nil)
        let screenAnchorFrame = window.convertToScreen(anchorFrame)
        copyToastPresenter.show(
            message: ClipboardCopyToast.message,
            anchorFrame: screenAnchorFrame,
            visibleFrame: screen.visibleFrame
        )
    }

    private func saveDebugArtifacts(
        for report: ScreenOCRRunReport,
        paths: AppRuntimePaths
    ) -> (pair: OCRDebugArtifactPair?, errorMessage: String?) {
        guard report.capturedImagePath != nil else {
            return (nil, nil)
        }

        do {
            let pair = try OCRDebugArtifactWriter(outputDirectory: paths.debugOutputDirectory)
                .savePair(from: report)
            return (pair, nil)
        } catch {
            return (nil, error.localizedDescription)
        }
    }

    private func runtimePaths() -> AppRuntimePaths {
        let resourceRoot = Bundle.main.resourceURL
        if let resourceRoot {
            let bundledPython = resourceRoot.appendingPathComponent("python-runtime/bin/python")
            let bundledSidecar = resourceRoot.appendingPathComponent("sidecar")
            let bundledFixture = resourceRoot.appendingPathComponent("fixtures/ocr/mixed-ko-en-simple.png")
            if FileManager.default.isExecutableFile(atPath: bundledPython.path),
               FileManager.default.fileExists(atPath: bundledSidecar.appendingPathComponent("screen_ocr_sidecar").path) {
                return AppRuntimePaths(
                    pythonExecutable: bundledPython,
                    sidecarDirectory: bundledSidecar,
                    fixtureImage: bundledFixture,
                    artifactsRoot: artifactsRootURL()
                )
            }
        }

        let root = projectRootURL()
        return AppRuntimePaths(
            pythonExecutable: root.appendingPathComponent(".venv-ocr/bin/python"),
            sidecarDirectory: root.appendingPathComponent("sidecar"),
            fixtureImage: root.appendingPathComponent("fixtures/ocr/mixed-ko-en-simple.png"),
            artifactsRoot: artifactsRootURL(projectRoot: root)
        )
    }

    private func projectRootURL() -> URL {
        if let path = ProcessInfo.processInfo.environment["SCREEN_OCR_PROJECT_ROOT"],
           !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }

        if let resourceURL = Bundle.main.resourceURL?.appendingPathComponent("project-root.txt"),
           let contents = try? String(contentsOf: resourceURL, encoding: .utf8) {
            let path = contents.trimmingCharacters(in: .whitespacesAndNewlines)
            if !path.isEmpty {
                return URL(fileURLWithPath: path, isDirectory: true)
            }
        }

        let currentDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        if FileManager.default.fileExists(atPath: currentDirectory.appendingPathComponent("Package.swift").path),
           FileManager.default.fileExists(atPath: currentDirectory.appendingPathComponent("sidecar/screen_ocr_sidecar").path) {
            return currentDirectory
        }

        return applicationSupportURL()
    }

    private func artifactsRootURL(projectRoot: URL? = nil) -> URL {
        if let path = ProcessInfo.processInfo.environment["SCREEN_OCR_ARTIFACT_ROOT"],
           !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }

        if let projectRoot {
            return projectRoot.appendingPathComponent("artifacts", isDirectory: true)
        }

        if let explicitProjectRoot = explicitProjectRootURL() {
            return explicitProjectRoot.appendingPathComponent("artifacts", isDirectory: true)
        }

        return applicationSupportURL().appendingPathComponent("artifacts", isDirectory: true)
    }

    private func explicitProjectRootURL() -> URL? {
        if let path = ProcessInfo.processInfo.environment["SCREEN_OCR_PROJECT_ROOT"],
           !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }

        if let resourceURL = Bundle.main.resourceURL?.appendingPathComponent("project-root.txt"),
           let contents = try? String(contentsOf: resourceURL, encoding: .utf8) {
            let path = contents.trimmingCharacters(in: .whitespacesAndNewlines)
            if !path.isEmpty {
                return URL(fileURLWithPath: path, isDirectory: true)
            }
        }

        return nil
    }

    private func applicationSupportURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return base.appendingPathComponent("Screen OCR", isDirectory: true)
    }

    private func ensureScreenCapturePermission() -> Bool {
        if CGPreflightScreenCaptureAccess() {
            return true
        }

        updateStatus("Screen Recording permission required")
        writeAppStatus(status: "screen_recording_permission_required", details: screenRecordingPermissionDetails())
        if CGRequestScreenCaptureAccess() {
            updateStatus("Screen Recording granted; try capture again")
            writeAppStatus(status: "screen_recording_permission_granted", details: screenRecordingPermissionDetails())
        } else {
            updateStatus("Enable Screen Recording in System Settings")
            writeAppStatus(status: "screen_recording_permission_denied", details: screenRecordingPermissionDetails())
            showScreenRecordingPermissionAlert()
        }

        return false
    }

    private func showScreenRecordingPermissionAlert() {
        let now = Date()
        if let lastScreenRecordingAlertDate,
           now.timeIntervalSince(lastScreenRecordingAlertDate) < 3 {
            return
        }
        lastScreenRecordingAlertDate = now

        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "Screen Recording permission is required"
        alert.informativeText = """
        Enable Screen OCR in System Settings > Privacy & Security > Screen Recording, then quit and reopen the app.
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "OK")

        if alert.runModal() == .alertFirstButtonReturn {
            openScreenRecordingSettings()
        }
    }

    private func screenRecordingPermissionDetails() -> [String: String] {
        [
            "app_path": Bundle.main.bundlePath,
            "bundle_identifier": Bundle.main.bundleIdentifier ?? "",
            "settings_hint": "System Settings > Privacy & Security > Screen Recording > Screen OCR"
        ]
    }

    private func writeAppStatus(status: String, details: [String: String]) {
        do {
            let url = runtimePaths().artifactsRoot.appendingPathComponent("app/latest-status.json")
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            var payload: [String: Any] = [
                "created_at": ISO8601DateFormatter().string(from: Date()),
                "status": status
            ]
            for (key, value) in details {
                payload[key] = value
            }
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: url)
        } catch {
            // Diagnostics must never break the user-facing OCR flow.
        }
    }

    private func prewarmOCRWorkerAtLaunch() {
        let paths = runtimePaths()
        let ocr = ocrRecognizer(paths: paths)
        updateStatus("Warming OCR...")
        writeWorkerStatus(status: "warming", details: ["shortcut": "Cmd+Shift+0"], paths: paths)

        Task {
            let started = Date()
            do {
                let ready = try await ocr.prewarm()
                let readyElapsedMs = appElapsedMilliseconds(since: started)
                let processID = await ocr.workerProcessIdentifier()
                var details: [String: String] = [
                    "ready_elapsed_ms": "\(readyElapsedMs)",
                    "worker_init_elapsed_ms": String(format: "%.3f", ready.initElapsedMs)
                ]
                if let processID {
                    details["worker_pid"] = "\(processID)"
                    if let rssMegabytes = residentMemoryMegabytes(processID: processID) {
                        details["worker_rss_mb"] = String(format: "%.1f", rssMegabytes)
                    }
                }

                updateStatus("Ready - Cmd+Shift+0")
                writeWorkerStatus(status: "ready", details: details, paths: paths)
            } catch {
                updateStatus("OCR worker failed")
                writeWorkerStatus(
                    status: "failed",
                    details: ["error": error.localizedDescription],
                    paths: paths
                )
            }
        }
    }

    private func ocrRecognizer(paths: AppRuntimePaths) -> PersistentPythonSidecarOCR {
        if let persistentOCR {
            return persistentOCR
        }

        let ocr = PersistentPythonSidecarOCR(
            pythonExecutablePath: paths.pythonExecutable.path,
            sidecarPath: paths.sidecarDirectory.path
        )
        persistentOCR = ocr
        return ocr
    }

    private func writeWorkerStatus(
        status: String,
        details: [String: String],
        paths: AppRuntimePaths
    ) {
        do {
            let url = paths.artifactsRoot.appendingPathComponent("app/latest-worker-status.json")
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            var payload: [String: Any] = [
                "created_at": ISO8601DateFormatter().string(from: Date()),
                "status": status
            ]
            for (key, value) in details {
                payload[key] = value
            }
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: url)
        } catch {
            // Diagnostics must never break the user-facing OCR flow.
        }
    }

    private func residentMemoryMegabytes(processID: Int32) -> Double? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-o", "rss=", "-p", "\(processID)"]

        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else {
            return nil
        }

        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let text, let rssKilobytes = Double(text) else {
            return nil
        }

        return rssKilobytes / 1024
    }
}

private struct AppRuntimePaths {
    let pythonExecutable: URL
    let sidecarDirectory: URL
    let fixtureImage: URL
    let artifactsRoot: URL

    var captureOutputDirectory: URL {
        artifactsRoot.appendingPathComponent("captures", isDirectory: true)
    }

    var debugOutputDirectory: URL {
        artifactsRoot.appendingPathComponent("debug-runs", isDirectory: true)
    }
}

let app = NSApplication.shared
let delegate = ScreenOCRApp()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()

private struct StaticImageCapture: ImageCapturing {
    let image: CapturedImage

    func captureRegion() async throws -> CapturedImage {
        image
    }
}

private final class PasteboardClipboard: ClipboardWriting {
    func writeText(_ text: String) throws {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

@MainActor
private final class CopyToastPresenter {
    private var window: NSWindow?
    private var closeTask: Task<Void, Never>?
    private let preferredSize = CGSize(width: 210, height: 44)

    func show(message: String, anchorFrame: CGRect?, visibleFrame: CGRect?) {
        closeTask?.cancel()

        let visibleFrame = visibleFrame ?? NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 320, height: 240)
        let frame: CGRect
        if let anchorFrame {
            frame = ClipboardCopyToast.frame(
                below: anchorFrame,
                preferredSize: preferredSize,
                visibleFrame: visibleFrame
            )
        } else {
            frame = CGRect(
                x: visibleFrame.maxX - preferredSize.width - 12,
                y: visibleFrame.maxY - preferredSize.height - 12,
                width: preferredSize.width,
                height: preferredSize.height
            )
        }

        let toastWindow = window ?? makeWindow()
        toastWindow.contentView = ToastView(message: message)
        toastWindow.setFrame(frame, display: true)
        toastWindow.alphaValue = 1
        toastWindow.orderFrontRegardless()
        window = toastWindow

        closeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            await MainActor.run {
                self?.window?.orderOut(nil)
            }
        }
    }

    private func makeWindow() -> NSWindow {
        let window = NSPanel(
            contentRect: CGRect(origin: .zero, size: preferredSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        window.ignoresMouseEvents = true
        return window
    }
}

private final class ToastView: NSView {
    private let message: String

    init(message: String) {
        self.message = message
        super.init(frame: CGRect(origin: .zero, size: CGSize(width: 210, height: 44)))
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.96).cgColor
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.5).cgColor
        layer?.borderWidth = 1
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.lineBreakMode = .byTruncatingTail

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraphStyle
        ]
        let rect = bounds.insetBy(dx: 12, dy: 13)
        message.draw(in: rect, withAttributes: attributes)
    }
}

private extension ScreenOCRStageTimings {
    var diagnosticStringPayload: [String: String] {
        diagnosticPayload.mapValues(String.init)
    }
}

private func appElapsedMilliseconds(since started: Date) -> Int {
    max(0, Int((Date().timeIntervalSince(started) * 1000).rounded()))
}
