import AppKit
import Common

@MainActor private var workspaceNameToWorkspace: [String: Workspace] = [:]

@MainActor private var screenPointToMonitorIdentity: [CGPoint: String] = [:]

@MainActor private var screenPointToPrevVisibleWorkspace: [CGPoint: String] = [:]
@MainActor private var screenPointToVisibleWorkspace: [CGPoint: Workspace] = [:]
@MainActor private var visibleWorkspaceToScreenPoint: [Workspace: CGPoint] = [:]

// The returned workspace must be invisible and it must belong to the requested monitor
@MainActor func getStubWorkspace(for monitor: MonitorInfo) -> Workspace {
    getStubWorkspace(forPoint: monitor.rect.topLeftCorner)
}

@MainActor
private func getStubWorkspace(forPoint point: CGPoint) -> Workspace {
    if let prev = screenPointToPrevVisibleWorkspace[point].map({ Workspace.get(byName: $0) }),
       prev.isUserFacing &&
       !prev.isVisible &&
       prev.workspaceMonitor.rect.topLeftCorner == point &&
       prev.forceAssignedMonitor == nil
    {
        return prev
    }
    if let candidate = Workspace.all
        .first(where: { $0.isUserFacing && !$0.isVisible && $0.workspaceMonitor.rect.topLeftCorner == point })
    {
        return candidate
    }
    return (1 ... Int.max).lazy
        .map { Workspace.get(byName: String($0)) }
        .first { $0.isEffectivelyEmpty && !$0.isVisible && !config.persistentWorkspaces.contains($0.name) && $0.forceAssignedMonitor == nil }
        .orDie("Can't create empty workspace")
}

final class Workspace: TreeNode, NonLeafTreeNodeObject, Hashable, Comparable {
    let name: String
    nonisolated private let nameLogicalSegments: StringLogicalSegments
    /// `assignedMonitorPoint` must be interpreted only when the workspace is invisible
    fileprivate var assignedMonitorPoint: CGPoint? = nil

    @MainActor
    private init(_ name: String) {
        self.name = name
        self.nameLogicalSegments = name.toLogicalSegments()
        super.init(parent: NilTreeNode.instance, adaptiveWeight: 0, index: 0)
    }

    @MainActor static var all: [Workspace] {
        workspaceNameToWorkspace.values.sorted()
    }

    @MainActor static func get(byName name: String) -> Workspace {
        if let existing = workspaceNameToWorkspace[name] {
            return existing
        } else {
            let workspace = Workspace(name)
            workspaceNameToWorkspace[name] = workspace
            return workspace
        }
    }

    nonisolated static func < (lhs: Workspace, rhs: Workspace) -> Bool {
        lhs.nameLogicalSegments < rhs.nameLogicalSegments
    }

    override func getWeight(_ targetOrientation: Orientation) -> CGFloat {
        workspaceMonitor.visibleRectPaddedByOuterGaps.getDimension(targetOrientation)
    }

    override func setWeight(_ targetOrientation: Orientation, _ newValue: CGFloat) {
        die("It's not possible to change weight of Workspace")
    }

    @MainActor
    var description: String {
        let description = [
            ("name", name),
            ("isVisible", String(isVisible)),
            ("isEffectivelyEmpty", String(isEffectivelyEmpty)),
            ("doKeepAlive", String(config.persistentWorkspaces.contains(name))),
        ].map { "\($0.0): \(String(describing: $0.1).singleQuoted)" }.joined(separator: ", ")
        return "Workspace(\(description))"
    }

    @MainActor
    static func garbageCollectUnusedWorkspaces() {
        for name in config.persistentWorkspaces {
            _ = get(byName: name) // Make sure that all persistent workspaces are "cached"
        }
        workspaceNameToWorkspace = workspaceNameToWorkspace.filter { (_, workspace: Workspace) in
            config.persistentWorkspaces.contains(workspace.name) ||
                !workspace.isEffectivelyEmpty ||
                workspace.isVisible ||
                workspace.name == focus.workspace.name
        }
    }

    nonisolated static func == (lhs: Workspace, rhs: Workspace) -> Bool {
        check((lhs === rhs) == (lhs.name == rhs.name), "lhs: \(lhs) rhs: \(rhs)")
        return lhs === rhs
    }

    nonisolated func hash(into hasher: inout Hasher) { hasher.combine(name) }
}

extension Workspace {
    nonisolated var isUserFacing: Bool { !name.hasPrefix("_smooth-") }

    @MainActor
    var isVisible: Bool { visibleWorkspaceToScreenPoint.keys.contains(self) }
    @MainActor
    var workspaceMonitor: MonitorInfo {
        forceAssignedMonitor
            ?? visibleWorkspaceToScreenPoint[self]?.monitorApproximation
            ?? assignedMonitorPoint?.monitorApproximation
            ?? mainMonitorInfo
    }

    @MainActor
    func assign(to monitor: MonitorInfo) -> Bool {
        if isVisible {
            return workspaceMonitor.stableIdentifier == monitor.stableIdentifier
        }
        if let forceAssignedMonitor, forceAssignedMonitor.stableIdentifier != monitor.stableIdentifier {
            return false
        }
        assignedMonitorPoint = monitor.rect.topLeftCorner
        return true
    }
}

@MainActor
func cachedWorkspaceForMonitor(
    identifier: String,
    origin: CGPoint,
    identities: [CGPoint: String],
    workspaces: [CGPoint: Workspace],
) -> Workspace? {
    if identities[origin] == identifier, let workspace = workspaces[origin] {
        return workspace
    }
    guard let currentOrigin = identities.first(where: { $0.value == identifier })?.key else { return nil }
    return workspaces[currentOrigin]
}

extension MonitorInfo {
    @MainActor
    var activeWorkspace: Workspace {
        gcMonitors()
        if let existing = cachedWorkspaceForMonitor(
            identifier: stableIdentifier, origin: rect.topLeftCorner,
            identities: screenPointToMonitorIdentity, workspaces: screenPointToVisibleWorkspace,
        ) {
            return existing
        }
        // What if monitor configuration changed? (frame.origin is changed)
        rearrangeWorkspacesOnMonitors()
        if let existing = cachedWorkspaceForMonitor(
            identifier: stableIdentifier, origin: rect.topLeftCorner,
            identities: screenPointToMonitorIdentity, workspaces: screenPointToVisibleWorkspace,
        ) {
            return existing
        }
        // An AX await can leave the caller holding a monitor that has since
        // disconnected or moved. Resolve its current identity before falling
        // back to an available display; never recurse on the stale origin.
        let monitors = monitorInfos
        if let current = monitors.first(where: { $0.stableIdentifier == stableIdentifier })
            ?? monitors.first(where: \.isMain) ?? monitors.first,
           let existing = screenPointToVisibleWorkspace[current.rect.topLeftCorner]
        {
            return existing
        }
        // NSScreen can briefly be empty during display reconfiguration. Keep
        // the last cached workspace without declaring a fictitious screen active.
        if let point = screenPointToMonitorIdentity.first(where: { $0.value == stableIdentifier })?.key,
           let existing = screenPointToVisibleWorkspace[point]
        {
            return existing
        }
        if let existing = screenPointToVisibleWorkspace.values.sorted().first {
            return existing
        }
        return Workspace.get(byName: config.persistentWorkspaces.first ?? "1")
    }

    @MainActor
    func setActiveWorkspace(_ workspace: Workspace) -> Bool {
        rect.topLeftCorner.setActiveWorkspace(workspace)
    }
}

@MainActor
func gcMonitors() {
    let current = Dictionary(monitorInfos.map { ($0.rect.topLeftCorner, $0.stableIdentifier) }, uniquingKeysWith: { first, _ in first })
    if screenPointToMonitorIdentity != current || screenPointToVisibleWorkspace.count != current.count {
        rearrangeWorkspacesOnMonitors()
    }
}

extension CGPoint {
    @MainActor
    fileprivate func setActiveWorkspace(_ workspace: Workspace) -> Bool {
        if !isValidAssignment(workspace: workspace, screen: self) {
            return false
        }
        if let prevMonitorPoint = visibleWorkspaceToScreenPoint[workspace] {
            visibleWorkspaceToScreenPoint.removeValue(forKey: workspace)
            screenPointToPrevVisibleWorkspace[prevMonitorPoint] =
                screenPointToVisibleWorkspace.removeValue(forKey: prevMonitorPoint)?.name
        }
        if let prevWorkspace = screenPointToVisibleWorkspace[self] {
            screenPointToPrevVisibleWorkspace[self] =
                screenPointToVisibleWorkspace.removeValue(forKey: self)?.name
            visibleWorkspaceToScreenPoint.removeValue(forKey: prevWorkspace)
        }
        visibleWorkspaceToScreenPoint[workspace] = self
        screenPointToVisibleWorkspace[self] = workspace
        workspace.assignedMonitorPoint = self
        return true
    }
}

@MainActor
private func rearrangeWorkspacesOnMonitors() {
    let monitors = monitorInfos
    guard !monitors.isEmpty else { return }
    let newScreens = monitors.map(\.rect.topLeftCorner)
    let newIdentities = Dictionary(monitors.map { ($0.rect.topLeftCorner, $0.stableIdentifier) }, uniquingKeysWith: { first, _ in first })
    let newScreenToOldScreenMapping = matchMonitorOrigins(
        oldIdentities: screenPointToMonitorIdentity,
        newIdentities: newIdentities,
        occupied: Set(screenPointToVisibleWorkspace.keys),
    )
    screenPointToMonitorIdentity = Dictionary(monitors.map { ($0.rect.topLeftCorner, $0.stableIdentifier) }, uniquingKeysWith: { first, _ in first })
    let oldScreenPointToVisibleWorkspace = screenPointToVisibleWorkspace
    screenPointToVisibleWorkspace = [:]
    visibleWorkspaceToScreenPoint = [:]

    for newScreen in newScreens {
        if let existingVisibleWorkspace = newScreenToOldScreenMapping[newScreen].flatMap({ oldScreenPointToVisibleWorkspace[$0] }),
           newScreen.setActiveWorkspace(existingVisibleWorkspace)
        {
            continue
        }
        let stubWorkspace = getStubWorkspace(forPoint: newScreen)
        check(newScreen.setActiveWorkspace(stubWorkspace),
              "getStubWorkspace generated incompatible stub workspace (\(stubWorkspace)) for the monitor (\(newScreen)")
    }
}

@MainActor
private func isValidAssignment(workspace: Workspace, screen: CGPoint) -> Bool {
    switch workspace.forceAssignedMonitor {
        case let forceAssigned? where forceAssigned.rect.topLeftCorner != screen: false
        default: true
    }
}

// Kept pure so display-origin swaps can be tested without moving physical displays.
func matchMonitorOrigins(
    oldIdentities: [CGPoint: String],
    newIdentities: [CGPoint: String],
    occupied: Set<CGPoint>,
) -> [CGPoint: CGPoint] {
    let newScreens = Array(newIdentities.keys)
    var newScreenToOldScreenMapping: [CGPoint: CGPoint] = [:]
    // Hardware identity wins over proximity when macOS changes display origins.
    for (point, identity) in newIdentities {
        if let oldPoint = oldIdentities.first(where: { $0.value == identity })?.key,
           occupied.contains(oldPoint)
        {
            newScreenToOldScreenMapping[point] = oldPoint
        }
    }
    let identityMatchedScreens = Set(newScreenToOldScreenMapping.keys)
    let identityMatchedOldScreens = Set(newScreenToOldScreenMapping.values)
    for oldScreen in occupied where !identityMatchedOldScreens.contains(oldScreen) {
        guard let newScreen = newScreens.filter({ !identityMatchedScreens.contains($0) }).minBy({ ($0 - oldScreen).vectorLength }) else { continue }
        if let prevOldScreen = newScreenToOldScreenMapping[newScreen] {
            if (prevOldScreen - newScreen).vectorLength <= (oldScreen - newScreen).vectorLength {
                // newScreen has already been assigned to a closer oldScreen.
                continue
            }
        }
        newScreenToOldScreenMapping[newScreen] = oldScreen
    }

    return newScreenToOldScreenMapping
}
