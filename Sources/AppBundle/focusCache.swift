@MainActor private var lastKnownNativeFocusedWindowId: UInt32? = nil

// AX visibility writes suspend the main actor. Their focus notifications must
// not change the selected workspace halfway through a layout pass.
@MainActor var workspaceVisibilityUpdateDepth = 0

/// The data should flow (from nativeFocused to focused) and
///                      (from nativeFocused to lastKnownNativeFocusedWindowId)
/// Alternative names: takeFocusFromMacOs, syncFocusFromMacOs
@MainActor func updateFocusCache(_ nativeFocused: Window?) async throws {
    guard workspaceVisibilityUpdateDepth == 0 else { return }
    if let nativeFocused, nativeFocused.isWorkspaceNativeHidden,
       try await nativeFocused.isMacosMinimized(.cancellable)
    {
        return
    }
    // Checking AX above can itself yield to a visibility pass.
    guard workspaceVisibilityUpdateDepth == 0 else { return }
    if nativeFocused?.parent is MacosPopupWindowsContainer {
        return
    }
    if nativeFocused?.windowId != lastKnownNativeFocusedWindowId {
        _ = nativeFocused?.focusWindow()
        lastKnownNativeFocusedWindowId = nativeFocused?.windowId
    }
    (nativeFocused as? MacWindow)?.macApp.lastNativeFocusedWindowId = nativeFocused?.windowId
}
