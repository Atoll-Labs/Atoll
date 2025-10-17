//
//  LockScreenPanelManager.swift
//  DynamicIsland
//
//  Manages the lock screen music panel window.
//

import SwiftUI
import AppKit
import SkyLightWindow
import Defaults

@MainActor
class LockScreenPanelManager {
    static let shared = LockScreenPanelManager()

    private var panelWindow: NSWindow?
    private var hasDelegated = false

    private init() {
        print("[\(timestamp())] LockScreenPanelManager: initialized")
    }

    private func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: Date())
    }

    func showPanel() {
        print("[\(timestamp())] LockScreenPanelManager: showPanel")

        guard Defaults[.enableLockScreenMediaWidget] else {
            print("[\(timestamp())] LockScreenPanelManager: widget disabled")
            hidePanel()
            return
        }

        guard let screen = NSScreen.main else {
            print("[\(timestamp())] LockScreenPanelManager: no main screen available")
            return
        }

        let panelWidth: CGFloat = 420
        let panelHeight: CGFloat = 150
        let screenFrame = screen.frame
        let originX = screenFrame.origin.x + (screenFrame.width / 2) - (panelWidth / 2)
        let originY = screenFrame.origin.y + (screenFrame.height / 2) - panelHeight - 40
        let targetFrame = NSRect(x: originX, y: originY, width: panelWidth, height: panelHeight)

        let window: NSWindow

        if let existingWindow = panelWindow {
            window = existingWindow
        } else {
            let newWindow = NSWindow(
                contentRect: targetFrame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )

            newWindow.isReleasedWhenClosed = false
            newWindow.isOpaque = false
            newWindow.backgroundColor = .clear
            newWindow.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
            newWindow.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
            newWindow.isMovable = false
            newWindow.hasShadow = false

            panelWindow = newWindow
            window = newWindow
            hasDelegated = false
        }

        window.setFrame(targetFrame, display: true)
        window.contentView = NSHostingView(rootView: LockScreenMusicPanel())

        if !hasDelegated {
            SkyLightOperator.shared.delegateWindow(window)
            hasDelegated = true
        }

        // Keep the window alive and simply order it out on unlock to avoid SkyLight crashes.
        window.orderFrontRegardless()

        print("[\(timestamp())] LockScreenPanelManager: panel visible")
    }

    func hidePanel() {
        print("[\(timestamp())] LockScreenPanelManager: hidePanel")

        guard let window = panelWindow else {
            print("LockScreenPanelManager: no panel to hide")
            return
        }

        window.orderOut(nil)
        window.contentView = nil

        print("[\(timestamp())] LockScreenPanelManager: panel hidden")
    }
}
