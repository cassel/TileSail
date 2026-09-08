import AppKit
import Combine
import Common
import SwiftUI

enum WorkspaceNavigatorMode: String, CaseIterable, Hashable, Identifiable {
    case overview
    case commandPalette

    var id: String { rawValue }

    var title: String {
        switch self {
            case .overview: "Overview"
            case .commandPalette: "Command Palette"
        }
    }

    var systemImage: String {
        switch self {
            case .overview: "rectangle.3.group"
            case .commandPalette: "command"
        }
    }
}

private struct NavigatorWindowItem: Identifiable {
    let id: UInt32
    let title: String
    let applicationName: String
    let applicationPath: String?
    let isFocused: Bool
    let isFloating: Bool
}

private struct NavigatorWorkspaceItem: Identifiable {
    let name: String
    let isActive: Bool
    let isFocused: Bool
    let windows: [NavigatorWindowItem]

    var id: String { name }
}

private struct NavigatorMonitorItem: Identifiable {
    let id: String
    let name: String
    let workspaces: [NavigatorWorkspaceItem]
}

private enum PaletteAction {
    case command([String])
    case showOverview
}

private struct PaletteItem: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let systemImage: String
    let action: PaletteAction

    var searchText: String { "\(title) \(subtitle)".lowercased() }
}

@MainActor
private final class WorkspaceNavigatorModel: ObservableObject {
    @Published var mode: WorkspaceNavigatorMode = .overview
    @Published var query = ""
    @Published var selectedPaletteItemId: String?
    @Published private(set) var monitors: [NavigatorMonitorItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var statusMessage = ""

    private var reloadTask: Task<(), Never>?

    func prepare(_ mode: WorkspaceNavigatorMode) {
        self.mode = mode
        query = ""
        statusMessage = ""
        reload()
    }

    func reload() {
        reloadTask?.cancel()
        isLoading = true
        reloadTask = Task.startUnstructured { @MainActor [weak self] in
            guard let self else { return }
            var nextMonitors: [NavigatorMonitorItem] = []
            for monitor in sortedMonitorInfos {
                let workspaces = Workspace.all
                    .filter {
                        $0.isUserFacing &&
                            $0.workspaceMonitor.stableIdentifier == monitor.stableIdentifier
                    }
                    .sorted()
                var workspaceItems: [NavigatorWorkspaceItem] = []
                for workspace in workspaces {
                    guard !Task.isCancelled else { return }
                    var windowItems: [NavigatorWindowItem] = []
                    for window in workspace.allLeafWindowsRecursive.sorted(by: { $0.windowId < $1.windowId }) {
                        let title = (try? await window.getTitle(.cancellable))
                            .flatMap { $0.takeIf { !$0.isEmpty } }
                            ?? window.app.name
                            ?? "Window \(window.windowId)"
                        windowItems.append(NavigatorWindowItem(
                            id: window.windowId,
                            title: title,
                            applicationName: window.app.name ?? "Application",
                            applicationPath: window.app.bundlePath,
                            isFocused: focus.windowOrNil == window,
                            isFloating: window.isFloating,
                        ))
                    }
                    workspaceItems.append(NavigatorWorkspaceItem(
                        name: workspace.name,
                        isActive: monitor.activeWorkspace == workspace,
                        isFocused: focus.workspace == workspace,
                        windows: windowItems,
                    ))
                }
                nextMonitors.append(NavigatorMonitorItem(
                    id: monitor.stableIdentifier,
                    name: monitor.name,
                    workspaces: workspaceItems,
                ))
            }
            guard !Task.isCancelled else { return }
            monitors = nextMonitors
            isLoading = false
            selectedPaletteItemId = filteredPaletteItems.first?.id
        }
    }

    var filteredMonitors: [NavigatorMonitorItem] {
        let needle = query.trim().lowercased()
        guard !needle.isEmpty else { return monitors }
        return monitors.compactMap { monitor in
            let monitorMatches = monitor.name.lowercased().contains(needle)
            let workspaces = monitor.workspaces.compactMap { workspace in
                let workspaceMatches = workspace.name.lowercased().contains(needle)
                let windows = workspace.windows.filter {
                    $0.title.lowercased().contains(needle) || $0.applicationName.lowercased().contains(needle)
                }
                return monitorMatches || workspaceMatches || !windows.isEmpty
                    ? NavigatorWorkspaceItem(
                        name: workspace.name,
                        isActive: workspace.isActive,
                        isFocused: workspace.isFocused,
                        windows: monitorMatches || workspaceMatches ? workspace.windows : windows,
                    )
                    : nil
            }
            return workspaces.isEmpty ? nil : NavigatorMonitorItem(id: monitor.id, name: monitor.name, workspaces: workspaces)
        }
    }

    var filteredPaletteItems: [PaletteItem] {
        let needle = query.trim().lowercased()
        let items = paletteItems
        return needle.isEmpty ? items : items.filter { $0.searchText.contains(needle) }
    }

    func queryDidChange() {
        selectedPaletteItemId = filteredPaletteItems.first?.id
    }

    func executeSelectedPaletteItem() {
        let items = filteredPaletteItems
        guard let item = items.first(where: { $0.id == selectedPaletteItemId }) ?? items.first else { return }
        execute(item)
    }

    func submitQuery() {
        switch mode {
            case .overview:
                guard let workspace = filteredMonitors.first?.workspaces.first else { return }
                if let window = workspace.windows.first {
                    focusWindow(id: window.id)
                } else {
                    focusWorkspace(named: workspace.name)
                }
            case .commandPalette:
                executeSelectedPaletteItem()
        }
    }

    func execute(_ item: PaletteItem) {
        switch item.action {
            case .showOverview:
                mode = .overview
                query = ""
            case .command(let arguments):
                run(arguments)
        }
    }

    func focusWindow(id: UInt32) {
        run(["focus", "--window-id", String(id)])
    }

    func focusWorkspace(named name: String) {
        run(["workspace", name])
    }

    private var paletteItems: [PaletteItem] {
        var items = [
            PaletteItem(
                id: "show-overview",
                title: "Show Overview",
                subtitle: "Browse monitors, workspaces and windows",
                systemImage: "rectangle.3.group",
                action: .showOverview,
            ),
            commandItem("balance", "Balance Window Sizes", "Equalize weights in the current workspace", "scale.3d", ["balance-sizes"]),
            commandItem("fullscreen", "Toggle Fullscreen", "TileSail fullscreen for the focused window", "arrow.up.left.and.arrow.down.right", ["fullscreen"]),
            commandItem("floating", "Toggle Floating / Tiling", "Change how the focused window participates in layout", "macwindow.on.rectangle", ["layout", "floating", "tiling"]),
            commandItem("tiles", "Toggle Tiles / Accordion", "Switch the current container layout", "rectangle.split.2x1", ["layout", "tiles", "accordion"]),
            commandItem("orientation", "Toggle Orientation", "Switch between horizontal and vertical", "arrow.left.and.right.righttriangle.left.righttriangle.right", ["layout", "horizontal", "vertical"]),
            commandItem("workspace-next", "Next Workspace", "Navigate on the focused monitor", "arrow.right.circle", ["workspace", "--wrap-around", "next"]),
            commandItem("workspace-prev", "Previous Workspace", "Navigate on the focused monitor", "arrow.left.circle", ["workspace", "--wrap-around", "prev"]),
            commandItem("reload", "Reload Configuration", "Read the active TOML file again", "arrow.clockwise", ["reload-config"]),
            commandItem("enable", "Toggle Window Management", "Pause or resume TileSail", "pause.circle", ["enable", "toggle"]),
        ]
        for direction in ["left", "down", "up", "right"] {
            items.append(commandItem(
                "focus-\(direction)",
                "Focus \(direction.capitalized)",
                "Move keyboard focus",
                "arrow.\(direction)",
                ["focus", direction],
            ))
            items.append(commandItem(
                "move-\(direction)",
                "Move Window \(direction.capitalized)",
                "Rearrange the focused window",
                "rectangle.portrait.and.arrow.\(direction)",
                ["move", direction],
            ))
        }
        for workspace in monitors.flatMap(\.workspaces) {
            items.append(commandItem(
                "workspace-\(workspace.name)",
                "Workspace \(workspace.name)",
                "Focus this workspace",
                workspace.isActive ? "square.fill" : "square",
                ["workspace", workspace.name],
            ))
        }
        for slot in 1 ... smoothWorkspaceSlotCount {
            items.append(commandItem(
                "scratchpad-\(slot)",
                "Toggle Scratchpad \(slot)",
                "\(ScratchpadManager.windowCount(slot: slot)) assigned windows",
                "macwindow.on.rectangle",
                ["scratchpad", "toggle", String(slot)],
            ))
        }
        return items
    }

    private func commandItem(
        _ id: String,
        _ title: String,
        _ subtitle: String,
        _ systemImage: String,
        _ arguments: [String],
    ) -> PaletteItem {
        PaletteItem(
            id: id,
            title: title,
            subtitle: subtitle,
            systemImage: systemImage,
            action: .command(arguments),
        )
    }

    private func run(_ arguments: [String]) {
        guard let command = parseCommand(arguments).cmdOrNil else {
            statusMessage = "The selected action could not be parsed."
            return
        }
        guard let token = RunSessionGuard.isServerEnabled(orIsEnableCommand: command) else {
            statusMessage = "Window management is disabled."
            return
        }
        statusMessage = "Running \(arguments.first ?? "action")…"
        Task.startUnstructured { @MainActor [weak self] in
            let result = try await runLightSession(.menuBarButton, token) {
                await command.run(.defaultEnv, .emptyStdin)
            }
            if result.exitCode.rawValue == 0 {
                WorkspaceNavigatorController.shared.close()
            } else {
                self?.statusMessage = result.stderr.joined(separator: " ")
            }
        }
    }
}

@MainActor
final class WorkspaceNavigatorController {
    static let shared = WorkspaceNavigatorController()

    private let model = WorkspaceNavigatorModel()
    private var windowController: NSWindowController?

    private init() {}

    func show(_ mode: WorkspaceNavigatorMode) {
        model.prepare(mode)
        let controller = windowController ?? makeWindowController()
        windowController = controller
        NSApp.activate(ignoringOtherApps: true)
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
    }

    func close() {
        windowController?.window?.orderOut(nil)
    }

    private func makeWindowController() -> NSWindowController {
        let content = NSHostingController(rootView: WorkspaceNavigatorView(model: model))
        let window = WorkspaceNavigatorPanel(contentViewController: content)
        window.title = "TileSail Navigator"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask = [.titled, .closable, .resizable, .fullSizeContentView]
        window.setContentSize(NSSize(width: 900, height: 620))
        window.minSize = NSSize(width: 680, height: 460)
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false
        window.center()
        return NSWindowController(window: window)
    }
}

private final class WorkspaceNavigatorPanel: NSPanel {
    override func cancelOperation(_ sender: Any?) {
        orderOut(sender)
    }
}

@MainActor
private struct WorkspaceNavigatorView: View {
    @ObservedObject var model: WorkspaceNavigatorModel
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 14) {
                Picker("Mode", selection: $model.mode) {
                    ForEach(WorkspaceNavigatorMode.allCases) { mode in
                        Label(mode.title, systemImage: mode.systemImage).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 390)

                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField(
                        model.mode == .overview ? "Search windows and workspaces" : "Search actions",
                        text: $model.query,
                    )
                    .textFieldStyle(.plain)
                    .focused($isSearchFocused)
                    .onSubmit { model.submitQuery() }
                    if !model.query.isEmpty {
                        Button { model.query = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .frame(height: 38)
                .background(.quaternary.opacity(0.7), in: RoundedRectangle(cornerRadius: 10))
            }
            .padding(.horizontal, 22)
            .padding(.top, 20)
            .padding(.bottom, 14)

            Divider()

            Group {
                switch model.mode {
                    case .overview: overview
                    case .commandPalette: commandPalette
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            HStack {
                if model.isLoading {
                    ProgressView().controlSize(.small)
                    Text("Refreshing windows…")
                } else if !model.statusMessage.isEmpty {
                    Text(model.statusMessage)
                } else {
                    Text(model.mode == .overview ? "Select a window to focus it" : "Press Return to run the first match")
                }
                Spacer()
                Button {
                    model.reload()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 18)
            .frame(height: 44)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { isSearchFocused = true }
        .onChange(of: model.mode) { _ in
            model.query = ""
            model.queryDidChange()
            isSearchFocused = true
        }
        .onChange(of: model.query) { _ in model.queryDidChange() }
    }

    private var overview: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                ForEach(model.filteredMonitors) { monitor in
                    VStack(alignment: .leading, spacing: 10) {
                        Label(monitor.name, systemImage: "display")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 245), spacing: 12)], spacing: 12) {
                            ForEach(monitor.workspaces) { workspace in
                                WorkspaceOverviewCard(workspace: workspace, model: model)
                            }
                        }
                    }
                }
                if model.filteredMonitors.isEmpty, !model.isLoading {
                    NavigatorEmptyState(
                        title: "No Windows Found",
                        message: "Try another search.",
                        systemImage: "rectangle.badge.xmark",
                    )
                    .frame(maxWidth: .infinity, minHeight: 280)
                }
            }
            .padding(18)
        }
    }

    private var commandPalette: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                ForEach(model.filteredPaletteItems) { item in
                    Button {
                        model.selectedPaletteItemId = item.id
                        model.execute(item)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: item.systemImage)
                                .frame(width: 24)
                                .foregroundStyle(Color.accentColor)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title).fontWeight(.medium)
                                Text(item.subtitle).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 52)
                        .background(
                            model.selectedPaletteItemId == item.id
                                ? Color.accentColor.opacity(0.14)
                                : Color.clear,
                            in: RoundedRectangle(cornerRadius: 9),
                        )
                    }
                    .buttonStyle(.plain)
                }
                if model.filteredPaletteItems.isEmpty {
                    NavigatorEmptyState(
                        title: "No Actions Found",
                        message: "Try a broader search.",
                        systemImage: "command",
                    )
                    .frame(maxWidth: .infinity, minHeight: 280)
                }
            }
            .padding(14)
        }
    }
}

private struct NavigatorEmptyState: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text(title).font(.headline)
            Text(message).font(.caption).foregroundStyle(.secondary)
        }
    }
}

@MainActor
private struct WorkspaceOverviewCard: View {
    let workspace: NavigatorWorkspaceItem
    let model: WorkspaceNavigatorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button {
                    model.focusWorkspace(named: workspace.name)
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: workspace.isActive ? "square.fill" : "square")
                        Text(workspace.name).font(.headline)
                    }
                }
                .buttonStyle(.plain)
                Spacer()
                if workspace.isFocused {
                    Text("FOCUSED")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                }
            }

            if workspace.windows.isEmpty {
                Text("Empty workspace")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
            } else {
                ForEach(workspace.windows) { window in
                    Button {
                        model.focusWindow(id: window.id)
                    } label: {
                        HStack(spacing: 8) {
                            applicationIcon(path: window.applicationPath)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(window.title).lineLimit(1)
                                HStack(spacing: 5) {
                                    Text(window.applicationName)
                                    if window.isFloating { Text("Floating") }
                                }
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if window.isFocused {
                                Circle().fill(.tint).frame(width: 6, height: 6)
                            }
                        }
                        .padding(6)
                        .background(window.isFocused ? Color.accentColor.opacity(0.1) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(workspace.isActive ? Color.accentColor.opacity(0.55) : Color.secondary.opacity(0.16)),
        )
    }

    private func applicationIcon(path: String?) -> some View {
        let icon = path.map(NSWorkspace.shared.icon(forFile:)) ?? NSImage(systemSymbolName: "app", accessibilityDescription: nil).orDie()
        return Image(nsImage: icon)
            .resizable()
            .scaledToFit()
            .frame(width: 24, height: 24)
    }
}
