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

    // Serial OCR queue: region selection runs immediately per hotkey, but the captured images
    // are processed one at a time so they never collide on the shared worker pipe. The batch
    // counter drives the live "n/m" toast.
    private var ocrJobQueue: [OCRJob] = []
    private var isDrainingQueue = false
    private var batchProgress = OCRBatchProgress()
    private var progressTimerTask: Task<Void, Never>?
    private var activeJobStartedAt: Date?
    private var progressToastShown = false

    private struct OCRJob {
        let image: CapturedImage
        let paths: AppRuntimePaths
        let isFixture: Bool
    }

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
        let capture = ScreenCaptureKitImageCapture(
            outputDirectory: paths.captureOutputDirectory,
            selectRegion: { [self] in
                try await self.selectionOverlay.selectRegion()
            }
        )

        // Capture (region selection + screenshot) happens immediately so the user can keep
        // selecting more regions; only the OCR stage is queued.
        do {
            let image = try await capture.captureRegion()
            enqueueOCRJob(OCRJob(image: image, paths: paths, isFixture: false))
        } catch {
            updateStatus("Capture failed: \(error.localizedDescription)")
            writeAppStatus(status: "capture_failed", details: ["error": error.localizedDescription])
        }
    }

    private func runFixtureOCRFlow() async {
        let paths = runtimePaths()
        let image = CapturedImage(
            id: "fixture://mixed-ko-en-simple",
            width: 640,
            height: 220,
            filePath: paths.fixtureImage.path
        )
        enqueueOCRJob(OCRJob(image: image, paths: paths, isFixture: true))
    }

    // MARK: - Serial OCR queue

    private func enqueueOCRJob(_ job: OCRJob) {
        batchProgress.enqueue()
        ocrJobQueue.append(job)
        updateStatus("Queued OCR (\(batchProgress.currentIndex)/\(batchProgress.total))")
        if !isDrainingQueue {
            Task { await drainQueue() }
        }
    }

    private func drainQueue() async {
        isDrainingQueue = true
        while !ocrJobQueue.isEmpty {
            let job = ocrJobQueue.removeFirst()
            await processOCRJob(job)
            batchProgress.complete()
        }
        isDrainingQueue = false
        stopProgressTimer()
        activeJobStartedAt = nil
    }

    private func processOCRJob(_ job: OCRJob) async {
        let started = Date()
        activeJobStartedAt = started
        startProgressTimer()

        let pipeline = ScreenOCRPipeline(
            capture: StaticImageCapture(image: job.image),
            ocr: ocrRecognizer(paths: job.paths),
            clipboard: PasteboardClipboard()
        )

        do {
            let report = try await pipeline.run()
            stopProgressTimer()
            let elapsed = Date().timeIntervalSince(started)
            let debugResult = saveDebugArtifacts(for: report, paths: job.paths)
            finishOCRJob(report: report, job: job, elapsed: elapsed, debugResult: debugResult)
        } catch {
            stopProgressTimer()
            updateStatus("OCR failed: \(error.localizedDescription)")
            showTerminalToast(OCRProgressToast.failed(reason: error.localizedDescription))
            writeAppStatus(
                status: job.isFixture ? "fixture_ocr_error" : "capture_ocr_error",
                details: ["error": error.localizedDescription]
            )
        }
    }

    private func finishOCRJob(
        report: ScreenOCRRunReport,
        job: OCRJob,
        elapsed: TimeInterval,
        debugResult: (pair: OCRDebugArtifactPair?, errorMessage: String?)
    ) {
        switch report.status {
        case .copiedText:
            // "완료" is only declared once the clipboard write actually succeeded (.copiedText).
            updateStatus("Copied \(report.lineCount) OCR lines")
            showTerminalToast(
                OCRProgressToast.copied(
                    index: batchProgress.currentIndex,
                    total: batchProgress.total,
                    elapsed: elapsed
                )
            )
        case .failed(let stage):
            updateStatus("OCR \(stage.diagnosticValue) failed")
            showTerminalToast(OCRProgressToast.failed(reason: stage.diagnosticValue))
        }

        var details: [String: String] = [
            "run_status": report.status.diagnosticValue,
            "line_count": "\(report.lineCount)",
            "captured_image_id": report.capturedImageID,
            "queue_index": "\(batchProgress.currentIndex)",
            "queue_total": "\(batchProgress.total)",
            "processing_elapsed_ms": "\(Int((elapsed * 1000).rounded()))"
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

        let statusKey: String
        if job.isFixture {
            statusKey = report.status == .copiedText ? "fixture_ocr_finished" : "fixture_ocr_failed"
        } else {
            statusKey = report.status == .copiedText ? "capture_ocr_finished" : "capture_ocr_failed"
        }
        writeAppStatus(status: statusKey, details: details)
    }

    // MARK: - Live progress toast

    private func startProgressTimer() {
        progressTimerTask?.cancel()
        let anchor = toastAnchor()
        renderProgressToast(anchor: anchor)
        progressTimerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 100_000_000)
                if Task.isCancelled { break }
                await MainActor.run {
                    self?.renderProgressToast(anchor: anchor)
                }
            }
        }
    }

    private func stopProgressTimer() {
        progressTimerTask?.cancel()
        progressTimerTask = nil
    }

    private func renderProgressToast(anchor: (anchorFrame: CGRect?, visibleFrame: CGRect?)) {
        let elapsed = activeJobStartedAt.map { Date().timeIntervalSince($0) } ?? 0
        let message = OCRProgressToast.processing(
            index: batchProgress.currentIndex,
            total: batchProgress.total,
            elapsed: elapsed
        )
        if progressToastShown {
            copyToastPresenter.update(message: message)
        } else {
            copyToastPresenter.showSticky(
                message: message,
                anchorFrame: anchor.anchorFrame,
                visibleFrame: anchor.visibleFrame
            )
            progressToastShown = true
        }
    }

    private func showTerminalToast(_ message: String) {
        let anchor = toastAnchor()
        copyToastPresenter.show(
            message: message,
            anchorFrame: anchor.anchorFrame,
            visibleFrame: anchor.visibleFrame
        )
        progressToastShown = false
    }

    private func toastAnchor() -> (anchorFrame: CGRect?, visibleFrame: CGRect?) {
        guard let button = statusItem?.button,
              let window = button.window,
              let screen = window.screen ?? NSScreen.main else {
            return (nil, nil)
        }
        let anchorFrame = button.convert(button.bounds, to: nil)
        return (window.convertToScreen(anchorFrame), screen.visibleFrame)
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
        if let configured = configuredProjectRootURL() {
            return configured
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
        configuredProjectRootURL()
    }

    private func configuredProjectRootURL() -> URL? {
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
        let url = runtimePaths().artifactsRoot.appendingPathComponent("app/latest-status.json")
        writeStatusJSON(to: url, status: status, details: details)
    }

    private func writeStatusJSON(to url: URL, status: String, details: [String: String]) {
        do {
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
                let readyElapsedMs = elapsedMilliseconds(since: started)
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
        let url = paths.artifactsRoot.appendingPathComponent("app/latest-worker-status.json")
        writeStatusJSON(to: url, status: status, details: details)
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

@MainActor
private final class CopyToastPresenter {
    private var window: NSWindow?
    private var closeTask: Task<Void, Never>?
    private let preferredSize = CGSize(width: 240, height: 44)

    /// Shows a toast that dismisses itself after a short delay. Used for terminal states
    /// (copy complete / failure).
    func show(message: String, anchorFrame: CGRect?, visibleFrame: CGRect?) {
        present(message: message, anchorFrame: anchorFrame, visibleFrame: visibleFrame)
        closeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            await MainActor.run {
                self?.window?.orderOut(nil)
            }
        }
    }

    /// Shows a toast that stays on screen until explicitly updated or dismissed. Used for the
    /// live "처리 중 n/m · 0.x초" indicator while the OCR queue drains.
    func showSticky(message: String, anchorFrame: CGRect?, visibleFrame: CGRect?) {
        present(message: message, anchorFrame: anchorFrame, visibleFrame: visibleFrame)
    }

    /// Replaces the text of the currently visible toast in place (cheap; no reframing).
    func update(message: String) {
        guard let window else { return }
        window.contentView = ToastView(message: message)
        window.orderFrontRegardless()
    }

    func dismiss() {
        closeTask?.cancel()
        window?.orderOut(nil)
    }

    private func present(message: String, anchorFrame: CGRect?, visibleFrame: CGRect?) {
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
        super.init(frame: CGRect(origin: .zero, size: CGSize(width: 240, height: 44)))
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

