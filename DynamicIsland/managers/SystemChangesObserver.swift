import Foundation
import CoreGraphics
import Defaults

final class SystemChangesObserver: MediaKeyInterceptorDelegate {
    private weak var coordinator: DynamicIslandViewCoordinator?
    private let volumeController = SystemVolumeController.shared
    private let brightnessController = SystemBrightnessController.shared
    private let mediaKeyInterceptor = MediaKeyInterceptor.shared

    private let standardVolumeStep: Float = 1.0 / 16.0
    private let standardBrightnessStep: Float = 1.0 / 16.0
    private let fineStepDivisor: Float = 4.0

    private var volumeEnabled = false
    private var brightnessEnabled = false

    init(coordinator: DynamicIslandViewCoordinator) {
        self.coordinator = coordinator
    }

    func startObserving(volumeEnabled: Bool, brightnessEnabled: Bool) {
        self.volumeEnabled = volumeEnabled
        self.brightnessEnabled = brightnessEnabled

        volumeController.onVolumeChange = { [weak self] volume, muted in
            guard let self, self.volumeEnabled else { return }
            let value = muted ? 0 : volume
            self.sendVolumeNotification(value: value)
        }
        volumeController.onRouteChange = { [weak self] in
            guard let self, self.volumeEnabled else { return }
            self.sendVolumeNotification(value: self.volumeController.isMuted ? 0 : self.volumeController.currentVolume)
        }
        volumeController.start()

        brightnessController.onBrightnessChange = { [weak self] brightness in
            guard let self, self.brightnessEnabled else { return }
            self.sendBrightnessNotification(value: brightness)
        }
        brightnessController.start()

        mediaKeyInterceptor.delegate = self
        let tapStarted = mediaKeyInterceptor.start()
        if !tapStarted {
            NSLog("⚠️ Media key interception unavailable; system HUD will remain visible")
        }
        mediaKeyInterceptor.configuration = MediaKeyConfiguration(
            interceptVolume: volumeEnabled,
            interceptBrightness: brightnessEnabled
        )
    }

    func update(volumeEnabled: Bool, brightnessEnabled: Bool) {
        self.volumeEnabled = volumeEnabled
        self.brightnessEnabled = brightnessEnabled
        mediaKeyInterceptor.configuration = MediaKeyConfiguration(
            interceptVolume: volumeEnabled,
            interceptBrightness: brightnessEnabled
        )
    }

    func stopObserving() {
        mediaKeyInterceptor.stop()
        mediaKeyInterceptor.delegate = nil

        volumeController.stop()
        volumeController.onVolumeChange = nil
        volumeController.onRouteChange = nil

        brightnessController.stop()
        brightnessController.onBrightnessChange = nil
    }

    // MARK: - MediaKeyInterceptorDelegate

    func mediaKeyInterceptor(
        _ interceptor: MediaKeyInterceptor,
        didReceiveVolumeCommand direction: MediaKeyDirection,
        step: MediaKeyStep,
        isRepeat: Bool
    ) {
        guard volumeEnabled else { return }
        let baseStep = stepSize(for: step, base: standardVolumeStep)
        let delta = direction == .up ? baseStep : -baseStep
        volumeController.adjust(by: delta)
    }

    func mediaKeyInterceptorDidToggleMute(_ interceptor: MediaKeyInterceptor) {
        guard volumeEnabled else { return }
        volumeController.toggleMute()
    }

    func mediaKeyInterceptor(
        _ interceptor: MediaKeyInterceptor,
        didReceiveBrightnessCommand direction: MediaKeyDirection,
        step: MediaKeyStep,
        isRepeat: Bool
    ) {
        guard brightnessEnabled else { return }
        let baseStep = stepSize(for: step, base: standardBrightnessStep)
        let delta = direction == .up ? baseStep : -baseStep
        brightnessController.adjust(by: delta)
    }

    // MARK: - HUD Dispatch

    private func sendVolumeNotification(value: Float) {
        if HUDSuppressionCoordinator.shared.shouldSuppressVolumeHUD {
            return
        }
        coordinator?.toggleSneakPeek(
            status: true,
            type: .volume,
            value: CGFloat(value),
            icon: ""
        )
    }

    private func sendBrightnessNotification(value: Float) {
        coordinator?.toggleSneakPeek(
            status: true,
            type: .brightness,
            value: CGFloat(value),
            icon: ""
        )
    }
}

private extension SystemChangesObserver {
    func stepSize(for step: MediaKeyStep, base: Float) -> Float {
        switch step {
        case .standard:
            return base
        case .fine:
            return base / fineStepDivisor
        }
    }
}


