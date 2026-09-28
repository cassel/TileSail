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

    init(screenFrame: NSRect, visibleFrame: NSRect, safeAreaTop: CGFloat, itemCount: Int) {
        let topStrip = screenFrame.maxY - visibleFrame.maxY
        let fitsMenuBar = safeAreaTop == 0 && topStrip >= Self.height
        let width = min(max(0, visibleFrame.width - 16), 30 + CGFloat(itemCount) * Self.dotPitch)
        reservedTopInset = fitsMenuBar ? 0 : Self.height + 4
        frame = NSRect(
            x: visibleFrame.midX - width / 2,
            y: fitsMenuBar
                ? visibleFrame.maxY + (topStrip - Self.height) / 2
                : visibleFrame.maxY - Self.height - 2,
            width: width,
            height: Self.height,
        )
    }
}

extension NSScreen {
    func workspaceBarGeometry(itemCount: Int = 0) -> WorkspaceBarGeometry {
        WorkspaceBarGeometry(
            screenFrame: frame, visibleFrame: visibleFrame,
            safeAreaTop: safeAreaInsets.top, itemCount: itemCount,
        )
    }
}

private struct WorkspaceBarItem: Identifiable {
    let name: String
    let isActive: Bool
    let isFocused: Bool
    let windowCount: Int
    let hasFullscreenWindow: Bool

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

    private init() {}

    func refresh() {
        guard !isUnitTest else { return }
        let settings = WorkspaceBarSettings.shared
        guard settings.isEnabled, TrayMenuModel.shared.isEnabled else {
            hideAll()
            return
        }

        let monitors = sortedMonitorInfos
        let activeIdentifiers = Set(monitors.map(\.stableIdentifier))
        for identifier in panels.keys where !activeIdentifiers.contains(identifier) {
            panels.removeValue(forKey: identifier)?.close()
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
                        hasFullscreenWindow: workspace.allLeafWindowsRecursive.contains(where: \.isFullscreen),
                    )
                },
            )
            let panel = panels[monitor.stableIdentifier] ?? makePanel()
            panels[monitor.stableIdentifier] = panel
            panel.contentViewController = NSHostingController(rootView: WorkspaceBarView(snapshot: snapshot))
            let geometry = screen.workspaceBarGeometry(itemCount: snapshot.items.count)
            panel.level = geometry.reservedTopInset == 0 ? .statusBar : .floating
            panel.setFrame(geometry.frame, display: true)
            // Fullscreen windows do not respect outer gaps; keep their controls clear.
            if snapshot.items.isEmpty || (geometry.reservedTopInset > 0 &&
                snapshot.items.contains(where: { $0.isActive && $0.hasFullscreenWindow })) {
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
