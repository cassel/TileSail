import AppKit
import Common

/// AX coordinates, like TileSail coordinates, have their origin at the primary display's top left.
struct DockWorkArea {
    static func excludingDock(from visible: CGRect, screen: CGRect, dock: CGRect?, edge: String) -> CGRect {
        guard let dock, dock.width > 2, dock.height > 2,
              screen.contains(CGPoint(x: dock.midX, y: dock.midY)) else { return visible }
        var result = visible
        switch edge {
            case "bottom":
                guard dock.height < screen.height / 3, dock.maxY >= screen.maxY - 32 else { return visible }
                result.size.height = max(0, min(visible.maxY, dock.minY - 4) - visible.minY)
            case "left":
                guard dock.width < screen.width / 3, dock.minX <= screen.minX + 32 else { return visible }
                result.origin.x = max(visible.minX, dock.maxX + 4)
                result.size.width = max(0, visible.maxX - result.minX)
            case "right":
                guard dock.width < screen.width / 3, dock.maxX >= screen.maxX - 32 else { return visible }
                result.size.width = max(0, min(visible.maxX, dock.minX - 4) - visible.minX)
            default: return visible
        }
        return result
    }

    static func readFrame(pid: pid_t) -> CGRect? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.1)
        var raw: CFTypeRef?
        guard unsafe AXUIElementCopyAttributeValue(app, kAXChildrenAttribute as CFString, &raw) == .success,
              let children = raw as? [AXUIElement] else { return nil }
        for child in children {
            var role: CFTypeRef?
            guard unsafe AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &role) == .success,
                  role as? String == kAXListRole else { continue }
            var position: CFTypeRef?
            var size: CFTypeRef?
            guard unsafe AXUIElementCopyAttributeValue(child, kAXPositionAttribute as CFString, &position) == .success,
                  unsafe AXUIElementCopyAttributeValue(child, kAXSizeAttribute as CFString, &size) == .success,
                  let position, let size,
                  CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { continue }
            var point = CGPoint.zero
            var dimensions = CGSize.zero
            guard unsafe AXValueGetValue(position as! AXValue, .cgPoint, &point),
                  unsafe AXValueGetValue(size as! AXValue, .cgSize, &dimensions) else { continue }
            return CGRect(origin: point, size: dimensions)
        }
        return nil
    }

    @MainActor static var frame: CGRect?
    @MainActor static var edge = "bottom"

    @MainActor
    static func adjusted(_ visible: Rect, screen: Rect) -> Rect {
        guard !isUnitTest else { return visible }
        let rect = excludingDock(
            from: CGRect(origin: visible.topLeftCorner, size: visible.size),
            screen: CGRect(origin: screen.topLeftCorner, size: screen.size), dock: frame, edge: edge,
        )
        return Rect(topLeftX: rect.minX, topLeftY: rect.minY, width: rect.width, height: rect.height)
    }
}
