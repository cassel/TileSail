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

    func testMinimizedOutgoingWindowCannotUndoWorkspaceSwitch() async throws {
        let outgoing = TestWindow.new(id: 401, parent: Workspace.get(byName: "3").rootTilingContainer)
        let incoming = TestWindow.new(id: 402, parent: Workspace.get(byName: "4").rootTilingContainer)
        outgoing.isWorkspaceNativeHidden = true
        outgoing.isMacosMinimizedForTest = true
        XCTAssertTrue(incoming.focusWindow())
        try await updateFocusCache(outgoing)
        XCTAssertEqual(focus.workspace.name, "4")
        XCTAssertTrue(focus.windowOrNil === incoming)
    }

    func testVisibilityPassIgnoresIntermediateNativeFocus() async throws {
        let outgoing = TestWindow.new(id: 403, parent: Workspace.get(byName: "3").rootTilingContainer)
        let incoming = TestWindow.new(id: 404, parent: Workspace.get(byName: "4").rootTilingContainer)
        XCTAssertTrue(incoming.focusWindow())
        workspaceVisibilityUpdateDepth += 1
        defer { workspaceVisibilityUpdateDepth -= 1 }
        try await updateFocusCache(outgoing)
        XCTAssertEqual(focus.workspace.name, "4")
    }

    func testUserRestoredWindowCanStillSelectItsWorkspace() async throws {
        let restored = TestWindow.new(id: 405, parent: Workspace.get(byName: "3").rootTilingContainer)
        let incoming = TestWindow.new(id: 406, parent: Workspace.get(byName: "4").rootTilingContainer)
        restored.isWorkspaceNativeHidden = true
        restored.isMacosMinimizedForTest = false
        XCTAssertTrue(incoming.focusWindow())
        try await updateFocusCache(restored)
        XCTAssertEqual(focus.workspace.name, "3")
        XCTAssertTrue(focus.windowOrNil === restored)
    }


    func testWorkspaceHideDuringAxReadDoesNotLosePlacement() async throws {
        let workspace = Workspace.get(byName: "4")
        let window = TestWindow.new(id: 407, parent: workspace.rootTilingContainer)
        window.onReadMinimized = {
            window.isWorkspaceNativeHidden = true
            window.isMacosMinimizedForTest = true
        }
        try await _normalizeLayoutReason(workspace: workspace, windows: [window])
        window.onReadMinimized = nil
        XCTAssertTrue(window.nodeWorkspace === workspace)
        XCTAssertEqual(window.layoutReason, .standard)
    }

    func testNewHideDuringRestoreCheckKeepsVisibilityOwnership() async throws {
        let workspace = Workspace.get(byName: "4")
        let window = TestWindow.new(id: 408, parent: workspace.rootTilingContainer)
        window.isWorkspaceNativeHidden = true
        window.isWorkspaceRestorePending = true
        window.onReadMinimized = { window.isWorkspaceRestorePending = false }
        try await _normalizeLayoutReason(workspace: workspace, windows: [window])
        window.onReadMinimized = nil
        XCTAssertTrue(window.isWorkspaceNativeHidden)
        XCTAssertTrue(window.nodeWorkspace === workspace)
    }

}
