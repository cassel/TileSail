@testable import AppBundle
import XCTest
import Common

@MainActor
final class LayoutAnimationTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testFinalFrameIsAppliedImmediatelyEvenWithLegacyAnimationEnabled() async throws {
        let savedConfig = config
        defer { config = savedConfig }
        config.layoutAnimationDurationMs = 1000
        let window = RecordingLayoutWindow(id: 91)
        let transaction = LayoutTransaction()
        let point = CGPoint(x: 100, y: 80)
        let size = CGSize(width: 900, height: 700)
        transaction.setFrame(window, point, size)
        let applier = LayoutFrameApplier()

        applier.apply(transaction)
        XCTAssertEqual(window.appliedFrames.count, 1)
        XCTAssertEqual(window.appliedFrames.first?.0, point)
        XCTAssertEqual(window.appliedFrames.first?.1, size)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(window.appliedFrames.count, 1)
        applier.apply(LayoutTransaction())
    }

    func testIdenticalTargetStillCorrectsExternalDisplacement() {
        let window = RecordingLayoutWindow(id: 92)
        let transaction = LayoutTransaction()
        let point = CGPoint(x: 100, y: 80)
        let size = CGSize(width: 900, height: 700)
        transaction.setFrame(window, point, size)
        let applier = LayoutFrameApplier()
        applier.apply(transaction)
        window.setAxFrame(.zero, size)
        applier.apply(transaction)
        XCTAssertEqual(window.appliedFrames.last?.0, point)
        applier.apply(LayoutTransaction())
    }

    func testApplierStopsResubmittingConfirmedClampedSize() async throws {
        let window = RecordingLayoutWindow(id: 93)
        window.clampedSize = CGSize(width: 640, height: 480)
        let transaction = LayoutTransaction()
        let point = CGPoint(x: 100, y: 80)
        transaction.setFrame(window, point, CGSize(width: 420, height: 300))
        let applier = LayoutFrameApplier()
        applier.apply(transaction)
        for _ in 0 ..< 100 {
            if window.readCount >= 2 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(window.readCount, 2)
        applier.apply(transaction)
        XCTAssertNil(window.appliedFrames.last?.1)
        XCTAssertEqual(window.appliedFrames.last?.0, point)
        applier.apply(LayoutTransaction())
    }

    func testClosedWindowRejectionsAreDiscarded() {
        var tracker = LayoutFrameAcceptanceTracker()
        let requested = CGSize(width: 420, height: 300)
        let observed = CGSize(width: 640, height: 480)
        for id: UInt32 in [7, 8] {
            tracker.observe(windowId: id, requested: requested, observed: observed)
            tracker.observe(windowId: id, requested: requested, observed: observed)
        }
        tracker.retain(windowIds: [8])
        XCTAssertEqual(tracker.sizeToApply(windowId: 7, requested: requested), requested)
        XCTAssertNil(tracker.sizeToApply(windowId: 8, requested: requested))
    }

    func testRepeatedRejectedSizeIsSuppressedAfterConfirmation() {
        var tracker = LayoutFrameAcceptanceTracker()
        let requested = CGSize(width: 420, height: 300)
        let clamped = CGSize(width: 640, height: 480)

        tracker.observe(windowId: 7, requested: requested, observed: clamped)
        assertEquals(tracker.sizeToApply(windowId: 7, requested: requested), requested)

        tracker.observe(windowId: 7, requested: requested, observed: clamped)
        XCTAssertNil(tracker.sizeToApply(windowId: 7, requested: requested))
    }

    func testNewRequestedSizeIsTriedAndAcceptedSizeClearsRejection() {
        var tracker = LayoutFrameAcceptanceTracker()
        let rejected = CGSize(width: 420, height: 300)
        let clamped = CGSize(width: 640, height: 480)
        let replacement = CGSize(width: 700, height: 520)

        tracker.observe(windowId: 9, requested: rejected, observed: clamped)
        tracker.observe(windowId: 9, requested: rejected, observed: clamped)
        assertEquals(tracker.sizeToApply(windowId: 9, requested: replacement), replacement)

        tracker.observe(windowId: 9, requested: replacement, observed: replacement)
        assertEquals(tracker.sizeToApply(windowId: 9, requested: rejected), rejected)
        XCTAssertNil(tracker.rejectedSizes[9])
    }

    func testRoundingNoiseDoesNotCountAsARefusal() {
        var tracker = LayoutFrameAcceptanceTracker()
        tracker.observe(
            windowId: 11,
            requested: CGSize(width: 500, height: 400),
            observed: CGSize(width: 500.5, height: 399.5),
        )

        XCTAssertNil(tracker.rejectedSizes[11])
    }
}

private final class RecordingLayoutWindow: Window {
    var appliedFrames: [(CGPoint?, CGSize?)] = []
    var clampedSize: CGSize?
    var readCount = 0
    private var rect = Rect(topLeftX: 0, topLeftY: 0, width: 400, height: 300)

    @MainActor
    init(id: UInt32) {
        super.init(id: id, TestApp.shared, lastFloatingSize: nil,
                   parent: Workspace.get(byName: "1").rootTilingContainer,
                   adaptiveWeight: 1, index: INDEX_BIND_LAST)
    }

    override func setAxFrame(_ topLeft: CGPoint?, _ size: CGSize?) {
        appliedFrames.append((topLeft, size))
        rect = Rect(topLeftX: topLeft?.x ?? rect.topLeftX, topLeftY: topLeft?.y ?? rect.topLeftY,
                    width: clampedSize?.width ?? size?.width ?? rect.width, height: clampedSize?.height ?? size?.height ?? rect.height)
    }

    override func getAxRect(_ cm: CancellationMode) async throws -> Rect? {
        readCount += 1
        return rect
    }
}
