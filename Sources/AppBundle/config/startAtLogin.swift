import AppKit
import Common
import ServiceManagement

/// Recognize external jobs without deleting or rewriting user configuration.
func isManagedStartupAgent(_ plist: [String: Any]) -> Bool {
    let names = ["TileSail.app", "AeroSpace.app", "AeroSpaceSmooth.app"]
    func appPath(_ value: String) -> Bool { names.contains { value.hasSuffix("/" + $0) } }
    func executablePath(_ value: String) -> Bool {
        names.contains { value.hasSuffix("/\($0)/Contents/MacOS/\($0.dropLast(4))") }
    }
    let args = plist["ProgramArguments"] as? [String] ?? []
    if let program = plist["Program"] as? String, executablePath(program) { return true }
    if let first = args.first, executablePath(first) { return true }
    if args.first == "/usr/bin/open", let flag = args.firstIndex(of: "-a"), args.indices.contains(flag + 1) {
        return appPath(args[flag + 1])
    }
    return false
}

enum StartupRegistrationAction: Equatable { case register, unregister, debugIgnored, scanFailed }

func startupRegistrationAction(externalAgent: Bool, enabled: Bool, debug: Bool, scanSucceeded: Bool = true) -> StartupRegistrationAction {
    if externalAgent || !enabled { return .unregister }
    if !scanSucceeded { return .scanFailed }
    return debug ? .debugIgnored : .register
}

@MainActor
func syncStartAtLogin() {
    let directory = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/LaunchAgents")
    var externalAgent = false
    var scanSucceeded = true
    do {
        if FileManager.default.fileExists(atPath: directory.path) {
            for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) where url.pathExtension == "plist" {
                let data = try Data(contentsOf: url)
                let object = try PropertyListSerialization.propertyList(from: data, format: nil)
                if let plist = object as? [String: Any], isManagedStartupAgent(plist) { externalAgent = true }
            }
        }
    } catch {
        eprint("Cannot inspect external startup agents: \(error.localizedDescription)")
        scanSucceeded = false
    }
    if externalAgent {
        eprint("An external TileSail LaunchAgent is independently managed. Update or disable that plist separately; start-at-login controls only TileSail’s own service.")
    }
    let service = SMAppService.mainApp
    do {
        switch startupRegistrationAction(externalAgent: externalAgent, enabled: config.startAtLogin, debug: isDebug, scanSucceeded: scanSucceeded) {
            case .unregister: try service.unregister()
            case .debugIgnored: print("'start-at-login = true' has no effect in debug builds")
            case .register: try service.register()
            case .scanFailed: break // Enabled registration fails closed.
        }
    } catch { eprint("Cannot synchronize startup registration: \(error.localizedDescription)") }
}
