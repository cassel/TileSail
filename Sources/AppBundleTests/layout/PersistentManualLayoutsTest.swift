@testable import AppBundle
import XCTest

@MainActor
final class PersistentManualLayoutsTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testCaptureAndRestoreNestedTreeOrderAndWeights() async throws {
        let suiteName = "PersistentManualLayoutsTest.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = PersistentManualLayoutStore(defaults: defaults)
        let root = Workspace.get(byName: name).rootTilingContainer
        let first = TestWindow.new(id: 1, parent: root, adaptiveWeight: 3)
        let nested = TilingContainer.newVTiles(parent: root, adaptiveWeight: 1)
        let second = TestWindow.new(id: 2, parent: nested, adaptiveWeight: 2)
        let third = TestWindow.new(id: 3, parent: nested, adaptiveWeight: 1)

        await store.capture()

        third.bind(to: root, adaptiveWeight: 7, index: 0)
        first.bind(to: root, adaptiveWeight: 7, index: INDEX_BIND_LAST)
        second.bind(to: root, adaptiveWeight: 7, index: INDEX_BIND_LAST)
        nested.unbindFromParent()
        root.changeOrientation(.v)
        root.layout = .accordion

        await store.restore()

        assertEquals(root.layoutDescription, .h_tiles([.window(1), .v_tiles([.window(2), .window(3)])]))
        assertEquals(first.getWeight(.h), 3)
        let restoredNested = try XCTUnwrap(root.children.getOrNil(atIndex: 1) as? TilingContainer)
        assertEquals(restoredNested.getWeight(.h), 1)
        assertEquals(second.getWeight(.v), 2)
        assertEquals(third.getWeight(.v), 1)
    }

    func testAutomaticWorkspaceIsCapturedAndRestored() async throws {
        let suiteName = "PersistentManualLayoutsTest.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        SmoothLayoutSettingsStore.shared.replaceProfilesForTests([
            "Test Monitor": SmoothMonitorLayoutProfile(
                monitorName: "Test Monitor",
                enabled: true,
                tileLimit: 10,
                styles: Array(repeating: .dwindle, count: SmoothMonitorLayoutProfile.configuredWindowCount),
            ),
        ])
        let store = PersistentManualLayoutStore(defaults: defaults)
        let workspace = Workspace.get(byName: name)
        let root = workspace.rootTilingContainer
        let first = TestWindow.new(id: 1, parent: root)
        TestWindow.new(id: 2, parent: root)
        reconcileSmoothWorkspaceLayouts()
        first.setWeight(.h, 3)
        await store.capture()
        let saved = root.layoutDescription
        first.bind(to: root, adaptiveWeight: 7, index: INDEX_BIND_LAST)
        let reloaded = PersistentManualLayoutStore(defaults: defaults)
        await reloaded.restore()
        reconcileSmoothWorkspaceLayouts()
        assertEquals(root.layoutDescription, saved)
        assertEquals(first.getWeight(.h), 3)
        XCTAssertEqual(reloaded.layouts.count, 1)
    }
    func testEmptyDiscoveryPreservesSavedLayout() async throws {
        let suite = "PersistentManualLayoutsTest.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = PersistentManualLayoutStore(defaults: defaults)
        let window = TestWindow.new(id: 1, parent: Workspace.get(byName: name).rootTilingContainer)
        await store.capture()
        let saved = store.layouts
        window.unbindFromParent()
        await store.capture()
        XCTAssertEqual(PersistentManualLayoutStore(defaults: defaults).layouts, saved)
    }

    func testStartupRecoversWorkspaceMembershipBeforeRestoringTree() async throws {
        let suite = "PersistentManualLayoutsTest.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = PersistentManualLayoutStore(defaults: defaults)
        let original = Workspace.get(byName: name)
        let other = Workspace.get(byName: "other")
        let first = TestWindow.new(id: 1, parent: original.rootTilingContainer, adaptiveWeight: 3)
        let second = TestWindow.new(id: 2, parent: original.rootTilingContainer, adaptiveWeight: 1)
        await store.capture()
        first.bind(to: other.rootTilingContainer, adaptiveWeight: 1, index: INDEX_BIND_LAST)
        second.bind(to: other.rootTilingContainer, adaptiveWeight: 1, index: INDEX_BIND_LAST)
        let reloaded = PersistentManualLayoutStore(defaults: defaults)
        await reloaded.restoreAfterInitialRefresh()
        XCTAssertTrue(first.nodeWorkspace === original)
        XCTAssertTrue(second.nodeWorkspace === original)
        assertEquals(first.getWeight(.h), 3)
    }

    func testMonitorIdentitySurvivesSwappedOrigins() {
        let left = CGPoint(x: 0, y: 0)
        let right = CGPoint(x: 1920, y: 0)
        let mapping = matchMonitorOrigins(
            oldIdentities: [left: "built-in", right: "external"],
            newIdentities: [left: "external", right: "built-in"],
            occupied: [left, right],
        )
        XCTAssertEqual(mapping[left], right)
        XCTAssertEqual(mapping[right], left)
    }

    func testQuitRecoveryUsesExternalMonitorOrigin() {
        let visible = Rect(topLeftX: -1920, topLeftY: 100, width: 1920, height: 1080)
        XCTAssertEqual(
            terminationWindowOrigin(visibleRect: visible, windowSize: CGSize(width: 1000, height: 800)),
            CGPoint(x: -1460, y: 240),
        )
    }

    func testMovingWindowRemovesStaleWorkspaceAndRecordsOneVisibleWorkspace() async throws {
        defer { _ = mainMonitorInfo.setActiveWorkspace(Workspace.get(byName: "setUpWorkspacesForTests")) }
        let suite = "PersistentManualLayoutsTest.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = PersistentManualLayoutStore(defaults: defaults)
        let old = Workspace.get(byName: "3")
        let new = Workspace.get(byName: "4")
        XCTAssertTrue(mainMonitorInfo.setActiveWorkspace(old))
        let window = TestWindow.new(id: 201, parent: old.rootTilingContainer)
        await store.capture()
        window.bind(to: new.rootTilingContainer, adaptiveWeight: 1, index: INDEX_BIND_LAST)
        XCTAssertTrue(mainMonitorInfo.setActiveWorkspace(new))
        await store.capture()
        XCTAssertNil(store.layouts["3"])
        XCTAssertEqual(store.layouts["4"]?.root.windowIdentities.first?.nativeWindowId, 201)
        XCTAssertEqual(store.layouts["4"]?.wasVisible, true)
        let active = defaults.dictionary(forKey: "AeroSpaceSmooth.active-workspaces-by-monitor.v1") as? [String: String]
        XCTAssertEqual(active?[mainMonitorInfo.stableIdentifier], "4")
    }

    func testStartupRestoresFloatingWindowWorkspace() async throws {
        defer { _ = mainMonitorInfo.setActiveWorkspace(Workspace.get(byName: "setUpWorkspacesForTests")) }
        let suite = "PersistentManualLayoutsTest.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = PersistentManualLayoutStore(defaults: defaults)
        let original = Workspace.get(byName: "7")
        let other = Workspace.get(byName: "3")
        let window = TestWindow.new(id: 202, parent: original.floatingWindowsContainer)
        await store.capture()
        window.bindAsFloatingWindow(to: other)
        let reloaded = PersistentManualLayoutStore(defaults: defaults)
        await reloaded.restoreAfterInitialRefresh()
        XCTAssertTrue(window.nodeWorkspace === original)
        XCTAssertTrue(window.parent === original.floatingWindowsContainer)
    }

    func testStartupRestoresFloatingStateWithinSameWorkspace() async throws {
        let suite = "PersistentManualLayoutsTest.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = PersistentManualLayoutStore(defaults: defaults)
        let workspace = Workspace.get(byName: name)
        let window = TestWindow.new(id: 204, parent: workspace.floatingWindowsContainer)
        await store.capture()
        window.bind(to: workspace.rootTilingContainer, adaptiveWeight: 1, index: INDEX_BIND_LAST)
        let reloaded = PersistentManualLayoutStore(defaults: defaults)
        await reloaded.restoreAfterInitialRefresh()
        XCTAssertTrue(window.parent === workspace.floatingWindowsContainer)
        await reloaded.restoreAfterInitialRefresh()
        XCTAssertTrue(window.parent === workspace.floatingWindowsContainer)
        XCTAssertEqual(workspace.floatingWindows.count, 1)
    }

    func testStartupRestoresTiledStateWithinSameWorkspace() async throws {
        let suite = "PersistentManualLayoutsTest.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = PersistentManualLayoutStore(defaults: defaults)
        let workspace = Workspace.get(byName: name)
        let window = TestWindow.new(id: 205, parent: workspace.rootTilingContainer)
        await store.capture()
        window.bindAsFloatingWindow(to: workspace)
        let reloaded = PersistentManualLayoutStore(defaults: defaults)
        await reloaded.restoreAfterInitialRefresh()
        XCTAssertTrue(window.parent === workspace.rootTilingContainer)
        XCTAssertTrue(workspace.floatingWindows.isEmpty)
    }

    func testStartupMatchesStableNativeIdAfterTitleChanges() async throws {
        defer { _ = mainMonitorInfo.setActiveWorkspace(Workspace.get(byName: "setUpWorkspacesForTests")) }
        let suite = "PersistentManualLayoutsTest.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = PersistentManualLayoutStore(defaults: defaults)
        let original = Workspace.get(byName: "4")
        let other = Workspace.get(byName: "3")
        let window = TestWindow.new(id: 203, parent: original.rootTilingContainer)
        window.persistentLayoutTitle = "Before"
        await store.capture()
        window.bind(to: other.rootTilingContainer, adaptiveWeight: 1, index: INDEX_BIND_LAST)
        window.persistentLayoutTitle = "After"
        let reloaded = PersistentManualLayoutStore(defaults: defaults)
        await reloaded.restoreAfterInitialRefresh()
        XCTAssertTrue(window.nodeWorkspace === original)
    }

}
