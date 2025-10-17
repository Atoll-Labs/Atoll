//
//  LockScreenLiveActivityWindowManager.swift
//  DynamicIsland
//
//  Delegates the lock screen live activity layout to SkyLight so it remains visible when the display is locked.
//

import AppKit
import Defaults
import SkyLightWindow
import SwiftUI

@MainActor
class LockScreenLiveActivityWindowManager {
    static let shared = LockScreenLiveActivityWindowManager()

    private var window: NSWindow?
    private var hasDelegated = false
    private var hideTask: Task<Void, Never>?
    private var hostingView: NSHostingView<LockScreenLiveActivityOverlay>?
    private let overlayModel = LockScreenLiveActivityOverlayViewModel()

    private init() {}

    private func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: Date())
    }

    private func frame(for notchSize: CGSize, on screen: NSScreen) -> NSRect {
        let indicatorSize = max(0, notchSize.height - 12)
        let horizontalPadding = cornerRadiusInsets.closed.bottom
        let totalWidth = notchSize.width + (indicatorSize * 2) + (horizontalPadding * 2)

        let screenFrame = screen.frame
        let originX = screenFrame.origin.x + (screenFrame.width / 2) - (totalWidth / 2)
        let originY = screenFrame.origin.y + screenFrame.height - notchSize.height

        return NSRect(x: originX, y: originY, width: totalWidth, height: notchSize.height)
    }

    private func ensureWindow(notchSize: CGSize, screen: NSScreen) -> NSWindow {
        if let window {
            return window
        }

        let window = NSWindow(
            contentRect: frame(for: notchSize, on: screen),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        window.isOpaque = false
        window.backgroundColor = .clear
        window.isReleasedWhenClosed = false
        window.ignoresMouseEvents = true
        window.hasShadow = false
        window.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        window.alphaValue = 0
        window.animationBehavior = .none

        self.window = window
        self.hasDelegated = false
        return window
    }

    private func present(state: LockLiveActivityState) {
        guard Defaults[.enableLockScreenLiveActivity] else {
            hideImmediately()
            return
        }

        guard let screen = NSScreen.main else {
            print("[\(timestamp())] LockScreenLiveActivityWindowManager: no main screen available")
            return
        }

        let notchSize = getClosedNotchSize(screen: screen.localizedName)
        let window = ensureWindow(notchSize: notchSize, screen: screen)
        let targetFrame = frame(for: notchSize, on: screen)
        window.setFrame(targetFrame, display: true)

        let overlay = LockScreenLiveActivityOverlay(state: state, notchSize: notchSize, viewModel: overlayModel)

        if let hostingView {
            hostingView.rootView = overlay
            hostingView.frame = CGRect(origin: .zero, size: targetFrame.size)
        } else {
            let view = NSHostingView(rootView: overlay)
            view.frame = CGRect(origin: .zero, size: targetFrame.size)
            hostingView = view
            window.contentView = view
        }

        if window.contentView !== hostingView {
            window.contentView = hostingView
        }

        window.displayIfNeeded()

        if !hasDelegated {
            SkyLightOperator.shared.delegateWindow(window)
            hasDelegated = true
        }

        window.orderFrontRegardless()

        if state == .locked {
            overlayModel.expansion = 0.2
            withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) {
                overlayModel.expansion = 1
            }
        } else {
            overlayModel.expansion = 1
        }

        if window.alphaValue < 1 {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                window.animator().alphaValue = 1
            }
        }
    }

    func showLocked() {
        hideTask?.cancel()
        present(state: .locked)
        print("[\(timestamp())] LockScreenLiveActivityWindowManager: showing locked state")
    }

    func showUnlockAndScheduleHide() {
        hideTask?.cancel()
        present(state: .unlocking)
        print("[\(timestamp())] LockScreenLiveActivityWindowManager: showing unlock state")

        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(Defaults[.waitInterval], 1.0)))
            guard let self, !Task.isCancelled else { return }
            await MainActor.run {
                self.hideImmediately()
            }
        }
    }

    func hideImmediately() {
        hideTask?.cancel()
        hideTask = nil

        guard let window else { return }

        withAnimation(.easeOut(duration: 0.1)) {
            overlayModel.expansion = 0.2
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.1
            window.animator().alphaValue = 0
        }

        print("[\(timestamp())] LockScreenLiveActivityWindowManager: HUD hidden")
    }
}
