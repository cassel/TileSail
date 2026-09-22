@testable import AppBundle
import Common
import XCTest

@MainActor
final class AppWorkspaceMemoryTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testFixedSizeStandardWindowsAreRememberedButDialogsAreNot() {
        let calculator: [String: Json] = ["AXSubrole": .string("AXStandardWindow")]
        XCTAssertTrue(calculator.isDialogHeuristic(nil, .normalWindow))
        XCTAssertTrue(calculator.isWorkspaceMemoryWindow(nil))
        let dialog: [String: Json] = ["AXSubrole": .string("AXDialog")]
        XCTAssertFalse(dialog.isWorkspaceMemoryWindow(nil))
        let popup: [String: Json] = ["AXSubrole": .string("AXUnknown")]
        XCTAssertFalse(popup.isWorkspaceMemoryWindow(nil))
    }

    func testReopenAfterQuitAndStoreReloadReturnsToSavedWorkspace() throws {
        let suite = "AppWorkspaceMemoryTest.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AppWorkspaceMemory(defaults: defaults)
        let saved = Workspace.get(byName: "saved")
        let first = TestWindow.new(id: 1, parent: saved.rootTilingContainer)
        store.start(windows: [first], focused: first)
        first.unbindFromParent()
        store.capture(windows: [], focused: nil)
        let reloaded = AppWorkspaceMemory(defaults: defaults)
        reloaded.start(windows: [], focused: nil)
        let current = Workspace.get(byName: "current")
        _ = current.focusWorkspace()
        let reopened = TestWindow.new(id: 2, parent: current.rootTilingContainer)
        XCTAssertTrue(reloaded.restore(reopened, duringStartup: false))
        XCTAssertTrue(reopened.nodeWorkspace === saved)
        // Placement alone must not steal focus from a background app.
        XCTAssertTrue(focus.workspace === current)
    }

    func testRefreshDuringRegistrationCannotOverwriteSavedWorkspace() throws {
        let suite = "AppWorkspaceMemoryTest.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AppWorkspaceMemory(defaults: defaults)
        let saved = Workspace.get(byName: "saved")
        let old = TestWindow.new(id: 1, parent: saved.rootTilingContainer)
        store.start(windows: [old], focused: old)
        old.unbindFromParent()
        store.capture(windows: [], focused: nil)
        let new = TestWindow.new(id: 2, parent: Workspace.get(byName: "current").rootTilingContainer)
        store.beginRegistration(new)
        store.capture(windows: [new], focused: new)
        XCTAssertEqual(store.workspaces[new.app.rawAppBundleId!], "saved")
        XCTAssertTrue(store.restore(new, duringStartup: false))
        store.endRegistration(new)
        XCTAssertTrue(new.nodeWorkspace === saved)
    }

    func testMoveWithoutFollowingUpdatesMemoryAndOtherWindowDoesNotOverwriteIt() throws {
        let suite = "AppWorkspaceMemoryTest.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AppWorkspaceMemory(defaults: defaults)
        let first = TestWindow.new(id: 1, parent: Workspace.get(byName: "a").rootTilingContainer)
        let second = TestWindow.new(id: 2, parent: Workspace.get(byName: "a").rootTilingContainer)
        store.start(windows: [first, second], focused: first)
        second.bind(to: Workspace.get(byName: "b").rootTilingContainer, adaptiveWeight: 1, index: INDEX_BIND_LAST)
        store.capture(windows: [first, second], focused: first)
        store.capture(windows: [second, first], focused: first)
        XCTAssertEqual(store.workspaces[first.app.rawAppBundleId!], "b")
        // Switching to another existing window intentionally updates the app's destination.
        store.capture(windows: [first, second], focused: second)
        store.capture(windows: [first, second], focused: first)
        XCTAssertEqual(store.workspaces[first.app.rawAppBundleId!], "a")
    }

    func testStartupDisabledDialogsAndScratchpadsAreNotRouted() throws {
        let suite = "AppWorkspaceMemoryTest.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AppWorkspaceMemory(defaults: defaults)
        let old = TestWindow.new(id: 1, parent: Workspace.get(byName: "saved").rootTilingContainer)
        store.start(windows: [old], focused: old)
        let current = Workspace.get(byName: "current")
        let new = TestWindow.new(id: 2, parent: current.floatingWindowsContainer)
        XCTAssertFalse(store.restore(new, duringStartup: true))
        store.setEligible(new, false)
        XCTAssertFalse(store.restore(new, duringStartup: false))
        store.capture(windows: [new], focused: new)
        XCTAssertEqual(store.workspaces[old.app.rawAppBundleId!], "saved")
        store.setEligible(new, true)
        new.scratchpadSlot = 1
        XCTAssertFalse(store.restore(new, duringStartup: false))
        new.scratchpadSlot = nil
        store.setEnabled(false)
        XCTAssertFalse(store.restore(new, duringStartup: false))
        XCTAssertFalse(AppWorkspaceMemory(defaults: defaults).isEnabled)
        XCTAssertTrue(new.nodeWorkspace === current)
    }

    func testExplicitWindowRuleOverridesRememberedDestination() async throws {
        let suite = "AppWorkspaceMemoryTest.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AppWorkspaceMemory(defaults: defaults)
        let old = TestWindow.new(id: 1, parent: Workspace.get(byName: "saved").rootTilingContainer)
        store.start(windows: [old], focused: old)
        let new = TestWindow.new(id: 2, parent: Workspace.get(byName: "current").rootTilingContainer)
        config.onWindowDetected = [WindowDetectedCallback(
            matcher: .command(.empty), rawRun: parseCommand("move-node-to-workspace explicit").cmdOrDie,
        )]
        XCTAssertTrue(store.restore(new, duringStartup: false))
        await tryOnWindowDetected(new)
        XCTAssertEqual(new.nodeWorkspace?.name, "explicit")
    }
}
