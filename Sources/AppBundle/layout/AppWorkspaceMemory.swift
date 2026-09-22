import Combine
import Common
import Foundation

/// An app's most recently used workspace survives closing its last window.
@MainActor
final class AppWorkspaceMemory: ObservableObject {
    static let shared = AppWorkspaceMemory()
    private static let enabledKey = "AeroSpaceSmooth.remember-app-workspaces"
    private static let workspacesKey = "AeroSpaceSmooth.app-workspaces.v1"
    private let defaults: UserDefaults
    @Published private(set) var isEnabled: Bool
    private(set) var workspaces: [String: String]
    private var previous: [UInt32: String] = [:]
    private var previousFocus: String?
    private var excluded: Set<UInt32> = []
    private var pending: Set<UInt32> = []
    private var isReady = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = defaults.object(forKey: Self.enabledKey) as? Bool ?? true
        workspaces = defaults.dictionary(forKey: Self.workspacesKey) as? [String: String] ?? [:]
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        defaults.set(enabled, forKey: Self.enabledKey)
    }

    func beginRegistration(_ window: Window) { pending.insert(window.windowId) }
    func endRegistration(_ window: Window) { pending.remove(window.windowId) }

    func setEligible(_ window: Window, _ eligible: Bool) {
        excluded.remove(window.windowId)
        if !eligible { excluded.insert(window.windowId) }
    }

    private func placement(_ window: Window, allowPending: Bool = false) -> (app: String, workspace: String)? {
        guard (allowPending || !pending.contains(window.windowId)),
              !excluded.contains(window.windowId), window.scratchpadSlot == nil,
              let app = window.app.rawAppBundleId,
              let workspace = window.nodeWorkspace, workspace.isUserFacing else { return nil }
        switch window.windowParentCases {
            case .tilingContainer, .floatingWindowsContainer: return (app, workspace.name)
            default: return nil
        }
    }

    /// Startup layout restoration owns existing windows; only seed missing apps here.
    func start(windows: [Window], focused: Window?) {
        isReady = true
        capture(windows: windows, focused: focused, seeding: true)
    }

    func capture(windows: [Window], focused: Window?, seeding: Bool = false) {
        guard isReady else { return }
        var updated = workspaces
        var current: [UInt32: String] = [:]
        var moved: [(app: String, workspace: String)] = []
        for window in windows.sorted(by: { $0.windowId < $1.windowId }) {
            guard let value = placement(window) else { continue }
            current[window.windowId] = value.workspace
            if updated[value.app] == nil { updated[value.app] = value.workspace }
            if let old = previous[window.windowId], old != value.workspace { moved.append(value) }
        }
        let focusedPlacement = focused.flatMap { placement($0) }
        let focusKey = focusedPlacement.map { "\($0.app):\(focused!.windowId):\($0.workspace)" }
        if !seeding, focusKey != previousFocus, let value = focusedPlacement {
            updated[value.app] = value.workspace
        }
        // Explicit moves also count when the user sends a window without following it.
        if !seeding { for value in moved { updated[value.app] = value.workspace } }
        previous = current
        previousFocus = focusKey
        guard isEnabled, updated != workspaces else { return }
        workspaces = updated
        defaults.set(workspaces, forKey: Self.workspacesKey)
    }

    /// Run before explicit window rules so those rules retain priority.
    @discardableResult
    func restore(_ window: Window, duringStartup: Bool) -> Bool {
        guard isReady, isEnabled, !duringStartup, let value = placement(window, allowPending: true),
              let name = workspaces[value.app], !name.isEmpty, !name.hasPrefix("_smooth-") else { return false }
        let destination = Workspace.get(byName: name)
        if window.nodeWorkspace != destination {
            _ = moveWindowToWorkspace(window, destination, CmdIoImpl.emptyStdinIgnoringOut,
                                      focusFollowsWindow: false, failIfNoop: false)
        }
        return true
    }
}
