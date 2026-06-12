import AppKit
import Foundation

private final class DummyTarget: NSObject {
    @objc func relaunchApp() {}
}

@main
struct PermissionDropPanelSmoke {
    @MainActor
    static func main() {
        _ = NSApplication.shared
        let size = CGSize(width: 340, height: 224)
        let root = PermissionDropPanelController.makeContentView(
            size: size,
            relaunchTarget: DummyTarget(),
            relaunchAction: #selector(DummyTarget.relaunchApp)
        )

        assert(root.identifier?.rawValue == "permission.drop.panel", "panel content has identifier")
        assert(findView(root, identifier: "permission.drop.icon") != nil, "draggable app icon exists")
        guard let direction = findView(root, identifier: "permission.drop.direction") as? NSTextField else {
            fail("direction cue exists")
        }
        assert(direction.stringValue == "←", "direction cue points left toward System Settings")
        assert(direction.font?.pointSize ?? 0 >= 40, "direction cue is visually large")
        assert(findView(root, identifier: "permission.drop.destination") == nil, "destination card is removed")
        assert(findView(root, identifier: "permission.drop.guide-title") == nil, "extra guide title is removed")
        assert(findView(root, identifier: "permission.drop.guide-row") != nil, "arrow and copy share an aligned row")
        assert(textExists(in: root, matchingAny: ["드래그", "drag"]), "copy explains dragging")
        assert(textExists(in: root, matchingAny: ["왼쪽 화면 기록 목록"]), "copy names the drop destination")
        assert(textExists(in: root, matchingAny: ["넣어주세요"]), "copy keeps the instruction minimal")

        print("PASS permission drop panel guidance smoke")
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

    private static func textExists(in root: NSView, matchingAny needles: [String]) -> Bool {
        if let label = root as? NSTextField {
            return needles.contains { label.stringValue.localizedCaseInsensitiveContains($0) }
        }
        return root.subviews.contains { textExists(in: $0, matchingAny: needles) }
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
