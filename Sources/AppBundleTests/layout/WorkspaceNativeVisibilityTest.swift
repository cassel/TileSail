@testable import AppBundle
import XCTest

@MainActor
final class WorkspaceNativeVisibilityTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testWorkspaceOwnedMinimizationKeepsTreeAndWorkspace() async throws {
        let workspace = Workspace.get(byName: "2")
        let window = TestWindow.new(id: 1, parent: workspace.rootTilingContainer, adaptiveWeight: 3)
        window.isMacosMinimizedForTest = true
        window.isWorkspaceNativeHidden = true
        let parent = window.parent
        try await _normalizeLayoutReason(workspace: workspace, windows: [window])
        XCTAssertTrue(window.parent === parent)
        XCTAssertTrue(window.nodeWorkspace === workspace)
        XCTAssertEqual(window.layoutReason, .standard)
    }

    func testRestoreWaitsForMacosBeforeReleasingOwnership() async throws {
        let workspace = Workspace.get(byName: "2")
        let window = TestWindow.new(id: 3, parent: workspace.rootTilingContainer)
        window.isWorkspaceNativeHidden = true
        window.isWorkspaceRestorePending = true
        window.isMacosMinimizedForTest = true
        try await _normalizeLayoutReason(workspace: workspace, windows: [window])
        XCTAssertTrue(window.isWorkspaceNativeHidden)
        XCTAssertTrue(window.nodeWorkspace === workspace)
        window.isMacosMinimizedForTest = false
        try await _normalizeLayoutReason(workspace: workspace, windows: [window])
        XCTAssertFalse(window.isWorkspaceNativeHidden)
        XCTAssertFalse(window.isWorkspaceRestorePending)
        XCTAssertTrue(window.nodeWorkspace === workspace)
    }

    func testUserMinimizationStillLeavesWorkspaceTree() async throws {
        let workspace = Workspace.get(byName: "2")
        let window = TestWindow.new(id: 2, parent: workspace.rootTilingContainer)
        window.isMacosMinimizedForTest = true
        try await _normalizeLayoutReason(workspace: workspace, windows: [window])
        XCTAssertTrue(window.parent === macosMinimizedWindowsContainer)
        XCTAssertFalse(window.isWorkspaceNativeHidden)
    }
}
