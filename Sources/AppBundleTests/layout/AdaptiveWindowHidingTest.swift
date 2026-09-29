@testable import AppBundle
import XCTest

final class AdaptiveWindowHidingTest: XCTestCase {
    func testPortraitWorkspaceDoesNotHideOverShorterAdjacentM14() {
        let portrait = Rect(topLeftX: -1296, topLeftY: -536, width: 1296, height: 2304)
        let screens = [
            portrait,
            Rect(topLeftX: 0, topLeftY: 0, width: 1512, height: 982),
            Rect(topLeftX: 0, topLeftY: 982, width: 1366, height: 768),
            Rect(topLeftX: 1512, topLeftY: -359, width: 3780, height: 2160),
        ]
        // Calendar and the two workspace-0 apps get shortened by AppKit when
        // sent to the right corner, so cover both original and clamped sizes.
        for height: CGFloat in [692, 1116, 2232] {
            let size = CGSize(width: 1280, height: height)
            let origin = adaptiveHideOrigin(monitorRect: portrait, screenRects: screens, windowSize: size)
            XCTAssertLessThan(origin.x, portrait.minX)
            let recovered = CGRect(x: origin.x, y: origin.y - 100, width: size.width, height: size.height + 100)
            XCTAssertTrue(recovered.intersection(CGRect(x: 0, y: 982, width: 1366, height: 768)).isNull)
        }
    }
}
