import Foundation
import CoreAudio
import CoreGraphics
import IOKit

extension Notification.Name {
    static let systemVolumeDidChange = Notification.Name("DynamicIsland.systemVolumeDidChange")
    static let systemBrightnessDidChange = Notification.Name("DynamicIsland.systemBrightnessDidChange")
    static let systemAudioRouteDidChange = Notification.Name("DynamicIsland.systemAudioRouteDidChange")
}

final class SystemVolumeController {
    static let shared = SystemVolumeController()

    var onVolumeChange: ((Float, Bool) -> Void)?
    var onRouteChange: (() -> Void)?

    private let callbackQueue = DispatchQueue(label: "com.dynamicisland.volume-listener")
    private var currentDeviceID: AudioDeviceID = 0
    private var listenersInstalled = false
    private var volumeElement: AudioObjectPropertyElement?
    private var muteElement: AudioObjectPropertyElement?

    private let candidateElements: [AudioObjectPropertyElement] = [
        kAudioObjectPropertyElementMain,
        AudioObjectPropertyElement(1),
        AudioObjectPropertyElement(2)
    ]

    private init() {
        currentDeviceID = resolveDefaultDevice()
        refreshPropertyElements()
        installDefaultDeviceListener()
        installVolumeListeners(for: currentDeviceID)
        notifyCurrentState()
    }

    func start() {
        // Listeners are installed during init, nothing else required.
    }

    func stop() {
        // We keep listeners alive for the app lifetime; clearing closures prevents UI updates.
        onVolumeChange = nil
        onRouteChange = nil
    }

    func adjust(by delta: Float) {
        var newValue = currentVolume + delta
        newValue = max(0, min(1, newValue))
        setVolume(newValue)
    }

    func toggleMute() {
        setMuted(!isMuted)
    }

    var currentVolume: Float {
        getVolume()
    }

    var isMuted: Bool {
        getMuteState()
    }

    func setVolume(_ value: Float) {
        var volume = max(0, min(1, value))
        let status = setData(selector: kAudioDevicePropertyVolumeScalar, data: &volume)
        if status != noErr {
            NSLog("⚠️ Failed to set volume: \(status)")
        }
    }

    func setMuted(_ muted: Bool) {
        var muteFlag: UInt32 = muted ? 1 : 0
        let status = setData(selector: kAudioDevicePropertyMute, data: &muteFlag)
        if status != noErr {
            NSLog("⚠️ Failed to set mute state: \(status)")
        }
    }

    // MARK: - Private

    private func resolveDefaultDevice() -> AudioDeviceID {
        var deviceID = AudioDeviceID()
        var size = UInt32(MemoryLayout.size(ofValue: deviceID))
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
        if status != noErr {
            NSLog("⚠️ Unable to fetch default audio device: \(status)")
        }
        return deviceID
    }

    private func installDefaultDeviceListener() {
        guard !listenersInstalled else { return }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            callbackQueue
        ) { [weak self] _, _ in
            guard let self else { return }
            self.handleDefaultDeviceChanged()
        }
        if status != noErr {
            NSLog("⚠️ Failed to install default device listener: \(status)")
        }
        listenersInstalled = true
    }

    private func installVolumeListeners(for deviceID: AudioDeviceID) {
        if let element = resolveElement(selector: kAudioDevicePropertyVolumeScalar, deviceID: deviceID) {
            volumeElement = element
            var address = makeAddress(selector: kAudioDevicePropertyVolumeScalar, element: element)
            AudioObjectAddPropertyListenerBlock(deviceID, &address, callbackQueue) { [weak self] _, _ in
                self?.notifyCurrentState()
            }
        }

        if let element = resolveElement(selector: kAudioDevicePropertyMute, deviceID: deviceID) {
            muteElement = element
            var address = makeAddress(selector: kAudioDevicePropertyMute, element: element)
            AudioObjectAddPropertyListenerBlock(deviceID, &address, callbackQueue) { [weak self] _, _ in
                self?.notifyCurrentState()
            }
        }
    }

    private func handleDefaultDeviceChanged() {
        callbackQueue.async { [weak self] in
            guard let self else { return }
            self.currentDeviceID = self.resolveDefaultDevice()
            self.refreshPropertyElements()
            self.installVolumeListeners(for: self.currentDeviceID)
            self.notifyCurrentState()
            DispatchQueue.main.async {
                self.onRouteChange?()
                NotificationCenter.default.post(name: .systemAudioRouteDidChange, object: nil)
            }
        }
    }

    private func notifyCurrentState() {
        let volume = getVolume()
        let muted = getMuteState()
        DispatchQueue.main.async {
            self.onVolumeChange?(volume, muted)
            NotificationCenter.default.post(name: .systemVolumeDidChange, object: nil, userInfo: ["value": volume, "muted": muted])
        }
    }

    private func getVolume() -> Float {
        var volume = Float32(0)
        let status = getData(selector: kAudioDevicePropertyVolumeScalar, data: &volume)
        if status != noErr {
            NSLog("⚠️ Unable to fetch volume: \(status)")
        }
        return volume
    }

    private func getMuteState() -> Bool {
        var mute: UInt32 = 0
        let status = getData(selector: kAudioDevicePropertyMute, data: &mute)
        if status != noErr {
            // Some devices do not support mute; treat as not muted
            return false
        }
        return mute != 0
    }

    private func refreshPropertyElements() {
        volumeElement = resolveElement(selector: kAudioDevicePropertyVolumeScalar, deviceID: currentDeviceID)
        muteElement = resolveElement(selector: kAudioDevicePropertyMute, deviceID: currentDeviceID)
    }

    private func resolveElement(selector: AudioObjectPropertySelector, deviceID: AudioDeviceID) -> AudioObjectPropertyElement? {
        for element in candidateElements {
            var address = makeAddress(selector: selector, element: element)
            if propertyExists(deviceID: deviceID, address: &address) {
                return element
            }
        }
        return nil
    }

    private func preferredElements(for selector: AudioObjectPropertySelector) -> [AudioObjectPropertyElement] {
        if let cached = cachedElement(for: selector) {
            return [cached] + candidateElements.filter { $0 != cached }
        }
        return candidateElements
    }

    private func cachedElement(for selector: AudioObjectPropertySelector) -> AudioObjectPropertyElement? {
        switch selector {
        case kAudioDevicePropertyVolumeScalar:
            return volumeElement
        case kAudioDevicePropertyMute:
            return muteElement
        default:
            return nil
        }
    }

    private func cache(element: AudioObjectPropertyElement, for selector: AudioObjectPropertySelector) {
        switch selector {
        case kAudioDevicePropertyVolumeScalar:
            volumeElement = element
        case kAudioDevicePropertyMute:
            muteElement = element
        default:
            break
        }
    }

    private func makeAddress(selector: AudioObjectPropertySelector, element: AudioObjectPropertyElement) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: element
        )
    }

    private func propertyExists(deviceID: AudioDeviceID, address: inout AudioObjectPropertyAddress) -> Bool {
        withUnsafePointer(to: &address) { pointer in
            AudioObjectHasProperty(deviceID, pointer)
        }
    }

    private func getData<T>(selector: AudioObjectPropertySelector, data: inout T) -> OSStatus {
        var lastStatus: OSStatus = kAudioHardwareUnspecifiedError
        for element in preferredElements(for: selector) {
            var address = makeAddress(selector: selector, element: element)
            guard propertyExists(deviceID: currentDeviceID, address: &address) else { continue }
            var size = UInt32(MemoryLayout<T>.size)
            lastStatus = AudioObjectGetPropertyData(currentDeviceID, &address, 0, nil, &size, &data)
            if lastStatus == noErr {
                cache(element: element, for: selector)
                return lastStatus
            }
        }
        return lastStatus
    }

    private func setData<T>(selector: AudioObjectPropertySelector, data: inout T) -> OSStatus {
        var lastStatus: OSStatus = kAudioHardwareUnspecifiedError
        for element in preferredElements(for: selector) {
            var address = makeAddress(selector: selector, element: element)
            guard propertyExists(deviceID: currentDeviceID, address: &address) else { continue }
            let size = UInt32(MemoryLayout<T>.size)
            lastStatus = AudioObjectSetPropertyData(currentDeviceID, &address, 0, nil, size, &data)
            if lastStatus == noErr {
                cache(element: element, for: selector)
                return lastStatus
            }
        }
        return lastStatus
    }
}

final class SystemBrightnessController {
    static let shared = SystemBrightnessController()

    var onBrightnessChange: ((Float) -> Void)?

    private let notificationCenter = NotificationCenter.default
    private var observers: [NSObjectProtocol] = []
    private var notificationsInstalled = false
    private var displayID: CGDirectDisplayID = CGMainDisplayID()

    private init() {
        registerExternalNotifications()
    }

    func start() {
        notifyCurrentBrightness()
    }

    func stop() {
        onBrightnessChange = nil
    }

    func adjust(by delta: Float) {
        setBrightness(currentBrightness + delta)
    }

    func setBrightness(_ value: Float) {
        let clamped = max(0, min(1, value))
        if setBrightnessViaDisplayServices(clamped) {
            notifyCurrentBrightness()
            return
        }
        guard let service = displayService() else { return }
        let status = IODisplaySetFloatParameter(service, 0, kIODisplayBrightnessKey as CFString, clamped)
        IOObjectRelease(service)
        if status == kIOReturnSuccess {
            notifyCurrentBrightness()
        } else {
            NSLog("⚠️ Failed to set brightness via IODisplay: \(status)")
        }
    }

    var currentBrightness: Float {
        if let level = getBrightnessViaDisplayServices() {
            return level
        }
        guard let service = displayService() else { return 0.5 }
        var brightness: Float = 0
        let result = IODisplayGetFloatParameter(service, 0, kIODisplayBrightnessKey as CFString, &brightness)
        IOObjectRelease(service)
        if result != kIOReturnSuccess {
            return 0.5
        }
        return brightness
    }

    private func notifyCurrentBrightness() {
        let brightness = currentBrightness
        DispatchQueue.main.async {
            self.onBrightnessChange?(brightness)
            self.notificationCenter.post(name: .systemBrightnessDidChange, object: nil, userInfo: ["value": brightness])
        }
    }

    private func displayService() -> io_service_t? {
        var iterator = io_iterator_t()
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IODisplayConnect"), &iterator) == KERN_SUCCESS else {
            return nil
        }
        let service = IOIteratorNext(iterator)
        IOObjectRelease(iterator)
        return service
    }

    private func setBrightnessViaDisplayServices(_ value: Float) -> Bool {
        let status = DisplayServicesSetBrightness(displayID, value)
        if status == kIOReturnSuccess {
            return true
        }
        // Attempt to refresh display ID in case the main display changed
        displayID = CGMainDisplayID()
        let retry = DisplayServicesSetBrightness(displayID, value)
        if retry != kIOReturnSuccess {
            NSLog("⚠️ DisplayServicesSetBrightness failed: \(retry)")
            return false
        }
        return true
    }

    private func getBrightnessViaDisplayServices() -> Float? {
        var brightness: Float = 0
        let status = DisplayServicesGetBrightness(displayID, &brightness)
        if status == kIOReturnSuccess {
            return brightness
        }
        displayID = CGMainDisplayID()
        let retry = DisplayServicesGetBrightness(displayID, &brightness)
        if retry == kIOReturnSuccess {
            return brightness
        }
        NSLog("⚠️ DisplayServicesGetBrightness failed: \(retry)")
        return nil
    }

    private func registerExternalNotifications() {
        guard !notificationsInstalled else { return }
        let names = [
            Notification.Name("com.apple.BezelEngine.BrightnessChanged"),
            Notification.Name("com.apple.BezelServices.BrightnessChanged"),
            Notification.Name("com.apple.controlcenter.display.brightness")
        ]
        observers = names.map { name in
            DistributedNotificationCenter.default().addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.notifyCurrentBrightness()
            }
        }
        notificationsInstalled = true
    }

    deinit {
        observers.forEach { DistributedNotificationCenter.default().removeObserver($0) }
    }
}

@_silgen_name("DisplayServicesGetBrightness")
private func DisplayServicesGetBrightness(_ display: UInt32, _ brightness: UnsafeMutablePointer<Float>) -> Int32

@_silgen_name("DisplayServicesSetBrightness")
private func DisplayServicesSetBrightness(_ display: UInt32, _ brightness: Float) -> Int32
