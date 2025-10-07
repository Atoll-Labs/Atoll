//
//  SystemHUDManager.swift
//  DynamicIsland
//
//  Created by GitHub Copilot on 06/09/25.
//

import Foundation
import Defaults
import Combine
import AppKit

class SystemHUDManager {
    static let shared = SystemHUDManager()
    
    private var changesObserver: SystemChangesObserver?
    private weak var coordinator: DynamicIslandViewCoordinator?
    private var isSetupComplete = false
    private var isSystemOperationInProgress = false
    
    private init() {
        // Set up observer for settings changes
        setupSettingsObserver()
    }
    
    private func setupSettingsObserver() {
        // Observe master toggle
        Defaults.publisher(.enableSystemHUD, options: []).sink { [weak self] change in
            guard let self = self, self.isSetupComplete else {
                return
            }
            Task { @MainActor in
                if change.newValue {
                    await self.startSystemHUD()
                } else {
                    await self.stopSystemHUD()
                }
            }
        }.store(in: &cancellables)
        
        // Observe individual HUD toggles
        Defaults.publisher(.enableVolumeHUD, options: []).sink { [weak self] change in
            guard let self = self, self.isSetupComplete, Defaults[.enableSystemHUD] else {
                return
            }
            // When volume HUD is enabled, ensure OSD is disabled
            if change.newValue {
                self.disableSystemHUD()
            }
        }.store(in: &cancellables)
        
        Defaults.publisher(.enableBrightnessHUD, options: []).sink { [weak self] change in
            guard let self = self, self.isSetupComplete, Defaults[.enableSystemHUD] else {
                return
            }
            // When brightness HUD is enabled, ensure OSD is disabled
            if change.newValue {
                self.disableSystemHUD()
            }
        }.store(in: &cancellables)
    }
    
    private var cancellables = Set<AnyCancellable>()
    
    /// Public property to check if system operations are in progress
    var isOperationInProgress: Bool {
        return isSystemOperationInProgress
    }
    
    func setup(coordinator: DynamicIslandViewCoordinator) {
        self.coordinator = coordinator
        
        if Defaults[.enableSystemHUD] {
            Task { @MainActor in
                await startSystemHUD()
                self.isSetupComplete = true
            }
        } else {
            isSetupComplete = true
        }
    }
    
    @MainActor
    private func startSystemHUD() async {
        guard let coordinator = coordinator, !isSystemOperationInProgress else { return }
        
        isSystemOperationInProgress = true
        await stopSystemHUD() // Stop any existing observer
        
        changesObserver = SystemChangesObserver(coordinator: coordinator)
        changesObserver?.startObserving()
        
        // Disable system HUD if possible
        disableSystemHUD()
        
        // Start event-driven OSD monitoring
        startOSDMonitoring()
        
        print("System HUD replacement started")
        isSystemOperationInProgress = false
    }
    
    @MainActor
    private func stopSystemHUD() async {
        guard !isSystemOperationInProgress else { return }
        
        isSystemOperationInProgress = true
        changesObserver?.stopObserving()
        changesObserver = nil
        
        // Stop OSD monitoring
        stopOSDMonitoring()
        
        // Re-enable system HUD
        enableOriginalSystemHUD()
        
        print("System HUD replacement stopped")
        isSystemOperationInProgress = false
    }
    
    private func disableSystemHUD() {
        print("🔇 Disabling system HUD (OSDUIHelper running: \(SystemOSDManager.isOSDUIHelperRunning()))")
        // Disable the system HUD using SystemOSDManager
        SystemOSDManager.disableSystemHUD()
    }
    
    private func enableOriginalSystemHUD() {
        print("🔊 Re-enabling system HUD (OSDUIHelper running: \(SystemOSDManager.isOSDUIHelperRunning()))")
        // Re-enable the system HUD using SystemOSDManager
        SystemOSDManager.enableSystemHUD()
        
        // Check status after a reasonable delay, using async to avoid blocking
        Task {
            try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds instead of 1
            let isRunning = await SystemOSDManager.isOSDUIHelperRunningAsync()
            print("🔍 OSDUIHelper status after re-enable: \(isRunning ? "✅ Running" : "❌ Not running")")
        }
    }
    
    // MARK: - Media Key Event Handling
    
    /// Handle volume key press events from MediaKeyApplication
    public func handleVolumeKeyEvent() {
        changesObserver?.handleVolumeKeyEvent()
    }
    
    /// Handle brightness key press events from MediaKeyApplication
    public func handleBrightnessKeyEvent() {
        changesObserver?.handleBrightnessKeyEvent()
    }
    
    // MARK: - OSD Monitoring
    
    /// Start event-driven monitoring for OSDUIHelper process launches
    @MainActor
    private func startOSDMonitoring() {
        stopOSDMonitoring() // Stop any existing observer
        
        // Listen for process launch notifications
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didLaunchApplicationNotification)
            .compactMap { notification -> NSRunningApplication? in
                notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            }
            .filter { app in
                // Check if OSDUIHelper was launched
                app.bundleIdentifier == "com.apple.OSDUIHelper" ||
                app.localizedName?.contains("OSDUIHelper") == true
            }
            .sink { [weak self] _ in
                guard let self = self else { return }
                
                // Check if any HUD is enabled
                let anyHUDEnabled = Defaults[.enableVolumeHUD] || Defaults[.enableBrightnessHUD]
                guard anyHUDEnabled else { return }
                
                Task { @MainActor in
                    print("⚠️ OSDUIHelper launched - re-disabling")
                    self.disableSystemHUD()
                }
            }
            .store(in: &cancellables)
        
        // Also listen for screen wake events (OSDUIHelper often restarts after wake)
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.screensDidWakeNotification)
            .sink { [weak self] _ in
                guard let self = self else { return }
                
                let anyHUDEnabled = Defaults[.enableVolumeHUD] || Defaults[.enableBrightnessHUD]
                guard anyHUDEnabled else { return }
                
                // Check after a short delay to ensure system is ready
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                    
                    let isRunning = await SystemOSDManager.isOSDUIHelperRunningAsync()
                    if isRunning {
                        print("⚠️ OSDUIHelper detected running after wake - re-disabling")
                        self.disableSystemHUD()
                    }
                }
            }
            .store(in: &cancellables)
        
        print("✅ OSD monitoring started (event-driven)")
    }
    
    /// Stop OSD monitoring
    @MainActor
    private func stopOSDMonitoring() {
        // Cancellables are automatically cleaned up
        print("🛑 OSD monitoring stopped")
    }
    
    deinit {
        cancellables.removeAll()
        Task { @MainActor in
            await stopSystemHUD()
        }
        // Emergency restore is available via SystemHUDManager.emergencyRestoreSystemHUD() if needed
    }
    
    /// Emergency restore function - call this if system HUD is not working
    public static func emergencyRestoreSystemHUD() {
        print("🚨 Emergency system HUD restore initiated")
        SystemHUDDebugger.forceRestartOSDUIHelper()
    }
}