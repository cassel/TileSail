import Combine
import Common
import Foundation

enum SmoothLayoutStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case manual
    case fullscreen
    case columns
    case rows
    case dwindle
    case verticalPairs = "vertical-pairs"
    case grid

    var id: String { rawValue }

    var title: String {
        switch self {
            case .manual: "Custom"
            case .fullscreen: "Fullscreen"
            case .columns: "Columns"
            case .rows: "Rows"
            case .dwindle: "Dwindle"
            case .verticalPairs: "Vertical Pairs"
            case .grid: "Grid"
        }
    }

    var detail: String {
        switch self {
            case .manual: "Uses the visual layout saved for this monitor and window count."
            case .fullscreen: "One window fills the entire usable area."
            case .columns: "Windows appear side by side with equal widths."
            case .rows: "Windows are stacked with equal heights."
            case .dwindle: "A large primary window with a tail alternating right and down."
            case .verticalPairs: "Stacked rows containing up to two windows each."
            case .grid: "Equal-sized windows in complete rows and columns."
        }
    }

    static func available(for windowCount: Int) -> [SmoothLayoutStyle] {
        windowCount == 1
            ? [.fullscreen, .manual]
            : [.dwindle, .verticalPairs, .grid, .columns, .rows, .manual]
    }
}

/// Choose a complete rectangle, then favor cells closest to square on this monitor.
/// Restricting columns to divisors prevents an oversized incomplete final row.
enum SmoothGridGeometry {
    static func columnCount(count: Int, aspectRatio: Double) -> Int {
        guard count > 1 else { return 1 }
        let aspect = aspectRatio.isFinite && aspectRatio > 0 ? aspectRatio : 1
        var bestColumns = 1
        var bestScore = Double.infinity
        for columns in 1 ... count where count.isMultiple(of: columns) {
            let rows = count / columns
            let score = abs(log(aspect * Double(rows) / Double(columns)))
            if score < bestScore {
                bestColumns = columns
                bestScore = score
            }
        }
        return bestColumns
    }
}

struct SmoothMonitorLayoutProfile: Codable, Equatable, Identifiable, Sendable {
    static let configuredWindowCount = 10

    var monitorIdentifier: String?
    var monitorName: String
    var enabled: Bool
    var tileLimit: Int
    var styles: [SmoothLayoutStyle]
    var customLayouts: [String: SmoothCustomLayoutBlueprint]
    var workspaceSlots: [String]

    var id: String { monitorIdentifier ?? "legacy-name:\(monitorName)" }

    func style(for windowCount: Int) -> SmoothLayoutStyle {
        let index = min(max(windowCount, 1), Self.configuredWindowCount) - 1
        // SwiftUI can evaluate Picker bindings many times in a single render
        // pass. Normalizing here copied the whole profile and revalidated every
        // custom layout for each evaluation, which could trap the monitor
        // settings window in an AttributeGraph update loop.
        guard styles.indices.contains(index) else {
            return styles.last ?? .dwindle
        }
        return styles[index]
    }

    func customLayout(for windowCount: Int) -> SmoothCustomLayoutBlueprint? {
        guard let layout = customLayouts[String(min(max(windowCount, 1), Self.configuredWindowCount))] else {
            return nil
        }
        return layout.windowCount == windowCount && layout.isValid ? layout : nil
    }

    var normalized: SmoothMonitorLayoutProfile {
        var result = self
        result.tileLimit = min(max(result.tileLimit, 1), Self.configuredWindowCount)
        let fallback = styles.last ?? .dwindle
        if result.styles.count < Self.configuredWindowCount {
            result.styles += Array(
                repeating: fallback,
                count: Self.configuredWindowCount - result.styles.count,
            )
        } else if result.styles.count > Self.configuredWindowCount {
            result.styles = Array(result.styles.prefix(Self.configuredWindowCount))
        }
        result.customLayouts = result.customLayouts.filter { key, layout in
            Int(key) == layout.windowCount && layout.isValid
        }
        if result.workspaceSlots.count < smoothWorkspaceSlotCount {
            result.workspaceSlots += Array(repeating: "", count: smoothWorkspaceSlotCount - result.workspaceSlots.count)
        } else if result.workspaceSlots.count > smoothWorkspaceSlotCount {
            result.workspaceSlots = Array(result.workspaceSlots.prefix(smoothWorkspaceSlotCount))
        }
        return result
    }

    static func defaultProfile(
        monitorIdentifier: String? = nil,
        monitorName: String,
        isHorizontal: Bool,
    ) -> SmoothMonitorLayoutProfile {
        SmoothMonitorLayoutProfile(
            monitorIdentifier: monitorIdentifier,
            monitorName: monitorName,
            enabled: true,
            tileLimit: monitorName == "Built-in Retina Display" ? 5 : 6,
            styles: isHorizontal
                ? [.fullscreen, .columns] + Array(repeating: .dwindle, count: configuredWindowCount - 2)
                : [.fullscreen, .rows] + Array(repeating: .verticalPairs, count: configuredWindowCount - 2),
            customLayouts: [:],
            workspaceSlots: Array(repeating: "", count: smoothWorkspaceSlotCount),
        )
    }

    init(
        monitorIdentifier: String? = nil,
        monitorName: String,
        enabled: Bool,
        tileLimit: Int = 6,
        styles: [SmoothLayoutStyle],
        customLayouts: [String: SmoothCustomLayoutBlueprint] = [:],
        workspaceSlots: [String] = [],
    ) {
        self.monitorIdentifier = monitorIdentifier
        self.monitorName = monitorName
        self.enabled = enabled
        self.tileLimit = tileLimit
        self.styles = styles
        self.customLayouts = customLayouts
        self.workspaceSlots = workspaceSlots
    }

    private enum CodingKeys: String, CodingKey {
        case monitorIdentifier
        case monitorName
        case enabled
        case tileLimit
        case styles
        case customLayouts
        case workspaceSlots
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        monitorIdentifier = try values.decodeIfPresent(String.self, forKey: .monitorIdentifier)
        monitorName = try values.decode(String.self, forKey: .monitorName)
        enabled = try values.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        tileLimit = try values.decodeIfPresent(Int.self, forKey: .tileLimit) ?? 6
        styles = try values.decodeIfPresent([SmoothLayoutStyle].self, forKey: .styles) ?? []
        customLayouts = try values.decodeIfPresent([String: SmoothCustomLayoutBlueprint].self, forKey: .customLayouts) ?? [:]
        workspaceSlots = try values.decodeIfPresent([String].self, forKey: .workspaceSlots) ?? []
    }

    func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encodeIfPresent(monitorIdentifier, forKey: .monitorIdentifier)
        try values.encode(monitorName, forKey: .monitorName)
        try values.encode(enabled, forKey: .enabled)
        try values.encode(tileLimit, forKey: .tileLimit)
        try values.encode(styles, forKey: .styles)
        try values.encode(customLayouts, forKey: .customLayouts)
        try values.encode(workspaceSlots, forKey: .workspaceSlots)
    }
}

@MainActor
final class SmoothLayoutSettingsStore: ObservableObject {
    static let shared = SmoothLayoutSettingsStore()

    private static let defaultsKey = "AeroSpaceSmooth.monitor-layout-profiles.v2"
    private static let legacyDefaultsKey = "AeroSpaceSmooth.monitor-layout-profiles.v1"
    private static let customSelectionRepairKey = "AeroSpaceSmooth.custom-layout-selection-repair.v1"
    private let defaults: UserDefaults

    @Published private(set) var profiles: [String: SmoothMonitorLayoutProfile]
    @Published private(set) var monitorConfigurationRevision = 0

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        profiles = (defaults.data(forKey: Self.defaultsKey) ?? defaults.data(forKey: Self.legacyDefaultsKey))
            .flatMap { try? JSONDecoder().decode([String: SmoothMonitorLayoutProfile].self, from: $0) }
            ?? [:]
        profiles = profiles.mapValues(\.normalized)
        repairCustomLayoutSelectionsIfNeeded()
    }

    func profile(for monitor: MonitorInfo) -> SmoothMonitorLayoutProfile {
        profile(
            identifier: monitor.stableIdentifier,
            named: monitor.name,
            isHorizontal: monitor.width >= monitor.height,
        )
    }

    func profile(identifier: String, named monitorName: String, isHorizontal: Bool) -> SmoothMonitorLayoutProfile {
        if var profile = profiles[identifier] {
            if profile.monitorIdentifier != identifier || profile.monitorName != monitorName {
                profile.monitorIdentifier = identifier
                profile.monitorName = monitorName
                profiles[identifier] = profile.normalized
                persist()
            }
            return profile.normalized
        }

        // Profiles from v1 were keyed only by the visible display name. Claim a
        // legacy profile once, then persist it under the hardware UUID.
        if let legacyKey = profiles.first(where: {
            $0.value.monitorIdentifier == nil && $0.value.monitorName == monitorName
        })?.key {
            var profile = profiles.removeValue(forKey: legacyKey).orDie()
            profile.monitorIdentifier = identifier
            profile.monitorName = monitorName
            profiles[identifier] = profile.normalized
            persist()
            return profile.normalized
        }

        let profile = SmoothMonitorLayoutProfile.defaultProfile(
            monitorIdentifier: identifier,
            monitorName: monitorName,
            isHorizontal: isHorizontal,
        )
        profiles[identifier] = profile
        persist()
        return profile
    }

    func profile(named monitorName: String, isHorizontal: Bool) -> SmoothMonitorLayoutProfile {
        profiles[monitorName]
            ?? profiles.values.first { $0.monitorName == monitorName }
            ?? SmoothMonitorLayoutProfile.defaultProfile(
                monitorName: monitorName,
                isHorizontal: isHorizontal,
            )
    }

    func setEnabled(_ enabled: Bool, monitorIdentifier: String, monitorName: String, isHorizontal: Bool) {
        var profile = profile(identifier: monitorIdentifier, named: monitorName, isHorizontal: isHorizontal)
        profile.enabled = enabled
        profiles[monitorIdentifier] = profile.normalized
        didChangeLayoutSettings()
    }

    func setTileLimit(_ tileLimit: Int, monitorIdentifier: String, monitorName: String, isHorizontal: Bool) {
        var profile = profile(identifier: monitorIdentifier, named: monitorName, isHorizontal: isHorizontal)
        profile.tileLimit = tileLimit
        profiles[monitorIdentifier] = profile.normalized
        didChangeLayoutSettings()
    }

    func setStyle(
        _ style: SmoothLayoutStyle,
        windowCount: Int,
        monitorIdentifier: String,
        monitorName: String,
        isHorizontal: Bool,
    ) {
        var profile = profile(identifier: monitorIdentifier, named: monitorName, isHorizontal: isHorizontal).normalized
        let index = min(max(windowCount, 1), SmoothMonitorLayoutProfile.configuredWindowCount) - 1
        let previousStyle = profile.styles[index]
        profile.styles[index] = style
        if style == .manual, profile.customLayout(for: windowCount) == nil {
            profile.customLayouts[String(windowCount)] = .preset(
                style: previousStyle == .manual ? .dwindle : previousStyle,
                windowCount: windowCount,
                monitorIsHorizontal: isHorizontal,
            )
        }
        profiles[monitorIdentifier] = profile
        didChangeLayoutSettings()
    }

    func setCustomLayout(
        _ layout: SmoothCustomLayoutBlueprint,
        windowCount: Int,
        monitorIdentifier: String,
        monitorName: String,
        isHorizontal: Bool,
    ) {
        guard layout.windowCount == windowCount, layout.isValid else { return }
        var profile = profile(identifier: monitorIdentifier, named: monitorName, isHorizontal: isHorizontal).normalized
        let index = min(max(windowCount, 1), SmoothMonitorLayoutProfile.configuredWindowCount) - 1
        profile.customLayouts[String(windowCount)] = layout
        profile.styles[index] = .manual
        profiles[monitorIdentifier] = profile
        // Closing the editor generates window events that can cancel the
        // settings refresh. Drop the cached topology first so the next refresh
        // must apply the newly saved blueprint even when that initial task is
        // superseded.
        invalidateSmoothWorkspaceLayoutSnapshots()
        didChangeLayoutSettings()
    }

    func resetProfile(monitorIdentifier: String, monitorName: String, isHorizontal: Bool) {
        let workspaceSlots = profile(
            identifier: monitorIdentifier,
            named: monitorName,
            isHorizontal: isHorizontal,
        ).normalized.workspaceSlots
        var reset = SmoothMonitorLayoutProfile.defaultProfile(
            monitorIdentifier: monitorIdentifier,
            monitorName: monitorName,
            isHorizontal: isHorizontal,
        )
        reset.workspaceSlots = workspaceSlots
        profiles[monitorIdentifier] = reset
        didChangeLayoutSettings()
    }

    func setWorkspaceName(
        _ workspaceName: String,
        slot: Int,
        monitorIdentifier: String,
        monitorName: String,
        isHorizontal: Bool,
    ) {
        guard (1 ... smoothWorkspaceSlotCount).contains(slot) else { return }
        var profile = profile(identifier: monitorIdentifier, named: monitorName, isHorizontal: isHorizontal).normalized
        profile.workspaceSlots[slot - 1] = workspaceName
        profiles[monitorIdentifier] = profile
        persist()
        objectWillChange.send()
    }

    func workspaceName(slot: Int, on monitor: MonitorInfo) -> String? {
        guard (1 ... smoothWorkspaceSlotCount).contains(slot) else { return nil }
        let configuredName = profile(for: monitor).normalized.workspaceSlots[slot - 1]
        if !configuredName.isEmpty { return configuredName }

        let workspaces = Workspace.all
            .filter { $0.workspaceMonitor.stableIdentifier == monitor.stableIdentifier && $0.isUserFacing }
            .sorted()
        return workspaces.getOrNil(atIndex: slot - 1)?.name
    }

    func monitorsDidChange(_ monitors: [MonitorInfo]) {
        // NSScreen indices and names can both change after a reconnect. Resolve
        // every monitor through its Core Graphics UUID before refreshing the UI.
        for monitor in monitors {
            _ = profile(for: monitor)
        }
        monitorConfigurationRevision &+= 1
        invalidateSmoothWorkspaceLayoutSnapshots()
    }

    private func didChangeLayoutSettings() {
        persist()
        // Reconciliation compares the selected style with its last snapshot,
        // so keeping that snapshot lets a transition to Manual distinguish an
        // auto-fullscreen window from a fullscreen choice made by the user.
        scheduleCancellableCompleteRefreshSession(.menuBarButton)
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(profiles) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }

    /// Early versions of the visual editor could persist the blueprint while a
    /// stale SwiftUI Picker binding immediately restored the previous preset.
    /// Repair those profiles once, while still allowing the user to switch away
    /// from Custom later without deleting the saved design.
    private func repairCustomLayoutSelectionsIfNeeded() {
        guard !defaults.bool(forKey: Self.customSelectionRepairKey) else { return }
        for monitorName in profiles.keys {
            var profile = profiles[monitorName].orDie().normalized
            for key in profile.customLayouts.keys {
                guard let windowCount = Int(key),
                      (1 ... SmoothMonitorLayoutProfile.configuredWindowCount).contains(windowCount)
                else { continue }
                profile.styles[windowCount - 1] = .manual
            }
            profiles[monitorName] = profile
        }
        persist()
        defaults.set(true, forKey: Self.customSelectionRepairKey)
    }

    func replaceProfilesForTests(
        _ profiles: [String: SmoothMonitorLayoutProfile],
        invalidateSnapshots: Bool = true,
    ) {
        self.profiles = profiles.mapValues(\.normalized)
        if invalidateSnapshots {
            invalidateSmoothWorkspaceLayoutSnapshots()
        }
    }
}
