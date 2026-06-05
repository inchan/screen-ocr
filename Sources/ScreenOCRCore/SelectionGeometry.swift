import CoreGraphics
import Foundation

public struct DisplayFrame: Equatable, Sendable {
    public let id: UInt32
    public let frame: CGRect

    public init(id: UInt32, frame: CGRect) {
        self.id = id
        self.frame = frame
    }
}

public struct ScreenRegionSelection: Equatable, Sendable {
    public static let defaultMinimumSize: CGFloat = 8

    public let rect: CGRect
    public let displayID: UInt32
    public let displayFrame: CGRect

    public init(rect: CGRect, displayID: UInt32, displayFrame: CGRect = .null) {
        self.rect = rect
        self.displayID = displayID
        self.displayFrame = displayFrame
    }

    public static func resolve(
        dragStart: CGPoint,
        dragEnd: CGPoint,
        displays: [DisplayFrame],
        minimumSize: CGFloat = defaultMinimumSize
    ) throws -> ScreenRegionSelection {
        let rect = CGRect(
            x: min(dragStart.x, dragEnd.x),
            y: min(dragStart.y, dragEnd.y),
            width: abs(dragStart.x - dragEnd.x),
            height: abs(dragStart.y - dragEnd.y)
        )

        guard rect.width >= minimumSize, rect.height >= minimumSize else {
            throw ScreenRegionSelectionError.tooSmall
        }

        let containingDisplays = displays.filter { display in
            display.frame.contains(rect)
        }

        guard containingDisplays.count == 1, let display = containingDisplays.first else {
            throw ScreenRegionSelectionError.crossesDisplays
        }

        return ScreenRegionSelection(rect: rect, displayID: display.id, displayFrame: display.frame)
    }
}

public enum DisplayCoordinateMapper {
    public static func appKitRectToCaptureGlobalRect(
        _ rect: CGRect,
        appKitDisplayFrame: CGRect,
        captureDisplayBounds: CGRect
    ) -> CGRect {
        return CGRect(
            x: captureDisplayBounds.minX + rect.minX - appKitDisplayFrame.minX,
            y: captureDisplayBounds.minY + appKitDisplayFrame.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    public static func appKitRectToDisplayLocalCaptureRect(
        _ rect: CGRect,
        appKitDisplayFrame: CGRect
    ) -> CGRect {
        return CGRect(
            x: rect.minX - appKitDisplayFrame.minX,
            y: appKitDisplayFrame.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }
}

public enum ScreenRegionSelectionError: Error, LocalizedError, Equatable, Sendable {
    case tooSmall
    case crossesDisplays

    public var errorDescription: String? {
        switch self {
        case .tooSmall:
            return "Selected region is too small"
        case .crossesDisplays:
            return "Selected region must stay within one display"
        }
    }
}
