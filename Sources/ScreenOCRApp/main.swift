import AppKit
import Carbon.HIToolbox
import CoreGraphics
import Foundation
import ImageIO
import ScreenOCRCore
import ServiceManagement
import UniformTypeIdentifiers

@MainActor
final class ScreenOCRApp: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var statusMenuItem: NSMenuItem?
    private var hotKeyRef: EventHotKeyRef?
    private var hotKeyEventHandler: EventHandlerRef?
    private let settingsStore = SettingsStore()
    private var settingsWindowController: SettingsWindowController?
    private var retentionTimer: Timer?
    private var lastScreenRecordingAlertDate: Date?
    private let permissionDropPanel = PermissionDropPanelController()
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
    private var progressToastShown = false
    // Step-by-step progress state for the multi-line toast.
    private var stageProgress = OCRStageProgress()
    private var activeStageStartedAt: Date?

    private struct OCRJob {
        let image: CapturedImage
        let paths: AppRuntimePaths
        let isFixture: Bool
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureStatusItem()
        installHotKeyHandler()
        _ = applyHotkey(settingsStore.settings.hotkey)
        syncLaunchAtLoginState()
        startRetentionSweep()
        prewarmOCRWorkerAtLaunch()
        if ProcessInfo.processInfo.environment["SCREEN_OCR_RUN_FIXTURE_ON_LAUNCH"] == "1" {
            Task {
                await runFixtureOCRFlow()
            }
        }
        if ProcessInfo.processInfo.environment["SCREEN_OCR_OPEN_SETTINGS_ON_LAUNCH"] == "1" {
            openSettings()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        retentionTimer?.invalidate()
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let hotKeyEventHandler {
            RemoveEventHandler(hotKeyEventHandler)
        }
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            let icon = Self.makeMenuBarIcon()
            button.image = icon
            button.imagePosition = .imageOnly
            button.toolTip = "Screen OCR"
            if icon == nil {
                button.title = "OCR"
            }
        }

        let menu = NSMenu()
        let status = NSMenuItem(title: "Starting...", action: nil, keyEquivalent: "")
        status.isEnabled = false
        statusMenuItem = status
        menu.addItem(status)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(makeMenuItem(title: "Capture OCR", action: #selector(runScreenOCR)))
        menu.addItem(makeMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(makeMenuItem(title: "Open Screen Recording Settings", action: #selector(openScreenRecordingSettings)))
        menu.addItem(makeMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))

        item.menu = menu
        statusItem = item
        updateStatus("Ready")
    }

    /// Menu bar icon — 심플 07: viewfinder brackets + center dot, rendered as a
    /// template image so it tracks the menu bar's light/dark appearance.
    private static func makeMenuBarIcon() -> NSImage? {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let line: CGFloat = 1.6
            let inset = line / 2
            let arm: CGFloat = 4.5      // bracket arm length
            let lo = inset + 1.0
            let hi = rect.width - inset - 1.0

            let brackets = NSBezierPath()
            brackets.lineWidth = line
            brackets.lineCapStyle = .round
            brackets.lineJoinStyle = .round
            // top-left
            brackets.move(to: NSPoint(x: lo, y: hi - arm)); brackets.line(to: NSPoint(x: lo, y: hi)); brackets.line(to: NSPoint(x: lo + arm, y: hi))
            // top-right
            brackets.move(to: NSPoint(x: hi - arm, y: hi)); brackets.line(to: NSPoint(x: hi, y: hi)); brackets.line(to: NSPoint(x: hi, y: hi - arm))
            // bottom-left
            brackets.move(to: NSPoint(x: lo, y: lo + arm)); brackets.line(to: NSPoint(x: lo, y: lo)); brackets.line(to: NSPoint(x: lo + arm, y: lo))
            // bottom-right
            brackets.move(to: NSPoint(x: hi - arm, y: lo)); brackets.line(to: NSPoint(x: hi, y: lo)); brackets.line(to: NSPoint(x: hi, y: lo + arm))
            NSColor.black.setStroke()
            brackets.stroke()

            // center dot
            let r: CGFloat = 1.9
            let c = NSPoint(x: rect.midX, y: rect.midY)
            let dot = NSBezierPath(ovalIn: NSRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            NSColor.black.setFill()
            dot.fill()
            return true
        }
        image.isTemplate = true
        return image
    }

    private func makeMenuItem(title: String, action: Selector, keyEquivalent: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        return item
    }

    /// Installs the Carbon hotkey event handler once. The actual key combination is registered
    /// separately by `applyHotkey(_:)` so it can change at runtime from the settings window.
    private func installHotKeyHandler() {
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

        if installStatus != noErr {
            updateStatus("Hotkey handler unavailable: \(installStatus)")
            writeAppStatus(
                status: "hotkey_handler_unavailable",
                details: ["install_status": "\(installStatus)"]
            )
        }
    }

    /// Registers `config` as the global capture hotkey, replacing any previously registered combo.
    /// Returns `false` if the OS refused it (e.g. the combination is already claimed elsewhere),
    /// in which case the previous registration has already been torn down — callers that need to
    /// keep the old shortcut should re-apply it.
    @discardableResult
    private func applyHotkey(_ config: HotkeyConfig) -> Bool {
        if let existing = hotKeyRef {
            UnregisterEventHotKey(existing)
            hotKeyRef = nil
        }

        let hotKeyID = EventHotKeyID(signature: OSType(0x534F4352), id: 1)
        let registerStatus = RegisterEventHotKey(
            config.keyCode,
            config.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if registerStatus == noErr {
            updateStatus("Ready - \(config.displayString)")
            writeAppStatus(status: "hotkey_registered", details: ["shortcut": config.displayString])
            return true
        } else {
            hotKeyRef = nil
            updateStatus("\(config.displayString) unavailable: \(registerStatus)")
            writeAppStatus(
                status: "hotkey_unavailable",
                details: ["register_status": "\(registerStatus)", "shortcut": config.displayString]
            )
            return false
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
            details: ["shortcut": settingsStore.settings.hotkey.displayString]
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
        activeStageStartedAt = nil
    }

    private func processOCRJob(_ job: OCRJob) async {
        let started = Date()

        // Seed the stage timeline: screen capture and PNG write already finished during the
        // (immediate) capture step, so show their measured durations; the worker will stream
        // preprocess/recognize, and the clipboard time comes from the final report.
        stageProgress = OCRStageProgress(
            completedMs: [
                .screenCapture: job.image.diagnostics["screen_capture_elapsed_ms"] ?? 0,
                .pngWrite: job.image.diagnostics["png_write_elapsed_ms"] ?? 0
            ],
            active: .preprocess,
            batchIndex: batchProgress.currentIndex,
            batchTotal: batchProgress.total
        )
        activeStageStartedAt = started
        startProgressTimer()

        let ocr = ocrRecognizer(paths: job.paths)
        await ocr.setStageHandler { [weak self] stage in
            Task { @MainActor in
                self?.handleWorkerStage(stage)
            }
        }

        let pipeline = ScreenOCRPipeline(
            capture: StaticImageCapture(image: job.image),
            ocr: ocr,
            clipboard: PasteboardClipboard()
        )

        defer { Task { await ocr.setStageHandler(nil) } }

        do {
            let report = try await pipeline.run()
            stopProgressTimer()
            let elapsed = Date().timeIntervalSince(started)
            let debugResult = saveDebugArtifacts(for: report, paths: job.paths)
            finishOCRJob(report: report, job: job, elapsed: elapsed, debugResult: debugResult)
        } catch {
            stopProgressTimer()
            activeStageStartedAt = nil
            recordOCRFailure(error: error, job: job)
        }
    }

    /// Central error sink: attributes a failure to a pipeline stage, shows a concise toast, and
    /// persists the full detail (app status + an append-only error log + a per-run error
    /// manifest) so any failure is later reproducible from its run id, stage, and traceback.
    private func recordOCRFailure(error: Error, job: OCRJob) {
        let detail = (error as? OCRDiagnosable)?.failureDetail ?? OCRFailureDetail()
        let stage = detail.stage ?? "unknown"
        let label = Self.stageLabel(stage)
        let summary = Self.firstLine(error.localizedDescription)
        let runID = job.image.id

        updateStatus("OCR \(label) 실패: \(summary)")
        showTerminalToast("❌ \(label) 실패 · \(summary)")

        let message = error.localizedDescription
        var details: [String: String] = ["error": message, "stage": stage, "run_id": runID]
        if let imagePath = job.image.filePath {
            details["image_path"] = imagePath
        }
        if detail.traceback != nil {
            details["traceback_captured"] = "1"
        }
        writeAppStatus(
            status: job.isFixture ? "fixture_ocr_error" : "capture_ocr_error",
            details: details
        )

        persistFailure(
            runID: runID,
            stage: stage,
            message: message,
            traceback: detail.traceback,
            imagePath: job.image.filePath,
            paths: job.paths
        )
    }

    /// Korean label for a pipeline stage id. Delegates to OCRStage.label for the stages that map
    /// to an OCRStage case; the rest are worker/app-only stage ids without an OCRStage.
    private static func stageLabel(_ stage: String) -> String {
        if let known = OCRStage(rawValue: stage) {
            return known.label
        }
        switch stage {
        case "capture": return "화면 캡처"
        case "validate": return "입력 검증"
        case "request": return "요청 처리"
        case "worker", "worker_start": return "OCR 워커"
        default: return "OCR"
        }
    }

    private static func firstLine(_ text: String, limit: Int = 120) -> String {
        let line = text.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? text
        return line.count > limit ? String(line.prefix(limit)) + "…" : line
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    /// Persists a failure to both the append-only error history (artifacts/errors.log) and a
    /// per-run error manifest (debug-runs/<run-id>.error.json) under one shared timestamp, so a
    /// failed capture leaves the same kind of reproducible artifact as a good run. Best-effort:
    /// write failures are reported to app status, never thrown.
    private func persistFailure(
        runID: String,
        stage: String,
        message: String,
        traceback: String?,
        imagePath: String?,
        paths: AppRuntimePaths
    ) {
        let timestamp = Self.isoFormatter.string(from: Date())

        var entry = "[\(timestamp)] run=\(runID) stage=\(stage) error=\(Self.firstLine(message, limit: 500))"
        if let imagePath { entry += " image=\(imagePath)" }
        entry += "\n"
        if let traceback, !traceback.isEmpty {
            entry += traceback
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map { "    \($0)" }
                .joined(separator: "\n") + "\n"
        }
        let logURL = paths.artifactsRoot.appendingPathComponent("errors.log")
        do {
            try FileManager.default.createDirectory(
                at: paths.artifactsRoot, withIntermediateDirectories: true
            )
            if let data = entry.data(using: .utf8) {
                if let handle = try? FileHandle(forWritingTo: logURL) {
                    defer { try? handle.close() }
                    try handle.seekToEnd()
                    try handle.write(contentsOf: data)
                } else {
                    try data.write(to: logURL)
                }
            }
        } catch {
            writeAppStatus(status: "error_log_write_failed", details: ["error": error.localizedDescription])
        }

        var manifest: [String: Any] = [
            "run_id": runID,
            "ok": false,
            "stage": stage,
            "error_message": message,
            "created_at": timestamp
        ]
        if let imagePath { manifest["image_path"] = imagePath }
        if let traceback { manifest["traceback"] = traceback }
        let manifestURL = paths.debugOutputDirectory.appendingPathComponent("\(runID).error.json")
        do {
            try FileManager.default.createDirectory(
                at: paths.debugOutputDirectory, withIntermediateDirectories: true
            )
            let data = try JSONSerialization.data(
                withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys]
            )
            try data.write(to: manifestURL)
        } catch {
            writeAppStatus(status: "error_manifest_write_failed", details: ["error": error.localizedDescription])
        }
    }

    /// Advances the stage timeline as the worker streams progress events: freeze the elapsed
    /// time of the stage that just ended and start the clock on the new one.
    private func handleWorkerStage(_ stage: OCRStage) {
        let now = Date()
        if stage == .recognize, let started = activeStageStartedAt, stageProgress.active == .preprocess {
            stageProgress.completedMs[.preprocess] = Int((now.timeIntervalSince(started) * 1000).rounded())
        }
        stageProgress.active = stage
        activeStageStartedAt = now
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
            // Freeze every stage with the authoritative durations from the report and show the
            // completed step-by-step breakdown.
            stageProgress = finalStageProgress(from: report)
            activeStageStartedAt = nil
            updateStatus("Copied \(report.lineCount) OCR lines")
            if debugProgressEnabled {
                // Debug mode: the final per-stage breakdown.
                showStageToast(sticky: false)
            } else {
                // Default: a single-line completion confirmation.
                showTerminalToast(OCRProgressToast.copied(
                    index: batchProgress.currentIndex,
                    total: batchProgress.total,
                    elapsed: elapsed
                ))
            }
            persistUserArtifacts(report: report)
            removeTemporaryCapture(report: report, job: job)
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

    /// Whether the step-by-step progress popup should appear. Off by default; users opt in via the
    /// 디버깅 toggle in settings. When off, only a single-line completion/failure toast is shown.
    private var debugProgressEnabled: Bool {
        settingsStore.settings.showDebugProgress
    }

    private func startProgressTimer() {
        // Without the debug toggle there is no live progress popup — skip the ticking entirely.
        guard debugProgressEnabled else { return }
        progressTimerTask?.cancel()
        showStageToast(sticky: true)
        progressTimerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 100_000_000)
                if Task.isCancelled { break }
                await MainActor.run {
                    self?.showStageToast(sticky: true)
                }
            }
        }
    }

    private func stopProgressTimer() {
        progressTimerTask?.cancel()
        progressTimerTask = nil
    }

    private func finalStageProgress(from report: ScreenOCRRunReport) -> OCRStageProgress {
        let timings = report.timings
        let preprocessMs = report.ocrDiagnostics["preprocess_elapsed_ms"]
            ?? stageProgress.completedMs[.preprocess] ?? 0
        let ocrTotalMs = timings?.ocrElapsedMs ?? 0
        return OCRStageProgress(
            completedMs: [
                .screenCapture: timings?.screenCaptureElapsedMs ?? stageProgress.completedMs[.screenCapture] ?? 0,
                .pngWrite: timings?.pngWriteElapsedMs ?? stageProgress.completedMs[.pngWrite] ?? 0,
                .preprocess: preprocessMs,
                .recognize: max(0, ocrTotalMs - preprocessMs),
                .clipboard: timings?.clipboardElapsedMs ?? 0
            ],
            active: nil,
            batchIndex: batchProgress.currentIndex,
            batchTotal: batchProgress.total
        )
    }

    /// Renders the multi-line step-by-step toast. `sticky` keeps it on screen (live updates);
    /// otherwise it auto-dismisses (terminal/completed state).
    private func showStageToast(sticky: Bool) {
        let activeElapsedMs = activeStageStartedAt
            .map { Int((Date().timeIntervalSince($0) * 1000).rounded()) } ?? 0
        let message = OCRStageToast.render(progress: stageProgress, activeElapsedMs: activeElapsedMs)
        let anchor = toastAnchor()
        if sticky {
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
        } else {
            copyToastPresenter.show(
                message: message,
                anchorFrame: anchor.anchorFrame,
                visibleFrame: anchor.visibleFrame
            )
            progressToastShown = false
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

    @objc private func openSettings() {
        if settingsWindowController == nil {
            let controller = SettingsWindowController(store: settingsStore)
            controller.applyHotkey = { [weak self] candidate in
                self?.applyHotkeyWithRevert(candidate) ?? false
            }
            controller.setHotkeySuspended = { [weak self] suspended in
                self?.setHotkeySuspended(suspended)
            }
            controller.applyLaunchAtLogin = { [weak self] enabled in
                self?.applyLaunchAtLogin(enabled) ?? false
            }
            settingsWindowController = controller
        }
        settingsWindowController?.present()
    }

    /// Suspends the global hotkey while the settings recorder is capturing — otherwise pressing
    /// the currently registered combo fires a capture instead of reaching the recorder. Resuming
    /// re-registers the persisted combo only if nothing else already did: a successful capture
    /// (or a revert) registers its own combo before the resume callback runs.
    private func setHotkeySuspended(_ suspended: Bool) {
        if suspended {
            if let existing = hotKeyRef {
                UnregisterEventHotKey(existing)
                hotKeyRef = nil
            }
        } else if hotKeyRef == nil {
            _ = applyHotkey(settingsStore.settings.hotkey)
        }
    }

    /// Applies a new hotkey, restoring the previously registered combo if the new one is rejected.
    private func applyHotkeyWithRevert(_ candidate: HotkeyConfig) -> Bool {
        let previous = settingsStore.settings.hotkey
        if applyHotkey(candidate) {
            return true
        }
        // Rejected: the candidate registration failed, so put the old shortcut back.
        _ = applyHotkey(previous)
        return false
    }

    // MARK: - Launch at login

    /// Registers/unregisters the app as a login item via SMAppService. Returns `false` (and shows
    /// an alert) if the system call fails — common in unsigned/dev builds — so the settings toggle
    /// can revert.
    private func applyLaunchAtLogin(_ enabled: Bool) -> Bool {
        let service = SMAppService.mainApp
        do {
            if enabled {
                if service.status != .enabled {
                    try service.register()
                }
            } else {
                if service.status == .enabled {
                    try service.unregister()
                }
            }
            writeAppStatus(status: "launch_at_login_updated", details: ["enabled": enabled ? "1" : "0"])
            return true
        } catch {
            let alert = NSAlert()
            alert.messageText = "자동 실행 설정을 변경할 수 없습니다"
            alert.informativeText = "로그인 항목 등록에 실패했습니다. 앱이 서명되어 /Applications 에 설치되어 있어야 합니다.\n\n\(error.localizedDescription)"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "확인")
            alert.runModal()
            writeAppStatus(status: "launch_at_login_failed", details: ["enabled": enabled ? "1" : "0", "error": error.localizedDescription])
            return false
        }
    }

    /// Reconciles the persisted launch-at-login preference with the actual SMAppService state at
    /// launch (the user may have toggled the login item in System Settings while the app was off).
    private func syncLaunchAtLoginState() {
        let actuallyEnabled = (SMAppService.mainApp.status == .enabled)
        if actuallyEnabled != settingsStore.settings.launchAtLogin {
            settingsStore.update { $0.launchAtLogin = actuallyEnabled }
        }
    }

    // MARK: - Retention sweep

    /// Runs an immediate retention sweep at launch, then schedules an hourly sweep so long-running
    /// sessions still clean up files that age past the retention window.
    private func startRetentionSweep() {
        runRetentionSweep()
        retentionTimer?.invalidate()
        let timer = Timer(timeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.runRetentionSweep() }
        }
        RunLoop.main.add(timer, forMode: .common)
        retentionTimer = timer
    }

    /// Deletes saved screenshots/text results older than the configured retention window
    /// (0 disables it), and always prunes the app-internal capture/debug directories after a
    /// fixed day — captures are uncompressed TIFF now, so letting them age would eat disk far
    /// faster than the old PNGs. Best-effort: per-file failures are skipped.
    private func runRetentionSweep() {
        let settings = settingsStore.settings
        var deleted = 0

        if settings.retentionDays > 0 {
            let cutoff = Date().addingTimeInterval(-Double(settings.retentionDays) * 86_400)
            deleted += Self.sweepDirectory(settings.saveDirectoryURL, cutoff: cutoff)
        }

        let internalCutoff = Date().addingTimeInterval(-86_400)
        let paths = runtimePaths()
        deleted += Self.sweepDirectory(paths.captureOutputDirectory, cutoff: internalCutoff)
        deleted += Self.sweepDirectory(paths.debugOutputDirectory, cutoff: internalCutoff)

        if deleted > 0 {
            writeAppStatus(
                status: "retention_sweep",
                details: ["deleted": "\(deleted)", "retention_days": "\(settings.retentionDays)"]
            )
        }
    }

    /// Removes regular files in `directory` modified before `cutoff`; returns how many.
    private static func sweepDirectory(_ directory: URL, cutoff: Date) -> Int {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var deleted = 0
        for url in entries {
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
            guard values?.isRegularFile == true,
                  let modified = values?.contentModificationDate,
                  modified < cutoff else { continue }
            if (try? fm.removeItem(at: url)) != nil {
                deleted += 1
            }
        }
        return deleted
    }

    /// Persists the captured screenshot and/or recognized text into the user's save directory,
    /// gated by the current settings. Best-effort; failures are recorded to app status only.
    private func persistUserArtifacts(report: ScreenOCRRunReport) {
        let settings = settingsStore.settings
        guard settings.saveScreenshots || settings.saveTextResults else { return }
        guard report.status == .copiedText else { return }

        let fm = FileManager.default
        let directory = settings.saveDirectoryURL
        do {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            writeAppStatus(status: "user_save_dir_failed", details: ["error": error.localizedDescription])
            return
        }

        // Shared timestamped basename so a screenshot and its text pair up.
        let stamp = Self.fileStampFormatter.string(from: Date())
        let base = "screen-ocr-\(stamp)"

        if settings.saveScreenshots, let sourcePath = report.capturedImagePath {
            let destination = directory.appendingPathComponent("\(base).png")
            do {
                if fm.fileExists(atPath: destination.path) {
                    try fm.removeItem(at: destination)
                }
                // The capture on disk is uncompressed TIFF (fast OCR transport); the user-facing
                // screenshot stays PNG, so transcode here — this runs after the completion toast,
                // off the latency-critical path, and only when saving is enabled.
                try Self.transcodeToPNG(from: URL(fileURLWithPath: sourcePath), to: destination)
            } catch {
                writeAppStatus(status: "user_save_image_failed", details: ["error": error.localizedDescription])
            }
        }

        if settings.saveTextResults, !report.recognizedText.isEmpty {
            let destination = directory.appendingPathComponent("\(base).txt")
            do {
                try report.recognizedText.write(to: destination, atomically: true, encoding: .utf8)
            } catch {
                writeAppStatus(status: "user_save_text_failed", details: ["error": error.localizedDescription])
            }
        }
    }

    /// Re-encodes any ImageIO-readable file as PNG. The mod date lands at "now", which is also
    /// what the retention sweep should measure (time since saved, not since captured).
    private static func transcodeToPNG(from source: URL, to destination: URL) throws {
        guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil),
              let imageDestination = CGImageDestinationCreateWithURL(
                  destination as CFURL, UTType.png.identifier as CFString, 1, nil
              ) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(imageDestination, image, nil)
        guard CGImageDestinationFinalize(imageDestination) else {
            throw CocoaError(.fileWriteUnknown)
        }
    }

    /// Deletes the temporary capture file once a run has fully succeeded (clipboard written,
    /// user/debug copies done). Captures are uncompressed TIFF, so leaving them to age would
    /// cost ~35x the disk of the old PNGs; failed runs keep their capture so the error manifest
    /// stays reproducible. Only files inside the app's own capture directory are touched —
    /// fixture jobs point at bundled resources.
    private func removeTemporaryCapture(report: ScreenOCRRunReport, job: OCRJob) {
        guard !job.isFixture,
              let capturedImagePath = report.capturedImagePath,
              capturedImagePath.hasPrefix(job.paths.captureOutputDirectory.path)
        else { return }
        try? FileManager.default.removeItem(atPath: capturedImagePath)
    }

    private static let fileStampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        return formatter
    }()

    @objc private func openScreenRecordingSettings() {
        // While the permission is still missing, float the drag-and-drop helper beside the
        // Settings window: dropping the app icon into the permission list registers the app
        // without digging through a file picker.
        if !Self.canCaptureScreen() {
            permissionDropPanel.show()
        }

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
        if Self.canCaptureScreen() {
            return true
        }

        // Deliberately never call CGRequestScreenCaptureAccess: it pops the system's own
        // permission dialog on top of (or instead of) our guided flow, and granting still
        // requires an app relaunch anyway. Our alert leads to System Settings plus the
        // drag-and-drop helper panel, which registers the app without the system prompt.
        updateStatus("Enable Screen Recording in System Settings")
        writeAppStatus(status: "screen_recording_permission_required", details: screenRecordingPermissionDetails())
        showScreenRecordingPermissionAlert()
        return false
    }

    /// True only when this process can *actually* capture. CGPreflightScreenCaptureAccess
    /// looks the app up loosely (bundle id), so after a rebuild of an ad-hoc-signed bundle —
    /// whose TCC grant is keyed to the old code hash — it keeps returning true while the
    /// first ScreenCaptureKit call pops the system permission dialog right past our guided
    /// flow. Creating a throwaway 1x1 CGDisplayStream exercises the real authorization and,
    /// unlike the capture APIs, never prompts.
    static func canCaptureScreen() -> Bool {
        guard CGPreflightScreenCaptureAccess() else {
            return false
        }
        let stream = CGDisplayStream(
            dispatchQueueDisplay: CGMainDisplayID(),
            outputWidth: 1,
            outputHeight: 1,
            pixelFormat: Int32(kCVPixelFormatType_32BGRA),
            properties: nil,
            queue: .main
        ) { _, _, _, _ in }
        return stream != nil
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
                "created_at": Self.isoFormatter.string(from: Date()),
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

    /// Sizes the toast to its content: width hugs the longest row (clamped to a sane range) and
    /// height grows by line count, reserving room for the divider under the total row.
    private func toastSize(for message: String) -> CGSize {
        ToastView.preferredSize(for: message)
    }

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

    /// Replaces the text of the currently visible toast in place, growing/shrinking the window
    /// if the line count changed (e.g. when a stage completes).
    func update(message: String) {
        guard let window else { return }
        let size = toastSize(for: message)
        if abs(window.frame.height - size.height) > 0.5 {
            var frame = window.frame
            // Keep the top edge anchored so the toast grows downward.
            frame.origin.y += frame.height - size.height
            frame.size = size
            window.setFrame(frame, display: true)
        }
        window.contentView = ToastView(message: message)
        window.orderFrontRegardless()
    }

    func dismiss() {
        closeTask?.cancel()
        window?.orderOut(nil)
    }

    private func present(message: String, anchorFrame: CGRect?, visibleFrame: CGRect?) {
        closeTask?.cancel()

        let preferredSize = toastSize(for: message)
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
            contentRect: CGRect(origin: .zero, size: CGSize(width: ToastView.maxWidth, height: 40)),
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
    static let topInset: CGFloat = 8
    static let bottomInset: CGFloat = 8
    static let lineHeight: CGFloat = 17
    static let dividerGap: CGFloat = 8
    static let horizontalInset: CGFloat = 12
    /// Minimum gap between the label column and the right-aligned duration column.
    static let columnGap: CGFloat = 16
    static let minWidth: CGFloat = 150
    static let maxWidth: CGFloat = 240

    static let multilineFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
    static let singleLineFont = NSFont.systemFont(ofSize: 13, weight: .semibold)

    private let message: String
    private var isMultiline: Bool { message.contains("\n") }

    init(message: String) {
        self.message = message
        super.init(frame: CGRect(origin: .zero, size: ToastView.preferredSize(for: message)))
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.96).cgColor
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.5).cgColor
        layer?.borderWidth = 1
    }

    required init?(coder: NSCoder) {
        nil
    }

    // Flip so multi-line layout reads top-to-bottom in the natural order.
    override var isFlipped: Bool { true }

    /// Measures the toast. Single-line toasts hug their text; the multi-line stage toast is sized
    /// to its *final* extent — every stage row plus the total — so the popup stays the same size
    /// while the list fills in one row at a time and when it completes. Width is clamped to
    /// [minWidth, maxWidth].
    static func preferredSize(for message: String) -> CGSize {
        guard message.contains("\n") else {
            let width = textSize(message, font: singleLineFont).width + horizontalInset * 2
            return CGSize(width: clampWidth(width), height: 40)
        }
        return stageToastSize
    }

    /// Fixed size of the step-by-step stage popup: the label column is sized to the widest stage
    /// label, the duration column reserves a worst-case "00.00초", and the height reserves a row
    /// per stage plus the total row — independent of how many rows are currently filled in.
    static let stageToastSize: CGSize = {
        // Left column is "<icon> <label>"; the icon glyphs are all roughly one cell, so measuring
        // against the total row and every stage label with a representative mark covers the max.
        var leftColumns = ["⏳ 전체"]
        leftColumns.append(contentsOf: OCRStage.allCases.map { "✓ \($0.label)" })
        let maxLabel = leftColumns.map { textSize($0, font: multilineFont).width }.max() ?? 0
        let maxSecs = textSize("00.00초", font: multilineFont).width
        let width = clampWidth(horizontalInset * 2 + maxLabel + columnGap + maxSecs)

        let rowCount = OCRStage.allCases.count + 1 // stages + total
        let height = topInset
            + lineHeight                                 // total row
            + dividerGap                                 // divider under total
            + CGFloat(rowCount - 1) * lineHeight
            + bottomInset
        return CGSize(width: width, height: ceil(height))
    }()

    /// Splits a rendered line into its (label, duration) columns at the tab separator.
    private static func columns(of line: String) -> (label: String, secs: String) {
        let parts = line.components(separatedBy: OCRStageToast.columnSeparator)
        return (parts.first ?? line, parts.count > 1 ? parts[1] : "")
    }

    private static func textSize(_ text: String, font: NSFont) -> CGSize {
        (text as NSString).size(withAttributes: [.font: font])
    }

    private static func clampWidth(_ width: CGFloat) -> CGFloat {
        min(maxWidth, max(minWidth, ceil(width)))
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard isMultiline else {
            drawCenteredSingleLine()
            return
        }

        let leftAttributes = attributes(font: Self.multilineFont, alignment: .left)
        let rightAttributes = attributes(font: Self.multilineFont, alignment: .right)

        let rect = CGRect(
            x: Self.horizontalInset,
            y: 0,
            width: bounds.width - Self.horizontalInset * 2,
            height: Self.lineHeight
        )
        var y = Self.topInset
        for (index, line) in message.components(separatedBy: "\n").enumerated() {
            let (label, secs) = Self.columns(of: line)
            var row = rect
            row.origin.y = y
            // Label left-aligned, duration right-aligned over the same row rect — the columns
            // line up exactly without any space padding.
            label.draw(in: row, withAttributes: leftAttributes)
            secs.draw(in: row, withAttributes: rightAttributes)
            y += Self.lineHeight
            // Divider under the total (first) row to set it apart from the stage list.
            if index == 0 {
                let dividerY = y + Self.dividerGap / 2
                NSColor.separatorColor.setFill()
                CGRect(x: Self.horizontalInset, y: dividerY, width: rect.width, height: 1).fill()
                y += Self.dividerGap
            }
        }
    }

    private func drawCenteredSingleLine() {
        let attributes = attributes(font: Self.singleLineFont, alignment: .center)
        message.draw(in: bounds.insetBy(dx: 12, dy: 11), withAttributes: attributes)
    }

    private func attributes(font: NSFont, alignment: NSTextAlignment) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byTruncatingTail
        return [
            .font: font,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph
        ]
    }
}

private extension ScreenOCRStageTimings {
    var diagnosticStringPayload: [String: String] {
        diagnosticPayload.mapValues(String.init)
    }
}

