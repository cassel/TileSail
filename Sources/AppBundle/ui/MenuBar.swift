import Common
import Foundation
import SwiftUI

@MainActor
public func menuBar(viewModel: TrayMenuModel) -> some Scene { // todo should it be converted to "SwiftUI struct"?
    MenuBarExtra {
        let identification      = "\(aeroSpaceAppName) v\(aeroSpaceAppVersion) \(gitHash)"
        Text(aeroSpaceAppName)
        Text("Version \(aeroSpaceAppVersion) (\(gitShortHash))")
        Button {
            identification.copyToClipboard()
        } label: {
            Label("Copy Version Information", systemImage: "doc.on.doc")
        }
        .keyboardShortcut("C", modifiers: .command)
        Divider()

        if viewModel.axPermissionStatus == .granted {
            OpenSmoothLayoutSettingsButton()
            Button {
                WorkspaceNavigatorController.shared.show(.overview)
            } label: {
                Label("Overview…", systemImage: "rectangle.3.group")
            }
            .keyboardShortcut("O", modifiers: [.command, .shift])
            Button {
                WorkspaceNavigatorController.shared.show(.commandPalette)
            } label: {
                Label("Command Palette…", systemImage: "command")
            }
            .keyboardShortcut("P", modifiers: [.command, .shift])
            Divider()
            if let token: RunSessionGuard = .isServerEnabled, viewModel.lastReloadConfigContainedWarnings {
                Button {
                    Task.startUnstructured {
                        try await runLightSession(.menuBarButton, token) {
                            let args: ReloadConfigCmdArgs = ReloadConfigCmdArgs(rawArgs: []).copy(\.warningsAsErrors, true)
                            _ = await reloadConfig_nonCancellable(args: args)
                        }
                    }
                } label: {
                    Label("Config contains warnings...", systemImage: "exclamationmark.triangle.fill")
                }
                Divider()
            }
            if let token: RunSessionGuard = .isServerEnabled {
                Text("Workspaces")
                ForEach(viewModel.workspaces, id: \.name) { workspace in
                    Toggle(
                        workspace.name + workspace.suffix,
                        isOn: Binding(
                            get: { workspace.isFocused },
                            set: { _ in
                                Task.startUnstructured {
                                    try await runLightSession(.menuBarButton, token) {
                                        _ = Workspace.get(byName: workspace.name).focusWorkspace()
                                    }
                                }
                            },
                        ),
                    )
                }
                Divider()
            }
            Button {
                Task.startUnstructured {
                    try await runLightSession(.menuBarButton, .forceRun) {
                        _ = await EnableCommand(args: EnableCmdArgs(rawArgs: [], targetState: .toggle))
                            .run(.defaultEnv, .emptyStdin)
                    }
                }
            } label: {
                Label(
                    viewModel.isEnabled ? "Pause Window Management" : "Resume Window Management",
                    systemImage: viewModel.isEnabled ? "pause.circle" : "play.circle",
                )
            }
            .keyboardShortcut("E", modifiers: .command)
            openConfigButton()
            reloadConfigButton(warningsAsErrors: false)
        } else {
            Button("TileSail requires accessibility permission to move windows") {
                viewModel.axPermissionStatus = .waitingWithPrompt
            }
        }
        Button {
            Task.startUnstructured {
                terminationHandler?.beforeTermination()
                terminateApp()
            }
        } label: {
            Label("Quit \(aeroSpaceAppName)", systemImage: "power")
        }
        .keyboardShortcut("Q", modifiers: .command)
    } label: {
        MenuBarLabel().environmentObject(viewModel)
    }
}

@MainActor @ViewBuilder
func openConfigButton(showShortcutGroup: Bool = false) -> some View {
    let editor = getTextEditorToOpenConfig()
    let button = Button {
        let fallbackConfig: URL = FileManager.default.homeDirectoryForCurrentUser.appending(path: configDotfileName)
        switch findCustomConfigUrl() {
            case .file(let url):
                url.open(with: editor)
            case .noCustomConfigExists:
                _ = try? FileManager.default.copyItem(atPath: defaultConfigUrl.path, toPath: fallbackConfig.path)
                fallbackConfig.open(with: editor)
            case .ambiguousConfigError:
                fallbackConfig.open(with: editor)
        }
    } label: {
        Label("Open Configuration…", systemImage: "doc.text")
    }
    .keyboardShortcut(",", modifiers: .command)
    switch showShortcutGroup {
        case true: shortcutGroup(label: Text("⌘ ,"), content: button)
        case false: button
    }
}

@MainActor @ViewBuilder
func reloadConfigButton(showShortcutGroup: Bool = false, warningsAsErrors: Bool) -> some View {
    if let token: RunSessionGuard = .isServerEnabled {
        let button = Button {
            Task.startUnstructured {
                try await runLightSession(.menuBarButton, token) {
                    let args: ReloadConfigCmdArgs = ReloadConfigCmdArgs(rawArgs: []).copy(\.warningsAsErrors, warningsAsErrors)
                    _ = await reloadConfig_nonCancellable(args: args)
                }
            }
        } label: {
            Label("Reload Configuration", systemImage: "arrow.clockwise")
        }
        .keyboardShortcut("R", modifiers: .command)
        switch showShortcutGroup {
            case true: shortcutGroup(label: Text("⌘ R"), content: button)
            case false: button
        }
    }
}

func shortcutGroup(label: some View, content: some View) -> some View {
    GroupBox {
        VStack(alignment: .trailing, spacing: 6) {
            label
                .foregroundStyle(Color.secondary)
            content
        }
    }
}

func getTextEditorToOpenConfig() -> URL {
    NSWorkspace.shared.urlForApplication(toOpen: findCustomConfigUrl().urlOrNil ?? defaultConfigUrl)?
        .takeIf { $0.lastPathComponent != "Xcode.app" } // Blacklist Xcode. It is too heavy to open plain text files
        ?? URL(filePath: "/System/Applications/TextEdit.app")
}
