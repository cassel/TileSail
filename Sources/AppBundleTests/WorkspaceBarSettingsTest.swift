@testable import AppBundle
import AppKit
import XCTest

@MainActor
final class WorkspaceBarSettingsTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testExternalBarStaysInsideMenuStrip() {
        let visible = NSRect(x: -1920, y: 0, width: 1920, height: 1056)
        let bar = WorkspaceBarGeometry(
            screenFrame: NSRect(x: -1920, y: 0, width: 1920, height: 1080),
            visibleFrame: visible, safeAreaTop: 0, itemCount: 4,
        )
        assertEquals(bar.reservedTopInset, 0)
        assertEquals(bar.frame.width, 94)
        assertEquals(bar.frame.midX, visible.midX)
        assertTrue(bar.frame.minY >= visible.maxY)
        assertTrue(bar.frame.maxY <= 1080)
    }

    func testNotchAndHiddenMenuBarReserveSpaceAboveGrid() {
        for (menuHeight, notch) in [(CGFloat(38), CGFloat(38)), (0, 0)] {
            let visible = NSRect(x: 0, y: 0, width: 1512, height: 982 - menuHeight)
            let bar = WorkspaceBarGeometry(
                screenFrame: NSRect(x: 0, y: 0, width: 1512, height: 982),
                visibleFrame: visible, safeAreaTop: notch, itemCount: 5,
            )
            assertEquals(bar.reservedTopInset, 24)
            assertTrue(bar.frame.maxY < visible.maxY)
            assertTrue(bar.frame.minY > visible.maxY - bar.reservedTopInset)
        }
    }

    func testManyWorkspacesFitNarrowPortraitMonitor() {
        let visible = NSRect(x: 0, y: 0, width: 320, height: 1056)
        let bar = WorkspaceBarGeometry(
            screenFrame: NSRect(x: 0, y: 0, width: 320, height: 1080),
            visibleFrame: visible, safeAreaTop: 0, itemCount: 100,
        )
        assertTrue(bar.frame.minX >= visible.minX)
        assertTrue(bar.frame.maxX <= visible.maxX)
        assertEquals(bar.frame.height, 20)
    }

    func testMenuIconsPushCompactBarBelowMenu() {
        let screen = NSRect(x: -1296, y: -728, width: 1296, height: 2304)
        let visible = NSRect(x: -1296, y: -728, width: 1296, height: 2274)
        let occupancy = WorkspaceBarMenuOccupancy(left: 300, right: 720)
        let overlaps = occupancy.overlaps(screenWidth: screen.width, barWidth: 62)
        assertTrue(overlaps)
        assertFalse(occupancy.overlaps(screenWidth: 3780, barWidth: 94))
        let bar = WorkspaceBarGeometry(
            screenFrame: screen, visibleFrame: visible, safeAreaTop: 0, itemCount: 2,
            menuBarHeight: 30, menuItemsOverlap: overlaps,
        )
        assertEquals(bar.frame.width, 62)
        assertEquals(bar.reservedTopInset, 24)
        assertTrue(bar.frame.maxY < visible.maxY)
    }

    func testCameraHousingKeepsBarBelowEvenWithoutSafeAreaReport() {
        let screen = NSRect(x: 0, y: 0, width: 1512, height: 982)
        let bar = WorkspaceBarGeometry(
            screenFrame: screen, visibleFrame: screen, safeAreaTop: 0, itemCount: 2,
            hasCameraHousing: true, menuBarHeight: 33,
        )
        assertTrue(bar.frame.maxY < screen.maxY - 33)
        assertEquals(bar.reservedTopInset, 57)
        assertTrue(bar.frame.minY > screen.maxY - bar.reservedTopInset)
    }

    func testAppMenusAlsoTriggerCollision() {
        assertTrue(WorkspaceBarMenuOccupancy(left: 650, right: 100).overlaps(screenWidth: 1296, barWidth: 94))
        assertFalse(WorkspaceBarMenuOccupancy(left: 300, right: 300).overlaps(screenWidth: 1296, barWidth: 94))
    }

    func testPreferencesPersistAcrossStoreInstances() throws {
        let suiteName = "WorkspaceBarSettingsTest.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = WorkspaceBarSettings(defaults: defaults)

        assertFalse(store.isEnabled)
        assertTrue(store.showsEmptyWorkspaces)
        store.setEnabled(true)
        store.setShowsEmptyWorkspaces(false)

        let reopened = WorkspaceBarSettings(defaults: defaults)
        assertTrue(reopened.isEnabled)
        assertFalse(reopened.showsEmptyWorkspaces)
    }

    func testTrayNeverPublishesInternalWorkspaceNames() {
        let scratchpad = Workspace.get(byName: "_smooth-scratchpad-2")
        TestWindow.new(id: 20, parent: scratchpad.floatingWindowsContainer)
        assertTrue(scratchpad.focusWorkspace())

        updateTrayText()

        assertFalse(TrayMenuModel.shared.trayText.contains("_smooth-"))
        assertFalse(TrayMenuModel.shared.activeWorkspaceNames.contains { $0.hasPrefix("_smooth-") })
        assertFalse(TrayMenuModel.shared.workspaces.contains { $0.name.hasPrefix("_smooth-") })
    }

    func testMenuBarPresentationDefaultsAndPersists() throws {
        let suiteName = "MenuBarAppearanceSettingsTest.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = MenuBarAppearanceSettings(defaults: defaults)

        assertEquals(settings.presentation, .focusedWorkspace)
        assertEquals(MenuBarPresentation.activeWorkspaces.rawValue, "allDisplays")
        settings.setPresentation(.iconOnly)

        let reopened = MenuBarAppearanceSettings(defaults: defaults)
        assertEquals(reopened.presentation, .iconOnly)
    }

    func testLegacyI3MenuBarPresentationsAreMigrated() throws {
        let suiteName = "MenuBarAppearanceMigrationTest.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set("i3", forKey: "displayStyle")
        assertEquals(MenuBarAppearanceSettings(defaults: defaults).presentation, .i3Grouped)

        defaults.set("i3Ordered", forKey: "displayStyle")
        assertEquals(MenuBarAppearanceSettings(defaults: defaults).presentation, .i3Ordered)
    }
}
