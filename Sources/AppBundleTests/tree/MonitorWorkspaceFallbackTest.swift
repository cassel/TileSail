@testable import AppBundle
import XCTest

private struct StaleMonitorInfo: MonitorInfo {
    let stableIdentifier: String
    var monitorAppKitNsScreenScreensId: Int { 99 }
    var name: String { "Disconnected Display" }
    var rect: Rect { Rect(topLeftX: 12000, topLeftY: 12000, width: 1920, height: 1080) }
    var visibleRect: Rect { rect }
    var width: CGFloat { rect.width }
    var height: CGFloat { rect.height }
    var isMain: Bool { false }
}

@MainActor
final class MonitorWorkspaceFallbackTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testDisconnectedMonitorUsesAvailableWorkspaceWithoutChangingItsAssignment() {
        let current = mainMonitorInfo
        let workspace = Workspace.get(byName: "retained")
        XCTAssertTrue(workspace.focusWorkspace())
        let stale = StaleMonitorInfo(stableIdentifier: "disconnected-display")

        XCTAssertTrue(stale.activeWorkspace === workspace)
        XCTAssertTrue(stale.activeWorkspace === workspace)
        XCTAssertTrue(current.activeWorkspace === workspace)
        XCTAssertEqual(workspace.workspaceMonitor.stableIdentifier, current.stableIdentifier)
        XCTAssertNotEqual(workspace.workspaceMonitor.rect.topLeftCorner, stale.rect.topLeftCorner)
    }

    func testMonitorAtOldOriginResolvesItsCurrentHardwareIdentity() {
        let current = mainMonitorInfo
        let workspace = Workspace.get(byName: "relocated")
        XCTAssertTrue(workspace.focusWorkspace())
        let stale = StaleMonitorInfo(stableIdentifier: current.stableIdentifier)

        XCTAssertTrue(stale.activeWorkspace === workspace)
        XCTAssertTrue(current.activeWorkspace === workspace)
        XCTAssertEqual(workspace.workspaceMonitor.rect.topLeftCorner, current.rect.topLeftCorner)
    }

    func testSwappedDisplayOriginsResolveWorkspaceByHardwareIdentity() {
        let originalA = CGPoint(x: 0, y: 0)
        let originalB = CGPoint(x: 1920, y: 0)
        let workspaceA = Workspace.get(byName: "display-a-workspace")
        let workspaceB = Workspace.get(byName: "display-b-workspace")
        let identities = [originalA: "display-b", originalB: "display-a"]
        let workspaces = [originalA: workspaceB, originalB: workspaceA]

        XCTAssertTrue(cachedWorkspaceForMonitor(
            identifier: "display-a", origin: originalA,
            identities: identities, workspaces: workspaces,
        ) === workspaceA)
        XCTAssertTrue(cachedWorkspaceForMonitor(
            identifier: "display-b", origin: originalB,
            identities: identities, workspaces: workspaces,
        ) === workspaceB)
        XCTAssertNil(cachedWorkspaceForMonitor(
            identifier: "disconnected-display", origin: originalA,
            identities: identities, workspaces: workspaces,
        ))
    }
}
