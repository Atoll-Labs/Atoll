//
//  BluetoothAudioManager.swift
//  DynamicIsland
//
//  Created for Bluetooth audio device connection detection and monitoring
//  Detects when audio devices connect and displays HUD with battery status
//

import Foundation
import Combine
import AppKit
import Defaults
import SwiftUI
import IOBluetooth

/// Manages detection and monitoring of Bluetooth audio device connections
class BluetoothAudioManager: ObservableObject {
    static let shared = BluetoothAudioManager()
    
    // MARK: - Published Properties
    @Published var lastConnectedDevice: BluetoothAudioDevice?
    @Published var connectedDevices: [BluetoothAudioDevice] = []
    @Published var isBluetoothAudioConnected: Bool = false
    
    // MARK: - Private Properties
    private var observers: [NSObjectProtocol] = []
    private var cancellables = Set<AnyCancellable>()
    private let coordinator = DynamicIslandViewCoordinator.shared
    private var pollingTimer: Timer?
    
    // MARK: - Initialization
    private init() {
        print("🎧 [BluetoothAudioManager] Initializing...")
        setupBluetoothObservers()
        checkInitialDevices()
        startPollingForChanges()
    }
    
    deinit {
        cleanup()
    }
    
    // MARK: - Setup Methods
    
    /// Sets up observers for Bluetooth device connection/disconnection events
    private func setupBluetoothObservers() {
        print("🎧 [BluetoothAudioManager] Setting up Bluetooth observers...")
        
        // Use DistributedNotificationCenter for IOBluetooth notifications
        let dnc = DistributedNotificationCenter.default()
        
        // Observe device connected notifications
        dnc.addObserver(
            self,
            selector: #selector(handleDeviceConnectedNotification(_:)),
            name: NSNotification.Name("IOBluetoothDeviceConnectedNotification"),
            object: nil
        )
        
        // Observe device disconnected notifications
        dnc.addObserver(
            self,
            selector: #selector(handleDeviceDisconnectedNotification(_:)),
            name: NSNotification.Name("IOBluetoothDeviceDisconnectedNotification"),
            object: nil
        )
        
        print("🎧 [BluetoothAudioManager] ✅ Observers registered with DistributedNotificationCenter")
    }
    
    /// Starts polling for device connection changes (fallback mechanism)
    private func startPollingForChanges() {
        print("🎧 [BluetoothAudioManager] Starting polling timer (3s interval)...")
        
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.checkForDeviceChanges()
        }
    }
    
    /// Checks for device connection/disconnection changes
    private func checkForDeviceChanges() {
        // Check if Bluetooth is powered on
        guard IOBluetoothHostController.default()?.powerState == kBluetoothHCIPowerStateON else {
            // Bluetooth is off - clear connected devices if any
            if !connectedDevices.isEmpty {
                print("🎧 [BluetoothAudioManager] ⚠️ Bluetooth powered off - clearing connected devices")
                connectedDevices.removeAll()
                isBluetoothAudioConnected = false
            }
            return
        }
        
        guard let pairedDevices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else {
            return
        }
        
        let currentlyConnectedAddresses = Set(
            pairedDevices
                .filter { $0.isConnected() && isAudioDevice($0) }
                .compactMap { $0.addressString }
        )
        
        let previousAddresses = Set(connectedDevices.map { $0.address })
        
        // Check for new connections
        let newAddresses = currentlyConnectedAddresses.subtracting(previousAddresses)
        if !newAddresses.isEmpty {
            print("🎧 [BluetoothAudioManager] 🔍 Polling detected new connection(s)")
            checkForNewlyConnectedDevices()
        }
        
        // Check for disconnections
        let removedAddresses = previousAddresses.subtracting(currentlyConnectedAddresses)
        if !removedAddresses.isEmpty {
            print("🎧 [BluetoothAudioManager] 🔍 Polling detected disconnection(s)")
            updateConnectedDevices()
        }
    }
    
    /// Checks for already connected Bluetooth audio devices on init
    private func checkInitialDevices() {
        print("🎧 [BluetoothAudioManager] Checking for initially connected devices...")
        
        // Check if Bluetooth is powered on
        guard IOBluetoothHostController.default()?.powerState == kBluetoothHCIPowerStateON else {
            print("🎧 [BluetoothAudioManager] ⚠️ Bluetooth is powered off - skipping initial check")
            return
        }
        
        guard let pairedDevices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else {
            print("🎧 [BluetoothAudioManager] No paired devices found")
            return
        }
        
        let connectedAudioDevices = pairedDevices.filter { device in
            device.isConnected() && isAudioDevice(device)
        }
        
        print("🎧 [BluetoothAudioManager] Found \(connectedAudioDevices.count) connected audio devices")
        
        connectedDevices = connectedAudioDevices.compactMap { device in
            createBluetoothAudioDevice(from: device)
        }
        
        // Update connection state
        isBluetoothAudioConnected = !connectedDevices.isEmpty
        
        if let lastDevice = connectedDevices.last {
            lastConnectedDevice = lastDevice
            print("🎧 [BluetoothAudioManager] ✅ Bluetooth audio connected: \(lastDevice.name)")
        }
    }
    
    // MARK: - Device Event Handlers
    
    /// Handles Bluetooth device connection notification from DistributedNotificationCenter
    @objc private func handleDeviceConnectedNotification(_ notification: Notification) {
        print("🎧 [BluetoothAudioManager] 📡 Device connection notification received")
        
        // Re-check all devices since distributed notification doesn't contain device object
        checkForNewlyConnectedDevices()
    }
    
    /// Handles Bluetooth device disconnection notification from DistributedNotificationCenter
    @objc private func handleDeviceDisconnectedNotification(_ notification: Notification) {
        print("🎧 [BluetoothAudioManager] 📡 Device disconnection notification received")
        
        // Re-check all devices to update connection state
        updateConnectedDevices()
    }
    
    /// Checks for newly connected devices and displays HUD for new ones
    private func checkForNewlyConnectedDevices() {
        // Check if Bluetooth is powered on
        guard IOBluetoothHostController.default()?.powerState == kBluetoothHCIPowerStateON else {
            print("🎧 [BluetoothAudioManager] ⚠️ Bluetooth is powered off - skipping device check")
            return
        }
        
        guard let pairedDevices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else {
            return
        }
        
        let currentlyConnectedDevices = pairedDevices.filter { device in
            device.isConnected() && isAudioDevice(device)
        }
        
        // Find devices that are newly connected
        for device in currentlyConnectedDevices {
            let address = device.addressString ?? "Unknown"
            
            // Check if this device wasn't in our list before
            if !connectedDevices.contains(where: { $0.address == address }) {
                print("🎧 [BluetoothAudioManager] 🎉 New audio device connected: \(device.name ?? "Unknown")")
                
                guard let audioDevice = createBluetoothAudioDevice(from: device) else {
                    continue
                }
                
                // Add to connected devices
                connectedDevices.append(audioDevice)
                lastConnectedDevice = audioDevice
                isBluetoothAudioConnected = true
                
                // Show HUD for new connection
                showDeviceConnectedHUD(audioDevice)
            }
        }
    }
    
    /// Updates the list of connected devices (for disconnections)
    private func updateConnectedDevices() {
        guard let pairedDevices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else {
            return
        }
        
        let currentlyConnectedAddresses = pairedDevices
            .filter { $0.isConnected() && isAudioDevice($0) }
            .compactMap { $0.addressString }
        
        // Remove disconnected devices
        let previousCount = connectedDevices.count
        connectedDevices.removeAll { device in
            !currentlyConnectedAddresses.contains(device.address)
        }
        
        if connectedDevices.count < previousCount {
            print("🎧 [BluetoothAudioManager] 👋 Audio device(s) disconnected")
        }
        
        isBluetoothAudioConnected = !connectedDevices.isEmpty
    }
    
    /// Handles Bluetooth device connection event (legacy - kept for compatibility)
    private func handleDeviceConnected(_ notification: Notification) {
        guard let device = notification.object as? IOBluetoothDevice else {
            print("🎧 [BluetoothAudioManager] ⚠️ Could not extract device from notification")
            return
        }
        
        // Only handle audio devices
        guard isAudioDevice(device) else {
            print("🎧 [BluetoothAudioManager] Device is not an audio device, ignoring")
            return
        }
        
        print("🎧 [BluetoothAudioManager] 🎉 Audio device connected: \(device.name ?? "Unknown")")
        
        guard let audioDevice = createBluetoothAudioDevice(from: device) else {
            return
        }
        
        // Add to connected devices list
        if !connectedDevices.contains(where: { $0.address == audioDevice.address }) {
            connectedDevices.append(audioDevice)
        }
        
        // Update last connected device
        lastConnectedDevice = audioDevice
        isBluetoothAudioConnected = true
        
        // Show HUD
        showDeviceConnectedHUD(audioDevice)
    }
    
    /// Handles Bluetooth device disconnection event
    private func handleDeviceDisconnected(_ notification: Notification) {
        guard let device = notification.object as? IOBluetoothDevice else {
            return
        }
        
        guard isAudioDevice(device) else {
            return
        }
        
        print("🎧 [BluetoothAudioManager] 👋 Audio device disconnected: \(device.name ?? "Unknown")")
        
        // Remove from connected devices
        let address = device.addressString ?? "Unknown"
        connectedDevices.removeAll { $0.address == address }
        isBluetoothAudioConnected = !connectedDevices.isEmpty
    }
    
    // MARK: - Device Detection Helpers
    
    /// Determines if a Bluetooth device is an audio device
    private func isAudioDevice(_ device: IOBluetoothDevice) -> Bool {
        // Check if device has audio service UUID
        let audioServiceUUID = IOBluetoothSDPUUID(uuid16: 0x110B)  // Audio Sink
        let headsetServiceUUID = IOBluetoothSDPUUID(uuid16: 0x1108)  // Headset
        let handsfreeServiceUUID = IOBluetoothSDPUUID(uuid16: 0x111E)  // Handsfree
        
        // Check if device has any audio-related services
        if device.getServiceRecord(for: audioServiceUUID) != nil {
            return true
        }
        if device.getServiceRecord(for: headsetServiceUUID) != nil {
            return true
        }
        if device.getServiceRecord(for: handsfreeServiceUUID) != nil {
            return true
        }
        
        // Check device class (major class: Audio/Video)
        let deviceClass = device.classOfDevice
        let majorClass = (deviceClass >> 8) & 0x1F
        let audioVideoMajorClass: UInt32 = 0x04
        
        return majorClass == audioVideoMajorClass
    }
    
    /// Creates a BluetoothAudioDevice model from IOBluetoothDevice
    private func createBluetoothAudioDevice(from device: IOBluetoothDevice) -> BluetoothAudioDevice? {
        let name = device.name ?? "Bluetooth Device"
        let address = device.addressString ?? "Unknown"
        let batteryLevel = getBatteryLevel(from: device)
        let deviceType = detectDeviceType(from: device, name: name)
        
        return BluetoothAudioDevice(
            name: name,
            address: address,
            batteryLevel: batteryLevel,
            deviceType: deviceType
        )
    }
    
    /// Extracts battery level from Bluetooth device
    private func getBatteryLevel(from device: IOBluetoothDevice) -> Int? {
        // Try to read battery level from device
        // Note: This may require additional permissions or may not be available for all devices
        
        // Placeholder: Return nil if not available
        // TODO: Implement actual battery level reading if device supports it
        return nil
    }
    
    /// Detects the type of audio device based on name and properties
    private func detectDeviceType(from device: IOBluetoothDevice, name: String) -> BluetoothAudioDeviceType {
        let lowercaseName = name.lowercased()
        
        // Check for specific AirPods models
        if lowercaseName.contains("airpods") {
            if lowercaseName.contains("max") {
                return .airpodsMax
            } else if lowercaseName.contains("pro") {
                return .airpodsPro
            }
            return .airpods
        }
        
        // Check for other brands
        if lowercaseName.contains("beats") {
            return .beats
        } else if lowercaseName.contains("speaker") || lowercaseName.contains("boombox") {
            return .speaker
        } else if lowercaseName.contains("headphone") || lowercaseName.contains("headset") || 
                  lowercaseName.contains("buds") || lowercaseName.contains("earbuds") {
            return .headphones
        }
        
        // Check device class for more specific detection
        let deviceClass = device.classOfDevice
        let minorClass = (deviceClass >> 2) & 0x3F
        
        // Minor classes for audio devices
        switch minorClass {
        case 0x01: return .headphones  // Wearable Headset
        case 0x02: return .headphones  // Hands-free
        case 0x06: return .headphones  // Headphones
        case 0x08: return .speaker     // Portable Audio
        case 0x0C: return .speaker     // Loudspeaker
        default: return .generic
        }
    }
    
    // MARK: - HUD Display
    
    /// Shows HUD notification for newly connected audio device
    private func showDeviceConnectedHUD(_ device: BluetoothAudioDevice) {
        guard Defaults[.showBluetoothDeviceConnections] else { return }
        
        print("🎧 [BluetoothAudioManager] 📱 Showing device connected HUD")
        
        // Convert battery percentage to 0.0-1.0 value
        let batteryValue: CGFloat = if let battery = device.batteryLevel {
            CGFloat(battery) / 100.0
        } else {
            0.0  // 0 means battery info not available
        }
        
        // Show HUD via coordinator
        coordinator.toggleSneakPeek(
            status: true,
            type: .bluetoothAudio,
            duration: 2.5,
            value: batteryValue,
            icon: device.deviceType.sfSymbol
        )
    }
    
    // MARK: - Cleanup
    
    private func cleanup() {
        print("🎧 [BluetoothAudioManager] Cleaning up observers...")
        
        pollingTimer?.invalidate()
        pollingTimer = nil
        
        let dnc = DistributedNotificationCenter.default()
        dnc.removeObserver(self)
        observers.removeAll()
        cancellables.removeAll()
    }
}

// MARK: - Models

struct BluetoothAudioDevice: Identifiable {
    let id = UUID()
    let name: String
    let address: String
    let batteryLevel: Int?  // 0-100, nil if not available
    let deviceType: BluetoothAudioDeviceType
}

enum BluetoothAudioDeviceType {
    case airpods
    case airpodsPro
    case airpodsMax
    case beats
    case headphones
    case speaker
    case generic
    
    var sfSymbol: String {
        switch self {
        case .airpods:
            return "airpods"
        case .airpodsPro:
            return "airpodspro"
        case .airpodsMax:
            return "airpodsmax"
        case .beats:
            return "beats.headphones"
        case .headphones:
            return "headphones"
        case .speaker:
            return "hifispeaker.fill"
        case .generic:
            return "bluetooth.circle.fill"
        }
    }
    
    var displayName: String {
        switch self {
        case .airpods: return "AirPods"
        case .airpodsPro: return "AirPods Pro"
        case .airpodsMax: return "AirPods Max"
        case .beats: return "Beats"
        case .headphones: return "Headphones"
        case .speaker: return "Speaker"
        case .generic: return "Bluetooth Device"
        }
    }
}

// MARK: - Notification Name Constants

private let IOBluetoothDeviceConnectionNotification = "IOBluetoothDeviceConnectionNotification"
private let IOBluetoothDeviceDisconnectionNotification = "IOBluetoothDeviceDisconnectionNotification"
