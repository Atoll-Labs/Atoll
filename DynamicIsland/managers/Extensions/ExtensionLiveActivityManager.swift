import Foundation
import Defaults
import AtollExtensionKit

@MainActor
final class ExtensionLiveActivityManager: ObservableObject {
    static let shared = ExtensionLiveActivityManager()

    @Published private(set) var activeActivities: [ExtensionLiveActivityPayload] = []

    private let authorizationManager = ExtensionAuthorizationManager.shared
    private let maxCapacityKey = Defaults.Keys.extensionLiveActivityCapacity

    private init() {}

    func present(descriptor: AtollLiveActivityDescriptor, bundleIdentifier: String) throws {
        guard authorizationManager.canProcessLiveActivityRequest(from: bundleIdentifier) else {
            throw ExtensionValidationError.unauthorized
        }
        guard descriptor.isValid else {
            throw ExtensionValidationError.invalidDescriptor("Structure validation failed")
        }
        guard activeActivities.count < Defaults[maxCapacityKey] else {
            throw ExtensionValidationError.exceedsCapacity
        }
        guard activeActivities.contains(where: { $0.descriptor.id == descriptor.id }) == false else {
            throw ExtensionValidationError.duplicateIdentifier
        }

        let payload = ExtensionLiveActivityPayload(
            bundleIdentifier: bundleIdentifier,
            descriptor: descriptor,
            receivedAt: .now
        )
        activeActivities.append(payload)
        sortActivities()
        authorizationManager.recordActivity(for: bundleIdentifier, scope: .liveActivities)
    }

    func update(descriptor: AtollLiveActivityDescriptor, bundleIdentifier: String) throws {
        guard descriptor.isValid else {
            throw ExtensionValidationError.invalidDescriptor("Structure validation failed")
        }
        guard let index = activeActivities.firstIndex(where: { $0.descriptor.id == descriptor.id && $0.bundleIdentifier == bundleIdentifier }) else {
            throw ExtensionValidationError.invalidDescriptor("Missing existing activity")
        }
        let payload = ExtensionLiveActivityPayload(
            bundleIdentifier: bundleIdentifier,
            descriptor: descriptor,
            receivedAt: activeActivities[index].receivedAt
        )
        activeActivities[index] = payload
        sortActivities()
        authorizationManager.recordActivity(for: bundleIdentifier, scope: .liveActivities)
    }

    func dismiss(activityID: String, bundleIdentifier: String) {
        let previousCount = activeActivities.count
        activeActivities.removeAll { $0.descriptor.id == activityID && $0.bundleIdentifier == bundleIdentifier }
        if previousCount != activeActivities.count {
            Logger.log("Dismissed extension live activity \(activityID) from \(bundleIdentifier)", category: .extensions)
            ExtensionXPCServiceHost.shared.notifyActivityDismiss(bundleIdentifier: bundleIdentifier, activityID: activityID)
        }
    }

    func dismissAll(for bundleIdentifier: String) {
        let ids = activeActivities
            .filter { $0.bundleIdentifier == bundleIdentifier }
            .map { $0.descriptor.id }
        activeActivities.removeAll { $0.bundleIdentifier == bundleIdentifier }
        ids.forEach { ExtensionXPCServiceHost.shared.notifyActivityDismiss(bundleIdentifier: bundleIdentifier, activityID: $0) }
    }

    func sortedActivities(for coexistence: Bool = false) -> [ExtensionLiveActivityPayload] {
        activeActivities
            .filter { coexistence ? $0.descriptor.allowsMusicCoexistence : true }
            .sorted(by: descriptorComparator)
    }

    private func descriptorComparator(lhs: ExtensionLiveActivityPayload, rhs: ExtensionLiveActivityPayload) -> Bool {
        if lhs.descriptor.priority == rhs.descriptor.priority {
            return lhs.receivedAt < rhs.receivedAt
        }
        return lhs.descriptor.priority > rhs.descriptor.priority
    }

    private func sortActivities() {
        activeActivities.sort(by: descriptorComparator)
    }
}
