@testable import AppBundle
import AppKit
import XCTest

final class DockWorkAreaTest: XCTestCase {
    func testStaleVisibleFrameReservesDockOnlyOnItsMonitor() {
        let screen = CGRect(x: 1512, y: -359, width: 3780, height: 2160)
        let dock = CGRect(x: 1576, y: 1697, width: 3652, height: 94)
        let adjusted = DockWorkArea.excludingDock(from: screen, screen: screen, dock: dock, edge: "bottom")
        XCTAssertEqual(adjusted.maxY, 1693)
        XCTAssertEqual(adjusted.minY, screen.minY)
        let other = CGRect(x: 0, y: 0, width: 1512, height: 982)
        XCTAssertEqual(DockWorkArea.excludingDock(from: other, screen: other, dock: dock, edge: "bottom"), other)
    }

    func testSideDocksAndExistingReservation() {
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let left = CGRect(x: 0, y: 100, width: 60, height: 600)
        XCTAssertEqual(DockWorkArea.excludingDock(from: screen, screen: screen, dock: left, edge: "left").minX, 64)
        let right = CGRect(x: 940, y: 100, width: 60, height: 600)
        XCTAssertEqual(DockWorkArea.excludingDock(from: screen, screen: screen, dock: right, edge: "right").maxX, 936)
        let visible = CGRect(x: 0, y: 30, width: 1000, height: 670)
        let bottom = CGRect(x: 100, y: 730, width: 800, height: 70)
        XCTAssertEqual(DockWorkArea.excludingDock(from: visible, screen: screen, dock: bottom, edge: "bottom"), visible)
    }

    func testHiddenAndFullscreenDockSurfacesAreIgnored() {
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
        XCTAssertEqual(DockWorkArea.excludingDock(from: screen, screen: screen, dock: nil, edge: "bottom"), screen)
        XCTAssertEqual(DockWorkArea.excludingDock(from: screen, screen: screen, dock: screen, edge: "bottom"), screen)
        let hidden = CGRect(x: 100, y: 800, width: 800, height: 70)
        XCTAssertEqual(DockWorkArea.excludingDock(from: screen, screen: screen, dock: hidden, edge: "bottom"), screen)
    }
}
