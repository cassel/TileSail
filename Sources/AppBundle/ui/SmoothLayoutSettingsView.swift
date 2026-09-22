import AppKit
import Common
import SwiftUI
import UniformTypeIdentifiers

let smoothLayoutSettingsWindowId = "aerospace-smooth-layout-settings"

private struct SmoothMonitorSummary: Identifiable, Hashable {
    let identifier: String
    let name: String
    let width: CGFloat
    let height: CGFloat

    var id: String { identifier }
    var isHorizontal: Bool { width >= height }
    var orientationTitle: String { isHorizontal ? "Horizontal" : "Vertical" }
    var layoutPreviewHeight: CGFloat { isHorizontal ? 180 : 260 }
}

private struct SmoothCustomLayoutEditorTarget: Identifiable {
    let monitor: SmoothMonitorSummary
    let windowCount: Int
    let layout: SmoothCustomLayoutBlueprint
    let previousLayout: SmoothCustomLayoutBlueprint?

    var id: String { "\(monitor.id):\(windowCount)" }
}

@MainActor
public func smoothLayoutSettingsWindow() -> some Scene {
    SwiftUI.Window("TileSail Settings", id: smoothLayoutSettingsWindowId) {
        SmoothLayoutSettingsView()
            .frame(minWidth: 1040, minHeight: 680)
    }
    .defaultSize(width: 1180, height: 820)
}

@MainActor
struct OpenSmoothLayoutSettingsButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: smoothLayoutSettingsWindowId)
        } label: {
            Label("Settings…", systemImage: "gearshape")
        }
        .keyboardShortcut("L", modifiers: [.command, .shift])
    }
}

@MainActor
private var commandLineSettingsWindowController: NSWindowController?

@MainActor
public func scheduleCommandLineSettingsWindowIfRequested() {
    guard serverArgs.openSettings else { return }
    DispatchQueue.main.async {
        let content = NSHostingController(rootView: SmoothLayoutSettingsView())
        let window = NSWindow(contentViewController: content)
        window.title = "TileSail Settings"
        window.setContentSize(NSSize(width: 1180, height: 820))
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.center()
        window.isReleasedWhenClosed = false
        let controller = NSWindowController(window: window)
        commandLineSettingsWindowController = controller
        NSApp.activate(ignoringOtherApps: true)
        controller.showWindow(nil)
    }
}

private enum SmoothSettingsSection: String, CaseIterable, Identifiable {
    case layouts
    case general
    case workspaces
    case applications
    case automation
    case shortcuts
    case configFile

    var id: String { rawValue }

    var title: String {
        switch self {
            case .layouts: "Layouts"
            case .general: "General"
            case .workspaces: "Workspaces"
            case .applications: "Applications"
            case .automation: "Automation"
            case .shortcuts: "Shortcuts"
            case .configFile: "TOML File"
        }
    }

    var systemImage: String {
        switch self {
            case .layouts: "rectangle.3.group"
            case .general: "switch.2"
            case .workspaces: "square.grid.3x3"
            case .applications: "app.badge"
            case .automation: "bolt.horizontal.circle"
            case .shortcuts: "keyboard"
            case .configFile: "doc.text"
        }
    }
}

@MainActor
private struct SmoothLayoutSettingsView: View {
    @StateObject private var configSettings = VisualConfigSettingsStore()
    @ObservedObject private var conflictMonitor = WindowManagerConflictMonitor.shared
    @ObservedObject private var appWorkspaces = AppWorkspaceMemory.shared
    @ObservedObject private var manualLayouts = PersistentManualLayoutStore.shared
    @ObservedObject private var updateChecker = UpdateChecker.shared
    @ObservedObject private var workspaceBar = WorkspaceBarSettings.shared
    @ObservedObject private var scratchpads = ScratchpadManager.shared
    @ObservedObject private var menuBarAppearance = MenuBarAppearanceSettings.shared
    @State private var selection: SmoothSettingsSection = .layouts

    var body: some View {
        HSplitView {
            List(SmoothSettingsSection.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.systemImage)
                    .padding(.vertical, 5)
                    .tag(section)
            }
            .listStyle(.sidebar)
            .frame(minWidth: 190, idealWidth: 210, maxWidth: 240)

            VStack(spacing: 0) {
                selectedPage
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                settingsFooter
            }
        }
        .navigationTitle("TileSail")
    }

    @ViewBuilder
    private var selectedPage: some View {
        switch selection {
            case .layouts:
                MonitorLayoutsSettingsPane()
            case .general:
                generalPage
            case .workspaces:
                workspacesPage
            case .applications:
                applicationsPage
            case .automation:
                automationPage
            case .shortcuts:
                shortcutsPage
            case .configFile:
                configFilePage
        }
    }

    private var generalPage: some View {
        SettingsPage(
            title: "General",
            subtitle: "Startup, window-tree behavior and AeroSpace defaults.",
        ) {
            if !conflictMonitor.conflicts.isEmpty {
                SettingsCard(
                    "Window Manager Conflict",
                    systemImage: "exclamationmark.triangle.fill",
                    help: "Only one window manager should control macOS windows at a time.",
                ) {
                    Text("Also running: \(conflictMonitor.conflicts.map(\.name).joined(separator: ", "))")
                        .foregroundStyle(.orange)
                    Text("Quit the other window manager or restart TileSail and choose which one should remain active.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            SettingsCard(
                "Application",
                systemImage: "gearshape.2",
                help: "Configuration version controls the TOML schema. Start at login launches AeroSpace automatically. Auto reload watches the TOML file and reloads external edits.",
            ) {
                Picker("Configuration version", selection: $configSettings.draft.configVersion) {
                    Text("1").tag(1)
                    Text("2").tag(2)
                }
                Toggle("Start at login", isOn: $configSettings.draft.startAtLogin)
                Text("Startup on this Mac is managed by a LaunchAgent. Keep this off to prevent duplicate instances.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Automatically reload the configuration file", isOn: $configSettings.draft.autoReloadConfig)
            }

            SettingsCard(
                "Window Tree",
                systemImage: "point.3.connected.trianglepath.dotted",
                help: "Flatten removes redundant nested containers. Opposite-orientation normalization alternates split directions. Root layout and orientation define new workspaces; accordion padding controls the visible edge of stacked accordion windows.",
            ) {
                Toggle("Automatically flatten containers", isOn: $configSettings.draft.flattenContainers)
                Toggle(
                    "Normalize nested containers with opposite orientations",
                    isOn: $configSettings.draft.normalizeOppositeOrientation,
                )
                Picker("Default root layout", selection: $configSettings.draft.defaultRootLayout) {
                    Text("Tiles").tag("tiles")
                    Text("Accordion").tag("accordion")
                }
                Picker("Default root orientation", selection: $configSettings.draft.defaultRootOrientation) {
                    Text("Automatic").tag("auto")
                    Text("Horizontal").tag("horizontal")
                    Text("Vertical").tag("vertical")
                }
                Stepper(
                    "Accordion padding: \(configSettings.draft.accordionPadding) px",
                    value: $configSettings.draft.accordionPadding,
                    in: 0 ... 1000,
                )
            }

            SettingsCard(
                "Animations",
                systemImage: "waveform.path",
                help: "Duration controls how long a coordinated window reflow takes. Reduce Motion follows the macOS Accessibility preference. A duration of 0 disables layout animations.",
            ) {
                Stepper(
                    "Duration: \(configSettings.draft.layoutAnimationDurationMs) ms",
                    value: $configSettings.draft.layoutAnimationDurationMs,
                    in: 0 ... 1000,
                    step: 10,
                )
                Toggle(
                    "Respect the macOS Reduce Motion setting",
                    isOn: $configSettings.draft.layoutAnimationRespectsReduceMotion,
                )
                Text("Use 0 ms to disable animations. The current default is 160 ms.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            SettingsCard(
                "Updates",
                systemImage: "arrow.down.circle",
                help: "Checks the public TileSail releases on GitHub. Updates are never downloaded or installed automatically.",
            ) {
                Toggle(
                    "Check for updates daily",
                    isOn: Binding(
                        get: { updateChecker.automaticallyChecks },
                        set: { updateChecker.setAutomaticallyChecks($0) },
                    ),
                )
                HStack {
                    updateStatus
                    Spacer()
                    Button("Check Now") {
                        Task.startUnstructured { await updateChecker.check() }
                    }
                    .disabled(updateChecker.status == .checking)
                }
            }

            SettingsCard(
                "Workspace Bar",
                systemImage: "rectangle.topthird.inset.filled",
                help: "Shows a compact clickable workspace strip below the menu bar on each display. It follows the monitor's active workspace and stays available across macOS Spaces.",
            ) {
                Toggle(
                    "Show workspace bar on every display",
                    isOn: Binding(
                        get: { workspaceBar.isEnabled },
                        set: { workspaceBar.setEnabled($0) },
                    ),
                )
                Toggle(
                    "Include empty workspaces",
                    isOn: Binding(
                        get: { workspaceBar.showsEmptyWorkspaces },
                        set: { workspaceBar.setShowsEmptyWorkspaces($0) },
                    ),
                )
                .disabled(!workspaceBar.isEnabled)
            }

            SettingsCard(
                "Menu Bar",
                systemImage: "menubar.rectangle",
                help: "TileSail appears in every menu bar macOS makes available. Choose exactly what each menu bar should show.",
            ) {
                LabeledContent("Appears On") {
                    Label("All Displays", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.secondary)
                }

                Divider()

                Picker(
                    "Show Only",
                    selection: Binding(
                        get: { menuBarAppearance.presentation },
                        set: { menuBarAppearance.setPresentation($0) },
                    ),
                ) {
                    ForEach(MenuBarPresentation.allCases) { presentation in
                        Text(presentation.title).tag(presentation)
                    }
                }
                .pickerStyle(.menu)

                LabeledContent("Preview") {
                    MenuBarLabel()
                        .environmentObject(TrayMenuModel.shared)
                        .padding(.vertical, 7)
                        .padding(.horizontal, 11)
                        .background(.quaternary.opacity(0.55), in: Capsule())
                }

                Text(menuBarAppearance.presentation.explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("Only this style is mirrored across every available menu bar.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    @ViewBuilder
    private var updateStatus: some View {
        switch updateChecker.status {
            case .idle:
                Text("Not checked yet").foregroundStyle(.secondary)
            case .checking:
                ProgressView().controlSize(.small)
                Text("Checking…").foregroundStyle(.secondary)
            case .current(let release):
                Label("Up to date (\(release.version))", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .available(let release):
                Button("\(release.title) is available") {
                    NSWorkspace.shared.open(release.pageUrl)
                }
            case .failed(let message):
                Text(message).foregroundStyle(.secondary)
        }
    }

    private var workspacesPage: some View {
        SettingsPage(
            title: "Workspaces",
            subtitle: "Define persistent workspaces, monitor assignments and gaps.",
        ) {
            SettingsCard(
                "Persistent Workspaces",
                systemImage: "square.grid.3x3",
                help: "Persistent workspaces exist even when they contain no windows, which keeps navigation and monitor assignments stable.",
            ) {
                StringListEditor(
                    items: $configSettings.draft.persistentWorkspaces,
                    placeholder: "Workspace name",
                    addTitle: "Add Workspace",
                )
            }

            SettingsCard(
                "Monitor-relative Workspace Slots",
                systemImage: "rectangle.3.group.bubble.left",
                help: "Map slots 1–10 independently on each monitor. Bind commands such as ‘workspace monitor 1’ or ‘move-node-to-workspace monitor 1’; the same shortcut then resolves through the currently focused monitor.",
            ) {
                MonitorRelativeWorkspaceEditor()
            }

            SettingsCard(
                "Scratchpads",
                systemImage: "macwindow.on.rectangle",
                help: "Arm a slot, then click the window you want to capture. Each slot can hold multiple floating windows and show them over any workspace. Keyboard automation remains available with ‘scratchpad assign N’ and ‘scratchpad toggle N’.",
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(1 ... smoothWorkspaceSlotCount, id: \.self) { slot in
                        scratchpadSlot(slot)
                        if slot < smoothWorkspaceSlotCount { Divider() }
                    }
                    if !scratchpads.statusMessage.isEmpty {
                        Text(scratchpads.statusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .onAppear { scratchpads.refreshWindowItems(force: true) }
            }

            SettingsCard(
                "App Workspaces",
                systemImage: "arrow.uturn.backward.square",
                help: "Remember each app's last used workspace. Reopening an app returns it there and takes you to it. Background apps do not switch your workspace. Explicit app rules take priority.",
            ) {
                Toggle(
                    "Remember where apps open",
                    isOn: Binding(
                        get: { appWorkspaces.isEnabled },
                        set: { appWorkspaces.setEnabled($0) },
                    ),
                )
                Text("Move an app to another workspace to update its saved location. For apps with several windows, the last used or moved window determines the location.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            SettingsCard(
                "Restore Window Layouts",
                systemImage: "arrow.counterclockwise.square",
                help: "TileSail automatically remembers tiling groups, order and proportions and restores them after relaunch when the windows and layout preset still match.",
            ) {
                Toggle(
                    "Remember window layouts automatically",
                    isOn: Binding(
                        get: { manualLayouts.isEnabled },
                        set: { manualLayouts.setEnabled($0) },
                    ),
                )
                HStack {
                    Text("\(manualLayouts.layouts.count) saved workspace layouts")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Clear Saved Layouts") { manualLayouts.clear() }
                        .disabled(manualLayouts.layouts.isEmpty)
                }
            }

            SettingsCard(
                "Workspace Monitor Assignment",
                systemImage: "display.2",
                help: "Pins each workspace to one or more preferred monitors. Monitor names are evaluated in order, and the first connected match is used.",
            ) {
                WorkspaceAssignmentsEditor(assignments: $configSettings.draft.workspaceAssignments)
            }

            SettingsCard(
                "Gaps",
                systemImage: "rectangle.inset.filled",
                help: "Inner gaps add space between tiled windows. Outer gaps reserve space between the tiling area and each screen edge.",
            ) {
                GapsEditor(gaps: $configSettings.draft.gaps)
            }
        }
    }

    private var applicationsPage: some View {
        SettingsPage(
            title: "Applications",
            subtitle: "Choose how application windows enter the AeroSpace layout.",
        ) {
            SettingsCard(
                "Visual App Rules",
                systemImage: "macwindow.badge.plus",
                help: "Match an application and optionally part of its window title, then choose floating or tiled layout and a destination workspace. Rules run from top to bottom and remain standard on-window-detected TOML entries.",
            ) {
                ApplicationRulesEditor(rules: $configSettings.draft.windowRules)
            }

            SettingsCard(
                "Advanced Window Detection Rules",
                systemImage: "arrowshape.turn.up.right.circle",
                help: "Rules that use expressions or commands not represented by the visual editor remain fully editable here.",
            ) {
                WindowRulesEditor(rules: $configSettings.draft.windowRules)
            }
        }
    }

    private var automationPage: some View {
        SettingsPage(
            title: "Automation",
            subtitle: "Environment variables and commands triggered by AeroSpace events.",
        ) {
            SettingsCard(
                "Execution Environment",
                systemImage: "terminal",
                help: "Inherited variables come from the AeroSpace process. Custom variables are added or overridden for commands executed by AeroSpace.",
            ) {
                Toggle(
                    "Inherit environment variables",
                    isOn: $configSettings.draft.inheritEnvironmentVariables,
                )
                KeyValueEditor(
                    pairs: $configSettings.draft.environmentVariables,
                    keyPlaceholder: "VARIABLE",
                    valuePlaceholder: "value",
                    addTitle: "Add Variable",
                )
            }

            SettingsCard(
                "After Login",
                systemImage: "person.crop.circle.badge.checkmark",
                help: "Legacy commands run after macOS login. Current AeroSpace versions keep this list empty; prefer After Startup for normal initialization.",
            ) {
                Text("This option is retained for compatibility; current versions expect this list to be empty.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                StringListEditor(
                    items: $configSettings.draft.afterLoginCommands,
                    placeholder: "Command",
                    addTitle: "Add Command",
                )
            }

            SettingsCard(
                "After Startup",
                systemImage: "play.circle",
                help: "Commands in this list run once after AeroSpace has started and loaded its configuration.",
            ) {
                StringListEditor(
                    items: $configSettings.draft.afterStartupCommands,
                    placeholder: "Command",
                    addTitle: "Add Command",
                )
            }

            SettingsCard(
                "Focused Monitor Changed",
                systemImage: "arrow.left.arrow.right",
                help: "Runs after focus crosses to a different monitor. Use it for status bars or monitor-specific automation, not for workspace reassignment.",
            ) {
                StringListEditor(
                    items: $configSettings.draft.onFocusedMonitorChanged,
                    placeholder: "Command",
                    addTitle: "Add Command",
                )
            }

            SettingsCard(
                "Focus Changed",
                systemImage: "scope",
                help: "Runs whenever the focused window or workspace changes. Keep these commands fast because the event may occur frequently.",
            ) {
                StringListEditor(
                    items: $configSettings.draft.onFocusChanged,
                    placeholder: "Command",
                    addTitle: "Add Command",
                )
            }
        }
    }

    private var shortcutsPage: some View {
        SettingsPage(
            title: "Shortcuts",
            subtitle: "All key bindings from the main and service modes.",
        ) {
            SettingsCard(
                "Quick Tools",
                systemImage: "command",
                help: "Overview shows every workspace and window. Command Palette searches common actions. Both are also regular commands, so any user can assign them to a key in Main Mode.",
            ) {
                HStack {
                    Button("Open Overview") {
                        WorkspaceNavigatorController.shared.show(.overview)
                    }
                    Button("Open Command Palette") {
                        WorkspaceNavigatorController.shared.show(.commandPalette)
                    }
                }
                Text("Example commands: ‘overview’ and ‘command-palette’")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            SettingsCard(
                "Main Mode",
                systemImage: "keyboard",
                help: "Main-mode bindings are the shortcuts available during normal use. A binding can run one command or a command chain.",
            ) {
                HotkeyBindingsEditor(bindings: $configSettings.draft.mainBindings)
            }
            SettingsCard(
                "Service Mode",
                systemImage: "wrench.and.screwdriver",
                help: "Service-mode bindings are available only after entering that mode and are typically used for maintenance or recovery commands.",
            ) {
                HotkeyBindingsEditor(bindings: $configSettings.draft.serviceBindings)
            }
        }
    }

    private var configFilePage: some View {
        SettingsPage(
            title: "TOML File",
            subtitle: configSettings.configPath,
        ) {
            HStack {
                Button("Open in Editor") { configSettings.openConfigFile() }
                Button("Reload from Disk") { configSettings.load() }
                Spacer()
            }

            SettingsCard(
                "Comment-Preserving Preview",
                systemImage: "doc.text.magnifyingglass",
                help: "Shows the exact TOML that will be saved. Existing comments and unrelated keys are preserved when visual settings are updated.",
            ) {
                ScrollView([.horizontal, .vertical]) {
                    Text(configSettings.previewText)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .frame(minHeight: 480)
                .background(.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var settingsFooter: some View {
        HStack(spacing: 12) {
            statusLabel
            Spacer()
            if selection == .layouts {
                Text("Layout changes are applied immediately.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Button("Discard") { configSettings.discardChanges() }
                    .disabled(!configSettings.hasChanges)
                Button("Save & Apply") {
                    Task.startUnstructured { await configSettings.save() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!configSettings.hasChanges || configSettings.status == .saving)
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 54)
    }

    @ViewBuilder
    private func scratchpadSlot(_ slot: Int) -> some View {
        let items = scratchpads.items(in: slot)
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("Slot \(slot)")
                    .fontWeight(.semibold)
                    .frame(width: 54, alignment: .leading)
                Text("\(items.count) \(items.count == 1 ? "window" : "windows")")
                    .foregroundStyle(.secondary)
                Spacer()
                if scratchpads.armedSlot == slot {
                    Button("Cancel Capture") { scratchpads.cancelCapture() }
                } else {
                    Button("Capture Next Window…") { scratchpads.beginCapture(for: slot) }
                        .disabled(scratchpads.armedSlot != nil)
                }
                Button(scratchpads.isPresented(slot: slot, on: focus.workspace) ? "Hide" : "Show") {
                    toggleScratchpad(slot)
                }
                .disabled(items.isEmpty)
            }

            if scratchpads.armedSlot == slot {
                Label("Now click the window you want to add to this slot.", systemImage: "scope")
                    .font(.caption)
                    .foregroundStyle(.blue)
            }

            ForEach(items) { item in
                ScratchpadWindowRow(item: item) {
                    removeScratchpadWindow(item.id, from: slot)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func toggleScratchpad(_ slot: Int) {
        guard let token: RunSessionGuard = .isServerEnabled else {
            scratchpads.cancelCapture()
            return
        }
        Task.startUnstructured { @MainActor in
            try await runLightSession(.menuBarButton, token) {
                let parsed = parseCommand(["scratchpad", "toggle", String(slot)])
                guard let command = parsed.cmdOrNil else {
                    return
                }
                _ = await command.run(.defaultEnv, .emptyStdin)
            }
        }
    }

    private func removeScratchpadWindow(_ windowId: UInt32, from slot: Int) {
        guard let token: RunSessionGuard = .isServerEnabled else { return }
        Task.startUnstructured { @MainActor in
            try await runLightSession(.menuBarButton, token) {
                scratchpads.remove(windowId: windowId, from: slot)
            }
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch configSettings.status {
            case .ready:
                if configSettings.hasChanges {
                    Label("Unsaved changes", systemImage: "circle.fill")
                        .foregroundStyle(.orange)
                }
            case .saving:
                ProgressView().controlSize(.small)
                Text("Validating and saving…")
            case .saved(let message):
                Label(message, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .lineLimit(1)
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .lineLimit(2)
        }
    }
}

@MainActor
private struct ScratchpadWindowRow: View {
    let item: ScratchpadWindowItem
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: applicationIcon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .lineLimit(1)
                Text(item.applicationName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(item.isPresented ? "Visible" : "Hidden")
                .font(.caption)
                .foregroundStyle(item.isPresented ? .green : .secondary)
            Button(action: onRemove) {
                Label("Remove", systemImage: "minus.circle")
            }
            .buttonStyle(.borderless)
            .help("Remove from this scratchpad, return it to the current workspace and restore its previous layout")
        }
        .padding(.leading, 64)
    }

    private var applicationIcon: NSImage {
        item.applicationPath
            .map { NSWorkspace.shared.icon(forFile: $0) }
            ?? NSImage(systemSymbolName: "macwindow", accessibilityDescription: nil)
            ?? NSImage()
    }
}

@MainActor
private struct MonitorRelativeWorkspaceEditor: View {
    @ObservedObject private var settings = SmoothLayoutSettingsStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(sortedMonitorInfos, id: \.stableIdentifier) { monitor in
                let profile = settings.profile(for: monitor).normalized
                DisclosureGroup(monitor.name) {
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                        ForEach(1 ... smoothWorkspaceSlotCount, id: \.self) { slot in
                            GridRow {
                                Text("Slot \(slot)")
                                    .frame(width: 54, alignment: .leading)
                                TextField(
                                    "Automatic",
                                    text: Binding(
                                        get: { settings.profile(for: monitor).normalized.workspaceSlots[slot - 1] },
                                        set: {
                                            settings.setWorkspaceName(
                                                $0,
                                                slot: slot,
                                                monitorIdentifier: monitor.stableIdentifier,
                                                monitorName: monitor.name,
                                                isHorizontal: monitor.width >= monitor.height,
                                            )
                                        },
                                    ),
                                )
                                .font(.system(.body, design: .monospaced))
                            }
                        }
                    }
                    .padding(.top, 8)
                }
                .padding(10)
                .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 9))
                .accessibilityValue("\(profile.workspaceSlots.count) workspace slots")
            }
            Text("Leave a slot empty to use the existing workspaces already associated with that monitor in natural sort order.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct SettingsPage<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.largeTitle.bold())
                    Text(subtitle).foregroundStyle(.secondary)
                }
                content
            }
            .padding(24)
            .frame(maxWidth: 920, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
    }
}

private struct SettingsCard<Content: View>: View {
    let title: String
    let systemImage: String
    let help: String
    @ViewBuilder let content: Content

    init(_ title: String, systemImage: String, help: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.help = help
        self.content = content()
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
        } label: {
            HStack(spacing: 6) {
                Label(title, systemImage: systemImage)
                SettingInfoButton(title: title, message: help)
            }
            .font(.headline)
        }
    }
}

struct SettingInfoButton: View {
    let title: String
    let message: String
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .font(.body)
        .help("About \(title)")
        .accessibilityLabel("About \(title)")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.headline)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(width: 320, alignment: .leading)
        }
    }
}

private struct StringListEditor: View {
    @Binding var items: [String]
    let placeholder: String
    let addTitle: String

    var body: some View {
        VStack(spacing: 8) {
            ForEach(items.indices, id: \.self) { index in
                HStack {
                    TextField(placeholder, text: $items[index])
                        .textFieldStyle(.roundedBorder)
                    RemoveRowButton { items.remove(at: index) }
                }
            }
            AddRowButton(addTitle) { items.append("") }
        }
    }
}

private struct KeyValueEditor: View {
    @Binding var pairs: [VisualConfigPair]
    let keyPlaceholder: String
    let valuePlaceholder: String
    let addTitle: String

    var body: some View {
        VStack(spacing: 8) {
            ForEach($pairs) { $pair in
                HStack {
                    TextField(keyPlaceholder, text: $pair.key).frame(width: 180)
                    TextField(valuePlaceholder, text: $pair.value)
                    RemoveRowButton { pairs.removeAll { $0.id == pair.id } }
                }
            }
            AddRowButton(addTitle) { pairs.append(VisualConfigPair(key: "", value: "")) }
        }
    }
}

private struct WorkspaceAssignmentsEditor: View {
    @Binding var assignments: [VisualWorkspaceAssignment]

    var body: some View {
        VStack(spacing: 8) {
            ForEach($assignments) { $assignment in
                HStack {
                    TextField("Workspace", text: $assignment.workspace).frame(width: 110)
                    TextField(
                        "Monitors separated by commas",
                        text: Binding(
                            get: { assignment.monitors.joined(separator: ", ") },
                            set: {
                                assignment.monitors = $0.split(separator: ",")
                                    .map { $0.trimmingCharacters(in: .whitespaces) }
                                    .filter { !$0.isEmpty }
                            },
                        ),
                    )
                    RemoveRowButton { assignments.removeAll { $0.id == assignment.id } }
                }
            }
            AddRowButton("Add Assignment") {
                assignments.append(VisualWorkspaceAssignment(workspace: "", monitors: ["main"]))
            }
        }
    }
}

@MainActor
private struct ApplicationRulesEditor: View {
    @Binding var rules: [VisualWindowRule]
    @State private var isApplicationPickerPresented = false

    private var applicationRuleIds: [UUID] {
        rules.filter { $0.visualApplicationRule != nil }.map(\.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if applicationRuleIds.isEmpty {
                Text("No visual application rules yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(applicationRuleIds.enumerated()), id: \.element) { visibleIndex, ruleId in
                    if let rule = rules.first(where: { $0.id == ruleId })?.visualApplicationRule {
                        ApplicationRuleEditorRow(
                            application: .resolve(bundleIdentifier: rule.bundleIdentifier),
                            ruleNumber: (rules.firstIndex(where: { $0.id == ruleId }) ?? 0) + 1,
                            rule: applicationRuleBinding(for: ruleId),
                            canMoveUp: visibleIndex > 0,
                            canMoveDown: visibleIndex < applicationRuleIds.count - 1,
                            onMoveUp: { moveRule(ruleId, offset: -1) },
                            onMoveDown: { moveRule(ruleId, offset: 1) },
                            onRemove: { rules.removeAll { $0.id == ruleId } },
                        )
                    }
                }
            }

            Button {
                isApplicationPickerPresented = true
            } label: {
                Label("Add Application…", systemImage: "plus")
            }
            .sheet(isPresented: $isApplicationPickerPresented) {
                ApplicationPicker(
                    excludedBundleIdentifiers: Set(rules.compactMap { $0.visualApplicationRule?.bundleIdentifier }),
                    onSelect: addApplication,
                )
            }
            Text("Rules apply to newly detected windows. Reopen existing windows after saving. Use the arrows to set priority.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func applicationRuleBinding(for ruleId: UUID) -> Binding<VisualApplicationRule> {
        Binding(
            get: {
                rules.first(where: { $0.id == ruleId })?.visualApplicationRule ?? VisualApplicationRule(
                    bundleIdentifier: "",
                    titleContains: "",
                    layout: .floating,
                    workspace: "",
                )
            },
            set: { applicationRule in
                guard let index = rules.firstIndex(where: { $0.id == ruleId }) else { return }
                rules[index] = VisualWindowRule(
                    id: ruleId,
                    applicationRule: applicationRule,
                    checkFurtherCallbacks: rules[index].checkFurtherCallbacks,
                )
            },
        )
    }

    private func moveRule(_ ruleId: UUID, offset: Int) {
        guard let visibleIndex = applicationRuleIds.firstIndex(of: ruleId) else { return }
        let destination = visibleIndex + offset
        guard applicationRuleIds.indices.contains(destination),
              let sourceIndex = rules.firstIndex(where: { $0.id == ruleId }),
              let destinationIndex = rules.firstIndex(where: { $0.id == applicationRuleIds[destination] })
        else { return }
        rules.swapAt(sourceIndex, destinationIndex)
    }

    private func addApplication(_ application: VisualApplicationChoice) {
        guard !rules.contains(where: { $0.visualApplicationRule?.bundleIdentifier == application.bundleIdentifier }) else { return }
        rules.insert(
            VisualWindowRule(applicationBundleIdentifier: application.bundleIdentifier, layout: .floating),
            at: 0,
        )
    }
}

@MainActor
private struct ApplicationRuleEditorRow: View {
    let application: VisualApplicationChoice
    let ruleNumber: Int
    @Binding var rule: VisualApplicationRule
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(nsImage: application.icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(ruleNumber). \(application.name)")
                    Text(application.bundleIdentifier)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Spacer(minLength: 12)
                Button(action: onMoveUp) { Image(systemName: "arrow.up") }
                    .disabled(!canMoveUp)
                    .help("Increase rule priority")
                Button(action: onMoveDown) { Image(systemName: "arrow.down") }
                    .disabled(!canMoveDown)
                    .help("Decrease rule priority")
                RemoveRowButton(action: onRemove)
            }

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    Text("Title contains")
                    TextField("Any title", text: $rule.titleContains)
                }
                GridRow {
                    Text("Layout")
                    Picker("Layout", selection: $rule.layout) {
                        Text("No change").tag(nil as VisualApplicationWindowLayout?)
                        ForEach(VisualApplicationWindowLayout.allCases) { layout in
                            Text(layout.title).tag(Optional(layout))
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }
                GridRow {
                    Text("Workspace")
                    TextField("Keep current, or enter a workspace without spaces", text: $rule.workspace)
                }
                GridRow {
                    Text("Scratchpad")
                    Picker("Scratchpad", selection: $rule.scratchpadSlot) {
                        Text("None").tag(nil as Int?)
                        ForEach(1 ... smoothWorkspaceSlotCount, id: \.self) { slot in
                            Text("Slot \(slot)").tag(Optional(slot))
                        }
                    }
                    .labelsHidden()
                }
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 9))
    }
}

@MainActor
private struct ApplicationPicker: View {
    @Environment(\.dismiss) private var dismiss
    let excludedBundleIdentifiers: Set<String>
    let onSelect: (VisualApplicationChoice) -> Void

    @State private var applications: [VisualApplicationChoice] = []
    @State private var searchText = ""
    @State private var isLoading = true

    private var filteredApplications: [VisualApplicationChoice] {
        applications.filter { application in
            !excludedBundleIdentifiers.contains(application.bundleIdentifier) &&
                (searchText.isEmpty || application.name.localizedCaseInsensitiveContains(searchText) ||
                    application.bundleIdentifier.localizedCaseInsensitiveContains(searchText))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Choose an Application")
                    .font(.title2.bold())
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search applications", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 10)
                .frame(height: 34)
                .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
            }
            .padding(18)

            Divider()

            if isLoading {
                Spacer()
                ProgressView("Finding applications…")
                Spacer()
            } else if filteredApplications.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "app.dashed")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text(searchText.isEmpty ? "No More Applications" : "No Applications Found")
                        .font(.headline)
                    Text(searchText.isEmpty ? "Every discovered application already has a layout choice." : "Try a different name or bundle identifier.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            } else {
                List(filteredApplications) { application in
                    Button {
                        select(application)
                    } label: {
                        HStack(spacing: 12) {
                            Image(nsImage: application.icon)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 32, height: 32)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(application.name)
                                    .foregroundStyle(.primary)
                                Text(application.bundleIdentifier)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.inset)
            }

            Divider()
            HStack {
                Button("Choose Other…", action: chooseOtherApplication)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(14)
        }
        .frame(width: 560, height: 620)
        .task {
            let runningApplicationURLs = NSWorkspace.shared.runningApplications.compactMap(\.bundleURL)
            applications = VisualApplicationChoice.discover(including: runningApplicationURLs)
            isLoading = false
        }
    }

    private func select(_ application: VisualApplicationChoice) {
        onSelect(application)
        dismiss()
    }

    private func chooseOtherApplication() {
        let panel = NSOpenPanel()
        panel.title = "Choose an Application"
        panel.prompt = "Choose"
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.treatsFilePackagesAsDirectories = false
        guard panel.runModal() == .OK, let url = panel.url, let application = VisualApplicationChoice(bundleURL: url) else { return }
        select(application)
    }
}

private struct VisualApplicationChoice: Identifiable, Sendable {
    let bundleIdentifier: String
    let name: String
    let bundleURL: URL?

    var id: String { bundleIdentifier }

    init?(bundleURL: URL) {
        guard let bundle = Bundle(url: bundleURL), let bundleIdentifier = bundle.bundleIdentifier else { return nil }
        self.bundleIdentifier = bundleIdentifier
        self.name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String) ??
            (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String) ??
            bundleURL.deletingPathExtension().lastPathComponent
        self.bundleURL = bundleURL
    }

    private init(bundleIdentifier: String, name: String, bundleURL: URL?) {
        self.bundleIdentifier = bundleIdentifier
        self.name = name
        self.bundleURL = bundleURL
    }

    @MainActor
    static func resolve(bundleIdentifier: String) -> Self {
        if let bundleURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier),
           let application = Self(bundleURL: bundleURL)
        {
            return application
        }
        return Self(bundleIdentifier: bundleIdentifier, name: bundleIdentifier, bundleURL: nil)
    }

    static func discover(including additionalURLs: [URL]) -> [Self] {
        let fileManager = FileManager.default
        let roots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Library/CoreServices/Applications", isDirectory: true),
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true),
        ]
        var applicationURLs = additionalURLs
        for root in roots {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
            ) else { continue }
            applicationURLs += enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "app" }
        }

        var applicationsByBundleIdentifier: [String: Self] = [:]
        for url in applicationURLs {
            guard let application = Self(bundleURL: url), applicationsByBundleIdentifier[application.bundleIdentifier] == nil else { continue }
            applicationsByBundleIdentifier[application.bundleIdentifier] = application
        }
        return applicationsByBundleIdentifier.values.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    @MainActor
    var icon: NSImage {
        if let bundleURL { return NSWorkspace.shared.icon(forFile: bundleURL.path) }
        return NSImage(systemSymbolName: "app", accessibilityDescription: nil) ?? NSImage(size: NSSize(width: 32, height: 32))
    }
}

private struct WindowRulesEditor: View {
    @Binding var rules: [VisualWindowRule]

    private var advancedRuleIds: [UUID] {
        rules.filter { $0.visualApplicationRule == nil }.map(\.id)
    }

    var body: some View {
        VStack(spacing: 12) {
            if advancedRuleIds.isEmpty {
                Text("No advanced window rules.")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(.secondary)
            }
            ForEach(advancedRuleIds, id: \.self) { ruleId in
                if let index = rules.firstIndex(where: { $0.id == ruleId }) {
                    WindowRuleEditorRow(
                        rule: $rules[index],
                        onRemove: { rules.removeAll { $0.id == ruleId } },
                    )
                }
            }
            AddRowButton("Add Rule") {
                rules.append(VisualWindowRule(condition: "", commands: [""]))
            }
        }
    }
}

private struct WindowRuleEditorRow: View {
    @Binding var rule: VisualWindowRule
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Condition").frame(width: 70, alignment: .leading)
                TextField("test %{app-bundle-id} = …", text: $rule.condition)
                RemoveRowButton(action: onRemove)
            }
            CommandListEditor(commands: $rule.commands)
            Toggle("Continue evaluating later rules after a match", isOn: $rule.checkFurtherCallbacks)
                .font(.caption)
        }
        .padding(10)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 9))
    }
}

private struct HotkeyBindingsEditor: View {
    @Binding var bindings: [VisualHotkeyBinding]

    var body: some View {
        VStack(spacing: 10) {
            ForEach($bindings) { $binding in
                HStack(alignment: .top, spacing: 10) {
                    TextField("alt-…", text: $binding.shortcut)
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 180)
                    CommandListEditor(commands: $binding.commands)
                    RemoveRowButton { bindings.removeAll { $0.id == binding.id } }
                }
                .padding(.vertical, 2)
            }
            AddRowButton("Add Shortcut") {
                bindings.append(VisualHotkeyBinding(shortcut: "", commands: [""]))
            }
        }
    }
}

private struct CommandListEditor: View {
    @Binding var commands: [String]

    var body: some View {
        VStack(spacing: 6) {
            ForEach(commands.indices, id: \.self) { index in
                HStack {
                    TextField("Command", text: $commands[index])
                        .font(.system(.body, design: .monospaced))
                    if commands.count > 1 {
                        RemoveRowButton { commands.remove(at: index) }
                    }
                }
            }
            Button {
                commands.append("")
            } label: {
                Label("Chain Command", systemImage: "arrow.right")
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct GapsEditor: View {
    @Binding var gaps: VisualConfigGaps

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 22, verticalSpacing: 10) {
            GridRow {
                gapStepper("Inner horizontal", value: $gaps.innerHorizontal)
                gapStepper("Inner vertical", value: $gaps.innerVertical)
            }
            GridRow {
                gapStepper("Outer left", value: $gaps.outerLeft)
                gapStepper("Outer right", value: $gaps.outerRight)
            }
            GridRow {
                gapStepper("Outer top", value: $gaps.outerTop)
                gapStepper("Outer bottom", value: $gaps.outerBottom)
            }
        }
    }

    private func gapStepper(_ title: String, value: Binding<Int>) -> some View {
        Stepper("\(title): \(value.wrappedValue) px", value: value, in: 0 ... 200)
            .frame(minWidth: 260, alignment: .leading)
    }
}

private struct AddRowButton: View {
    let title: String
    let action: () -> Void

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: "plus.circle")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.tint)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct RemoveRowButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "minus.circle.fill")
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help("Remove")
    }
}

@MainActor
private struct MonitorLayoutsSettingsPane: View {
    @ObservedObject private var settings = SmoothLayoutSettingsStore.shared
    @State private var selectedMonitorId: String?
    @State private var customEditorTarget: SmoothCustomLayoutEditorTarget?

    private var monitors: [SmoothMonitorSummary] {
        sortedMonitorInfos.map {
            SmoothMonitorSummary(
                identifier: $0.stableIdentifier,
                name: $0.name,
                width: $0.width,
                height: $0.height,
            )
        }
    }

    private var selectedMonitor: SmoothMonitorSummary? {
        monitors.first { $0.id == selectedMonitorId } ?? monitors.first
    }

    var body: some View {
        HSplitView {
            monitorSidebar
                .frame(minWidth: 220, idealWidth: 240, maxWidth: 280)

            if let monitor = selectedMonitor {
                monitorEditor(monitor)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "display.trianglebadge.exclamationmark")
                        .font(.largeTitle)
                    Text("No monitors found")
                        .font(.headline)
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            for monitor in sortedMonitorInfos {
                _ = settings.profile(for: monitor)
            }
            if selectedMonitorId == nil {
                selectedMonitorId = monitors.first?.id
            }
        }
        .onChange(of: settings.monitorConfigurationRevision) { _ in
            if !monitors.contains(where: { $0.id == selectedMonitorId }) {
                selectedMonitorId = monitors.first?.id
            }
        }
        .sheet(item: $customEditorTarget) { target in
            SmoothCustomLayoutEditorView(
                monitorName: target.monitor.name,
                monitorWidth: target.monitor.width,
                monitorHeight: target.monitor.height,
                layout: target.layout,
                previousLayout: target.previousLayout,
            ) { layout in
                settings.setCustomLayout(
                    layout,
                    windowCount: target.windowCount,
                    monitorIdentifier: target.monitor.identifier,
                    monitorName: target.monitor.name,
                    isHorizontal: target.monitor.isHorizontal,
                )
            }
        }
    }

    private var monitorSidebar: some View {
        List(monitors, selection: $selectedMonitorId) { monitor in
            VStack(alignment: .leading, spacing: 4) {
                Label(monitor.name, systemImage: monitor.isHorizontal ? "display" : "rectangle.portrait")
                    .font(.headline)
                Text("\(monitor.orientationTitle) · \(Int(monitor.width))×\(Int(monitor.height))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 6)
            .tag(monitor.id)
        }
    }

    private func monitorEditor(_ monitor: SmoothMonitorSummary) -> some View {
        let profile = settings.profile(
            identifier: monitor.identifier,
            named: monitor.name,
            isHorizontal: monitor.isHorizontal,
        ).normalized
        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(monitor.name)
                            .font(.largeTitle.bold())
                        Text("Choose how this monitor arranges from 1 to 10 windows.")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Reset to Defaults") {
                        settings.resetProfile(
                            monitorIdentifier: monitor.identifier,
                            monitorName: monitor.name,
                            isHorizontal: monitor.isHorizontal,
                        )
                    }
                }

                HStack {
                    Toggle(
                        "Automatic layout on this monitor",
                        isOn: Binding(
                            get: {
                                settings.profile(
                                    identifier: monitor.identifier,
                                    named: monitor.name,
                                    isHorizontal: monitor.isHorizontal,
                                ).enabled
                            },
                            set: {
                                settings.setEnabled(
                                    $0,
                                    monitorIdentifier: monitor.identifier,
                                    monitorName: monitor.name,
                                    isHorizontal: monitor.isHorizontal,
                                )
                            },
                        ),
                    )
                    .toggleStyle(.switch)
                    SettingInfoButton(
                        title: "Automatic layout",
                        message: "When enabled, TileSail selects the layout configured for the current number of tiled windows on this monitor. Disable it to use standard AeroSpace behavior.",
                    )
                }

                HStack {
                    Text("Window limit per workspace")
                    SettingInfoButton(
                        title: "Window limit per workspace",
                        message: "When a workspace exceeds this number of tiled windows, overflow windows move to another workspace assigned to the same monitor.",
                    )
                    Spacer()
                    Stepper(
                        "\(profile.tileLimit)",
                        value: Binding(
                            get: {
                                settings.profile(
                                    identifier: monitor.identifier,
                                    named: monitor.name,
                                    isHorizontal: monitor.isHorizontal,
                                ).tileLimit
                            },
                            set: {
                                settings.setTileLimit(
                                    $0,
                                    monitorIdentifier: monitor.identifier,
                                    monitorName: monitor.name,
                                    isHorizontal: monitor.isHorizontal,
                                )
                            },
                        ),
                        in: 1 ... SmoothMonitorLayoutProfile.configuredWindowCount,
                    )
                    .frame(width: 110)
                    .disabled(!profile.enabled)
                }

                VStack(alignment: .leading, spacing: 14) {
                    ForEach(1 ... SmoothMonitorLayoutProfile.configuredWindowCount, id: \.self) { count in
                        layoutCard(
                            monitor: monitor,
                            count: count,
                            style: profile.style(for: count),
                            customLayout: profile.customLayout(for: count),
                            previousLayout: count > 1 ? editableLayout(
                                profile: profile,
                                count: count - 1,
                                monitorIsHorizontal: monitor.isHorizontal,
                            ) : nil,
                            enabled: profile.enabled,
                        )
                    }
                }
            }
            .padding(24)
        }
    }

    private func layoutCard(
        monitor: SmoothMonitorSummary,
        count: Int,
        style: SmoothLayoutStyle,
        customLayout: SmoothCustomLayoutBlueprint?,
        previousLayout: SmoothCustomLayoutBlueprint?,
        enabled: Bool,
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(count) \(count == 1 ? "window" : "windows")")
                    .font(.headline)
                SettingInfoButton(
                    title: "\(count)-window layout",
                    message: style.detail + " This selection applies only to this monitor when exactly \(count) tiled \(count == 1 ? "window is" : "windows are") present.",
                )
                Spacer()
                Menu {
                    ForEach(SmoothLayoutStyle.available(for: count)) { candidate in
                        Button {
                            settings.setStyle(
                                candidate,
                                windowCount: count,
                                monitorIdentifier: monitor.identifier,
                                monitorName: monitor.name,
                                isHorizontal: monitor.isHorizontal,
                            )
                        } label: {
                            if candidate == style {
                                Label(candidate.title, systemImage: "checkmark")
                            } else {
                                Text(candidate.title)
                            }
                        }
                    }
                } label: {
                    Text(style.title)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(width: 160)
            }

            SmoothMonitorPreviewFrame(
                monitorName: monitor.name,
                monitorWidth: monitor.width,
                monitorHeight: monitor.height,
            ) {
                SmoothLayoutPreview(
                    style: style,
                    windowCount: count,
                    monitorIsHorizontal: monitor.isHorizontal,
                    customLayout: customLayout,
                )
            }
            .frame(height: monitor.layoutPreviewHeight)

            if style == .manual {
                Button {
                    customEditorTarget = SmoothCustomLayoutEditorTarget(
                        monitor: monitor,
                        windowCount: count,
                        layout: customLayout ?? .preset(
                            style: count == 1 ? .fullscreen : .dwindle,
                            windowCount: count,
                            monitorIsHorizontal: monitor.isHorizontal,
                        ),
                        previousLayout: previousLayout,
                    )
                } label: {
                    Label("Edit Custom Layout", systemImage: "slider.horizontal.3")
                }
                .buttonStyle(.borderedProminent)
            }

            Text(style.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(14)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .opacity(enabled ? 1 : 0.7)
    }

    private func editableLayout(
        profile: SmoothMonitorLayoutProfile,
        count: Int,
        monitorIsHorizontal: Bool,
    ) -> SmoothCustomLayoutBlueprint {
        profile.customLayout(for: count) ?? .preset(
            style: profile.style(for: count),
            windowCount: count,
            monitorIsHorizontal: monitorIsHorizontal,
        )
    }
}

private struct SmoothLayoutPreview: View {
    let style: SmoothLayoutStyle
    let windowCount: Int
    let monitorIsHorizontal: Bool
    let customLayout: SmoothCustomLayoutBlueprint?

    var body: some View {
        GeometryReader { geometry in
            let inset = CGFloat(5)
            let canvas = CGRect(
                x: inset,
                y: inset,
                width: geometry.size.width - inset * 2,
                height: geometry.size.height - inset * 2,
            )
            let frames: [(Int, CGRect)] = if style == .manual, let customLayout {
                customLayout.frames.sorted { $0.key < $1.key }
            } else {
                SmoothLayoutPreviewGeometry.frames(
                    style: style,
                    count: windowCount,
                    monitorIsHorizontal: monitorIsHorizontal,
                ).enumerated().map { ($0.offset, $0.element) }
            }

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.black.opacity(0.72))

                if style == .manual, customLayout == nil {
                    VStack(spacing: 6) {
                        Image(systemName: "hand.draw")
                            .font(.title2)
                        Text("Custom layout not configured")
                            .font(.caption.bold())
                    }
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ForEach(Array(frames.enumerated()), id: \.offset) { _, item in
                        let (index, frame) = item
                        let rect = CGRect(
                            x: canvas.minX + frame.minX * canvas.width,
                            y: canvas.minY + frame.minY * canvas.height,
                            width: frame.width * canvas.width,
                            height: frame.height * canvas.height,
                        ).insetBy(dx: 2, dy: 2)

                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: index == 0
                                        ? [Color.cyan, Color.green]
                                        : [Color.blue.opacity(0.75), Color.purple.opacity(0.8)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing,
                                ),
                            )
                            .overlay {
                                Text("\(index + 1)")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.white)
                            }
                            .frame(width: max(rect.width, 1), height: max(rect.height, 1))
                            .offset(x: rect.minX, y: rect.minY)
                    }
                }
            }
        }
        .accessibilityLabel("Preview of \(style.title) with \(windowCount) windows")
    }
}

enum SmoothLayoutPreviewGeometry {
    static func frames(style requestedStyle: SmoothLayoutStyle, count: Int, monitorIsHorizontal: Bool) -> [CGRect] {
        guard count > 0 else { return [] }
        let style: SmoothLayoutStyle = count == 1
            ? requestedStyle == .manual ? .manual : .fullscreen
            : requestedStyle == .fullscreen ? .columns : requestedStyle
        let full = CGRect(x: 0, y: 0, width: 1, height: 1)

        switch style {
            case .manual:
                return []
            case .fullscreen:
                return [full]
            case .columns:
                return (0 ..< count).map {
                    CGRect(x: CGFloat($0) / CGFloat(count), y: 0, width: 1 / CGFloat(count), height: 1)
                }
            case .rows:
                return (0 ..< count).map {
                    CGRect(x: 0, y: CGFloat($0) / CGFloat(count), width: 1, height: 1 / CGFloat(count))
                }
            case .dwindle:
                var result: [CGRect] = []
                appendDwindleFrames(count: count, depth: 0, region: full, result: &result)
                return result
            case .verticalPairs:
                return rowFrames(count: count, columnsPerRow: 2)
            case .grid:
                let aspectRatio = monitorIsHorizontal ? 16.0 / 9.0 : 9.0 / 16.0
                let columns = min(count, max(1, Int(ceil(sqrt(Double(count) * aspectRatio)))))
                return rowFrames(count: count, columnsPerRow: columns)
        }
    }

    private static func appendDwindleFrames(count: Int, depth: Int, region: CGRect, result: inout [CGRect]) {
        if count == 1 {
            result.append(region)
            return
        }

        if depth.isMultiple(of: 2) {
            result.append(CGRect(x: region.minX, y: region.minY, width: region.width / 2, height: region.height))
            appendDwindleFrames(
                count: count - 1,
                depth: depth + 1,
                region: CGRect(x: region.midX, y: region.minY, width: region.width / 2, height: region.height),
                result: &result,
            )
        } else {
            result.append(CGRect(x: region.minX, y: region.minY, width: region.width, height: region.height / 2))
            appendDwindleFrames(
                count: count - 1,
                depth: depth + 1,
                region: CGRect(x: region.minX, y: region.midY, width: region.width, height: region.height / 2),
                result: &result,
            )
        }
    }

    private static func rowFrames(count: Int, columnsPerRow: Int) -> [CGRect] {
        let rowCount = Int(ceil(Double(count) / Double(columnsPerRow)))
        var result: [CGRect] = []
        var remaining = count

        for row in 0 ..< rowCount {
            let columnsInThisRow = min(columnsPerRow, remaining)
            for column in 0 ..< columnsInThisRow {
                result.append(
                    CGRect(
                        x: CGFloat(column) / CGFloat(columnsInThisRow),
                        y: CGFloat(row) / CGFloat(rowCount),
                        width: 1 / CGFloat(columnsInThisRow),
                        height: 1 / CGFloat(rowCount),
                    ),
                )
            }
            remaining -= columnsInThisRow
        }
        return result
    }
}
