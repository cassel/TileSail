import Combine
import Common
import Foundation

struct PersistentWindowIdentity: Codable, Hashable, Sendable {
    let applicationIdentifier: String
    let title: String
    let titleOccurrence: Int
    let applicationOccurrence: Int
    var nativeWindowId: UInt32? = nil
}

struct PersistentLayoutNode: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case container
        case window
    }

    let kind: Kind
    let weight: Double
    let orientation: String?
    let layout: String?
    let window: PersistentWindowIdentity?
    let children: [PersistentLayoutNode]

    var windowIdentities: [PersistentWindowIdentity] {
        window.map { [$0] } ?? children.flatMap(\.windowIdentities)
    }
}

struct PersistentWorkspaceLayout: Codable, Equatable, Sendable {
    let workspaceName: String
    let monitorIdentifier: String
    let root: PersistentLayoutNode
    var wasVisible: Bool? = nil
    var automaticProfile: SmoothMonitorLayoutProfile? = nil
}

@MainActor
final class PersistentManualLayoutStore: ObservableObject {
    static let shared = PersistentManualLayoutStore()

    private static let layoutsKey = "AeroSpaceSmooth.manual-workspace-layouts.v1"
    private static let enabledKey = "AeroSpaceSmooth.restore-manual-workspace-layouts"
    private let defaults: UserDefaults
    private var isReadyToCapture = false

    @Published private(set) var isEnabled: Bool
    @Published private(set) var layouts: [String: PersistentWorkspaceLayout]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = defaults.object(forKey: Self.enabledKey) as? Bool ?? true
        layouts = defaults.data(forKey: Self.layoutsKey)
            .flatMap { try? JSONDecoder().decode([String: PersistentWorkspaceLayout].self, from: $0) }
            ?? [:]
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        defaults.set(enabled, forKey: Self.enabledKey)
    }

    func clear() {
        layouts = [:]
        persist()
    }

    func restoreAfterInitialRefresh() async {
        defer { isReadyToCapture = true }
        guard isEnabled else { return }
        await restoreWindowPlacement()
        reconcileSmoothWorkspaceLayouts()
        await restore()
    }

    func captureIfReady() async {
        guard isReadyToCapture else { return }
        await capture()
    }

    func capture() async {
        guard isEnabled else { return }
        var updated = layouts

        for workspace in Workspace.all where workspace.isUserFacing {
            let monitor = workspace.workspaceMonitor
            let profile = SmoothLayoutSettingsStore.shared.profile(for: monitor)
            let windows = workspace.rootTilingContainer.allLeafWindowsRecursive
            // Empty discovery during shutdown must not erase the last usable layout.
            guard !windows.isEmpty else { continue }

            let identities = await windowIdentities(windows)
            let root = captureNode(workspace.rootTilingContainer, weight: 1, identities: identities)
            updated[workspace.name] = PersistentWorkspaceLayout(
                workspaceName: workspace.name,
                monitorIdentifier: monitor.stableIdentifier,
                root: root,
                wasVisible: workspace.isVisible,
                automaticProfile: profile.enabled ? profile : nil,
            )
        }

        if updated != layouts {
            layouts = updated
            persist()
        }
    }

    func restore() async {
        guard isEnabled else { return }

        for workspace in Workspace.all where workspace.isUserFacing {
            guard let saved = layouts[workspace.name] else { continue }
            let monitor = workspace.workspaceMonitor
            guard saved.workspaceName == workspace.name,
                  saved.monitorIdentifier == monitor.stableIdentifier
            else { continue }
            let profile = SmoothLayoutSettingsStore.shared.profile(for: monitor)
            // A changed preset is intentional and takes precedence over the saved tree.
            guard saved.automaticProfile == (profile.enabled ? profile : nil) else { continue }

            let windows = workspace.rootTilingContainer.allLeafWindowsRecursive
            guard windows.count == saved.root.windowIdentities.count, !windows.isEmpty else { continue }
            let currentIdentities = await windowIdentities(windows)
            guard let matchedWindows = matchWindows(
                saved.root.windowIdentities,
                currentWindows: windows,
                currentIdentities: currentIdentities,
            ) else { continue }

            restorePersistentLayout(saved.root, in: workspace, windows: matchedWindows)
            preserveCurrentSmoothWorkspaceTreeAfterUserCommand(workspace)
        }
    }

    // Startup discovery puts every window on a monitor into its active workspace.
    // Recover workspace membership before attempting to reconstruct individual trees.
    private func restoreWindowPlacement() async {
        let windows = Workspace.all.flatMap { $0.rootTilingContainer.allLeafWindowsRecursive }
        let identities = await windowIdentities(windows)
        let savedIdentities = layouts.values.flatMap { $0.root.windowIdentities }
        var used: Set<UInt32> = []
        for saved in layouts.values.sorted(by: { $0.workspaceName < $1.workspaceName }) {
            guard let monitor = monitorInfos.first(where: { $0.stableIdentifier == saved.monitorIdentifier }) else { continue }
            let profile = SmoothLayoutSettingsStore.shared.profile(for: monitor)
            guard saved.automaticProfile == (profile.enabled ? profile : nil) else { continue }
            let workspace = Workspace.get(byName: saved.workspaceName)
            if saved.wasVisible == true {
                guard monitor.setActiveWorkspace(workspace) else { continue }
            } else {
                guard workspace.assign(to: monitor) else { continue }
            }
            for identity in saved.root.windowIdentities {
                let candidates = windows.filter { window in
                    guard !used.contains(window.windowId), let current = identities[window.windowId] else { return false }
                    return current.applicationIdentifier == identity.applicationIdentifier && current.title == identity.title
                }
                let sameNative = candidates.first { $0.windowId == identity.nativeWindowId }
                let uniqueTitle = !identity.title.isEmpty && candidates.count == 1 && savedIdentities.filter {
                    $0.applicationIdentifier == identity.applicationIdentifier && $0.title == identity.title
                }.count == 1
                guard let window = sameNative ?? (uniqueTitle ? candidates.first : nil) else { continue }
                used.insert(window.windowId)
                if window.nodeWorkspace != workspace {
                    window.bind(to: workspace.rootTilingContainer, adaptiveWeight: 1, index: INDEX_BIND_LAST)
                }
            }
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(layouts) else { return }
        defaults.set(data, forKey: Self.layoutsKey)
    }
}

@MainActor
private func windowIdentities(_ windows: [Window]) async -> [UInt32: PersistentWindowIdentity] {
    var applicationCounts: [String: Int] = [:]
    var titleCounts: [String: Int] = [:]
    var result: [UInt32: PersistentWindowIdentity] = [:]

    for window in windows {
        let applicationIdentifier = window.app.rawAppBundleId ?? window.app.execPath ?? window.app.name ?? "unknown-application"
        let title: String
        if let cached = window.persistentLayoutTitle {
            title = cached
        } else {
            title = (try? await window.getTitle(.nonCancellable)) ?? ""
            window.persistentLayoutTitle = title
        }
        let titleKey = "\(applicationIdentifier)\u{1f}\(title)"
        let identity = PersistentWindowIdentity(
            applicationIdentifier: applicationIdentifier,
            title: title,
            titleOccurrence: titleCounts[titleKey, default: 0],
            applicationOccurrence: applicationCounts[applicationIdentifier, default: 0],
            nativeWindowId: window.windowId,
        )
        titleCounts[titleKey, default: 0] += 1
        applicationCounts[applicationIdentifier, default: 0] += 1
        result[window.windowId] = identity
    }
    return result
}

@MainActor
private func captureNode(
    _ node: TreeNode,
    weight: Double,
    identities: [UInt32: PersistentWindowIdentity],
) -> PersistentLayoutNode {
    switch node.nodeCases {
        case .window(let window):
            return PersistentLayoutNode(
                kind: .window,
                weight: weight,
                orientation: nil,
                layout: nil,
                window: identities[window.windowId].orDie(),
                children: [],
            )
        case .tilingContainer(let container):
            return PersistentLayoutNode(
                kind: .container,
                weight: weight,
                orientation: container.orientation == .h ? "horizontal" : "vertical",
                layout: container.layout.rawValue,
                window: nil,
                children: container.children.map {
                    captureNode(
                        $0,
                        weight: Double($0.getWeight(container.orientation)),
                        identities: identities,
                    )
                },
            )
        case .workspace, .floatingWindowsContainer, .macosMinimizedWindowsContainer,
             .macosHiddenAppsWindowsContainer, .macosFullscreenWindowsContainer,
             .macosPopupWindowsContainer:
            return dieT("Persistent manual layouts only support tiling trees")
    }
}

@MainActor
private func matchWindows(
    _ savedIdentities: [PersistentWindowIdentity],
    currentWindows: [Window],
    currentIdentities: [UInt32: PersistentWindowIdentity],
) -> [PersistentWindowIdentity: Window]? {
    var exact: [String: Window] = [:]
    var byApplication: [String: [Window]] = [:]
    for window in currentWindows {
        guard let identity = currentIdentities[window.windowId] else { return nil }
        exact[persistentExactWindowKey(identity)] = window
        byApplication[identity.applicationIdentifier, default: []].append(window)
    }

    var usedWindowIds: Set<UInt32> = []
    var result: [PersistentWindowIdentity: Window] = [:]
    for identity in savedIdentities {
        guard let window = exact[persistentExactWindowKey(identity)],
              usedWindowIds.insert(window.windowId).inserted else { continue }
        result[identity] = window
    }
    for identity in savedIdentities where result[identity] == nil {
        let exactWindow = exact[persistentExactWindowKey(identity)].flatMap { window in
            usedWindowIds.contains(window.windowId) ? nil : window
        }
        let fallbackWindow = byApplication[identity.applicationIdentifier]?
            .getOrNil(atIndex: identity.applicationOccurrence)
            .flatMap { window in usedWindowIds.contains(window.windowId) ? nil : window }
        let window = exactWindow ?? fallbackWindow
        guard let window else { return nil }
        usedWindowIds.insert(window.windowId)
        result[identity] = window
    }
    return result
}

private func persistentExactWindowKey(_ identity: PersistentWindowIdentity) -> String {
    "\(identity.applicationIdentifier)\u{1f}\(identity.title)\u{1f}\(identity.titleOccurrence)"
}

@MainActor
private func restorePersistentLayout(
    _ savedRoot: PersistentLayoutNode,
    in workspace: Workspace,
    windows: [PersistentWindowIdentity: Window],
) {
    guard savedRoot.kind == .container,
          let orientation = savedRoot.orientation.flatMap(persistentOrientation),
          let layout = savedRoot.layout.flatMap(Layout.init(rawValue:))
    else { return }

    let root = workspace.rootTilingContainer
    let previouslyFocusedWindow = focus.windowOrNil?.takeIf { workspace.rootTilingContainer.allLeafWindowsRecursive.contains($0) }
    for window in workspace.rootTilingContainer.allLeafWindowsRecursive { window.unbindFromParent() }
    for child in root.children { child.unbindFromParent() }
    root.changeOrientation(orientation)
    root.layout = layout
    restoreChildren(savedRoot.children, parent: root, windows: windows)
    previouslyFocusedWindow?.markAsMostRecentChild()
}

@MainActor
private func restoreChildren(
    _ children: [PersistentLayoutNode],
    parent: TilingContainer,
    windows: [PersistentWindowIdentity: Window],
) {
    for child in children {
        switch child.kind {
            case .window:
                guard let identity = child.window, let window = windows[identity] else { continue }
                window.bind(to: parent, adaptiveWeight: CGFloat(child.weight), index: INDEX_BIND_LAST)
            case .container:
                guard let orientation = child.orientation.flatMap(persistentOrientation),
                      let layout = child.layout.flatMap(Layout.init(rawValue:))
                else { continue }
                let container = TilingContainer(
                    parent: parent,
                    adaptiveWeight: CGFloat(child.weight),
                    orientation,
                    layout,
                    index: INDEX_BIND_LAST,
                )
                restoreChildren(child.children, parent: container, windows: windows)
        }
    }
}

private func persistentOrientation(_ raw: String) -> Orientation? {
    switch raw {
        case "horizontal": .h
        case "vertical": .v
        default: nil
    }
}
