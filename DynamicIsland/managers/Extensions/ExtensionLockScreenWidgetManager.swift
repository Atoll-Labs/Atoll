import Foundation
import Defaults
import AtollExtensionKit

@MainActor
final class ExtensionLockScreenWidgetManager: ObservableObject {
    static let shared = ExtensionLockScreenWidgetManager()

    @Published private(set) var activeWidgets: [ExtensionLockScreenWidgetPayload] = []

    private let authorizationManager = ExtensionAuthorizationManager.shared
    private let maxCapacityKey = Defaults.Keys.extensionLockScreenWidgetCapacity
    private var presentationController: ExtensionLockScreenWidgetPresentationController!

    private init() {
        presentationController = ExtensionLockScreenWidgetPresentationController(manager: self)
        presentationController.activate()
    }

    func present(descriptor: AtollLockScreenWidgetDescriptor, bundleIdentifier: String) throws {
        guard authorizationManager.canProcessLockScreenRequest(from: bundleIdentifier) else {
            throw ExtensionValidationError.unauthorized
        }
        guard descriptor.isValid else {
            throw ExtensionValidationError.invalidDescriptor("Structure validation failed")
        }
        guard activeWidgets.count < Defaults[maxCapacityKey] else {
            throw ExtensionValidationError.exceedsCapacity
        }
        guard activeWidgets.contains(where: { $0.descriptor.id == descriptor.id }) == false else {
            throw ExtensionValidationError.duplicateIdentifier
        }

        let payload = ExtensionLockScreenWidgetPayload(
            bundleIdentifier: bundleIdentifier,
            descriptor: descriptor,
            receivedAt: .now
        )
        activeWidgets.append(payload)
        sortWidgets()
        authorizationManager.recordActivity(for: bundleIdentifier, scope: .lockScreenWidgets)
    }

    func update(descriptor: AtollLockScreenWidgetDescriptor, bundleIdentifier: String) throws {
        guard descriptor.isValid else {
            throw ExtensionValidationError.invalidDescriptor("Structure validation failed")
        }
        guard let index = activeWidgets.firstIndex(where: { $0.descriptor.id == descriptor.id && $0.bundleIdentifier == bundleIdentifier }) else {
            throw ExtensionValidationError.invalidDescriptor("Missing existing widget")
        }

        let payload = ExtensionLockScreenWidgetPayload(
            bundleIdentifier: bundleIdentifier,
            descriptor: descriptor,
            receivedAt: activeWidgets[index].receivedAt
        )
        activeWidgets[index] = payload
        sortWidgets()
        authorizationManager.recordActivity(for: bundleIdentifier, scope: .lockScreenWidgets)
    }

    func dismiss(widgetID: String, bundleIdentifier: String) {
        let previousCount = activeWidgets.count
        activeWidgets.removeAll { $0.descriptor.id == widgetID && $0.bundleIdentifier == bundleIdentifier }
        if previousCount != activeWidgets.count {
            Logger.log("Dismissed extension widget \(widgetID) from \(bundleIdentifier)", category: .extensions)
            ExtensionXPCServiceHost.shared.notifyWidgetDismiss(bundleIdentifier: bundleIdentifier, widgetID: widgetID)
        }
    }

    func dismissAll(for bundleIdentifier: String) {
        let ids = activeWidgets
            .filter { $0.bundleIdentifier == bundleIdentifier }
            .map { $0.descriptor.id }
        activeWidgets.removeAll { $0.bundleIdentifier == bundleIdentifier }
        ids.forEach { ExtensionXPCServiceHost.shared.notifyWidgetDismiss(bundleIdentifier: bundleIdentifier, widgetID: $0) }
    }

    private func sortWidgets() {
        activeWidgets.sort { lhs, rhs in
            if lhs.priority == rhs.priority {
                return lhs.receivedAt < rhs.receivedAt
            }
            return lhs.priority > rhs.priority
        }
    }
}
