//
//  LockScreenManager.swift
//  DynamicIsland
//
//  Created for lock screen detection feature
//  Monitors system lock/unlock events and provides real-time status updates
//

import Foundation
import Combine
import AppKit
import Defaults
import SwiftUI

@MainActor
class LockScreenManager: ObservableObject {
    static let shared = LockScreenManager()
    
    // MARK: - Coordinator
    private let coordinator = DynamicIslandViewCoordinator.shared
    private weak var viewModel: DynamicIslandViewModel?
    
    // MARK: - Published Properties
    @Published var isLocked: Bool = false
    @Published var isLockIdle: Bool = true
    @Published var lastUpdated: Date = .distantPast
    
    // MARK: - Private Properties
    private var debounceIdleTask: Task<Void, Never>?
    
    // MARK: - Helpers
    
    private func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: Date())
    }
    
    // MARK: - Initialization
    private init() {
        setupObservers()
        print("LockScreenManager: 🔒 Initialized")
    }
    
    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
        debounceIdleTask?.cancel()
    }
    
    // MARK: - Setup
    
    private func setupObservers() {
        // Observe screen locked event
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(screenLocked),
            name: .init("com.apple.screenIsLocked"),
            object: nil
        )
        
        // Observe screen unlocked event
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(screenUnlocked),
            name: .init("com.apple.screenIsUnlocked"),
            object: nil
        )
        
        print("LockScreenManager: ✅ Observers registered for lock/unlock events")
    }
    
    // MARK: - Event Handlers
    
    @objc private func screenLocked() {
        print("[\(timestamp())] LockScreenManager: 🔒 Screen LOCKED event received")
        
        // Update state SYNCHRONOUSLY without Task/await to avoid any delay
        lastUpdated = Date()
        updateIdleState(locked: true)
        
        // Set locked state immediately without animation wrapper
        isLocked = true

        viewModel?.closeForLockScreen()

        if coordinator.expandingView.show {
            let currentType = coordinator.expandingView.type
            coordinator.toggleExpandingView(status: false, type: currentType)
        }

        if coordinator.sneakPeek.show {
            coordinator.toggleSneakPeek(status: false, type: coordinator.sneakPeek.type)
        }
        
        // Show panel FIRST (creates and shows window on lock screen)
        print("[\(timestamp())] LockScreenManager: 🎵 Showing lock screen panel")
        LockScreenPanelManager.shared.showPanel()
        LockScreenLiveActivityWindowManager.shared.showLocked()
        
        // THEN trigger lock icon in Dynamic Island (only if enabled in settings)
        if Defaults[.enableLockScreenLiveActivity] {
            print("[\(timestamp())] LockScreenManager: 🔴 Starting lock icon live activity")
            coordinator.toggleExpandingView(status: true, type: .lockScreen)
        } else {
            print("[\(timestamp())] LockScreenManager: ⏭️ Lock icon disabled in settings")
        }
        
        print("[\(timestamp())] LockScreenManager: ✅ Lock screen activated")
    }
    
    @objc private func screenUnlocked() {
        print("[\(timestamp())] LockScreenManager: 🔓 Screen UNLOCKED event received")
        
        // Hide panel window immediately and synchronously
        print("[\(timestamp())] LockScreenManager: 🚪 Hiding panel window")
        LockScreenPanelManager.shared.hidePanel()
        LockScreenLiveActivityWindowManager.shared.showUnlockAndScheduleHide()
        
        // Update state immediately
        if Defaults[.enableLockScreenLiveActivity] {
            self.coordinator.toggleExpandingView(status: false, type: .lockScreen)
        }
        
        self.lastUpdated = Date()
        self.updateIdleState(locked: false)
        self.isLocked = false
        
        print("[\(self.timestamp())] LockScreenManager: ✅ Lock screen deactivated")
    }
    
    // MARK: - Idle State Management
    
    /// Copy EXACT logic from ScreenRecordingManager
    private func updateIdleState(locked: Bool) {
        if locked {
            isLockIdle = false
            debounceIdleTask?.cancel()
        } else {
            debounceIdleTask?.cancel()
            debounceIdleTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(Defaults[.waitInterval]))
                guard let self = self, !Task.isCancelled else { return }
                await MainActor.run {
                    if self.lastUpdated.timeIntervalSinceNow < -Defaults[.waitInterval] {
                        withAnimation {
                            self.isLockIdle = !self.isLocked
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Extensions

extension LockScreenManager {
    func configure(viewModel: DynamicIslandViewModel) {
        self.viewModel = viewModel
    }
    
    /// Get current lock status without async
    var currentLockStatus: Bool {
        return isLocked
    }
    
    /// Check if monitoring is available (for settings UI)
    var isMonitoringAvailable: Bool {
        return true // Always available on macOS
    }
}
