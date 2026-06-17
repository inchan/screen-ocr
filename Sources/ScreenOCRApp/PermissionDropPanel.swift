import AppKit

final class PermissionDropPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Floating helper shown next to System Settings when Screen Recording permission is missing:
/// the app icon can be dragged straight into the Settings permission list (the list accepts
/// app-bundle file drops), which beats hunting for the app in a file picker.
@MainActor
final class PermissionDropPanelController {
    private var panel: NSPanel?
    private var positioningTask: Task<Void, Never>?

    func show() {
        if let panel {
            panel.orderFrontRegardless()
            return
        }

        let size = CGSize(width: 340, height: 224)
        let panel = PermissionDropPanel(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "화면 기록 권한 설정"
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false

        let content = Self.makeContentView(
            size: size,
            relaunchTarget: self,
            relaunchAction: #selector(relaunchApp)
        )

        panel.contentView = content
        panel.center()
        panel.orderFrontRegardless()
        self.panel = panel
        snapBesideSystemSettings()
    }

    static func makeContentView(
        size: CGSize,
        relaunchTarget: AnyObject,
        relaunchAction: Selector
    ) -> NSView {
        let content = NSView(frame: CGRect(origin: .zero, size: size))
        content.identifier = NSUserInterfaceItemIdentifier("permission.drop.panel")

        let iconSize: CGFloat = 92
        let iconView = DraggableAppIconView(
            frame: CGRect(x: (size.width - iconSize) / 2, y: 108, width: iconSize, height: iconSize)
        )
        iconView.identifier = NSUserInterfaceItemIdentifier("permission.drop.icon")
        iconView.image = NSApp.applicationIconImage
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.toolTip = "이 앱 아이콘을 왼쪽 화면 기록 목록으로 드래그"
        iconView.setAccessibilityLabel("Screen OCR 앱 아이콘")
        content.addSubview(iconView)

        let direction = NSTextField(labelWithString: "←")
        direction.identifier = NSUserInterfaceItemIdentifier("permission.drop.direction")
        direction.alignment = .center
        direction.font = .systemFont(ofSize: 44, weight: .bold)
        direction.textColor = .controlAccentColor
        direction.setAccessibilityLabel("왼쪽으로 드래그")

        let instruction = NSTextField(labelWithString: "왼쪽 화면 기록 목록에 드래그해서 넣어주세요.")
        instruction.identifier = NSUserInterfaceItemIdentifier("permission.drop.instruction")
        instruction.alignment = .left
        instruction.font = .systemFont(ofSize: 14, weight: .medium)
        instruction.textColor = .labelColor
        instruction.setContentCompressionResistancePriority(.required, for: .horizontal)

        let guideRow = NSStackView(views: [direction, instruction])
        guideRow.identifier = NSUserInterfaceItemIdentifier("permission.drop.guide-row")
        guideRow.orientation = .horizontal
        guideRow.alignment = .centerY
        guideRow.spacing = 10
        guideRow.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(guideRow)

        NSLayoutConstraint.activate([
            guideRow.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            guideRow.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 4)
        ])

        let relaunchButton = NSButton(
            title: "앱 재시작",
            target: relaunchTarget,
            action: relaunchAction
        )
        relaunchButton.identifier = NSUserInterfaceItemIdentifier("permission.drop.relaunch")
        relaunchButton.bezelStyle = .rounded
        relaunchButton.keyEquivalent = "\r"
        relaunchButton.sizeToFit()
        relaunchButton.frame.origin = CGPoint(
            x: (size.width - relaunchButton.frame.width) / 2,
            y: 18
        )
        content.addSubview(relaunchButton)

        return content
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
