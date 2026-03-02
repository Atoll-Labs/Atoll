/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

@preconcurrency import Foundation
import AppKit
import Defaults
import Combine

// MARK: - BetterDisplay OSD Notification Model

/// Matches the JSON structure dispatched by BetterDisplay's OSD notification system.
/// See: https://github.com/waydabber/BetterDisplay/wiki/Integration-features,-CLI#osd-notification-dispatch-integration
struct BetterDisplayOSDNotification: Codable {
    var displayID: Int?
    var systemIconID: Int?
    var customSymbol: String?
    var text: String?
    var lock: Bool?
    var controlTarget: String?
    var value: Double?
    var maxValue: Double?
    var symbolFadeAfter: Int?
    var symbolSizeMultiplier: Double?
    var textFadeAfter: Int?
}

// MARK: - BetterDisplay Request / Response Models

/// JSON structure for sending commands to BetterDisplay via distributed notifications.
struct BetterDisplayRequestData: Codable {
    var uuid: String?
    var commands: [String] = []
    var parameters: [String: String?] = [:]
}

/// JSON structure for receiving responses from BetterDisplay.
struct BetterDisplayResponseData: Codable {
    var uuid: String?
    var result: Bool?
    var payload: String?
}

// MARK: - BetterDisplay Control Target Classification

enum BetterDisplayControlCategory {
    case brightness
    case volume
    case other
}

private let brightnessControlTargets: Set<String> = [
    "combinedBrightness",
    "hardwareBrightness",
    "softwareBrightness",
]

private let volumeControlTargets: Set<String> = [
    "volume",
    "mute",
]

// MARK: - BetterDisplay Manager

/// Manages integration with the BetterDisplay app (waydabber.BetterDisplay).
///
/// Responsibilities:
/// - Detect whether BetterDisplay is installed
/// - Observe OSD notifications from BetterDisplay and route them to Atoll's HUD pipeline
/// - Provide request/response primitives for controlling display properties
@MainActor
final class BetterDisplayManager: ObservableObject {
    static let shared = BetterDisplayManager()

    /// The bundle identifier of BetterDisplay.
    nonisolated static let bundleID = "pro.betterdisplay.BetterDisplay"

    // Notification names
    private static let osdNotificationName = NSNotification.Name("com.betterdisplay.BetterDisplay.osd")
    private static let requestNotificationName = NSNotification.Name("com.betterdisplay.BetterDisplay.request")
    private static let responseNotificationName = NSNotification.Name("com.betterdisplay.BetterDisplay.response")

    // MARK: Published state

    /// Whether BetterDisplay is currently detected on this machine.
    @Published private(set) var isDetected: Bool = false

    // MARK: Private

    private var osdObserver: NSObjectProtocol?
    private var responseObserver: NSObjectProtocol?
    private var workspaceObserver: NSObjectProtocol?
    private var cancellables = Set<AnyCancellable>()
    private weak var coordinator: DynamicIslandViewCoordinator?

    private init() {
        isDetected = Self.checkInstallation()
        setupWorkspaceObserver()
        setupSettingsObserver()
    }

    // MARK: - Public API

    /// Configure with the view coordinator for HUD dispatch.
    func configure(coordinator: DynamicIslandViewCoordinator) {
        self.coordinator = coordinator

        // Start listening if integration is enabled and BetterDisplay is detected
        if Defaults[.enableBetterDisplayIntegration] && isDetected {
            startListening()
        }
    }

    /// Refresh detection status (e.g. after app install/uninstall).
    func refreshDetectionStatus() {
        let wasDetected = isDetected
        isDetected = Self.checkInstallation()
        if wasDetected && !isDetected {
            stopListening()
        } else if !wasDetected && isDetected && Defaults[.enableBetterDisplayIntegration] {
            startListening()
        }
    }

    // MARK: - Detection

    /// Check if BetterDisplay is installed by looking for its bundle ID in running apps
    /// and falling back to NSWorkspace URL lookup.
    static func checkInstallation() -> Bool {
        // Check running apps first (fast path)
        if NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier == bundleID }) {
            return true
        }

        // Fallback: check if the app is installed via URL scheme or bundle lookup
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return FileManager.default.fileExists(atPath: url.path)
        }

        return false
    }

    // MARK: - OSD Listening

    private func startListening() {
        guard osdObserver == nil else { return }

        osdObserver = DistributedNotificationCenter.default().addObserver(
            forName: Self.osdNotificationName,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.handleOSDNotification(notification)
            }
        }

        NSLog("✅ BetterDisplay OSD listener started")
    }

    private func stopListening() {
        if let observer = osdObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
            osdObserver = nil
            NSLog("⏹ BetterDisplay OSD listener stopped")
        }
    }

    // MARK: - OSD Handling

    private func handleOSDNotification(_ notification: Notification) {
        guard Defaults[.enableBetterDisplayIntegration] else { return }

        guard let notificationString = notification.object as? String else {
            NSLog("⚠️ BetterDisplay OSD: unexpected notification format")
            return
        }

        NSLog("📺 BetterDisplay OSD raw payload: \(notificationString)")

        do {
            let osd = try JSONDecoder().decode(
                BetterDisplayOSDNotification.self,
                from: Data(notificationString.utf8)
            )
            routeOSDToHUD(osd)
        } catch {
            NSLog("⚠️ BetterDisplay OSD decode error: \(error.localizedDescription)")
        }
    }

    /// Route a decoded BetterDisplay OSD notification to the active Atoll HUD variant.
    private func routeOSDToHUD(_ osd: BetterDisplayOSDNotification) {
        let category = classifyControlTarget(osd.controlTarget, systemIconID: osd.systemIconID)
        let normalizedValue = normalizeValue(osd.value, maxValue: osd.maxValue)
        let targetScreen = resolveScreen(for: osd.displayID)
        let isExternalDisplay = isExternal(displayID: osd.displayID)

        NSLog("📺 BetterDisplay OSD: target=\(osd.controlTarget ?? "nil") displayID=\(osd.displayID.map(String.init) ?? "nil") resolvedScreen=\(targetScreen?.localizedName ?? "nil") isExternal=\(isExternalDisplay) value=\(osd.value ?? -1)")

        switch category {
        case .brightness:
            let icon = isExternalDisplay ? "display" : nil
            dispatchBrightnessHUD(value: normalizedValue, customSymbol: icon, onScreen: targetScreen)

        case .volume:
            let isMuted = osd.controlTarget == "mute" || osd.systemIconID == 4
            dispatchVolumeHUD(value: normalizedValue, isMuted: isMuted, onScreen: targetScreen)

        case .other:
            // For unsupported control targets (contrast, gamma, temperature, etc.),
            // show a generic brightness-style HUD if the user has brightness HUD enabled
            let icon = isExternalDisplay ? "display" : osd.customSymbol
            dispatchBrightnessHUD(value: normalizedValue, customSymbol: icon, onScreen: targetScreen)
        }
    }

    // MARK: - HUD Dispatch (mirrors SystemChangesObserver logic)

    private func dispatchVolumeHUD(value: CGFloat, isMuted: Bool, onScreen targetScreen: NSScreen? = nil) {
        if HUDSuppressionCoordinator.shared.shouldSuppressVolumeHUD { return }

        if Defaults[.enableCircularHUD] {
            CircularHUDWindowManager.shared.show(type: .volume, value: value, onScreen: targetScreen)
            return
        }
        if Defaults[.enableVerticalHUD] {
            VerticalHUDWindowManager.shared.show(type: .volume, value: value, icon: "", onScreen: targetScreen)
            return
        }
        if Defaults[.enableCustomOSD] && Defaults[.enableOSDVolume] {
            CustomOSDWindowManager.shared.showVolume(value: value, onScreen: targetScreen)
        }
        if Defaults[.enableSystemHUD] && !Defaults[.enableCustomOSD] && !Defaults[.enableVerticalHUD] && !Defaults[.enableCircularHUD] {
            coordinator?.toggleSneakPeek(
                status: true,
                type: .volume,
                value: value,
                icon: ""
            )
        }
    }

    private func dispatchBrightnessHUD(value: CGFloat, customSymbol: String? = nil, onScreen targetScreen: NSScreen? = nil) {
        let icon = customSymbol ?? ""
        if Defaults[.enableCircularHUD] {
            CircularHUDWindowManager.shared.show(type: .brightness, value: value, icon: icon, onScreen: targetScreen)
            return
        }
        if Defaults[.enableVerticalHUD] {
            VerticalHUDWindowManager.shared.show(type: .brightness, value: value, icon: icon, onScreen: targetScreen)
            return
        }
        if Defaults[.enableCustomOSD] && Defaults[.enableOSDBrightness] {
            CustomOSDWindowManager.shared.showBrightness(value: value, icon: icon, onScreen: targetScreen)
        }
        if Defaults[.enableSystemHUD] && !Defaults[.enableCustomOSD] && !Defaults[.enableVerticalHUD] && !Defaults[.enableCircularHUD] {
            coordinator?.toggleSneakPeek(
                status: true,
                type: .brightness,
                value: value,
                icon: icon
            )
        }
    }

    // MARK: - Helpers

    /// Resolve a BetterDisplay `displayID` (CGDirectDisplayID) to the matching NSScreen, if any.
    private func resolveScreen(for displayID: Int?) -> NSScreen? {
        guard let displayID else {
            NSLog("📺 BetterDisplay resolveScreen: displayID is nil, falling back to all screens")
            return nil
        }
        let target = UInt32(displayID)
        let availableScreens = NSScreen.screens.map { screen -> (String, UInt32) in
            let num = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
            return (screen.localizedName, num)
        }
        NSLog("📺 BetterDisplay resolveScreen: looking for displayID=\(displayID) (UInt32=\(target)) among screens: \(availableScreens)")
        let matched = NSScreen.screens.first { screen in
            guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return false
            }
            return screenNumber.uint32Value == target
        }
        if matched == nil {
            NSLog("📺 BetterDisplay resolveScreen: no match found for displayID=\(displayID), HUD will show on all screens")
        }
        return matched
    }

    /// Whether the given displayID refers to an external (non-built-in) display.
    private func isExternal(displayID: Int?) -> Bool {
        guard let displayID else { return false }
        return CGDisplayIsBuiltin(UInt32(displayID)) == 0
    }

    private func classifyControlTarget(_ target: String?, systemIconID: Int?) -> BetterDisplayControlCategory {
        if let target {
            if brightnessControlTargets.contains(target) { return .brightness }
            if volumeControlTargets.contains(target) { return .volume }
        }

        // Fallback to systemIconID
        switch systemIconID {
        case 1: return .brightness  // brightness icon
        case 3: return .volume      // volume icon
        case 4: return .volume      // mute icon
        default: return .other
        }
    }

    /// Normalize a BetterDisplay value (0...maxValue) to 0...1 range.
    private func normalizeValue(_ value: Double?, maxValue: Double?) -> CGFloat {
        guard let value else { return 0 }
        let maxVal = maxValue ?? 1.0
        guard maxVal > 0 else { return 0 }
        return CGFloat(Swift.min(Swift.max(value / maxVal, 0), 1))
    }

    // MARK: - Request API

    /// Send a command to BetterDisplay and optionally receive a response.
    /// - Parameters:
    ///   - commands: e.g. ["set"], ["get"]
    ///   - parameters: e.g. ["brightness": "0.8"]
    ///   - completion: Called with the response on the main queue, or nil on timeout.
    func sendRequest(
        commands: [String],
        parameters: [String: String?],
        completion: (@MainActor @Sendable (BetterDisplayResponseData?) -> Void)? = nil
    ) {
        let uuid = UUID().uuidString
        let request = BetterDisplayRequestData(uuid: uuid, commands: commands, parameters: parameters)

        // If we need a response, set up a temporary observer
        if let completion {
            // Use a class wrapper so the observer closure can safely capture & cancel
            final class ResponseState: @unchecked Sendable {
                var observer: NSObjectProtocol?
                var timeoutItem: DispatchWorkItem?
            }
            let state = ResponseState()

            let timeoutItem = DispatchWorkItem {
                if let obs = state.observer {
                    DistributedNotificationCenter.default().removeObserver(obs)
                    state.observer = nil
                }
                Task { @MainActor in
                    completion(nil)
                }
            }
            state.timeoutItem = timeoutItem

            state.observer = DistributedNotificationCenter.default().addObserver(
                forName: Self.responseNotificationName,
                object: nil,
                queue: .main
            ) { notification in
                guard let responseString = notification.object as? String,
                      let response = try? JSONDecoder().decode(
                        BetterDisplayResponseData.self,
                        from: Data(responseString.utf8)
                      ),
                      response.uuid == uuid
                else { return }

                state.timeoutItem?.cancel()
                if let obs = state.observer {
                    DistributedNotificationCenter.default().removeObserver(obs)
                    state.observer = nil
                }
                Task { @MainActor in
                    completion(response)
                }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0, execute: timeoutItem)
        }

        // Send the request
        do {
            let encoded = try JSONEncoder().encode(request)
            if let encodedString = String(data: encoded, encoding: .utf8) {
                DistributedNotificationCenter.default().postNotificationName(
                    Self.requestNotificationName,
                    object: encodedString,
                    userInfo: nil,
                    deliverImmediately: true
                )
            }
        } catch {
            NSLog("⚠️ BetterDisplay request encode error: \(error.localizedDescription)")
            completion?(nil)
        }
    }

    // MARK: - Workspace Observer (detect install/uninstall)

    private func setupWorkspaceObserver() {
        let betterDisplayBundleID = Self.bundleID

        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier == betterDisplayBundleID
            else { return }
            Task { @MainActor in
                self?.refreshDetectionStatus()
            }
        }

        // Also observe app termination
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier == betterDisplayBundleID
            else { return }
            // Don't clear isDetected on termination — app is still installed, just not running.
        }
    }

    // MARK: - Settings Observer

    private func setupSettingsObserver() {
        Defaults.publisher(.enableBetterDisplayIntegration, options: [])
            .sink { [weak self] change in
                Task { @MainActor in
                    guard let self else { return }
                    if change.newValue && self.isDetected {
                        self.startListening()
                    } else {
                        self.stopListening()
                    }
                }
            }
            .store(in: &cancellables)
    }

    deinit {
        if let osdObserver {
            DistributedNotificationCenter.default().removeObserver(osdObserver)
        }
        if let workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
        }
        cancellables.removeAll()
    }
}
