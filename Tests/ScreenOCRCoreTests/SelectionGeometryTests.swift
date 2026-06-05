import CoreGraphics
import XCTest
@testable import ScreenOCRCore

final class SelectionGeometryTests: XCTestCase {
    func testNormalizesDragDirectionAndFindsContainingDisplay() throws {
        let displays = [
            DisplayFrame(id: 1, frame: CGRect(x: 0, y: 0, width: 1440, height: 900))
        ]

        let selection = try ScreenRegionSelection.resolve(
            dragStart: CGPoint(x: 500, y: 400),
            dragEnd: CGPoint(x: 100, y: 100),
            displays: displays
        )

        XCTAssertEqual(selection.rect, CGRect(x: 100, y: 100, width: 400, height: 300))
        XCTAssertEqual(selection.displayID, 1)
        XCTAssertEqual(selection.displayFrame, CGRect(x: 0, y: 0, width: 1440, height: 900))
    }

    func testRejectsSelectionsThatCrossDisplays() throws {
        let displays = [
            DisplayFrame(id: 1, frame: CGRect(x: 0, y: 0, width: 1440, height: 900)),
            DisplayFrame(id: 2, frame: CGRect(x: 1440, y: 0, width: 1440, height: 900))
        ]

        XCTAssertThrowsError(
            try ScreenRegionSelection.resolve(
                dragStart: CGPoint(x: 1400, y: 100),
                dragEnd: CGPoint(x: 1500, y: 200),
                displays: displays
            )
        ) { error in
            XCTAssertEqual(error as? ScreenRegionSelectionError, .crossesDisplays)
        }
    }

    func testRejectsTooSmallSelections() throws {
        XCTAssertThrowsError(
            try ScreenRegionSelection.resolve(
                dragStart: CGPoint(x: 10, y: 10),
                dragEnd: CGPoint(x: 14, y: 14),
                displays: [DisplayFrame(id: 1, frame: CGRect(x: 0, y: 0, width: 100, height: 100))]
            )
        ) { error in
            XCTAssertEqual(error as? ScreenRegionSelectionError, .tooSmall)
        }
    }

    func testMapsMainDisplayRectToDisplayLocalCaptureRectWithTopOrigin() throws {
        let rect = CGRect(x: 100, y: 120, width: 300, height: 80)
        let mapped = DisplayCoordinateMapper.appKitRectToDisplayLocalCaptureRect(
            rect,
            appKitDisplayFrame: CGRect(x: 0, y: 0, width: 1440, height: 900)
        )

        XCTAssertEqual(mapped, CGRect(x: 100, y: 700, width: 300, height: 80))
    }

    func testMapsSecondaryDisplayRectToDisplayLocalCaptureRectWithTopOrigin() throws {
        let rect = CGRect(x: 2660, y: 100, width: 300, height: 80)
        let mapped = DisplayCoordinateMapper.appKitRectToDisplayLocalCaptureRect(
            rect,
            appKitDisplayFrame: CGRect(x: 2560, y: 0, width: 1512, height: 982)
        )

        XCTAssertEqual(mapped, CGRect(x: 100, y: 802, width: 300, height: 80))
    }

    func testMapsSecondaryDisplayRectToCaptureGlobalRectUsingCaptureBounds() throws {
        let rect = CGRect(x: 2660, y: 100, width: 300, height: 80)
        let mapped = DisplayCoordinateMapper.appKitRectToCaptureGlobalRect(
            rect,
            appKitDisplayFrame: CGRect(x: 2560, y: 0, width: 1512, height: 982),
            captureDisplayBounds: CGRect(x: 2560, y: 458, width: 1512, height: 982)
        )

        XCTAssertEqual(mapped, CGRect(x: 2660, y: 1260, width: 300, height: 80))
    }
}
