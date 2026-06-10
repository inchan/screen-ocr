import AppKit
import Carbon.HIToolbox

/// The preferences window. Built programmatically (the app ships no storyboard) as a labeled
/// grid form. File-only preferences (save toggles, directory, retention) are written straight to
/// the `SettingsStore`; the two preferences with side effects that can fail — the global hotkey
/// and launch-at-login — are applied through closures the owner installs, so the owner can reject
/// a change (e.g. a hotkey already taken by the system) and have the control revert.
@MainActor
final class SettingsWindowController: NSWindowController {
    private let store: SettingsStore

    /// Applies a candidate hotkey. Return `true` if registration succeeded.
    var applyHotkey: ((HotkeyConfig) -> Bool)?
    /// Suspends (`true`) / resumes (`false`) the global hotkey while the recorder is capturing,
    /// so pressing the currently registered combo re-records it instead of firing a capture.
    var setHotkeySuspended: ((Bool) -> Void)?
    /// Applies launch-at-login. Return `true` if the change took effect.
    var applyLaunchAtLogin: ((Bool) -> Bool)?

    private var screenshotCheckbox: NSButton!
    private var textCheckbox: NSButton!
    private var pathLabel: NSTextField!
    private var retentionPopup: NSPopUpButton!
    private var hotkeyRecorder: HotkeyRecorderView!
    private var hotkeyConflictLabel: NSTextField!
    private var hotkeyConflictRow: NSGridRow?
    private var launchCheckbox: NSButton!
    private var debugCheckbox: NSButton!

    private let retentionOptions: [(title: String, days: Int)] = [
        ("끄기", 0), ("1일", 1), ("7일", 7), ("30일", 30)
    ]

    init(store: SettingsStore) {
        self.store = store
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 460, height: 320),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Screen OCR 설정"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        window.contentView = buildContentView()
        window.center()
        syncFromSettings(store.settings)
    }

    required init?(coder: NSCoder) { nil }

    /// Brings the (accessory app's) settings window to the front.
    func present() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Layout

    private func buildContentView() -> NSView {
        screenshotCheckbox = NSButton(checkboxWithTitle: "스크린샷 저장", target: self, action: #selector(toggleScreenshot))
        textCheckbox = NSButton(checkboxWithTitle: "텍스트 결과 저장", target: self, action: #selector(toggleText))

        pathLabel = NSTextField(labelWithString: "")
        pathLabel.lineBreakMode = .byTruncatingMiddle
        pathLabel.font = .systemFont(ofSize: 12)
        pathLabel.textColor = .secondaryLabelColor
        pathLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let changePathButton = NSButton(title: "변경…", target: self, action: #selector(chooseDirectory))
        changePathButton.bezelStyle = .rounded
        let revealButton = NSButton(title: "열기", target: self, action: #selector(revealDirectory))
        revealButton.bezelStyle = .rounded
        let pathRow = NSStackView(views: [pathLabel, changePathButton, revealButton])
        pathRow.orientation = .horizontal
        pathRow.spacing = 8

        retentionPopup = NSPopUpButton()
        retentionPopup.addItems(withTitles: retentionOptions.map(\.title))
        retentionPopup.target = self
        retentionPopup.action = #selector(changeRetention)

        hotkeyRecorder = HotkeyRecorderView(initial: store.settings.hotkey)
        hotkeyRecorder.onCapture = { [weak self] candidate in
            self?.handleHotkeyCapture(candidate) ?? false
        }
        hotkeyRecorder.onRecordingStateChanged = { [weak self] recording in
            self?.setHotkeySuspended?(recording)
            if recording {
                self?.setHotkeyConflictMessage(nil)
            }
        }

        hotkeyConflictLabel = NSTextField(labelWithString: "")
        hotkeyConflictLabel.font = .systemFont(ofSize: 11)
        hotkeyConflictLabel.textColor = .systemRed

        launchCheckbox = NSButton(checkboxWithTitle: "컴퓨터 시작 시 자동 실행", target: self, action: #selector(toggleLaunchAtLogin))

        debugCheckbox = NSButton(checkboxWithTitle: "진행 상황 팝업 표시 (단계별 소요 시간)", target: self, action: #selector(toggleDebug))

        let grid = NSGridView(views: [
            [makeCaption("저장 항목"), wrap(screenshotCheckbox)],
            [NSGridCell.emptyContentView, wrap(textCheckbox)],
            [makeCaption("저장 위치"), pathRow],
            [makeCaption("자동 정리"), labeled(retentionPopup, suffix: "이 지나면 삭제")],
            [makeCaption("캡처 단축키"), wrap(hotkeyRecorder)],
            [NSGridCell.emptyContentView, hotkeyConflictLabel],
            [makeCaption("시작 프로그램"), wrap(launchCheckbox)],
            [makeCaption("디버깅"), wrap(debugCheckbox)]
        ])
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.rowAlignment = .firstBaseline
        grid.columnSpacing = 16
        grid.rowSpacing = 14
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .leading

        // The conflict message row is collapsed until a rejected combo needs explaining.
        hotkeyConflictRow = grid.cell(for: hotkeyConflictLabel)?.row
        hotkeyConflictRow?.isHidden = true

        let container = NSView()
        container.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            grid.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -24),
            grid.topAnchor.constraint(equalTo: container.topAnchor, constant: 24),
            grid.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -24)
        ])
        return container
    }

    private func makeCaption(_ text: String) -> NSView {
        let field = NSTextField(labelWithString: text)
        field.font = .systemFont(ofSize: 13, weight: .semibold)
        field.textColor = .secondaryLabelColor
        return field
    }

    private func wrap(_ view: NSView) -> NSView {
        let stack = NSStackView(views: [view])
        stack.orientation = .horizontal
        return stack
    }

    private func labeled(_ view: NSView, suffix: String) -> NSView {
        let label = NSTextField(labelWithString: suffix)
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [view, label])
        stack.orientation = .horizontal
        stack.spacing = 8
        return stack
    }

    // MARK: - Sync

    private func syncFromSettings(_ settings: AppSettings) {
        screenshotCheckbox.state = settings.saveScreenshots ? .on : .off
        textCheckbox.state = settings.saveTextResults ? .on : .off
        pathLabel.stringValue = settings.saveDirectoryPath
        pathLabel.toolTip = settings.saveDirectoryPath
        let index = retentionOptions.firstIndex { $0.days == settings.retentionDays } ?? 1
        retentionPopup.selectItem(at: index)
        hotkeyRecorder.setConfig(settings.hotkey)
        launchCheckbox.state = settings.launchAtLogin ? .on : .off
        debugCheckbox.state = settings.showDebugProgress ? .on : .off
    }

    // MARK: - Actions

    @objc private func toggleScreenshot() {
        store.update { $0.saveScreenshots = (screenshotCheckbox.state == .on) }
    }

    @objc private func toggleText() {
        store.update { $0.saveTextResults = (textCheckbox.state == .on) }
    }

    @objc private func toggleDebug() {
        store.update { $0.showDebugProgress = (debugCheckbox.state == .on) }
    }

    @objc private func changeRetention() {
        let index = retentionPopup.indexOfSelectedItem
        guard retentionOptions.indices.contains(index) else { return }
        store.update { $0.retentionDays = retentionOptions[index].days }
    }

    @objc private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = store.settings.saveDirectoryURL
        panel.prompt = "선택"
        if panel.runModal() == .OK, let url = panel.url {
            store.update { $0.saveDirectoryPath = url.path }
            syncFromSettings(store.settings)
        }
    }

    @objc private func revealDirectory() {
        let url = store.settings.saveDirectoryURL
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @objc private func toggleLaunchAtLogin() {
        let desired = (launchCheckbox.state == .on)
        let applied = applyLaunchAtLogin?(desired) ?? false
        if applied {
            store.update { $0.launchAtLogin = desired }
        } else {
            // Revert the checkbox if the system rejected the change.
            launchCheckbox.state = store.settings.launchAtLogin ? .on : .off
        }
    }

    /// Tries to register a freshly recorded hotkey. On success, persists it; on conflict, shows an
    /// inline message and returns false so the recorder reverts to the previous value.
    ///
    /// System shortcuts need an explicit pre-check: `RegisterEventHotKey` reports success for
    /// combos macOS itself owns (⇧⌘3 etc.), but the system swallows them first, leaving a hotkey
    /// that silently never fires.
    private func handleHotkeyCapture(_ candidate: HotkeyConfig) -> Bool {
        guard !Self.isClaimedBySystem(candidate) else {
            setHotkeyConflictMessage("\(candidate.displayString) 은(는) macOS 시스템 단축키라 지정할 수 없습니다.")
            return false
        }
        guard applyHotkey?(candidate) ?? false else {
            setHotkeyConflictMessage("\(candidate.displayString) 은(는) 다른 앱에서 이미 사용 중이라 지정할 수 없습니다.")
            return false
        }
        setHotkeyConflictMessage(nil)
        store.update { $0.hotkey = candidate }
        return true
    }

    /// Shows the red message under the recorder, or collapses the row when `nil`.
    private func setHotkeyConflictMessage(_ message: String?) {
        hotkeyConflictLabel.stringValue = message ?? ""
        hotkeyConflictRow?.isHidden = (message == nil)
    }

    /// Whether `candidate` matches an enabled macOS symbolic hotkey (Mission Control, screenshot
    /// shortcuts, …). Comparison is on Carbon key code + the four standard modifier bits — the
    /// same representation `HotkeyConfig` stores.
    static func isClaimedBySystem(_ candidate: HotkeyConfig) -> Bool {
        var hotkeysRef: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&hotkeysRef) == noErr,
              let entries = hotkeysRef?.takeRetainedValue() as? [[String: Any]] else {
            return false
        }
        let relevantMask = UInt32(cmdKey | shiftKey | optionKey | controlKey)
        for entry in entries {
            guard (entry[kHISymbolicHotKeyEnabled as String] as? Bool) == true,
                  let keyCode = entry[kHISymbolicHotKeyCode as String] as? Int,
                  let modifiers = entry[kHISymbolicHotKeyModifiers as String] as? Int else {
                continue
            }
            if UInt32(keyCode) == candidate.keyCode,
               UInt32(truncatingIfNeeded: modifiers) & relevantMask == candidate.modifiers {
                return true
            }
        }
        return false
    }
}

extension SettingsWindowController: NSWindowDelegate {
    /// Closing the window does not resign the first responder, so a recording left in progress
    /// would keep the global hotkey suspended forever. Force-end it here.
    func windowWillClose(_ notification: Notification) {
        window?.makeFirstResponder(nil)
    }
}
