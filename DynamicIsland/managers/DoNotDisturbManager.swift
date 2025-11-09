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
                let trimmedIdentifier = metadata.identifier?.trimmingCharacters(in: .whitespacesAndNewlines)
                let trimmedName = metadata.name?.trimmingCharacters(in: .whitespacesAndNewlines)

                let resolvedMode = FocusModeType.resolve(identifier: trimmedIdentifier, name: trimmedName)

                debugPrint("[DoNotDisturbManager] Focus update -> notification: \(notification.name.rawValue) | identifier: \(trimmedIdentifier ?? "<nil>") | name: \(trimmedName ?? "<nil>") | resolved: \(resolvedMode.rawValue)")

                let finalIdentifier: String
                if let identifier = trimmedIdentifier, !identifier.isEmpty {
                    finalIdentifier = identifier
                } else {
                    finalIdentifier = resolvedMode.rawValue
                }

                if finalIdentifier != self.currentFocusModeIdentifier {
                    self.currentFocusModeIdentifier = finalIdentifier
                }

                let finalName: String
                if let name = trimmedName, !name.isEmpty {
                    finalName = name
                } else if !resolvedMode.displayName.isEmpty {
                    finalName = resolvedMode.displayName
                } else if let identifier = trimmedIdentifier, !identifier.isEmpty {
                    finalName = identifier
                } else {
                    finalName = "Focus"
                }

                if finalName != self.currentFocusModeName {
                    self.currentFocusModeName = finalName
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

        debugPrint("[DoNotDisturbManager] raw focus payload -> name: \(notification.name.rawValue), object: \(String(describing: notification.object)), userInfo: \(userInfo)")

        let identifierKeys = [
            "FocusModeIdentifier",
            "focusModeIdentifier",
            "FocusModeUUID",
            "focusModeUUID",
            "UUID",
            "uuid",
            "identifier",
            "Identifier"
        ]

        let nameKeys = [
            "FocusModeName",
            "focusModeName",
            "FocusMode",
            "focusMode",
            "name",
            "Name"
        ]

        let identifier = firstMatch(for: identifierKeys, in: userInfo)
        let name = firstMatch(for: nameKeys, in: userInfo)

        return (name, identifier)
    }

}

private extension Notification.Name {
    static let focusModeEnabled = Notification.Name("_NSDoNotDisturbEnabledNotification")
    static let focusModeDisabled = Notification.Name("_NSDoNotDisturbDisabledNotification")
}

// MARK: - Focus Mode Types

enum FocusModeType: String, CaseIterable {
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
        case .unknown: return "moon.fill"
        }
    }

    var accentColor: Color {
        switch self {
        case .doNotDisturb:
            return Color(red: 0.370, green: 0.360, blue: 0.902)
        case .work:
            return Color(red: 0.133, green: 0.475, blue: 0.992)
        case .personal:
            return Color(red: 0.937, green: 0.282, blue: 0.624)
        case .sleep:
            return Color(red: 0.341, green: 0.384, blue: 0.980)
        case .driving:
            return Color(red: 0.988, green: 0.561, blue: 0.153)
        case .fitness:
            return Color(red: 0.176, green: 0.804, blue: 0.459)
        case .gaming:
            return Color(red: 0.639, green: 0.329, blue: 0.937)
        case .mindfulness:
            return Color(red: 0.239, green: 0.718, blue: 0.682)
        case .reading:
            return Color(red: 0.239, green: 0.596, blue: 0.965)
        case .custom:
            return Color(red: 0.513, green: 0.478, blue: 0.965)
        case .unknown:
            return Color(red: 0.370, green: 0.360, blue: 0.902)
        }
    }

    var inactiveSymbol: String {
        switch self {
        case .doNotDisturb:
            return "moon.circle.fill"
        default:
            return sfSymbol
        }
    }
}

extension FocusModeType {
    init(identifier: String) {
        let normalized = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedLowercased = normalized.lowercased()

        guard !normalized.isEmpty else {
            self = .doNotDisturb
            return
        }

        if let direct = FocusModeType(rawValue: normalized) ?? FocusModeType(rawValue: normalizedLowercased) {
            self = direct
            return
        }

        if let resolved = FocusModeType.allCases.first(where: {
            guard !$0.rawValue.isEmpty else { return false }
            return normalized.hasPrefix($0.rawValue) || normalizedLowercased.hasPrefix($0.rawValue)
        }) {
            self = resolved
            return
        }

        if normalizedLowercased.hasPrefix("com.apple.focus.") {
            self = .custom
            return
        }

        self = .doNotDisturb
    }

    static func resolve(identifier: String?, name: String?) -> FocusModeType {
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedName.isEmpty {
            if let match = FocusModeType.allCases.first(where: {
                guard !$0.displayName.isEmpty else { return false }
                return $0.displayName.compare(trimmedName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            }) {
                return match
            }
        }

        let trimmedIdentifier = identifier?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedIdentifier.isEmpty {
            return FocusModeType(identifier: trimmedIdentifier)
        }

        return .doNotDisturb
    }
}

// MARK: - Metadata helpers

private extension DoNotDisturbManager {
    func firstMatch(for keys: [String], in value: Any) -> String? {
        if let dictionary = value as? [AnyHashable: Any] {
            for key in keys {
                if let candidate = dictionary[key], let string = normalizedString(from: candidate) {
                    return string
                }
            }

            for nestedValue in dictionary.values {
                if let nestedMatch = firstMatch(for: keys, in: nestedValue) {
                    return nestedMatch
                }
            }
        } else if let array = value as? [Any] {
            for element in array {
                if let nestedMatch = firstMatch(for: keys, in: element) {
                    return nestedMatch
                }
            }
        }

        return nil
    }

    func normalizedString(from value: Any) -> String? {
        switch value {
        case let string as String:
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        case let number as NSNumber:
            return number.stringValue
        case let uuid as UUID:
            return uuid.uuidString
        case let uuid as NSUUID:
            return uuid.uuidString
        case let data as Data:
            if let string = String(data: data, encoding: .utf8) {
                return string.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return nil
        case let dict as [AnyHashable: Any]:
            // Attempt to pull common keys from nested dictionaries
            if let nested = firstMatch(for: ["identifier", "Identifier", "uuid", "UUID"], in: dict) {
                return nested
            }
            if let name = firstMatch(for: ["name", "Name", "displayName", "display_name"], in: dict) {
                return name
            }
            return nil
        default:
            return nil
        }
    }
}
