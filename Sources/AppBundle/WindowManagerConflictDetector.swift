import AppKit
import Combine
import Common

struct RunningWindowManagerCandidate: Equatable, Sendable {
    let processIdentifier: pid_t
    let name: String
    let bundleIdentifier: String?
    let executableName: String?
}

struct WindowManagerConflict: Identifiable, Equatable, Sendable {
    let processIdentifier: pid_t
    let name: String

    var id: pid_t { processIdentifier }
}

enum WindowManagerConflictDetector {
    private static let knownNames: Set<String> = [
        "aerospace",
        "aerospacesmooth",
        "tilesail",
        "amethyst",
        "omniwm",
        "yabai",
    ]

    static func conflicts(
        among candidates: [RunningWindowManagerCandidate],
        currentProcessIdentifier: pid_t,
    ) -> [WindowManagerConflict] {
        candidates.compactMap { candidate in
            guard candidate.processIdentifier != currentProcessIdentifier else { return nil }
            let normalizedNames = [candidate.name, candidate.executableName]
                .compactMap { $0?.lowercased().replacingOccurrences(of: " ", with: "") }
            let normalizedBundleIdentifier = candidate.bundleIdentifier?.lowercased() ?? ""
            guard normalizedNames.contains(where: knownNames.contains) ||
                knownNames.contains(where: normalizedBundleIdentifier.contains)
            else { return nil }
            return WindowManagerConflict(
                processIdentifier: candidate.processIdentifier,
                name: candidate.name,
            )
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

@MainActor
final class WindowManagerConflictMonitor: ObservableObject {
    static let shared = WindowManagerConflictMonitor()

    @Published private(set) var conflicts: [WindowManagerConflict] = []

    private init() {}

    func refresh() {
        let candidates = NSWorkspace.shared.runningApplications.map {
            RunningWindowManagerCandidate(
                processIdentifier: $0.processIdentifier,
                name: $0.localizedName ?? $0.executableURL?.deletingPathExtension().lastPathComponent ?? "Unknown",
                bundleIdentifier: $0.bundleIdentifier,
                executableName: $0.executableURL?.deletingPathExtension().lastPathComponent,
            )
        }
        conflicts = WindowManagerConflictDetector.conflicts(
            among: candidates,
            currentProcessIdentifier: NSRunningApplication.current.processIdentifier,
        )
    }

    func confirmStartupIfNeeded() -> Bool {
        refresh()
        guard !conflicts.isEmpty, !serverArgs.isReadOnly else { return true }

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Another window manager is running"
        alert.informativeText = "Running two window managers at the same time can make windows jump or fight for focus. Detected: \(conflicts.map(\.name).joined(separator: ", "))."
        alert.addButton(withTitle: "Quit \(aeroSpaceAppName)")
        alert.addButton(withTitle: "Run Anyway")
        return alert.runModal() == .alertSecondButtonReturn
    }
}
