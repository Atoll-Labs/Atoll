import AppKit
import Foundation
import Defaults
import AtollExtensionKit

@MainActor
final class ExtensionXPCService: NSObject, AtollXPCServiceProtocol {
    private let bundleIdentifier: String
    private weak var host: ExtensionXPCServiceHost?
    private weak var connection: NSXPCConnection?

    private let authorizationManager = ExtensionAuthorizationManager.shared
    private let liveActivityManager = ExtensionLiveActivityManager.shared
    private let widgetManager = ExtensionLockScreenWidgetManager.shared
    private let decoder = JSONDecoder()

    init(bundleIdentifier: String, host: ExtensionXPCServiceHost, connection: NSXPCConnection) {
        self.bundleIdentifier = bundleIdentifier
        self.host = host
        self.connection = connection
        super.init()
    }

    // MARK: Authorization

    func requestAuthorization(bundleIdentifier providedBundleIdentifier: String, reply: @escaping (Bool, Error?) -> Void) {
        guard validate(bundleIdentifier: providedBundleIdentifier, reply: reply) else { return }

        guard authorizationManager.isExtensionsFeatureEnabled else {
            reply(false, ExtensionValidationError.featureDisabled.asNSError)
            return
        }

        let entry = authorizationManager.ensureEntryExists(bundleIdentifier: bundleIdentifier, appName: resolvedApplicationName())

        if entry.status == .pending {
            authorizationManager.authorize(bundleIdentifier: bundleIdentifier, appName: resolvedApplicationName())
            host?.notifyAuthorizationChange(bundleIdentifier: bundleIdentifier, isAuthorized: true)
            reply(true, nil)
            return
        }

        reply(entry.isAuthorized, entry.isAuthorized ? nil : ExtensionValidationError.unauthorized.asNSError)
    }

    func checkAuthorization(bundleIdentifier providedBundleIdentifier: String, reply: @escaping (Bool) -> Void) {
        guard providedBundleIdentifier == bundleIdentifier else {
            reply(false)
            return
        }

        let isAuthorized = authorizationManager.authorizationEntry(for: bundleIdentifier)?.isAuthorized ?? false
        reply(isAuthorized)
    }

    // MARK: Live Activities

    func presentLiveActivity(descriptorData: Data, reply: @escaping (Bool, Error?) -> Void) {
        respond(reply: reply) {
            let descriptor = try decoder.decode(AtollLiveActivityDescriptor.self, from: descriptorData)
            try ExtensionDescriptorValidator.validate(descriptor)
            try liveActivityManager.present(descriptor: descriptor, bundleIdentifier: bundleIdentifier)
        }
    }

    func updateLiveActivity(descriptorData: Data, reply: @escaping (Bool, Error?) -> Void) {
        respond(reply: reply) {
            let descriptor = try decoder.decode(AtollLiveActivityDescriptor.self, from: descriptorData)
            try ExtensionDescriptorValidator.validate(descriptor)
            try liveActivityManager.update(descriptor: descriptor, bundleIdentifier: bundleIdentifier)
        }
    }

    func dismissLiveActivity(activityID: String, bundleIdentifier providedBundleIdentifier: String, reply: @escaping (Bool, Error?) -> Void) {
        guard validate(bundleIdentifier: providedBundleIdentifier, reply: reply) else { return }

        liveActivityManager.dismiss(activityID: activityID, bundleIdentifier: bundleIdentifier)
        reply(true, nil)
    }

    // MARK: Lock Screen Widgets

    func presentLockScreenWidget(descriptorData: Data, reply: @escaping (Bool, Error?) -> Void) {
        respond(reply: reply) {
            let descriptor = try decoder.decode(AtollLockScreenWidgetDescriptor.self, from: descriptorData)
            try ExtensionDescriptorValidator.validate(descriptor)
            try widgetManager.present(descriptor: descriptor, bundleIdentifier: bundleIdentifier)
        }
    }

    func updateLockScreenWidget(descriptorData: Data, reply: @escaping (Bool, Error?) -> Void) {
        respond(reply: reply) {
            let descriptor = try decoder.decode(AtollLockScreenWidgetDescriptor.self, from: descriptorData)
            try ExtensionDescriptorValidator.validate(descriptor)
            try widgetManager.update(descriptor: descriptor, bundleIdentifier: bundleIdentifier)
        }
    }

    func dismissLockScreenWidget(widgetID: String, bundleIdentifier providedBundleIdentifier: String, reply: @escaping (Bool, Error?) -> Void) {
        guard validate(bundleIdentifier: providedBundleIdentifier, reply: reply) else { return }

        widgetManager.dismiss(widgetID: widgetID, bundleIdentifier: bundleIdentifier)
        reply(true, nil)
    }

    // MARK: Diagnostics

    func getVersion(reply: @escaping (String) -> Void) {
        reply(appVersion)
    }

    // MARK: Helpers

    private func respond(reply: @escaping (Bool, Error?) -> Void, operation: () throws -> Void) {
        do {
            try operation()
            reply(true, nil)
        } catch {
            if Defaults[.extensionDiagnosticsLoggingEnabled] {
                Logger.log("Extension XPC request failed: \(error)", category: .extensions)
            }
            reply(false, error.asNSError)
        }
    }

    private func validate(bundleIdentifier providedBundleIdentifier: String, reply: @escaping (Bool, Error?) -> Void) -> Bool {
        guard providedBundleIdentifier == bundleIdentifier else {
            let error = ExtensionXPCServiceError.bundleMismatch(expected: bundleIdentifier, received: providedBundleIdentifier)
            reply(false, error.asNSError)
            return false
        }
        return true
    }

    private func resolvedApplicationName() -> String {
        guard let processIdentifier = connection?.processIdentifier,
              processIdentifier != 0,
              let app = NSRunningApplication(processIdentifier: pid_t(processIdentifier)),
              let name = app.localizedName else {
            return bundleIdentifier
        }
        return name
    }
}

private enum ExtensionXPCServiceError: LocalizedError {
    case bundleMismatch(expected: String, received: String)

    var errorDescription: String? {
        switch self {
        case let .bundleMismatch(expected, received):
            return "Bundle identifier mismatch. Expected \(expected) but received \(received)."
        }
    }
}

private extension Error {
    var asNSError: NSError { self as NSError }
}
