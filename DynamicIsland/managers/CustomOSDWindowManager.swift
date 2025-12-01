#if os(macOS)
import AppKit
import SwiftUI
import SkyLightWindow
import QuartzCore
import Defaults

/// Manages custom OSD windows for volume, brightness, and keyboard backlight controls
/// Mimics macOS native OSD behavior with custom styling
@MainActor
final class CustomOSDWindowManager {
    static let shared = CustomOSDWindowManager()
    
    private var volumeWindow: OSDWindow?
    private var brightnessWindow: OSDWindow?
    private var backlightWindow: OSDWindow?
    
    private var hideWorkItem: DispatchWorkItem?
    private let displayDuration: TimeInterval = 2.0
    private let animationDuration: TimeInterval = 0.3
    private var isInitialized = false
    
    // Standard macOS OSD dimensions (approximate)
    private let osdWidth: CGFloat = 200
    private let osdHeight: CGFloat = 200
    
    private init() {}
    
    // MARK: - Public API
    
    func showVolume(value: CGFloat, isMuted: Bool = false, icon: String = "") {
        guard Defaults[.enableCustomOSD], isInitialized else { return }
        show(type: .volume, value: value, icon: icon)
    }
    
    func showBrightness(value: CGFloat) {
        guard Defaults[.enableCustomOSD], isInitialized else { return }
        show(type: .brightness, value: value, icon: "")
    }
    
    func showBacklight(value: CGFloat) {
        guard Defaults[.enableCustomOSD], isInitialized else { return }
        show(type: .backlight, value: value, icon: "")
    }
    
    func initialize() {
        isInitialized = true
    }
    
    // MARK: - Private Implementation
    
    private func show(type: SneakContentType, value: CGFloat, icon: String) {
        guard let screen = NSScreen.main else { return }
        
        // Close other windows first
        hideAllWindowsExcept(type: type)
        
        let window = ensureWindow(for: type)
        updateContent(window: window, type: type, value: value, icon: icon)
        
        let targetFrame = calculateFrame(for: screen)
        
        if window.nsWindow.alphaValue <= 0.01 {
            // Initial presentation
            presentWindow(window, targetFrame: targetFrame)
        } else {
            // Update existing window
            window.nsWindow.setFrame(targetFrame, display: true)
            window.nsWindow.orderFrontRegardless()
        }
        
        scheduleHide(for: type)
    }
    
    private func ensureWindow(for type: SneakContentType) -> OSDWindow {
        let window: OSDWindow
        
        switch type {
        case .volume:
            if let existing = volumeWindow {
                return existing
            }
            window = createWindow(for: type)
            volumeWindow = window
        case .brightness:
            if let existing = brightnessWindow {
                return existing
            }
            window = createWindow(for: type)
            brightnessWindow = window
        case .backlight:
            if let existing = backlightWindow {
                return existing
            }
            window = createWindow(for: type)
            backlightWindow = window
        default:
            fatalError("Unsupported OSD type: \(type)")
        }
        
        return window
    }
    
    private func createWindow(for type: SneakContentType) -> OSDWindow {
        guard let screen = NSScreen.main else {
            fatalError("No main screen available")
        }
        
        let osdView = CustomOSDView(type: .constant(type), value: .constant(0), icon: .constant(""))
        let hostingView = NSHostingView(rootView: osdView)
        
        let frame = calculateFrame(for: screen)
        let window = NSWindow(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .statusBar + 1
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        window.hasShadow = false
        window.contentView = hostingView
        window.alphaValue = 0
        
        // Delegate to SkyLight for proper rendering
        SkyLightOperator.shared.delegateWindow(window)
        
        return OSDWindow(nsWindow: window, hostingView: hostingView, type: type)
    }
    
    private func updateContent(window: OSDWindow, type: SneakContentType, value: CGFloat, icon: String) {
        let osdView = CustomOSDView(type: .constant(type), value: .constant(value), icon: .constant(icon))
        window.hostingView.rootView = osdView
    }
    
    private func calculateFrame(for screen: NSScreen) -> NSRect {
        let screenFrame = screen.frame
        let centerX = screenFrame.midX - (osdWidth / 2)
        // Position at bottom center, similar to native macOS OSD
        let bottomOffset: CGFloat = 120 // Distance from bottom of screen
        let centerY = screenFrame.minY + bottomOffset
        
        return NSRect(x: centerX, y: centerY, width: osdWidth, height: osdHeight)
    }
    
    private func presentWindow(_ window: OSDWindow, targetFrame: NSRect) {
        let startFrame = targetFrame.offsetBy(dx: 0, dy: -20)
        window.nsWindow.setFrame(startFrame, display: true)
        window.nsWindow.alphaValue = 0
        window.nsWindow.orderFrontRegardless()
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = animationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.nsWindow.animator().setFrame(targetFrame, display: true)
            window.nsWindow.animator().alphaValue = 1
        }
    }
    
    private func hideAllWindowsExcept(type: SneakContentType) {
        if type != .volume, let volumeWindow = volumeWindow, volumeWindow.nsWindow.alphaValue > 0.01 {
            hideWindowImmediately(volumeWindow)
        }
        if type != .brightness, let brightnessWindow = brightnessWindow, brightnessWindow.nsWindow.alphaValue > 0.01 {
            hideWindowImmediately(brightnessWindow)
        }
        if type != .backlight, let backlightWindow = backlightWindow, backlightWindow.nsWindow.alphaValue > 0.01 {
            hideWindowImmediately(backlightWindow)
        }
    }
    
    private func hideWindowImmediately(_ window: OSDWindow) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.nsWindow.animator().alphaValue = 0
        } completionHandler: {
            window.nsWindow.orderOut(nil)
        }
    }
    
    private func scheduleHide(for type: SneakContentType) {
        hideWorkItem?.cancel()
        
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                self.hideWindow(for: type)
            }
        }
        
        hideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + displayDuration, execute: workItem)
    }
    
    private func hideWindow(for type: SneakContentType) {
        let window: OSDWindow?
        
        switch type {
        case .volume:
            window = volumeWindow
        case .brightness:
            window = brightnessWindow
        case .backlight:
            window = backlightWindow
        default:
            return
        }
        
        guard let window else { return }
        
        let currentFrame = window.nsWindow.frame
        let hideFrame = currentFrame.offsetBy(dx: 0, dy: -20)
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = animationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.nsWindow.animator().setFrame(hideFrame, display: true)
            window.nsWindow.animator().alphaValue = 0
        } completionHandler: {
            window.nsWindow.orderOut(nil)
        }
    }
    
    // MARK: - Cleanup
    
    func tearDown() {
        hideWorkItem?.cancel()
        hideWorkItem = nil
        
        volumeWindow?.nsWindow.orderOut(nil)
        brightnessWindow?.nsWindow.orderOut(nil)
        backlightWindow?.nsWindow.orderOut(nil)
        
        volumeWindow = nil
        brightnessWindow = nil
        backlightWindow = nil
    }
}

// MARK: - OSD Window Container

private struct OSDWindow {
    let nsWindow: NSWindow
    let hostingView: NSHostingView<CustomOSDView>
    let type: SneakContentType
}

#endif
