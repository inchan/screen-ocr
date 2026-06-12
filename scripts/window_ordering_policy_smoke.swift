import AppKit
import Foundation

@main
struct WindowOrderingPolicySmoke {
    @MainActor
    static func main() {
        _ = NSApplication.shared

        let settingsWindow = makeWindow(title: "Settings")
        let hiddenWindow = makeWindow(title: "Hidden")
        let floatingPanel = NSPanel(
            contentRect: CGRect(x: -10_000, y: -10_000, width: 120, height: 80),
            styleMask: [.titled, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        floatingPanel.level = .floating

        settingsWindow.orderFront(nil)
        floatingPanel.orderFront(nil)
        defer {
            settingsWindow.close()
            hiddenWindow.close()
            floatingPanel.close()
        }

        let inactiveMatches = WindowOrderingPolicy.windowsToKeepBehindDuringCapture(
            appWasActive: false,
            windows: [settingsWindow, hiddenWindow, floatingPanel]
        )
        assert(inactiveMatches == [settingsWindow], "inactive capture preserves visible normal window behind")

        let activeMatches = WindowOrderingPolicy.windowsToKeepBehindDuringCapture(
            appWasActive: true,
            windows: [settingsWindow, hiddenWindow, floatingPanel]
        )
        assert(activeMatches.isEmpty, "active capture does not reorder existing front app windows")

        print("PASS window ordering policy smoke")
    }

    private static func makeWindow(title: String) -> NSWindow {
        let window = NSWindow(
            contentRect: CGRect(x: -10_000, y: -10_000, width: 120, height: 80),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.isReleasedWhenClosed = false
        return window
    }

    private static func assert(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            fail(message)
        }
    }

    private static func fail(_ message: String) -> Never {
        fputs("FAIL \(message)\n", stderr)
        exit(1)
    }
}
