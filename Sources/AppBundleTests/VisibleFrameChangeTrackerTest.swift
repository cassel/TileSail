@testable import AppBundle
import AppKit
import XCTest

final class VisibleFrameChangeTrackerTest: XCTestCase {
    func testDockMigrationRequiresStableFramesAndOnlyRefreshesOnce() {
        var tracker = VisibleFrameChangeTracker()
        let full = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let dock = CGRect(x: 0, y: 70, width: 1000, height: 730)
        XCTAssertFalse(tracker.update([1: dock, 2: full]))
        XCTAssertFalse(tracker.update([1: full, 2: dock]))
        XCTAssertTrue(tracker.update([1: full, 2: dock]))
        XCTAssertFalse(tracker.update([1: full, 2: dock]))
        XCTAssertFalse(tracker.update([1: dock, 2: full]))
        XCTAssertTrue(tracker.update([1: dock, 2: full]))
    }

    func testTransientFrameAndEmptyDisplayListDoNotTriggerLayout() {
        var tracker = VisibleFrameChangeTracker()
        let full = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let dock = CGRect(x: 70, y: 0, width: 930, height: 800)
        XCTAssertFalse(tracker.update([1: full]))
        XCTAssertFalse(tracker.update([:]))
        XCTAssertFalse(tracker.update([1: dock]))
        XCTAssertFalse(tracker.update([1: full]))
        XCTAssertFalse(tracker.update([1: dock]))
        XCTAssertTrue(tracker.update([1: dock]))
    }
}
