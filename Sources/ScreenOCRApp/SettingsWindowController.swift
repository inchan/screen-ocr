import AppKit
import Carbon.HIToolbox

/// The preferences window. Built programmatically (the app ships no storyboard). File-only
/// preferences are written straight to the `SettingsStore`; preferences with side effects that
/// can fail are applied through closures the owner installs, so the owner can reject a change and
/// have the control revert.
@MainActor
final class SettingsWindowController: NSWindowController {
    private let store: SettingsStore
    private let copy = SettingsCopy.current

    /// Applies a candidate hotkey. Return `true` if registration succeeded.
    var applyHotkey: ((HotkeyConfig) -> Bool)?
    /// Suspends (`true`) / resumes (`false`) the global hotkey while the recorder is capturing,
    /// so pressing the currently registered combo re-records it instead of firing a capture.
    var setHotkeySuspended: ((Bool) -> Void)?
    /// Applies launch-at-login. Return `true` if the change took effect.
    var applyLaunchAtLogin: ((Bool) -> Bool)?
    /// Opens System Settings at the Screen Recording pane (owned by the app, which also
    /// shows the drag-and-drop helper when the permission is missing).
    var openScreenRecordingSettings: (() -> Void)?

    private var selectedPage: SettingsPage = .general
    private var sidebarItems: [SettingsPage: SettingsSidebarItemView] = [:]
    private var detailContainer: NSView!
    private var paddleSectionView: NSView?

    private var screenshotCheckbox: NSButton!
    private var textCheckbox: NSButton!
    private var saveLocationRow: NSStackView!
    private var pathLabel: NSTextField!
    private var retentionPopup: NSPopUpButton!
    private var hotkeyRecorder: HotkeyRecorderView!
    private var hotkeyToast: NSVisualEffectView!
    private var hotkeyToastLabel: NSTextField!
    private var hotkeyToastHideWork: DispatchWorkItem?
    private var launchCheckbox: NSButton!
    private var debugCheckbox: NSButton!
    private var enginePopup: NSPopUpButton!
    private var workerPopup: NSPopUpButton!
    private var screenRecordingStatusLabel: NSTextField!
    private var screenRecordingButton: NSButton!

    private let sidebarWidth: CGFloat = 180
    private let formLabelWidth: CGFloat = 116

    /// Toast container that never intercepts clicks aimed at the controls underneath it.
    private final class PassthroughEffectView: NSVisualEffectView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    private var retentionOptions: [(title: String, days: Int)] {
        [
            (copy.off, 0),
            (copy.oneDay, 1),
            (copy.sevenDays, 7),
            (copy.thirtyDays, 30)
        ]
    }

    private var engineOptions: [(title: String, engine: OCREngineChoice)] {
        [
            (copy.paddleEngineTitle, .paddleOCR),
            (copy.visionEngineTitle, .vision)
        ]
    }

    private var workerOptions: [(title: String, count: Int?)] {
        [(copy.workerAuto, nil)] + AppSettings.paddleOCRWorkerCountRange.map { ("\($0)", Optional($0)) }
    }

    init(store: SettingsStore) {
        self.store = store
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 720, height: 440),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = copy.windowTitle
        window.minSize = NSSize(width: 640, height: 390)
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

    /// Moves settings directly to the permission controls when Screen Recording is missing.
    func focusCapturePermissions() {
        showPage(.capture)
    }

    func presentCapturePermissions() {
        focusCapturePermissions()
        present()
    }

    // MARK: - Layout

    private func buildContentView() -> NSView {
        buildControls()

        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let sidebar = buildSidebar()
        detailContainer = NSView()
        detailContainer.translatesAutoresizingMaskIntoConstraints = false
        detailContainer.identifier = NSUserInterfaceItemIdentifier("settings.detail")

        let separator = NSView()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.wantsLayer = true
        separator.layer?.backgroundColor = NSColor.separatorColor.cgColor

        container.addSubview(sidebar)
        container.addSubview(separator)
        container.addSubview(detailContainer)
        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            sidebar.topAnchor.constraint(equalTo: container.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: sidebarWidth),

            separator.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            separator.topAnchor.constraint(equalTo: container.topAnchor),
            separator.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            separator.widthAnchor.constraint(equalToConstant: 1),

            detailContainer.leadingAnchor.constraint(equalTo: separator.trailingAnchor),
            detailContainer.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            detailContainer.topAnchor.constraint(equalTo: container.topAnchor),
            detailContainer.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        installHotkeyToast(in: container)
        showPage(.general)
        return container
    }

    private func buildControls() {
        screenshotCheckbox = NSButton(checkboxWithTitle: copy.saveScreenshots, target: self, action: #selector(toggleScreenshot))
        textCheckbox = NSButton(checkboxWithTitle: copy.saveTextResults, target: self, action: #selector(toggleText))

        pathLabel = NSTextField(labelWithString: "")
        pathLabel.lineBreakMode = .byTruncatingMiddle
        pathLabel.font = .systemFont(ofSize: 12)
        pathLabel.textColor = .secondaryLabelColor
        pathLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        pathLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 180).isActive = true

        let changePathButton = NSButton(title: copy.changeButton, target: self, action: #selector(chooseDirectory))
        changePathButton.bezelStyle = .rounded
        let revealButton = NSButton(title: copy.openButton, target: self, action: #selector(revealDirectory))
        revealButton.bezelStyle = .rounded
        saveLocationRow = NSStackView(views: [pathLabel, changePathButton, revealButton])
        saveLocationRow.orientation = .horizontal
        saveLocationRow.alignment = .centerY
        saveLocationRow.spacing = 8

        retentionPopup = NSPopUpButton()
        retentionPopup.addItems(withTitles: retentionOptions.map(\.title))
        retentionPopup.target = self
        retentionPopup.action = #selector(changeRetention)

        hotkeyRecorder = HotkeyRecorderView(initial: store.settings.hotkey)
        hotkeyRecorder.onCapture = { [weak self] candidate in
            self?.handleHotkeyCapture(candidate) ?? false
        }
        hotkeyRecorder.onRecordingStateChanged = { [weak self] recording in
            guard let self else { return }
            self.setHotkeySuspended?(recording)
            if recording {
                self.hideHotkeyToast()
            }
        }
        hotkeyRecorder.onConsumedShortcutDetected = { [weak self] in
            guard let self else { return }
            self.showHotkeyToast(self.copy.consumedShortcutMessage, color: .systemOrange)
        }

        launchCheckbox = NSButton(checkboxWithTitle: copy.launchAtLogin, target: self, action: #selector(toggleLaunchAtLogin))
        debugCheckbox = NSButton(checkboxWithTitle: copy.showProgressPopup, target: self, action: #selector(toggleDebug))
        debugCheckbox.identifier = NSUserInterfaceItemIdentifier("settings.control.debug-progress")

        enginePopup = NSPopUpButton()
        enginePopup.identifier = NSUserInterfaceItemIdentifier("settings.control.engine")
        enginePopup.addItems(withTitles: engineOptions.map(\.title))
        applyEngineOptionAvailability()
        enginePopup.target = self
        enginePopup.action = #selector(changeEngine)

        workerPopup = NSPopUpButton()
        workerPopup.identifier = NSUserInterfaceItemIdentifier("settings.control.paddle-workers")
        workerPopup.addItems(withTitles: workerOptions.map(\.title))
        workerPopup.target = self
        workerPopup.action = #selector(changeWorkerCount)

        screenRecordingStatusLabel = NSTextField(labelWithString: "")
        screenRecordingStatusLabel.font = .systemFont(ofSize: 12, weight: .medium)

        screenRecordingButton = NSButton(
            title: copy.openScreenRecordingSettings,
            target: self,
            action: #selector(openScreenRecording)
        )
        screenRecordingButton.bezelStyle = .rounded
    }

    private func buildSidebar() -> NSView {
        let sidebar = NSVisualEffectView()
        sidebar.material = .sidebar
        sidebar.blendingMode = .withinWindow
        sidebar.state = .active
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        sidebar.identifier = NSUserInterfaceItemIdentifier("settings.sidebar")

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 10, bottom: 10, right: 10)
        stack.translatesAutoresizingMaskIntoConstraints = false
        sidebar.addSubview(stack)

        for page in SettingsPage.allCases {
            let item = SettingsSidebarItemView(
                page: page,
                title: copy.title(for: page),
                symbolName: page.symbolName
            )
            item.target = self
            item.action = #selector(selectPage(_:))
            sidebarItems[page] = item
            stack.addArrangedSubview(item)
            item.widthAnchor.constraint(equalToConstant: sidebarWidth - 20).isActive = true
        }

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .vertical)
        stack.addArrangedSubview(spacer)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            stack.topAnchor.constraint(equalTo: sidebar.topAnchor),
            stack.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor)
        ])

        return sidebar
    }

    private func installHotkeyToast(in container: NSView) {
        hotkeyToastLabel = NSTextField(wrappingLabelWithString: "")
        hotkeyToastLabel.font = .systemFont(ofSize: 11, weight: .medium)
        hotkeyToastLabel.alignment = .center
        hotkeyToastLabel.isSelectable = false
        hotkeyToastLabel.maximumNumberOfLines = 2
        hotkeyToastLabel.translatesAutoresizingMaskIntoConstraints = false

        hotkeyToast = PassthroughEffectView()
        hotkeyToast.material = .hudWindow
        hotkeyToast.blendingMode = .withinWindow
        hotkeyToast.state = .active
        hotkeyToast.wantsLayer = true
        hotkeyToast.layer?.cornerRadius = 8
        hotkeyToast.layer?.masksToBounds = true
        hotkeyToast.translatesAutoresizingMaskIntoConstraints = false
        hotkeyToast.alphaValue = 0
        hotkeyToast.addSubview(hotkeyToastLabel)
        container.addSubview(hotkeyToast)

        NSLayoutConstraint.activate([
            hotkeyToastLabel.leadingAnchor.constraint(equalTo: hotkeyToast.leadingAnchor, constant: 12),
            hotkeyToastLabel.trailingAnchor.constraint(equalTo: hotkeyToast.trailingAnchor, constant: -12),
            hotkeyToastLabel.topAnchor.constraint(equalTo: hotkeyToast.topAnchor, constant: 7),
            hotkeyToastLabel.bottomAnchor.constraint(equalTo: hotkeyToast.bottomAnchor, constant: -7),
            hotkeyToast.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            hotkeyToast.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12),
            hotkeyToast.widthAnchor.constraint(lessThanOrEqualToConstant: 420)
        ])
    }

    private func showPage(_ page: SettingsPage) {
        selectedPage = page
        updateSidebarSelection()
        paddleSectionView = nil

        detailContainer.subviews.forEach { $0.removeFromSuperview() }
        let pageView = makeDetailPage(for: page)
        detailContainer.addSubview(pageView)
        NSLayoutConstraint.activate([
            pageView.leadingAnchor.constraint(equalTo: detailContainer.leadingAnchor),
            pageView.trailingAnchor.constraint(equalTo: detailContainer.trailingAnchor),
            pageView.topAnchor.constraint(equalTo: detailContainer.topAnchor),
            pageView.bottomAnchor.constraint(equalTo: detailContainer.bottomAnchor)
        ])
        syncFromSettings(store.settings)
    }

    private func makeDetailPage(for page: SettingsPage) -> NSView {
        let pageView = NSView()
        pageView.translatesAutoresizingMaskIntoConstraints = false
        pageView.identifier = NSUserInterfaceItemIdentifier(page.detailIdentifier)

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 24
        stack.translatesAutoresizingMaskIntoConstraints = false
        pageView.addSubview(stack)

        switch page {
        case .general:
            stack.addArrangedSubview(makeSection(title: copy.launchSection, rows: [
                makeRow(label: copy.loginItemLabel, content: wrap(launchCheckbox))
            ]))
            stack.addArrangedSubview(makeSection(title: copy.saveSection, rows: [
                makeRow(label: copy.saveItemsLabel, content: checkboxStack([screenshotCheckbox, textCheckbox])),
                makeRow(label: copy.saveLocationLabel, content: saveLocationRow),
                makeRow(label: copy.retentionLabel, content: labeled(retentionPopup, suffix: copy.retentionSuffix))
            ]))
            stack.addArrangedSubview(makeSection(title: copy.displaySection, rows: [
                makeRow(label: copy.progressLabel, content: wrap(debugCheckbox))
            ]))
        case .capture:
            stack.addArrangedSubview(makeSection(title: copy.shortcutSection, rows: [
                makeRow(label: copy.captureShortcutLabel, content: wrap(hotkeyRecorder))
            ]))
            let permissionSection = makeSection(title: copy.permissionSection, rows: [
                makeRow(label: copy.screenRecordingLabel, content: permissionControls())
            ])
            stack.addArrangedSubview(permissionSection)
        case .engine:
            stack.addArrangedSubview(makeSection(title: copy.ocrEngineSection, rows: [
                makeRow(label: copy.engineLabel, content: wrap(enginePopup))
            ]))
            let paddleSection = makeSection(title: "PaddleOCR", rows: [
                makeRow(label: copy.workersLabel, content: labeled(workerPopup, suffix: copy.workerSuffix))
            ])
            paddleSection.identifier = NSUserInterfaceItemIdentifier("settings.section.paddle")
            paddleSectionView = paddleSection
            stack.addArrangedSubview(paddleSection)
        }

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: pageView.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: pageView.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: pageView.topAnchor, constant: 28),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: pageView.bottomAnchor, constant: -28)
        ])

        return pageView
    }

    private func makeSection(title: String, rows: [[NSView]]) -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .labelColor
        stack.addArrangedSubview(titleLabel)

        let grid = NSGridView(views: rows)
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.rowAlignment = .firstBaseline
        grid.columnSpacing = 16
        grid.rowSpacing = 12
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .leading
        stack.addArrangedSubview(grid)

        return stack
    }

    private func makeRow(label: String, content: NSView) -> [NSView] {
        [makeFormLabel(label), content]
    }

    private func makeFormLabel(_ text: String) -> NSView {
        let field = NSTextField(labelWithString: text)
        field.font = .systemFont(ofSize: 13, weight: .semibold)
        field.textColor = .secondaryLabelColor
        field.alignment = .right
        field.translatesAutoresizingMaskIntoConstraints = false
        field.widthAnchor.constraint(equalToConstant: formLabelWidth).isActive = true
        return field
    }

    private func wrap(_ view: NSView) -> NSView {
        let stack = NSStackView(views: [view])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        return stack
    }

    private func checkboxStack(_ views: [NSView]) -> NSView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        return stack
    }

    private func labeled(_ view: NSView, suffix: String) -> NSView {
        let label = NSTextField(labelWithString: suffix)
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [view, label])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        return stack
    }

    private func permissionControls() -> NSView {
        let stack = NSStackView(views: [screenRecordingStatusLabel, screenRecordingButton])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 10
        return stack
    }

    private func applyEngineOptionAvailability() {
        for (index, option) in engineOptions.enumerated() {
            enginePopup.menu?.item(at: index)?.isEnabled = option.engine.isAvailableOnCurrentPlatform
        }
    }

    private func updateSidebarSelection() {
        for (page, item) in sidebarItems {
            item.isSelected = page == selectedPage
        }
    }

    private func syncScreenRecordingStatus() {
        let allowed = CGPreflightScreenCaptureAccess()
        screenRecordingStatusLabel.stringValue = allowed ? copy.permissionAllowed : copy.permissionRequired
        screenRecordingStatusLabel.textColor = allowed ? .systemGreen : .systemOrange
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
        let normalizedEngine = OCREngineChoice.normalizedForCurrentPlatform(settings.ocrEngine)
        let engineIndex = engineOptions.firstIndex { $0.engine == normalizedEngine } ?? 0
        enginePopup.selectItem(at: engineIndex)
        let workerCount = AppSettings.normalizedPaddleOCRWorkerCount(settings.paddleOCRWorkerCount)
        let workerIndex = workerOptions.firstIndex { $0.count == workerCount } ?? 0
        workerPopup.selectItem(at: workerIndex)
        let isPaddleSelected = normalizedEngine == .paddleOCR
        paddleSectionView?.isHidden = !isPaddleSelected
        workerPopup.isEnabled = isPaddleSelected
        workerPopup.toolTip = isPaddleSelected
            ? copy.workerTooltip
            : copy.workerUnavailableTooltip
        syncScreenRecordingStatus()
        updateSidebarSelection()
    }

    // MARK: - Actions

    @objc private func selectPage(_ sender: SettingsSidebarItemView) {
        showPage(sender.page)
    }

    @objc private func toggleScreenshot() {
        store.update { $0.saveScreenshots = (screenshotCheckbox.state == .on) }
    }

    @objc private func toggleText() {
        store.update { $0.saveTextResults = (textCheckbox.state == .on) }
    }

    @objc private func openScreenRecording() {
        openScreenRecordingSettings?()
        syncScreenRecordingStatus()
    }

    @objc private func toggleDebug() {
        store.update { $0.showDebugProgress = (debugCheckbox.state == .on) }
    }

    @objc private func changeEngine() {
        let index = enginePopup.indexOfSelectedItem
        guard engineOptions.indices.contains(index) else { return }
        let engine = engineOptions[index].engine
        guard engine.isAvailableOnCurrentPlatform else {
            syncFromSettings(store.settings)
            return
        }
        let updated = store.update { $0.ocrEngine = engine }
        syncFromSettings(updated)
    }

    @objc private func changeWorkerCount() {
        let index = workerPopup.indexOfSelectedItem
        guard workerOptions.indices.contains(index) else { return }
        store.update { $0.paddleOCRWorkerCount = workerOptions[index].count }
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
        panel.prompt = copy.chooseButton
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
    /// combos macOS itself owns (Shift-Command-3 etc.), but the system swallows them first,
    /// leaving a hotkey that silently never fires.
    private func handleHotkeyCapture(_ candidate: HotkeyConfig) -> Bool {
        guard !Self.isClaimedBySystem(candidate) else {
            showHotkeyToast(copy.systemShortcutRejected(candidate.displayString), color: .systemRed)
            return false
        }
        guard applyHotkey?(candidate) ?? false else {
            showHotkeyToast(copy.shortcutUnavailable(candidate.displayString), color: .systemRed)
            return false
        }
        hideHotkeyToast()
        store.update { $0.hotkey = candidate }
        return true
    }

    /// Fades the toast in at the bottom of the window and auto-dismisses it. Red = definite
    /// rejection; orange = heuristic warning (may be a bare modifier tap).
    private func showHotkeyToast(_ message: String, color: NSColor) {
        hotkeyToastLabel.stringValue = message
        hotkeyToastLabel.textColor = color
        hotkeyToastHideWork?.cancel()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            hotkeyToast.animator().alphaValue = 1
        }
        let work = DispatchWorkItem { [weak self] in
            self?.hideHotkeyToast()
        }
        hotkeyToastHideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: work)
    }

    private func hideHotkeyToast() {
        hotkeyToastHideWork?.cancel()
        hotkeyToastHideWork = nil
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            hotkeyToast.animator().alphaValue = 0
        }
    }

    /// Whether `candidate` matches an enabled macOS symbolic hotkey (Mission Control, screenshot
    /// shortcuts, etc.). Comparison is on Carbon key code + the four standard modifier bits: the
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

private enum SettingsPage: CaseIterable {
    case general
    case capture
    case engine

    var symbolName: String {
        switch self {
        case .general: return "gearshape"
        case .capture: return "viewfinder"
        case .engine: return "cpu"
        }
    }

    var sidebarIdentifier: String {
        switch self {
        case .general: return "settings.sidebar.general"
        case .capture: return "settings.sidebar.capture"
        case .engine: return "settings.sidebar.engine"
        }
    }

    var detailIdentifier: String {
        switch self {
        case .general: return "settings.detail.general"
        case .capture: return "settings.detail.capture"
        case .engine: return "settings.detail.engine"
        }
    }
}

private final class SettingsSidebarItemView: NSControl {
    let page: SettingsPage

    private let imageView = NSImageView()
    private let titleLabel: NSTextField

    var isSelected = false {
        didSet { updateAppearance() }
    }

    init(page: SettingsPage, title: String, symbolName: String) {
        self.page = page
        self.titleLabel = NSTextField(labelWithString: title)
        super.init(frame: .zero)

        identifier = NSUserInterfaceItemIdentifier(page.sidebarIdentifier)
        toolTip = title
        setAccessibilityLabel(title)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false

        imageView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: title)
        imageView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
        imageView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .systemFont(ofSize: 13)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(imageView)
        addSubview(titleLabel)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 32),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 18),
            imageView.heightAnchor.constraint(equalToConstant: 18),
            titleLabel.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -10),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        updateAppearance()
    }

    required init?(coder: NSCoder) { nil }

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        _ = sendAction(action, to: target)
    }

    override func keyDown(with event: NSEvent) {
        let key = event.charactersIgnoringModifiers ?? ""
        if key == " " || key == "\r" {
            _ = sendAction(action, to: target)
        } else {
            super.keyDown(with: event)
        }
    }

    private func updateAppearance() {
        layer?.cornerRadius = 6
        layer?.backgroundColor = isSelected
            ? NSColor.controlAccentColor.withAlphaComponent(0.18).cgColor
            : NSColor.clear.cgColor
        let tint: NSColor = isSelected ? .controlAccentColor : .secondaryLabelColor
        imageView.contentTintColor = tint
        titleLabel.textColor = isSelected ? .labelColor : .secondaryLabelColor
    }
}

private struct SettingsCopy {
    let windowTitle: String
    let general: String
    let capture: String
    let engine: String
    let launchSection: String
    let saveSection: String
    let displaySection: String
    let shortcutSection: String
    let permissionSection: String
    let ocrEngineSection: String
    let loginItemLabel: String
    let saveItemsLabel: String
    let saveLocationLabel: String
    let retentionLabel: String
    let progressLabel: String
    let captureShortcutLabel: String
    let screenRecordingLabel: String
    let engineLabel: String
    let workersLabel: String
    let launchAtLogin: String
    let saveScreenshots: String
    let saveTextResults: String
    let showProgressPopup: String
    let changeButton: String
    let openButton: String
    let chooseButton: String
    let openScreenRecordingSettings: String
    let off: String
    let oneDay: String
    let sevenDays: String
    let thirtyDays: String
    let retentionSuffix: String
    let paddleEngineTitle: String
    let visionEngineTitle: String
    let workerAuto: String
    let workerSuffix: String
    let workerTooltip: String
    let workerUnavailableTooltip: String
    let permissionAllowed: String
    let permissionRequired: String
    let consumedShortcutMessage: String

    static var current: SettingsCopy {
        prefersKorean ? .korean : .english
    }

    func title(for page: SettingsPage) -> String {
        switch page {
        case .general: return general
        case .capture: return capture
        case .engine: return engine
        }
    }

    func systemShortcutRejected(_ shortcut: String) -> String {
        if Self.prefersKorean {
            return "\(shortcut) 은(는) macOS 시스템 단축키라 지정할 수 없습니다."
        }
        return "\(shortcut) is a macOS system shortcut and cannot be assigned."
    }

    func shortcutUnavailable(_ shortcut: String) -> String {
        if Self.prefersKorean {
            return "\(shortcut) 은(는) 다른 앱에서 이미 사용 중이라 지정할 수 없습니다."
        }
        return "\(shortcut) is already used by another app and cannot be assigned."
    }

    private static var prefersKorean: Bool {
        let preferred = Locale.preferredLanguages.first?.lowercased()
        return preferred?.hasPrefix("ko") == true
    }

    private static let korean = SettingsCopy(
        windowTitle: "Screen OCR 설정",
        general: "일반",
        capture: "캡처",
        engine: "엔진",
        launchSection: "시작",
        saveSection: "저장",
        displaySection: "표시",
        shortcutSection: "단축키",
        permissionSection: "권한",
        ocrEngineSection: "OCR 엔진",
        loginItemLabel: "자동 실행",
        saveItemsLabel: "저장 항목",
        saveLocationLabel: "저장 위치",
        retentionLabel: "자동 정리",
        progressLabel: "진행 상황",
        captureShortcutLabel: "캡처 단축키",
        screenRecordingLabel: "화면 기록",
        engineLabel: "엔진",
        workersLabel: "워커 수",
        launchAtLogin: "컴퓨터 시작 시 자동 실행",
        saveScreenshots: "스크린샷 저장",
        saveTextResults: "텍스트 결과 저장",
        showProgressPopup: "진행 상황 팝업 표시",
        changeButton: "변경...",
        openButton: "열기",
        chooseButton: "선택",
        openScreenRecordingSettings: "화면 기록 설정 열기...",
        off: "끄기",
        oneDay: "1일",
        sevenDays: "7일",
        thirtyDays: "30일",
        retentionSuffix: "이 지나면 삭제",
        paddleEngineTitle: "PaddleOCR (정밀 · 한국어 특화)",
        visionEngineTitle: "Apple Vision (빠름 · macOS 내장)",
        workerAuto: "자동 (CPU 기준)",
        workerSuffix: "다음 PaddleOCR 워커부터 적용됨",
        workerTooltip: "자동은 Python worker의 CPU 기준 계산을 사용합니다.",
        workerUnavailableTooltip: "PaddleOCR 선택 시에만 적용됩니다.",
        permissionAllowed: "허용됨",
        permissionRequired: "필요함",
        consumedShortcutMessage: "키 입력이 감지되지 않았습니다 - 시스템 또는 다른 앱이 사용 중인 단축키일 수 있습니다."
    )

    private static let english = SettingsCopy(
        windowTitle: "Screen OCR Settings",
        general: "General",
        capture: "Capture",
        engine: "Engine",
        launchSection: "Launch",
        saveSection: "Save",
        displaySection: "Display",
        shortcutSection: "Shortcut",
        permissionSection: "Permission",
        ocrEngineSection: "OCR Engine",
        loginItemLabel: "Login Item",
        saveItemsLabel: "Save Items",
        saveLocationLabel: "Save Location",
        retentionLabel: "Retention",
        progressLabel: "Progress",
        captureShortcutLabel: "Capture Shortcut",
        screenRecordingLabel: "Screen Recording",
        engineLabel: "Engine",
        workersLabel: "Workers",
        launchAtLogin: "Open at login",
        saveScreenshots: "Save screenshots",
        saveTextResults: "Save text results",
        showProgressPopup: "Show progress popup",
        changeButton: "Change...",
        openButton: "Open",
        chooseButton: "Choose",
        openScreenRecordingSettings: "Open Screen Recording Settings...",
        off: "Off",
        oneDay: "1 day",
        sevenDays: "7 days",
        thirtyDays: "30 days",
        retentionSuffix: "then delete",
        paddleEngineTitle: "PaddleOCR (accurate · Korean-focused)",
        visionEngineTitle: "Apple Vision (fast · built in to macOS)",
        workerAuto: "Auto (CPU based)",
        workerSuffix: "Applies to the next PaddleOCR worker",
        workerTooltip: "Auto uses the Python worker CPU-count calculation.",
        workerUnavailableTooltip: "Only applies when PaddleOCR is selected.",
        permissionAllowed: "Allowed",
        permissionRequired: "Required",
        consumedShortcutMessage: "No key input was detected - the system or another app may be using this shortcut."
    )
}
