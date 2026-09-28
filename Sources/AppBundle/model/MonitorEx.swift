import AppKit
import Common

extension MonitorInfo {
    @MainActor
    var visibleRectPaddedByOuterGaps: Rect {
        let topLeft = visibleRect.topLeftCorner
        let gaps = ResolvedGaps(gaps: config.gaps, monitor: self)
        let barInset: CGFloat
        if !isUnitTest, WorkspaceBarSettings.shared.isEnabled, TrayMenuModel.shared.isEnabled,
           let screen = NSScreen.screens.getOrNil(atIndex: monitorAppKitNsScreenScreensId - 1) {
            barInset = screen.workspaceBarGeometry().reservedTopInset
        } else {
            barInset = 0
        }
        let topGap = max(gaps.outer.top.toDouble(), barInset)
        return Rect(
            topLeftX: topLeft.x + gaps.outer.left.toDouble(),
            topLeftY: topLeft.y + topGap,
            width: visibleRect.width - gaps.outer.left.toDouble() - gaps.outer.right.toDouble(),
            height: visibleRect.height - topGap - gaps.outer.bottom.toDouble(),
        )
    }

    var monitorId_oneBased: Int? {
        let sorted = sortedMonitorInfos
        let origin = self.rect.topLeftCorner
        return sorted.firstIndex { $0.rect.topLeftCorner == origin }.map { $0 + 1 }
    }
}
