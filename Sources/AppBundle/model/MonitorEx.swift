import AppKit
import Common

extension MonitorInfo {
    @MainActor
    var visibleRectPaddedByOuterGaps: Rect {
        let visibleRect = DockWorkArea.adjusted(self.visibleRect, screen: rect)
        let topLeft = visibleRect.topLeftCorner
        let gaps = ResolvedGaps(gaps: config.gaps, monitor: self)
        let barInset = workspaceBarTopInset
        let topGap = max(gaps.outer.top.toDouble(), barInset)
        return Rect(
            topLeftX: topLeft.x + gaps.outer.left.toDouble(),
            topLeftY: topLeft.y + topGap,
            width: visibleRect.width - gaps.outer.left.toDouble() - gaps.outer.right.toDouble(),
            height: visibleRect.height - topGap - gaps.outer.bottom.toDouble(),
        )
    }

    @MainActor
    private var workspaceBarTopInset: CGFloat {
        guard !isUnitTest, WorkspaceBarSettings.shared.isEnabled, TrayMenuModel.shared.isEnabled else { return 0 }
        return WorkspaceBarController.shared.reservedTopInset(for: self)
    }

    /// Expanded TileSail windows still leave room for the workspace switcher.
    @MainActor
    var visibleRectAvoidingWorkspaceBar: Rect {
        let visibleRect = DockWorkArea.adjusted(self.visibleRect, screen: rect)
        let inset = workspaceBarTopInset
        return Rect(
            topLeftX: visibleRect.topLeftX, topLeftY: visibleRect.topLeftY + inset,
            width: visibleRect.width, height: visibleRect.height - inset,
        )
    }

    var monitorId_oneBased: Int? {
        let sorted = sortedMonitorInfos
        let origin = self.rect.topLeftCorner
        return sorted.firstIndex { $0.rect.topLeftCorner == origin }.map { $0 + 1 }
    }
}
