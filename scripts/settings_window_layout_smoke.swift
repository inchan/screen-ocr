import AppKit
import Foundation

@main
struct SettingsWindowLayoutSmoke {
    @MainActor
    static func main() {
        _ = NSApplication.shared

        let settingsURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("screen-ocr-settings-window-smoke-\(UUID().uuidString)")
            .appendingPathComponent("settings.json")
        let controller = SettingsWindowController(store: SettingsStore(fileURL: settingsURL))
        guard let window = controller.window,
              let root = window.contentView else {
            fail("settings window did not construct")
        }

        assert(window.styleMask.contains(.resizable), "settings window is resizable")
        assert(window.minSize.width >= 640, "settings window has practical minimum width")
        assert(findView(root, identifier: "settings.sidebar") != nil, "sidebar exists")
        assert(findView(root, identifier: "settings.sidebar.general") != nil, "general sidebar item exists")
        assert(findView(root, identifier: "settings.sidebar.capture") != nil, "capture sidebar item exists")
        assert(findView(root, identifier: "settings.sidebar.engine") != nil, "engine sidebar item exists")
        assert(findView(root, identifier: "settings.detail.general") != nil, "general detail is initially selected")

        activateSidebar("settings.sidebar.capture", root: root)
        assert(findView(root, identifier: "settings.detail.capture") != nil, "capture detail opens from sidebar")

        activateSidebar("settings.sidebar.engine", root: root)
        assert(findView(root, identifier: "settings.detail.engine") != nil, "engine detail opens from sidebar")
        guard let paddleSection = findView(root, identifier: "settings.section.paddle") else {
            fail("paddle section exists on engine page")
        }
        assert(!paddleSection.isHidden, "paddle section is visible for PaddleOCR")

        if let enginePopup = findView(root, identifier: "settings.control.engine") as? NSPopUpButton,
           enginePopup.numberOfItems > 1,
           enginePopup.item(at: 1)?.isEnabled == true {
            enginePopup.selectItem(at: 1)
            _ = enginePopup.sendAction(enginePopup.action, to: enginePopup.target)
            assert(paddleSection.isHidden, "paddle section hides for non-Paddle engine")

            enginePopup.selectItem(at: 0)
            _ = enginePopup.sendAction(enginePopup.action, to: enginePopup.target)
            assert(!paddleSection.isHidden, "paddle section returns for PaddleOCR")
        }

        print("PASS settings window two-pane layout smoke")
    }

    private static func activateSidebar(_ identifier: String, root: NSView) {
        guard let control = findView(root, identifier: identifier) as? NSControl else {
            fail("missing sidebar control: \(identifier)")
        }
        _ = control.sendAction(control.action, to: control.target)
    }

    private static func findView(_ root: NSView, identifier: String) -> NSView? {
        if root.identifier?.rawValue == identifier {
            return root
        }
        for subview in root.subviews {
            if let match = findView(subview, identifier: identifier) {
                return match
            }
        }
        return nil
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
