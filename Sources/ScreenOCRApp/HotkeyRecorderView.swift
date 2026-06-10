import AppKit
import Carbon.HIToolbox

/// A click-to-record control for a global hotkey. When focused it shows "키 입력…" and captures
/// the next modifier+key combination, mapping Cocoa event flags to the Carbon masks that
/// `RegisterEventHotKey` requires. Rejects combinations without a modifier (a bare key would
/// hijack normal typing). Reports the captured config via `onCapture`; the owner is responsible
/// for actually registering it and may reject/revert it (e.g. on a system conflict).
@MainActor
final class HotkeyRecorderView: NSView {
    /// Called with a candidate hotkey. Return `true` if it was accepted (registered), `false` to
    /// reject — on rejection the control keeps showing the previous value.
    var onCapture: ((HotkeyConfig) -> Bool)?

    private var current: HotkeyConfig
    private var isRecording = false
    private let label = NSTextField(labelWithString: "")

    init(initial: HotkeyConfig) {
        current = initial
        super.init(frame: CGRect(x: 0, y: 0, width: 140, height: 24))
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 1
        translatesAutoresizingMaskIntoConstraints = false

        label.translatesAutoresizingMaskIntoConstraints = false
        label.alignment = .center
        label.font = .systemFont(ofSize: 13, weight: .medium)
        addSubview(label)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(greaterThanOrEqualToConstant: 130),
            heightAnchor.constraint(equalToConstant: 24),
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        refresh()
    }

    required init?(coder: NSCoder) { nil }

    /// Updates the displayed value without firing `onCapture` (used to revert after a rejection).
    func setConfig(_ config: HotkeyConfig) {
        current = config
        refresh()
    }

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        isRecording = true
        refresh()
    }

    // Becoming first responder (e.g. AppKit auto-focusing on window open) must NOT start
    // recording — only an explicit click does. Otherwise the field would show "키 입력…" and
    // swallow keystrokes before the user ever interacts with it.
    override func becomeFirstResponder() -> Bool {
        true
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        refresh()
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }

        // Escape cancels recording without changing the value.
        if event.keyCode == UInt16(kVK_Escape) {
            isRecording = false
            window?.makeFirstResponder(nil)
            refresh()
            return
        }

        let carbonModifiers = Self.carbonModifiers(from: event.modifierFlags)
        guard carbonModifiers != 0 else {
            NSSound.beep()  // reject modifier-less keys
            return
        }

        let candidate = HotkeyConfig(
            keyCode: UInt32(event.keyCode),
            modifiers: carbonModifiers,
            displayString: Self.displayString(keyCode: event.keyCode, flags: event.modifierFlags)
        )

        isRecording = false
        window?.makeFirstResponder(nil)

        if onCapture?(candidate) ?? false {
            current = candidate
        }
        refresh()
    }

    private func refresh() {
        if isRecording {
            label.stringValue = "키 입력…"
            label.textColor = .secondaryLabelColor
            layer?.borderColor = NSColor.controlAccentColor.cgColor
            layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.08).cgColor
        } else {
            label.stringValue = current.displayString
            label.textColor = .labelColor
            layer?.borderColor = NSColor.separatorColor.cgColor
            layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        }
    }

    // MARK: - Mapping helpers

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var mask: UInt32 = 0
        if flags.contains(.command) { mask |= UInt32(cmdKey) }
        if flags.contains(.shift) { mask |= UInt32(shiftKey) }
        if flags.contains(.option) { mask |= UInt32(optionKey) }
        if flags.contains(.control) { mask |= UInt32(controlKey) }
        return mask
    }

    static func displayString(keyCode: UInt16, flags: NSEvent.ModifierFlags) -> String {
        var prefix = ""
        if flags.contains(.control) { prefix += "⌃" }
        if flags.contains(.option) { prefix += "⌥" }
        if flags.contains(.shift) { prefix += "⇧" }
        if flags.contains(.command) { prefix += "⌘" }
        return prefix + keyName(for: keyCode)
    }

    /// Human label for a virtual key code. Falls back to the uppercased character for the keys
    /// not in the special-key table.
    static func keyName(for keyCode: UInt16) -> String {
        let special: [Int: String] = [
            kVK_Return: "↩", kVK_Tab: "⇥", kVK_Space: "Space", kVK_Delete: "⌫",
            kVK_Escape: "⎋", kVK_ForwardDelete: "⌦",
            kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
            kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
            kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5",
            kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10",
            kVK_F11: "F11", kVK_F12: "F12"
        ]
        if let name = special[Int(keyCode)] { return name }
        if let char = character(for: keyCode) { return char.uppercased() }
        return "Key \(keyCode)"
    }

    /// Resolves the unmodified character a key produces, via the current keyboard layout.
    private static func character(for keyCode: UInt16) -> String? {
        guard let layoutData = TISGetInputSourceProperty(
            TISCopyCurrentKeyboardLayoutInputSource().takeRetainedValue(),
            kTISPropertyUnicodeKeyLayoutData
        ) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(layoutData).takeUnretainedValue() as Data
        var deadKeyState: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = data.withUnsafeBytes { raw -> OSStatus in
            guard let ptr = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return -1 }
            return UCKeyTranslate(
                ptr,
                keyCode,
                UInt16(kUCKeyActionDisplay),
                0,
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                chars.count,
                &length,
                &chars
            )
        }
        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: chars, count: length)
    }
}
