import AppKit
import Common
import Foundation

struct BalanceSizesCommand: Command {
    let args: BalanceSizesCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = false

    func run(_ env: CmdEnv, _ io: CmdIo) async -> BinaryExitCode {
        guard let target = args.resolveTargetOrReportError(env, io) else { return .fail }
        balance(target.workspace.rootTilingContainer)
        // In TileSail this command is also the explicit "reorganize"
        // action. Rebuild the focused workspace from its selected monitor/count
        // profile instead of merely equalizing the current (possibly stale)
        // tree. Other workspaces retain their snapshots and are left untouched.
        invalidateSmoothWorkspaceLayoutSnapshot(workspaceName: target.workspace.name)
        await reconcileSmoothWorkspaceLayoutsRespectingWindowConstraints()
        return .succ
    }
}

@MainActor
private func balance(_ parent: TilingContainer) {
    for child in parent.children {
        switch parent.layout {
            case .tiles: child.setWeight(parent.orientation, 1)
            case .accordion: break // Do nothing
        }
        if let child = child as? TilingContainer {
            balance(child)
        }
    }
}
