import AppKit
import Combine
import Common
import SwiftUI

@MainActor
final class WorkspaceBarSettings: ObservableObject {
    static let shared = WorkspaceBarSettings()

    private static let enabledKey = "AeroSpaceSmooth.workspace-bar.enabled"
    private static let showEmptyKey = "AeroSpaceSmooth.workspace-bar.show-empty"
    private let defaults: UserDefaults

    @Published private(set) var isEnabled: Bool
    @Published private(set) var showsEmptyWorkspaces: Bool

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = defaults.bool(forKey: Self.enabledKey)
        showsEmptyWorkspaces = defaults.object(forKey: Self.showEmptyKey) as? Bool ?? true
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        defaults.set(enabled, forKey: Self.enabledKey)
        WorkspaceBarController.shared.refresh()
        guard !isUnitTest, let token = RunSessionGuard.isServerEnabled else { return }
        Task.startUnstructured { @MainActor in
            try await runLightSession(.menuBarButton, token) {}
        }
    }

    func setShowsEmptyWorkspaces(_ show: Bool) {
        showsEmptyWorkspaces = show
        defaults.set(show, forKey: Self.showEmptyKey)
        WorkspaceBarController.shared.refresh()
    }
}

/// Shared geometry keeps the panel and the tiling exclusion area in agreement.
struct WorkspaceBarGeometry {
    static let height: CGFloat = 20
    static let dotPitch: CGFloat = 16
    let frame: NSRect
    let reservedTopInset: CGFloat

    init(
        screenFrame: NSRect, visibleFrame: NSRect, safeAreaTop: CGFloat, itemCount: Int,
        hasCameraHousing: Bool = false, menuBarHeight: CGFloat = 0, menuItemsOverlap: Bool = false,
    ) {
        let contentTop = min(visibleFrame.maxY, screenFrame.maxY - max(safeAreaTop, menuBarHeight))
        let topStrip = screenFrame.maxY - contentTop
        let fitsMenuBar = !hasCameraHousing && safeAreaTop == 0 &&
            topStrip >= Self.height && !menuItemsOverlap
        let width = min(max(0, visibleFrame.width - 16), 30 + CGFloat(itemCount) * Self.dotPitch)
        reservedTopInset = fitsMenuBar ? max(0, visibleFrame.maxY - contentTop) :
            visibleFrame.maxY - contentTop + Self.height + 4
        frame = NSRect(
            x: visibleFrame.midX - width / 2,
            y: fitsMenuBar
                ? contentTop + (topStrip - Self.height) / 2
                : contentTop - Self.height - 2,
            width: width,
            height: Self.height,
        )
    }
}

/// Width occupied at either edge of the menu bar. macOS may expose the menu
/// items on only one display, so apply the occupied widths to every display.
struct WorkspaceBarMenuOccupancy: Equatable, Sendable {
    var left: CGFloat = 0
    var right: CGFloat = 0

    func overlaps(screenWidth: CGFloat, barWidth: CGFloat) -> Bool {
        let start = (screenWidth - barWidth) / 2
        return start < left + 8 || start + barWidth > screenWidth - right - 8
    }

    static func read(pids: [pid_t], frontmost: pid_t?, screens: [CGRect]) -> Self? {
        var result = Self()
        var foundExtras = false
        for pid in pids {
            let app = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(app, 0.05)
            let keys = pid == frontmost ? ["AXMenuBar", "AXExtrasMenuBar"] : ["AXExtrasMenuBar"]
            for key in keys {
                var raw: CFTypeRef?
                guard unsafe AXUIElementCopyAttributeValue(app, key as CFString, &raw) == .success,
                      let raw, CFGetTypeID(raw) == AXUIElementGetTypeID() else { continue }
                let menu = raw as! AXUIElement
                var children: CFTypeRef?
                guard unsafe AXUIElementCopyAttributeValue(menu, kAXChildrenAttribute as CFString, &children) == .success,
                      let items = children as? [AXUIElement] else { continue }
                for item in items {
                    var position: CFTypeRef?
                    var size: CFTypeRef?
                    guard unsafe AXUIElementCopyAttributeValue(item, kAXPositionAttribute as CFString, &position) == .success,
                          unsafe AXUIElementCopyAttributeValue(item, kAXSizeAttribute as CFString, &size) == .success,
                          let position, let size,
                          CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID()
                    else { continue }
                    var point = CGPoint.zero
                    var dimensions = CGSize.zero
                    guard unsafe AXValueGetValue(position as! AXValue, .cgPoint, &point),
                          unsafe AXValueGetValue(size as! AXValue, .cgSize, &dimensions),
                          dimensions.width > 0, dimensions.height > 0 else { continue }
                    let rect = CGRect(origin: point, size: dimensions)
                    guard let screen = screens.first(where: {
                        $0.contains(CGPoint(x: rect.midX, y: rect.midY)) && rect.minY < $0.minY + 80
                    }), rect.width < screen.width / 2 else { continue }
                    if key == "AXMenuBar" {
                        result.left = max(result.left, rect.maxX - screen.minX)
                    } else {
                        foundExtras = true
                        result.right = max(result.right, screen.maxX - rect.minX)
                    }
                }
            }
        }
        return foundExtras ? result : nil
    }
}

private struct WorkspaceBarItem: Identifiable {
    let name: String
    let isActive: Bool
    let isFocused: Bool
    let windowCount: Int

    var id: String { name }
}

private struct WorkspaceBarSnapshot {
    let monitorName: String
    let items: [WorkspaceBarItem]
}

@MainActor
final class WorkspaceBarController {
    static let shared = WorkspaceBarController()

    private var panels: [String: NSPanel] = [:]
    private var geometries: [String: WorkspaceBarGeometry] = [:]
    private var menuOccupancy: WorkspaceBarMenuOccupancy?
    private var scanInProgress = false
    private var lastScan = Date.distantPast
    private var timer: Timer?

    func reservedTopInset(for monitor: MonitorInfo) -> CGFloat {
        geometries[monitor.stableIdentifier]?.reservedTopInset ?? 0
    }

    private func scanMenuItemsIfNeeded() {
        guard !scanInProgress, Date().timeIntervalSince(lastScan) >= 3 else { return }
        scanInProgress = true
        lastScan = Date()
        let pids = NSWorkspace.shared.runningApplications.map(\.processIdentifier)
        let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let primaryTop = NSScreen.screens.first(where: { $0.frame.origin == .zero })?.frame.maxY ?? 0
        let screens = NSScreen.screens.map {
            CGRect(x: $0.frame.minX, y: primaryTop - $0.frame.maxY, width: $0.frame.width, height: $0.frame.height)
        }
        Task.startUnstructured { @MainActor in
            let occupancy = await Task.detached(priority: .utility) {
                WorkspaceBarMenuOccupancy.read(pids: pids, frontmost: frontmost, screens: screens)
            }.value
            self.scanInProgress = false
            guard self.menuOccupancy != occupancy else { return }
            self.menuOccupancy = occupancy
            guard let token = RunSessionGuard.isServerEnabled else { return }
            try await runLightSession(.menuBarButton, token) {}
        }
    }

    private init() {}

    func refresh() {
        guard !isUnitTest else { return }
        let settings = WorkspaceBarSettings.shared
        guard settings.isEnabled, TrayMenuModel.shared.isEnabled else {
            hideAll()
            return
        }

        if timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
                Task.startUnstructured { @MainActor in
                    guard let self, WorkspaceBarSettings.shared.isEnabled,
                          let token = RunSessionGuard.isServerEnabled else { return }
                    // Also reflow the grid if the menu bar visibility or display geometry changed.
                    let before = self.geometries.mapValues(\.reservedTopInset)
                    self.refresh()
                    if before != self.geometries.mapValues(\.reservedTopInset) {
                        try await runLightSession(.menuBarButton, token) {}
                    }
                }
            }
        }
        scanMenuItemsIfNeeded()
        let monitors = sortedMonitorInfos
        let activeIdentifiers = Set(monitors.map(\.stableIdentifier))
        for identifier in panels.keys where !activeIdentifiers.contains(identifier) {
            panels.removeValue(forKey: identifier)?.close()
            geometries.removeValue(forKey: identifier)
        }

        for monitor in monitors {
            guard let screen = NSScreen.screens.getOrNil(atIndex: monitor.monitorAppKitNsScreenScreensId - 1) else { continue }
            let workspaces = Workspace.all
                .filter { workspace in
                    workspace.isUserFacing &&
                        workspace.workspaceMonitor.stableIdentifier == monitor.stableIdentifier &&
                        (settings.showsEmptyWorkspaces || workspace.isVisible || !workspace.isEffectivelyEmpty)
                }
                .sorted()
            let snapshot = WorkspaceBarSnapshot(
                monitorName: monitor.name,
                items: workspaces.map { workspace in
                    WorkspaceBarItem(
                        name: workspace.name,
                        isActive: monitor.activeWorkspace == workspace,
                        isFocused: focus.workspace == workspace,
                        windowCount: workspace.allLeafWindowsRecursive.count,
                    )
                },
            )
            let panel = panels[monitor.stableIdentifier] ?? makePanel()
            panels[monitor.stableIdentifier] = panel
            panel.contentViewController = NSHostingController(rootView: WorkspaceBarView(snapshot: snapshot))
            let width = min(screen.visibleFrame.width - 16, 30 + CGFloat(snapshot.items.count) * WorkspaceBarGeometry.dotPitch)
            let hasCameraHousing = screen.safeAreaInsets.top > 0 ||
                (screen.auxiliaryTopLeftArea != nil && screen.auxiliaryTopRightArea != nil)
            // Until macOS provides item bounds, use the safe position below the menu.
            let overlaps = menuOccupancy?.overlaps(screenWidth: screen.frame.width, barWidth: width) ?? true
            let geometry = WorkspaceBarGeometry(
                screenFrame: screen.frame, visibleFrame: screen.visibleFrame,
                safeAreaTop: screen.safeAreaInsets.top, itemCount: snapshot.items.count,
                hasCameraHousing: hasCameraHousing,
                menuBarHeight: max(NSStatusBar.system.thickness, screen.safeAreaInsets.top),
                menuItemsOverlap: overlaps,
            )
            geometries[monitor.stableIdentifier] = geometry
            panel.level = geometry.frame.minY >= screen.visibleFrame.maxY ? .statusBar : .floating
            panel.setFrame(geometry.frame, display: true)
            if snapshot.items.isEmpty {
                panel.orderOut(nil)
            } else {
                panel.orderFrontRegardless()
            }
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false,
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        return panel
    }

    private func hideAll() {
        timer?.invalidate()
        timer = nil
        geometries.removeAll()
        for panel in panels.values { panel.orderOut(nil) }
    }
}

@MainActor
private struct WorkspaceBarView: View {
    let snapshot: WorkspaceBarSnapshot

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: "display")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 22)
                .help(snapshot.monitorName)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(snapshot.items) { item in
                        Button {
                            focusWorkspace(named: item.name)
                        } label: {
                            Circle()
                                .fill(item.isActive ? Color.accentColor : Color.secondary.opacity(0.55))
                                .frame(width: item.isActive ? 7 : 5, height: item.isActive ? 7 : 5)
                                .overlay {
                                    if item.isFocused {
                                        Circle().stroke(Color.primary.opacity(0.75), lineWidth: 1)
                                            .frame(width: 10, height: 10)
                                    }
                                }
                                .frame(width: WorkspaceBarGeometry.dotPitch, height: WorkspaceBarGeometry.height)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Workspace \(item.name), \(item.windowCount) windows")
                        .accessibilityValue(item.isActive ? "Active" : "Inactive")
                        .help("\(item.name) · \(item.windowCount) windows")
                    }
                }
            }
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.12)))
    }

    private func focusWorkspace(named name: String) {
        guard let token: RunSessionGuard = .isServerEnabled else { return }
        Task.startUnstructured { @MainActor in
            try await runLightSession(.menuBarButton, token) {
                _ = Workspace.get(byName: name).focusWorkspace()
            }
        }
    }
}
