import AppKit
import Common

// Require two matching samples so Dock animations do not repeatedly resize windows.
struct VisibleFrameChangeTracker {
    private var applied: [Int: CGRect]?
    private var pending: [Int: CGRect]?

    mutating func update(_ frames: [Int: CGRect]) -> Bool {
        guard !frames.isEmpty else { return false }
        guard let applied else {
            self.applied = frames
            return false
        }
        guard frames != applied else {
            pending = nil
            return false
        }
        guard pending == frames else {
            pending = frames
            return false
        }
        self.applied = frames
        pending = nil
        return true
    }
}

enum GlobalObserver {
    @MainActor private static var visibleFrameTimer: Timer?
    @MainActor private static var visibleFrameTracker = VisibleFrameChangeTracker()

    @MainActor
    private static func observeVisibleFrames() {
        guard TrayMenuModel.shared.isEnabled else { return }
        let frames = Dictionary(uniqueKeysWithValues: NSScreen.screens.compactMap { screen -> (Int, CGRect)? in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            return (number.intValue, screen.visibleFrame)
        })
        guard visibleFrameTracker.update(frames) else { return }
        // Moving the Dock need not deliver a screen-parameters notification.
        // The regular layout reads fresh visible frames for every active monitor.
        scheduleCancellableCompleteRefreshSession(.globalObserver("visibleFrameChanged"))
    }

    private static func onNotif(_ notification: Notification) {
        // Third line of defence against lock screen window. See: closedWindowsCache
        // Second and third lines of defence are technically needed only to avoid potential flickering
        if (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier == lockScreenAppBundleId {
            return
        }
        let notifName = notification.name.rawValue
        let activatedApplicationPid = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?
            .processIdentifier
        Task.startUnstructured { @MainActor in
            if notifName == NSWorkspace.didActivateApplicationNotification.rawValue,
               activatedApplicationPid != nil,
               activatedApplicationPid != myPid
            {
                ScratchpadManager.shared.noteExternalSelection()
            }
            if notifName == NSWorkspace.didLaunchApplicationNotification.rawValue ||
                notifName == NSWorkspace.didTerminateApplicationNotification.rawValue
            {
                WindowManagerConflictMonitor.shared.refresh()
            }
            if !TrayMenuModel.shared.isEnabled { return }
            if notifName == NSWorkspace.didActivateApplicationNotification.rawValue {
                scheduleCancellableCompleteRefreshSession(.globalObserver(notifName), optimisticallyPreLayoutWorkspaces: true)
            } else {
                scheduleCancellableCompleteRefreshSession(.globalObserver(notifName))
            }
        }
    }

    private static func onHideApp(_ notification: Notification) {
        let notifName = notification.name.rawValue
        Task.startUnstructured { @MainActor in
            guard let token: RunSessionGuard = .isServerEnabled else { return }
            try await runLightSession(.globalObserver(notifName), token) {
                if config.automaticallyUnhideMacosHiddenApps {
                    if let w = prevFocus?.windowOrNil,
                       w.macAppUnsafe.nsApp.isHidden,
                       // "Hide others" (cmd-alt-h) -> don't force focus
                       // "Hide app" (cmd-h) -> force focus
                       MacApp.allAppsMap.values.count(where: { $0.nsApp.isHidden }) == 1
                    {
                        // Force focus
                        _ = w.focusWindow()
                        w.nativeFocus()
                    }
                    for app in MacApp.allAppsMap.values {
                        app.nsApp.unhide()
                    }
                }
            }
        }
    }

    private static func onScreenParametersChanged(_ notification: Notification) {
        let notifName = notification.name.rawValue
        Task.startUnstructured { @MainActor in
            SmoothLayoutSettingsStore.shared.monitorsDidChange(monitorInfos)
            guard TrayMenuModel.shared.isEnabled else { return }
            scheduleCancellableCompleteRefreshSession(.globalObserver(notifName))
        }
    }

    @MainActor
    static func initObserver() {
        if visibleFrameTimer == nil {
            observeVisibleFrames()
            let timer = Timer(timeInterval: 0.5, repeats: true) { _ in
                Task.startUnstructured { @MainActor in observeVisibleFrames() }
            }
            timer.tolerance = 0.1
            RunLoop.main.add(timer, forMode: .common)
            visibleFrameTimer = timer
        }
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main, using: onNotif)
        nc.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main, using: onNotif)
        nc.addObserver(forName: NSWorkspace.didHideApplicationNotification, object: nil, queue: .main, using: onHideApp)
        nc.addObserver(forName: NSWorkspace.didUnhideApplicationNotification, object: nil, queue: .main, using: onNotif)
        nc.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main, using: onNotif)
        nc.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main, using: onNotif)

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main,
            using: onScreenParametersChanged,
        )

        NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { _ in
            // todo reduce number of refreshSession in the callback
            //  resetManipulatedWithMouseIfPossible might call its own refreshSession
            //  The end of the callback calls refreshSession
            Task.startUnstructured { @MainActor in
                ScratchpadManager.shared.noteExternalSelection()
                guard let token: RunSessionGuard = .isServerEnabled else { return }
                try await resetManipulatedWithMouseIfPossible()
                let mouseLocation = mouseLocation
                let clickedMonitor = mouseLocation.monitorApproximation
                switch true {
                    // Detect clicks on desktop of different monitors
                    case clickedMonitor.visibleRect.contains(mouseLocation) && clickedMonitor.activeWorkspace != focus.workspace:
                        _ = try await runLightSession(.globalObserverLeftMouseUp, token) {
                            clickedMonitor.activeWorkspace.focusWorkspace()
                        }
                    // Detect close button clicks for unfocused windows. Yes, kAXUIElementDestroyedNotification is that unreliable
                    //  And trigger new window detection that could be delayed due to mouseDown event
                    default:
                        scheduleCancellableCompleteRefreshSession(.globalObserverLeftMouseUp)
                }
            }
        }
    }
}
