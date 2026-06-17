import AppKit
import Carbon.HIToolbox
import Foundation

@main
struct HotkeyRecorderLayoutSmoke {
    @MainActor
    static func main() {
        _ = NSApplication.shared

        let recorder = HotkeyRecorderView(initial: .default)
        recorder.frame = CGRect(x: 0, y: 0, width: 140, height: 24)
        recorder.layoutSubtreeIfNeeded()

        let referenceLabel = NSTextField(labelWithString: HotkeyConfig.default.displayString)
        referenceLabel.font = .systemFont(ofSize: 13, weight: .medium)

        let verticalInset = max(0, (recorder.bounds.height - referenceLabel.intrinsicContentSize.height) / 2)
        let expectedFirstBaseline = verticalInset + referenceLabel.firstBaselineOffsetFromTop
        let expectedLastBaseline = verticalInset + referenceLabel.lastBaselineOffsetFromBottom

        assertClose(
            recorder.firstBaselineOffsetFromTop,
            expectedFirstBaseline,
            label: "firstBaselineOffsetFromTop"
        )
        assertClose(
            recorder.lastBaselineOffsetFromBottom,
            expectedLastBaseline,
            label: "lastBaselineOffsetFromBottom"
        )
        assertHotkeyDefaults()

        print(
            "PASS hotkey recorder baseline first=\(format(recorder.firstBaselineOffsetFromTop)) " +
            "last=\(format(recorder.lastBaselineOffsetFromBottom))"
        )
    }

    private static func assertHotkeyDefaults() {
        assert(
            HotkeyConfig.default == HotkeyConfig(
                keyCode: UInt32(kVK_ANSI_2),
                modifiers: UInt32(cmdKey | shiftKey),
                displayString: "⇧⌘2"
            ),
            "default hotkey is Cmd+Shift+2"
        )
        assert(
            HotkeyConfig.fallback == HotkeyConfig(
                keyCode: UInt32(kVK_ANSI_0),
                modifiers: UInt32(cmdKey | shiftKey),
                displayString: "⇧⌘0"
            ),
            "fallback hotkey is Cmd+Shift+0"
        )
        assert(
            HotkeyConfig.fallbackCandidate(afterRegistrationFailureOf: .default) == .fallback,
            "default registration failure falls back to Cmd+Shift+0"
        )
        assert(
            HotkeyConfig.startupPreferredCandidate(for: .fallback, autoFallback: true) == .default,
            "stored automatic fallback retries Cmd+Shift+2 at next launch"
        )
        assert(
            HotkeyConfig.startupPreferredCandidate(for: .fallback, autoFallback: false) == .fallback,
            "user-selected Cmd+Shift+0 remains the startup candidate"
        )
        let custom = HotkeyConfig(
            keyCode: UInt32(kVK_ANSI_9),
            modifiers: UInt32(cmdKey | shiftKey),
            displayString: "⇧⌘9"
        )
        assert(
            HotkeyConfig.fallbackCandidate(afterRegistrationFailureOf: custom) == nil,
            "custom hotkey registration failure does not silently change shortcut"
        )
        assert(
            HotkeyConfig.startupPreferredCandidate(for: custom, autoFallback: true) == custom,
            "custom hotkey remains the startup candidate"
        )
        let legacyFallbackJSON = """
        {"hotkey":{"keyCode":\(kVK_ANSI_0),"modifiers":\(cmdKey | shiftKey),"displayString":"⇧⌘0"}}
        """.data(using: .utf8)!
        let legacySettings = try! JSONDecoder().decode(AppSettings.self, from: legacyFallbackJSON)
        assert(legacySettings.hotkeyAutoFallback, "legacy Cmd+Shift+0 settings migrate as automatic fallback")
        let manualFallback = AppSettings(hotkey: .fallback, hotkeyAutoFallback: false)
        assert(
            HotkeyConfig.startupPreferredCandidate(
                for: manualFallback.hotkey,
                autoFallback: manualFallback.hotkeyAutoFallback
            ) == .fallback,
            "new user-selected Cmd+Shift+0 settings stay on Cmd+Shift+0"
        )
    }

    private static func assertClose(_ actual: CGFloat, _ expected: CGFloat, label: String) {
        guard actual.isFinite, abs(actual - expected) <= 0.75 else {
            fputs(
                "FAIL \(label): actual=\(format(actual)) expected=\(format(expected))\n",
                stderr
            )
            exit(1)
        }
    }

    private static func assert(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            fputs("FAIL \(message)\n", stderr)
            exit(1)
        }
    }

    private static func format(_ value: CGFloat) -> String {
        String(format: "%.2f", Double(value))
    }
}
