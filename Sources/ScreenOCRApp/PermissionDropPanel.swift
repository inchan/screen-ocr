import AppKit

/// Floating helper shown next to System Settings when Screen Recording permission is missing:
/// the app icon can be dragged straight into the Settings permission list (the list accepts
/// app-bundle file drops), which beats hunting for the app in a file picker. Codex-style UX.
@MainActor
final class PermissionDropPanelController {
    private var panel: NSPanel?
    private var positioningTask: Task<Void, Never>?

    func show() {
        if let panel {
            panel.makeKeyAndOrderFront(nil)
            return
        }

        let size = CGSize(width: 380, height: 240)
        let panel = NSPanel(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "화면 기록 권한 설정"
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false

        let content = NSView(frame: CGRect(origin: .zero, size: size))

        let iconView = DraggableAppIconView(
            frame: CGRect(x: (size.width - 96) / 2, y: 110, width: 96, height: 96)
        )
        iconView.image = NSApp.applicationIconImage
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.toolTip = "이 아이콘을 시스템 설정 목록으로 드래그"
        content.addSubview(iconView)

        let instruction = NSTextField(wrappingLabelWithString:
            "위 아이콘을 시스템 설정 > 개인정보 보호 및 보안 > 화면 기록 목록으로 드래그해서 추가한 뒤, 아래 버튼으로 앱을 재시작하세요."
        )
        instruction.frame = CGRect(x: 24, y: 52, width: size.width - 48, height: 50)
        instruction.alignment = .center
        instruction.font = .systemFont(ofSize: 12)
        instruction.textColor = .secondaryLabelColor
        content.addSubview(instruction)

        let relaunchButton = NSButton(
            title: "앱 재시작",
            target: self,
            action: #selector(relaunchApp)
        )
        relaunchButton.bezelStyle = .rounded
        relaunchButton.keyEquivalent = "\r"
        relaunchButton.sizeToFit()
        relaunchButton.frame.origin = CGPoint(
            x: (size.width - relaunchButton.frame.width) / 2,
            y: 16
        )
        content.addSubview(relaunchButton)

        panel.contentView = content
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
        snapBesideSystemSettings()
    }

    /// Positions the panel next to the System Settings window: to its right when there is
    /// room, otherwise below it. Settings takes a moment to launch, so poll briefly; window
    /// bounds and owner PIDs are readable without any permission (only titles are gated).
    private func snapBesideSystemSettings() {
        positioningTask?.cancel()
        positioningTask = Task { [weak self] in
            for _ in 0..<12 {
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard let self, let panel = self.panel, panel.isVisible else { return }
                guard let settingsFrame = Self.systemSettingsWindowFrame() else { continue }

                let gap: CGFloat = 16
                let panelSize = panel.frame.size
                let visible = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
                    ?? CGRect(x: 0, y: 0, width: 1440, height: 900)

                // Prefer the right edge, top-aligned; fall back to below, left-aligned.
                var origin = CGPoint(
                    x: settingsFrame.maxX + gap,
                    y: settingsFrame.maxY - panelSize.height
                )
                if origin.x + panelSize.width > visible.maxX {
                    origin = CGPoint(
                        x: settingsFrame.minX,
                        y: settingsFrame.minY - panelSize.height - gap
                    )
                }
                origin.x = min(max(origin.x, visible.minX), visible.maxX - panelSize.width)
                origin.y = min(max(origin.y, visible.minY), visible.maxY - panelSize.height)

                panel.setFrameOrigin(origin)
                return
            }
        }
    }

    /// Frame of the main System Settings window in AppKit (bottom-left origin) coordinates,
    /// or nil while it has not appeared yet.
    private static func systemSettingsWindowFrame() -> CGRect? {
        guard let settings = NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.apple.systempreferences").first
        else { return nil }

        guard let entries = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { return nil }

        for entry in entries {
            guard let pid = entry[kCGWindowOwnerPID as String] as? Int32,
                  pid == settings.processIdentifier,
                  (entry[kCGWindowLayer as String] as? Int) == 0,
                  let bounds = entry[kCGWindowBounds as String] as? [String: CGFloat]
            else { continue }

            let width = bounds["Width"] ?? 0
            let height = bounds["Height"] ?? 0
            // Skip tooltips/sheets — the real Settings window is the only sizeable one.
            guard width > 300, height > 300 else { continue }

            // CGWindow bounds use a top-left origin on the primary display; AppKit uses
            // bottom-left. Flip through the primary screen's height.
            let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
            return CGRect(
                x: bounds["X"] ?? 0,
                y: primaryHeight - (bounds["Y"] ?? 0) - height,
                width: width,
                height: height
            )
        }
        return nil
    }

    func close() {
        positioningTask?.cancel()
        panel?.close()
    }

    /// Screen Recording grants only take effect on a fresh process, so offer the restart here.
    /// The relaunch is delegated to a detached shell that waits for this instance to be gone:
    /// launching the new instance first (openApplication + terminate) briefly ran two copies —
    /// two OCR worker trees in Activity Monitor and a global-hotkey registration race.
    @objc private func relaunchApp() {
        let relauncher = Process()
        relauncher.executableURL = URL(fileURLWithPath: "/bin/sh")
        relauncher.arguments = [
            "-c",
            // $0 = bundle path; wait until our pid is gone (max ~5s) before reopening.
            "for _ in $(seq 1 50); do kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null || break; sleep 0.1; done; open \"$0\"",
            Bundle.main.bundlePath
        ]
        try? relauncher.run()
        NSApp.terminate(nil)
    }
}

/// App icon that starts an outside-app drag carrying the app bundle's file URL — exactly what
/// the System Settings permission list accepts as a drop.
final class DraggableAppIconView: NSImageView, NSDraggingSource {
    override func mouseDown(with event: NSEvent) {
        // Intentionally empty: the drag starts from mouseDragged; without this override the
        // panel would begin a window drag instead.
    }

    override func mouseDragged(with event: NSEvent) {
        let item = NSDraggingItem(pasteboardWriter: Bundle.main.bundleURL as NSURL)
        item.setDraggingFrame(bounds, contents: image)
        beginDraggingSession(with: [item], event: event, source: self)
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        context == .outsideApplication ? .copy : []
    }
}
