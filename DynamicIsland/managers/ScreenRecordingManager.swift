//
//  ScreenRecordingManager.swift
//  DynamicIsland
//
//  Created for screen recording detection feature
//  Monitors system for active screen recording and provides real-time status updates

import Foundation
import Combine
import ScreenCaptureKit
import AppKit
import Defaults
import SwiftUI

@MainActor
class ScreenRecordingManager: ObservableObject {
    static let shared = ScreenRecordingManager()
    
    // MARK: - Coordinator
    private let coordinator = DynamicIslandViewCoordinator.shared
    
    // MARK: - Published Properties
    @Published var isRecording: Bool = false
    @Published var isMonitoring: Bool = false
    @Published var recordingDuration: TimeInterval = 0
    @Published var isRecorderIdle: Bool = true
    @Published var lastUpdated: Date = .distantPast
    
    // MARK: - Private Properties
    private var monitoringTimer: Timer?
    private var lastScreensHaveSeparateSpaces: Bool = false
    private var cancellables = Set<AnyCancellable>()
    private var recordingStartTime: Date?
    private var durationTimer: Timer?
    private var debounceIdleTask: Task<Void, Never>?
    
    // MARK: - Configuration
    private let monitoringInterval: TimeInterval = 1.0 // Check every second
    private let debounceDelay: TimeInterval = 0.5 // Debounce rapid changes
    
    // MARK: - Initialization
    private init() {
        setupInitialState()
    }
    
    deinit {
        Task { @MainActor in
            stopMonitoring()
            debounceIdleTask?.cancel()
        }
    }
    
    // MARK: - Public Methods
    
    /// Start monitoring for screen recording activity
    func startMonitoring() {
        guard !isMonitoring else { 
            print("ScreenRecordingManager: Already monitoring, skipping start")
            return 
        }
        
        isMonitoring = true
        lastScreensHaveSeparateSpaces = NSScreen.screensHaveSeparateSpaces
        
        print("ScreenRecordingManager: 🟢 Starting monitoring...")
        print("ScreenRecordingManager: Initial screensHaveSeparateSpaces = \(lastScreensHaveSeparateSpaces)")
        
        // Start timer-based monitoring
        monitoringTimer = Timer.scheduledTimer(withTimeInterval: monitoringInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.checkRecordingStatus()
            }
        }
        
        print("ScreenRecordingManager: ✅ Started monitoring with \(monitoringInterval)s interval")
    }
    
    /// Stop monitoring for screen recording activity
    func stopMonitoring() {
        guard isMonitoring else { 
            print("ScreenRecordingManager: Not monitoring, skipping stop")
            return 
        }
        
        print("ScreenRecordingManager: 🛑 Stopping monitoring...")
        
        isMonitoring = false
        monitoringTimer?.invalidate()
        monitoringTimer = nil
        
        // Stop duration tracking
        stopDurationTracking()
        
        // Reset recording state when stopping
        if isRecording {
            print("ScreenRecordingManager: Resetting isRecording from true to false")
        }
        isRecording = false
        
        print("ScreenRecordingManager: ✅ Stopped monitoring")
    }
    
    /// Toggle monitoring state
    func toggleMonitoring() {
        if isMonitoring {
            stopMonitoring()
        } else {
            startMonitoring()
        }
    }
    
    // MARK: - Private Methods
    
    private func setupInitialState() {
        lastScreensHaveSeparateSpaces = NSScreen.screensHaveSeparateSpaces
    }
    
    /// Check current recording status using multiple detection methods
    private func checkRecordingStatus() async {
        let currentRecordingState = await detectScreenRecording()
        
        // Debug: Always log current check
        print("ScreenRecordingManager: 🔍 Checking... current=\(isRecording), detected=\(currentRecordingState)")
        
        // Debounce changes to avoid flickering
        if currentRecordingState != isRecording {
            print("ScreenRecordingManager: 🔄 State change detected (\(isRecording) -> \(currentRecordingState)), debouncing...")
            
            // Add a small delay to confirm the state change
            try? await Task.sleep(nanoseconds: UInt64(debounceDelay * 1_000_000_000))
            
            // Double-check the state after debounce
            let confirmedState = await detectScreenRecording()
            print("ScreenRecordingManager: 🔍 After debounce: confirmed=\(confirmedState), original=\(currentRecordingState)")
            
            if confirmedState == currentRecordingState {
                if confirmedState && !isRecording {
                    // Started recording
                    lastUpdated = Date()
                    startDurationTracking()
                    updateIdleState(recording: true)
                    // Trigger expanding view like music activity
                    coordinator.toggleExpandingView(status: true, type: .recording)
                    withAnimation(.smooth) {
                        isRecording = confirmedState
                    }
                } else if !confirmedState && isRecording {
                    // Stopped recording - let expanding view auto-collapse naturally (like music)
                    lastUpdated = Date()
                    stopDurationTracking()
                    updateIdleState(recording: false)
                    withAnimation(.smooth) {
                        isRecording = confirmedState
                    }
                } else {
                    isRecording = confirmedState
                }
                
                print("ScreenRecordingManager: ✅ Recording state changed to \(confirmedState)")
            } else {
                print("ScreenRecordingManager: ❌ State not confirmed, keeping \(isRecording)")
            }
        }
    }
    
    /// Detect screen recording using hybrid approach
    private func detectScreenRecording() async -> Bool {
        print("ScreenRecordingManager: 🔎 Starting detection...")
        
        // Method 1: NSScreen.screensHaveSeparateSpaces detection
        let screensHaveSeparateSpaces = NSScreen.screensHaveSeparateSpaces
        let screenSpacesChanged = screensHaveSeparateSpaces != lastScreensHaveSeparateSpaces
        
        print("ScreenRecordingManager: Method 1 - screensHaveSeparateSpaces: \(screensHaveSeparateSpaces), last: \(lastScreensHaveSeparateSpaces), changed: \(screenSpacesChanged)")
        
        // Update last known state
        lastScreensHaveSeparateSpaces = screensHaveSeparateSpaces
        
        // Method 2: ScreenCaptureKit detection (if available)
        let screencaptureKitDetection = await detectWithScreenCaptureKit()
        print("ScreenRecordingManager: Method 2 - ScreenCaptureKit: \(screencaptureKitDetection)")
        
        // Method 3: Process-based detection for common recording apps
        let processBasedDetection = detectRecordingProcesses()
        print("ScreenRecordingManager: Method 3 - Process detection: \(processBasedDetection)")
        
        // Combine detection methods (any positive result indicates recording)
        let isCurrentlyRecording = screenSpacesChanged || screencaptureKitDetection || processBasedDetection
        
        print("ScreenRecordingManager: 🎯 Final result: \(isCurrentlyRecording) (spaces:\(screenSpacesChanged) || kit:\(screencaptureKitDetection) || process:\(processBasedDetection))")
        
        return isCurrentlyRecording
    }
    
    /// Detect recording using ScreenCaptureKit (requires macOS 12.3+)
    private func detectWithScreenCaptureKit() async -> Bool {
        guard #available(macOS 12.3, *) else { return false }
        
        do {
            // Check if there are any active capture sessions
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            
            // If we can successfully get content and there are running applications with capture capabilities,
            // it might indicate active screen capture
            let runningApps = content.applications.filter { $0.applicationName.lowercased().contains("screen") || 
                                                          $0.applicationName.lowercased().contains("record") ||
                                                          $0.applicationName.lowercased().contains("capture") }
            
            return !runningApps.isEmpty
        } catch {
            // If ScreenCaptureKit fails, fall back to other detection methods
            return false
        }
    }
    
    /// Detect recording by checking for known recording processes
    private func detectRecordingProcesses() -> Bool {
        let recordingProcessNames = [
            "QuickTime Player",
            "ScreenSearch", 
            "OBS",
            "Camtasia",
            "ScreenFlow",
            "CleanMyMac",
            "Screenshot",
            "screencapture"
        ]
        
        let runningApps = NSWorkspace.shared.runningApplications
        
        print("ScreenRecordingManager: Checking \(runningApps.count) running apps for recording processes...")
        
        for app in runningApps {
            if let appName = app.localizedName {
                for processName in recordingProcessNames {
                    if appName.lowercased().contains(processName.lowercased()) {
                        print("ScreenRecordingManager: 🎬 Found recording app: \(appName)")
                        return true
                    }
                }
            }
        }
        
        print("ScreenRecordingManager: No recording processes found")
        return false
    }
    
    /// Start tracking recording duration
    private func startDurationTracking() {
        recordingStartTime = Date()
        recordingDuration = 0
        
        durationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateDuration()
            }
        }
        
        print("ScreenRecordingManager: ⏱️ Started duration tracking")
    }
    
    /// Stop tracking recording duration
    private func stopDurationTracking() {
        durationTimer?.invalidate()
        durationTimer = nil
        recordingStartTime = nil
        
        // Keep the last duration for a moment before resetting
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.recordingDuration = 0
        }
        
        print("ScreenRecordingManager: ⏹️ Stopped duration tracking")
    }
    
    /// Update the current recording duration
    private func updateDuration() {
        guard let startTime = recordingStartTime else { return }
        recordingDuration = Date().timeIntervalSince(startTime)
    }
    
    /// Copy EXACT music idle state logic
    private func updateIdleState(recording: Bool) {
        if recording {
            isRecorderIdle = false
            debounceIdleTask?.cancel()
        } else {
            debounceIdleTask?.cancel()
            debounceIdleTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(Defaults[.waitInterval]))
                guard let self = self, !Task.isCancelled else { return }
                await MainActor.run {
                    if self.lastUpdated.timeIntervalSinceNow < -Defaults[.waitInterval] {
                        withAnimation {
                            self.isRecorderIdle = !self.isRecording
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Extensions

extension ScreenRecordingManager {
    /// Get current recording status without async
    var currentRecordingStatus: Bool {
        return isRecording
    }
    
    /// Check if monitoring is available (for settings UI)
    var isMonitoringAvailable: Bool {
        return true // Basic monitoring is always available
    }
    
    /// Get current monitoring interval for debugging
    var currentMonitoringInterval: TimeInterval {
        return monitoringInterval
    }
    
    /// Get formatted recording duration string
    var formattedDuration: String {
        let totalSeconds = Int(recordingDuration)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}