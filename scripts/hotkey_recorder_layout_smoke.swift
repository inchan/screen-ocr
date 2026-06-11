import AppKit
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

        print(
            "PASS hotkey recorder baseline first=\(format(recorder.firstBaselineOffsetFromTop)) " +
            "last=\(format(recorder.lastBaselineOffsetFromBottom))"
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

    private static func format(_ value: CGFloat) -> String {
        String(format: "%.2f", Double(value))
    }
}
