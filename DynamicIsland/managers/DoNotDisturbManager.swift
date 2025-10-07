//
//  DoNotDisturbManager.swift
//  DynamicIsland
//
//  Created for Do Not Disturb / Focus Mode detection
//  Monitors macOS Focus Mode state changes via distributed notifications
//

import Foundation
import Combine
import AppKit
import Defaults
import SwiftUI
import UserNotifications  // For notification permission checks
import ApplicationServices  // For AXIsProcessTrusted

/// Manages detection and state tracking for macOS Focus Mode (Do Not Disturb)
class DoNotDisturbManager: ObservableObject {
    static let shared = DoNotDisturbManager()
    
    // MARK: - Published Properties
    @Published var isDoNotDisturbActive: Bool = false
    @Published var currentFocusModeName: String = ""
    @Published var currentFocusModeIdentifier: String = ""
    
    // MARK: - Private Properties
    private var observers: [NSObjectProtocol] = []
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    private init() {
        print("🔔 [DoNotDisturbManager] Initializing...")
        checkPermissions()
        setupFocusModeObservers()
        checkInitialState()
    }
    
    deinit {
        cleanup()
    }
    
    // MARK: - Permission Checks
    
    /// Checks if the app has necessary permissions for notification observation
    private func checkPermissions() {
        print("🔔 [DoNotDisturbManager] ==========================================")
        print("🔔 [DoNotDisturbManager] 🔐 CHECKING PERMISSIONS & CAPABILITIES")
        print("🔔 [DoNotDisturbManager] ==========================================")
        
        // Check if running in sandbox
        let isSandboxed = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
        print("   📦 Sandboxed: \(isSandboxed ? "YES ⚠️" : "NO ✅")")
        
        // Check notification center permissions
        let notificationCenter = UNUserNotificationCenter.current()
        notificationCenter.getNotificationSettings { settings in
            print("   🔔 Notification Authorization: \(settings.authorizationStatus.rawValue)")
            print("      - .notDetermined = 0")
            print("      - .denied = 1")
            print("      - .authorized = 2")
            print("      - .provisional = 3")
            print("      - .ephemeral = 4")
        }
        
        // Check accessibility permissions
        let trusted = AXIsProcessTrusted()
        print("   ♿️ Accessibility Trusted: \(trusted ? "YES ✅" : "NO ⚠️")")
        if !trusted {
            print("      ⚠️  App needs Accessibility permission!")
            print("      ⚠️  Go to: System Settings > Privacy & Security > Accessibility")
        }
        
        // Check entitlements
        print("   📝 Checking Entitlements...")
        if let entitlements = Bundle.main.object(forInfoDictionaryKey: "Entitlements") as? [String: Any] {
            print("      Entitlements found: \(entitlements.keys)")
        } else {
            print("      ⚠️  No entitlements in Info.plist")
        }
        
        // Test if we can observe notifications at all
        print("   🧪 Testing notification observation capability...")
        testNotificationObservation()
        
        print("🔔 [DoNotDisturbManager] ==========================================")
    }
    
    /// Test if notification observation is working at all
    private func testNotificationObservation() {
        // Test 1: Local NotificationCenter
        let testObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("TEST_NOTIFICATION"),
            object: nil,
            queue: .main,
            using: { notification in
                print("   ✅ Local NotificationCenter works!")
            }
        )
        NotificationCenter.default.post(name: NSNotification.Name("TEST_NOTIFICATION"), object: nil)
        NotificationCenter.default.removeObserver(testObserver)
        
        // Test 2: Distributed NotificationCenter (this is what we need)
        let dnc = DistributedNotificationCenter.default()
        print("   🌐 DistributedNotificationCenter instance: \(dnc)")
        print("   🌐 Attempting to post test distributed notification...")
        
        let testDistributedObserver = dnc.addObserver(
            forName: NSNotification.Name("com.test.distributed.notification"),
            object: nil,
            queue: .main,
            using: { notification in
                print("   ✅ Distributed NotificationCenter observation works!")
            }
        )
        
        // Post a test distributed notification
        dnc.postNotificationName(
            NSNotification.Name("com.test.distributed.notification"),
            object: nil,
            userInfo: ["test": "data"],
            deliverImmediately: true
        )
        
        // Wait a bit then remove observer
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            dnc.removeObserver(testDistributedObserver)
            print("   🧹 Test observer cleaned up")
        }
    }
    
    // MARK: - Setup Methods
    
    /// Sets up distributed notification observers for Focus Mode changes
    private func setupFocusModeObservers() {
        print("🔔 [DoNotDisturbManager] ==========================================")
        print("🔔 [DoNotDisturbManager] 🚨 SETTING UP NOTIFICATION OBSERVERS 🚨")
        print("🔔 [DoNotDisturbManager] ==========================================")
        
        // Method 1: Darwin Notifications (low-level, no permissions needed)
        setupDarwinNotificationObserver()
        
        // Method 2: Distributed Notifications (system-wide)
        setupDistributedNotificationObserver()
        
        // Method 3: NSWorkspace Notifications (local)
        setupNSWorkspaceNotificationObserver()
        
        // Method 4: Polling as fallback
        startPollingForDND()
        
        print("🔔 [DoNotDisturbManager] ✅ All observers registered")
        print("🔔 [DoNotDisturbManager] Please toggle Do Not Disturb now...")
        print("🔔 [DoNotDisturbManager] ==========================================")
    }
    
    private func setupDarwinNotificationObserver() {
        print("🔔 [DoNotDisturbManager] Setting up DARWIN notification observer...")
        
        // Darwin notifications - these are low-level and work without special permissions
        let darwinNotificationNames = [
            "com.apple.controlcenter.modeChanged",
            "com.apple.donotdisturb.changed",
            "com.apple.donotdisturb.state",
            "com.apple.springboard.donotdisturb"
        ]
        
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        
        for notificationName in darwinNotificationNames {
            CFNotificationCenterAddObserver(
                center,
                Unmanaged.passUnretained(self).toOpaque(),
                { (center, observer, name, object, userInfo) in
                    guard let name = name else { return }
                    let notificationName = name.rawValue as String
                    print("🎯 [DARWIN NOTIFICATION] \(notificationName)")
                    
                    // Get the manager instance
                    if let observer = observer {
                        let manager = Unmanaged<DoNotDisturbManager>.fromOpaque(observer).takeUnretainedValue()
                        manager.handleDarwinNotification(notificationName)
                    }
                },
                notificationName as CFString,
                nil,
                .deliverImmediately
            )
            print("   ✅ Darwin observer registered for: \(notificationName)")
        }
    }
    
    private func handleDarwinNotification(_ name: String) {
        DispatchQueue.main.async { [weak self] in
            print("🔔🔔🔔 [DARWIN] Focus Mode notification received: \(name)")
            // Toggle DND state
            self?.isDoNotDisturbActive.toggle()
            self?.showFocusModeActivatedHUD()
        }
    }
    
    private func setupDistributedNotificationObserver() {
        let dnc = DistributedNotificationCenter.default()
        
        print("🔔 [DoNotDisturbManager] Setting up DISTRIBUTED notification observer...")
        
        // Observer for ANY AND ALL distributed notifications (for discovery)
        let allNotificationsObserver = dnc.addObserver(
            forName: nil,  // nil = listen to EVERYTHING
            object: nil,
            queue: .main,
            using: { [weak self] notification in
                let notificationName = notification.name.rawValue
                
                // PRINT EVERY SINGLE NOTIFICATION (no filtering)
                print("📢 [DISTRIBUTED] \(notificationName)")
                
                // Also check if it looks Focus Mode related
                if notificationName.lowercased().contains("focus") ||
                   notificationName.lowercased().contains("dnd") ||
                   notificationName.lowercased().contains("disturb") ||
                   notificationName.lowercased().contains("mode") ||
                   notificationName.contains("com.apple.controlcenter") ||
                   notificationName.contains("com.apple.donotdisturb") {
                    
                    print("🔔🔔🔔 [DoNotDisturbManager] ⚡️⚡️⚡️ POTENTIAL FOCUS MODE NOTIFICATION:")
                    print("       Name: \(notificationName)")
                    print("       Object: \(String(describing: notification.object))")
                    print("       UserInfo Keys: \(notification.userInfo?.keys.map { String(describing: $0) } ?? [])")
                    print("       UserInfo: \(notification.userInfo ?? [:])")
                    print("       ===============================================")
                    
                    self?.handleFocusModeNotification(notification)
                }
            }
        )
        observers.append(allNotificationsObserver)
        print("   ✅ Distributed notification observer registered")
    }
    
    private func setupNSWorkspaceNotificationObserver() {
        let nc = NSWorkspace.shared.notificationCenter
        
        print("🔔 [DoNotDisturbManager] Setting up NSWORKSPACE notification observer...")
        
        // Try to observe workspace notifications
        let workspaceObserver = nc.addObserver(
            forName: nil,  // Listen to all workspace notifications
            object: nil,
            queue: .main,
            using: { notification in
                let notificationName = notification.name.rawValue
                
                // Print all workspace notifications
                print("🏢 [NSWORKSPACE] \(notificationName)")
                
                // Check for Focus Mode related
                if notificationName.lowercased().contains("focus") ||
                   notificationName.lowercased().contains("dnd") ||
                   notificationName.lowercased().contains("disturb") {
                    print("🔔🔔🔔 [WORKSPACE FOCUS NOTIFICATION]")
                    print("       Name: \(notificationName)")
                    print("       UserInfo: \(notification.userInfo ?? [:])")
                }
            }
        )
        observers.append(workspaceObserver)
        print("   ✅ NSWorkspace notification observer registered")
    }
    
    private func startPollingForDND() {
        print("🔔 [DoNotDisturbManager] Starting polling fallback (every 2 seconds)...")
        
        // Poll every 2 seconds to check for DND state changes
        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.checkDNDStateViaDefaults()
        }
        print("   ✅ Polling timer started")
    }
    
    private func checkDNDStateViaDefaults() {
        // Try to read DND state from UserDefaults or system preferences
        // This is a fallback detection method
        
        let cfPrefs = CFPreferencesCopyAppValue("dndStart" as CFString, "com.apple.controlcenter" as CFString)
        if let prefs = cfPrefs {
            print("🔍 [POLLING] Found controlcenter prefs: \(prefs)")
        }
        
        // Try reading notification center settings
        let ncPrefs = CFPreferencesCopyAppValue("doNotDisturb" as CFString, "com.apple.notificationcenterui" as CFString)
        if let nc = ncPrefs {
            print("🔍 [POLLING] Found notification center prefs: \(nc)")
        }
    }
    
    /// Checks initial Focus Mode state on app launch
    private func checkInitialState() {
        // TODO: Find a way to check current Focus Mode state
        // Options to explore:
        // 1. NSWorkspace properties (if any exist)
        // 2. Private APIs
        // 3. AppleScript (last resort)
        
        print("🔔 [DoNotDisturbManager] Checking initial Focus Mode state...")
        print("   Note: Initial state detection not yet implemented")
    }
    
    // MARK: - Notification Handling
    
    /// Handles incoming Focus Mode notifications
    private func handleFocusModeNotification(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Parse notification payload
            let userInfo = notification.userInfo ?? [:]
            
            // Try to extract Focus Mode state and identifier
            // Note: Actual keys depend on the notification structure (to be discovered)
            if let stateString = userInfo["state"] as? String {
                self.isDoNotDisturbActive = (stateString == "enabled" || stateString == "on" || stateString == "active")
            } else if let enabled = userInfo["enabled"] as? Bool {
                self.isDoNotDisturbActive = enabled
            } else if let active = userInfo["active"] as? Bool {
                self.isDoNotDisturbActive = active
            }
            
            // Try to extract mode name
            if let modeName = userInfo["name"] as? String {
                self.currentFocusModeName = modeName
            } else if let mode = userInfo["mode"] as? String {
                self.currentFocusModeName = mode
            }
            
            // Try to extract mode identifier
            if let identifier = userInfo["identifier"] as? String {
                self.currentFocusModeIdentifier = identifier
            }
            
            print("🔔 [DoNotDisturbManager] State updated:")
            print("   Active: \(self.isDoNotDisturbActive)")
            print("   Mode Name: \(self.currentFocusModeName.isEmpty ? "N/A" : self.currentFocusModeName)")
            print("   Identifier: \(self.currentFocusModeIdentifier.isEmpty ? "N/A" : self.currentFocusModeIdentifier)")
            
            // Trigger HUD display
            if self.isDoNotDisturbActive {
                self.showFocusModeActivatedHUD()
            } else {
                self.showFocusModeDeactivatedHUD()
            }
        }
    }
    
    // MARK: - HUD Display Methods
    
    /// Shows HUD when Focus Mode is activated
    private func showFocusModeActivatedHUD() {
        print("🔔 [DoNotDisturbManager] 📱 Showing Focus Mode ACTIVATED HUD")
        
        // TODO: Integrate with DynamicIslandViewCoordinator to show HUD
        // coordinator.toggleSneakPeek(status: true, type: .doNotDisturb, value: 1)
    }
    
    /// Shows HUD when Focus Mode is deactivated
    private func showFocusModeDeactivatedHUD() {
        print("🔔 [DoNotDisturbManager] 📱 Showing Focus Mode DEACTIVATED HUD")
        
        // TODO: Integrate with DynamicIslandViewCoordinator to show HUD
        // coordinator.toggleSneakPeek(status: true, type: .doNotDisturb, value: 0)
    }
    
    // MARK: - Public Methods
    
    /// Manually refresh Focus Mode state
    func refreshState() {
        print("🔔 [DoNotDisturbManager] Manual state refresh requested")
        checkInitialState()
    }
    
    // MARK: - Cleanup
    
    private func cleanup() {
        print("🔔 [DoNotDisturbManager] Cleaning up observers...")
        
        // Remove Darwin notification observers
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterRemoveEveryObserver(center, Unmanaged.passUnretained(self).toOpaque())
        
        // Remove other observers
        let dnc = DistributedNotificationCenter.default()
        for observer in observers {
            dnc.removeObserver(observer)
        }
        observers.removeAll()
        cancellables.removeAll()
    }
}

// MARK: - Focus Mode Types

enum FocusModeType: String {
    case doNotDisturb = "com.apple.donotdisturb.mode"
    case work = "com.apple.focus.work"
    case personal = "com.apple.focus.personal"
    case sleep = "com.apple.focus.sleep"
    case driving = "com.apple.focus.driving"
    case fitness = "com.apple.focus.fitness"
    case gaming = "com.apple.focus.gaming"
    case mindfulness = "com.apple.focus.mindfulness"
    case reading = "com.apple.focus.reading"
    case custom = "com.apple.focus.custom"
    case unknown = ""
    
    var displayName: String {
        switch self {
        case .doNotDisturb: return "Do Not Disturb"
        case .work: return "Work"
        case .personal: return "Personal"
        case .sleep: return "Sleep"
        case .driving: return "Driving"
        case .fitness: return "Fitness"
        case .gaming: return "Gaming"
        case .mindfulness: return "Mindfulness"
        case .reading: return "Reading"
        case .custom: return "Focus"
        case .unknown: return "Focus Mode"
        }
    }
    
    var sfSymbol: String {
        switch self {
        case .doNotDisturb: return "moon.fill"
        case .work: return "briefcase.fill"
        case .personal: return "person.fill"
        case .sleep: return "bed.double.fill"
        case .driving: return "car.fill"
        case .fitness: return "figure.run"
        case .gaming: return "gamecontroller.fill"
        case .mindfulness: return "brain.head.profile"
        case .reading: return "book.fill"
        case .custom: return "app.badge"
        case .unknown: return "moon.zzz.fill"
        }
    }
}
