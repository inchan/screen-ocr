import AppKit

/// Floating helper shown next to System Settings when Screen Recording permission is missing:
/// the app icon can be dragged straight into the Settings permission list (the list accepts
/// app-bundle file drops), which beats hunting for the app in a file picker. Codex-style UX.
@MainActor
final class PermissionDropPanelController {
    private var panel: NSPanel?

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
        // Nudge to the left so it sits beside the System Settings window instead of under it.
        if let screen = NSScreen.main {
            panel.setFrameOrigin(CGPoint(
                x: screen.visibleFrame.minX + 80,
                y: panel.frame.origin.y
            ))
        }
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
    }

    func close() {
        panel?.close()
    }

    /// Screen Recording grants only take effect on a fresh process, so offer the restart here.
    @objc private func relaunchApp() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(
            at: Bundle.main.bundleURL,
            configuration: configuration
        ) { _, _ in
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        }
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
