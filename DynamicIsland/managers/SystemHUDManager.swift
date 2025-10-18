//
//  SystemHUDManager.swift
//  DynamicIsland
//
//  Created by GitHub Copilot on 06/09/25.
//

import Foundation
import Defaults
import Combine

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
            self.changesObserver?.update(
                volumeEnabled: change.newValue,
                brightnessEnabled: Defaults[.enableBrightnessHUD]
            )
        }.store(in: &cancellables)
        
        Defaults.publisher(.enableBrightnessHUD, options: []).sink { [weak self] change in
            guard let self = self, self.isSetupComplete, Defaults[.enableSystemHUD] else {
                return
            }
            self.changesObserver?.update(
                volumeEnabled: Defaults[.enableVolumeHUD],
                brightnessEnabled: change.newValue
            )
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
        let volumeEnabled = Defaults[.enableVolumeHUD]
        let brightnessEnabled = Defaults[.enableBrightnessHUD]
        changesObserver?.startObserving(volumeEnabled: volumeEnabled, brightnessEnabled: brightnessEnabled)
        
        print("System HUD replacement started")
        isSystemOperationInProgress = false
    }
    
    @MainActor
    private func stopSystemHUD() async {
        guard !isSystemOperationInProgress else { return }
        
        isSystemOperationInProgress = true
        changesObserver?.stopObserving()
        changesObserver = nil
        
        print("System HUD replacement stopped")
        isSystemOperationInProgress = false
    }
    
    deinit {
        cancellables.removeAll()
        Task { @MainActor in
            await stopSystemHUD()
        }
    }
}