//
//  DoNotDisturbManager.swift
//  DynamicIsland
//
//  Replaces the legacy polling-based Focus detection with
//  NSDistributedNotificationCenter-backed monitoring.
//

import AppKit
import Combine
import Defaults
import Foundation
import SwiftUI

final class DoNotDisturbManager: ObservableObject {
    static let shared = DoNotDisturbManager()

    @Published private(set) var isMonitoring = false
    @Published var isDoNotDisturbActive = false
    @Published var currentFocusModeName: String = ""
    @Published var currentFocusModeIdentifier: String = ""

    private let notificationCenter = DistributedNotificationCenter.default()
    private let metadataExtractionQueue = DispatchQueue(label: "com.dynamicisland.focus.metadata", qos: .userInitiated)
    private var hasLoggedPayload = false

    private init() {}

    deinit {
        stopMonitoring()
    }

    func startMonitoring() {
        guard !isMonitoring else { return }

        notificationCenter.addObserver(
            self,
            selector: #selector(handleFocusEnabled(_:)),
            name: .focusModeEnabled,
            object: nil,
            suspensionBehavior: .deliverImmediately
        )

        notificationCenter.addObserver(
            self,
            selector: #selector(handleFocusDisabled(_:)),
            name: .focusModeDisabled,
            object: nil,
            suspensionBehavior: .deliverImmediately
        )

        isMonitoring = true
    }

    func stopMonitoring() {
        guard isMonitoring else { return }

        notificationCenter.removeObserver(self, name: .focusModeEnabled, object: nil)
        notificationCenter.removeObserver(self, name: .focusModeDisabled, object: nil)

        isMonitoring = false

        DispatchQueue.main.async {
            self.isDoNotDisturbActive = false
            self.currentFocusModeIdentifier = ""
            self.currentFocusModeName = ""
        }
    }

    @objc private func handleFocusEnabled(_ notification: Notification) {
        apply(notification: notification, isActive: true)
    }

    @objc private func handleFocusDisabled(_ notification: Notification) {
        apply(notification: notification, isActive: false)
    }

    private func apply(notification: Notification, isActive: Bool) {
        metadataExtractionQueue.async { [weak self] in
            guard let self = self else { return }

            let metadata = self.extractMetadata(from: notification)

            DispatchQueue.main.async {
                if let identifier = metadata.identifier, identifier != self.currentFocusModeIdentifier {
                    self.currentFocusModeIdentifier = identifier
                }

                if let name = metadata.name {
                    if name != self.currentFocusModeName {
                        self.currentFocusModeName = name
                    }
                } else if !self.currentFocusModeIdentifier.isEmpty {
                    let derivedName = FocusModeType(rawValue: self.currentFocusModeIdentifier)?.displayName ?? ""
                    if !derivedName.isEmpty {
                        self.currentFocusModeName = derivedName
                    }
                }

                guard self.isDoNotDisturbActive != isActive else { return }

                withAnimation(.smooth(duration: 0.25)) {
                    self.isDoNotDisturbActive = isActive
                }
            }
        }
    }

    private func extractMetadata(from notification: Notification) -> (name: String?, identifier: String?) {
        guard let userInfo = notification.userInfo else { return (nil, nil) }

        if !hasLoggedPayload {
            hasLoggedPayload = true
            debugPrint("[DoNotDisturbManager] focus notification payload: \(userInfo)")
        }

        let identifierKeys = [
            "FocusModeIdentifier",
            "focusModeIdentifier",
            "identifier",
            "Identifier"
        ]

        let nameKeys = [
            "FocusModeName",
            "focusModeName",
            "name",
            "Name"
        ]

        let identifier = identifierKeys.compactMap { userInfo[$0] as? String }.first
        let name = nameKeys.compactMap { userInfo[$0] as? String }.first

        return (name, identifier)
    }

}

private extension Notification.Name {
    static let focusModeEnabled = Notification.Name("_NSDoNotDisturbEnabledNotification")
    static let focusModeDisabled = Notification.Name("_NSDoNotDisturbDisabledNotification")
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
