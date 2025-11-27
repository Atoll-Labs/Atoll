import SwiftUI
import Defaults

struct LockScreenTimerWidget: View {
    static let preferredSize = CGSize(width: 420, height: 104)
    static let cornerRadius: CGFloat = 26

    @ObservedObject private var animator: LockScreenTimerWidgetAnimator
    @ObservedObject private var timerManager = TimerManager.shared
    @Default(.lockScreenGlassStyle) private var glassStyle
    @Default(.lockScreenPanelUsesBlur) private var enableBlur
    @Default(.timerPresets) private var timerPresets

    @MainActor
    init(animator: LockScreenTimerWidgetAnimator? = nil) {
        if let animator {
            _animator = ObservedObject(wrappedValue: animator)
        } else {
            _animator = ObservedObject(wrappedValue: LockScreenTimerWidgetAnimator(isPresented: true))
        }
    }

    private var clampedProgress: Double {
        min(max(timerManager.progress, 0), 1)
    }

    private var titleFont: Font { .system(size: 18, weight: .semibold, design: .rounded) }
    private var statusFont: Font { .system(size: 12, weight: .medium, design: .rounded) }
    private var countdownFont: Font { .system(size: 42, weight: .semibold, design: .default) }

    private var timerLabel: String {
        timerManager.timerName.isEmpty ? "Timer" : timerManager.timerName
    }

    private var countdownText: String {
        timerManager.formattedRemainingTime()
    }

    private var activePresetColor: Color? {
        guard let presetId = timerManager.activePresetId else { return nil }
        return timerPresets.first { $0.id == presetId }?.color
    }

    private var accentColor: Color {
        (activePresetColor ?? timerManager.timerColor)
            .ensureMinimumBrightness(factor: 0.75)
    }

    private var secondaryAccentColor: Color {
        accentColor.ensureMinimumBrightness(factor: 0.55).opacity(0.45)
    }

    private var accentGradient: LinearGradient {
        LinearGradient(
            colors: [
                accentColor.opacity(0.35),
                accentColor.ensureMinimumBrightness(factor: 0.5)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var usesLiquidGlass: Bool {
        if #available(macOS 26.0, *) {
            return glassStyle == .liquid
        }
        return false
    }

    @ViewBuilder
    private var widgetBackground: some View {
        if enableBlur {
            if usesLiquidGlass {
                liquidBackground
            } else {
                frostedBackground
            }
        } else {
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .fill(Color.black.opacity(0.65))
        }
    }

    @ViewBuilder
    private var liquidBackground: some View {
        if #available(macOS 26.0, *) {
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .glassEffect(
                    .clear.tint(accentColor.opacity(0.18)).interactive(),
                    in: .rect(cornerRadius: Self.cornerRadius)
                )
        } else {
            frostedBackground
        }
    }

    private var frostedBackground: some View {
        RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
            .fill(.ultraThinMaterial)
    }

    private var pauseIcon: String {
        timerManager.isPaused ? "play.fill" : "pause.fill"
    }

    private var pauseLabel: String {
        timerManager.isPaused ? "Resume" : "Pause"
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack(alignment: .center, spacing: 20) {
                controlButtons

                titleSection
                    .frame(maxWidth: .infinity)

                countdownSection
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .frame(width: Self.preferredSize.width, height: Self.preferredSize.height)
        .background(widgetBackground)
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.25), radius: 18, x: 0, y: 16)
        .overlay(alignment: .topLeading) {
            accentRibbon
        }
        .animation(.smooth(duration: 0.22), value: timerManager.isPaused)
        .animation(.smooth(duration: 0.22), value: timerManager.remainingTime)
        .scaleEffect(animator.isPresented ? 1 : 0.9)
        .opacity(animator.isPresented ? 1 : 0)
        .animation(.spring(response: 0.45, dampingFraction: 0.85, blendDuration: 0.22), value: animator.isPresented)
    }

    private var controlButtons: some View {
        HStack(spacing: 10) {
            CircleButton(
                icon: pauseIcon,
                foreground: accentColor,
                background: Color.white.opacity(0.15),
                borderColor: accentColor.opacity(0.8),
                action: togglePause,
                isEnabled: timerManager.allowsManualInteraction,
                helpText: pauseLabel
            )

            CircleButton(
                icon: "xmark",
                foreground: Color.white.opacity(0.92),
                background: Color.white.opacity(0.18),
                borderColor: Color.white.opacity(0.35),
                action: stopTimer,
                isEnabled: timerManager.allowsManualInteraction,
                helpText: "Stop"
            )
        }
    }

    private var titleSection: some View {
        Group {
            if timerManager.timerName.count > 18 {
                MarqueeText(
                    .constant(timerLabel),
                    font: .system(size: 18, weight: .semibold, design: .rounded),
                    nsFont: .title3,
                    textColor: accentColor,
                    minDuration: 0.18,
                    frameWidth: Self.preferredSize.width * 0.4
                )
            } else {
                Text(timerLabel)
                    .font(titleFont)
                    .foregroundStyle(accentColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var countdownSection: some View {
        VStack(alignment: .trailing, spacing: 6) {
            Text(countdownText)
                .font(countdownFont)
                .foregroundStyle(timerManager.isOvertime ? Color.red : accentColor)
                .contentTransition(.numericText())
                .animation(.smooth(duration: 0.25), value: timerManager.remainingTime)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(minWidth: 140, maxWidth: 180, alignment: .trailing)
        .padding(.trailing, 2)
    }

    private var accentRibbon: some View {
        Capsule()
            .fill(accentGradient)
            .frame(width: 110, height: 26)
            .blur(radius: 12)
            .offset(x: 18, y: -6)
            .opacity(0.45)
    }

    private func togglePause() {
        guard timerManager.allowsManualInteraction else { return }
        if timerManager.isPaused {
            timerManager.resumeTimer()
        } else {
            timerManager.pauseTimer()
        }
    }

    private func stopTimer() {
        guard timerManager.allowsManualInteraction else {
            timerManager.endExternalTimer(triggerSmoothClose: false)
            return
        }
        timerManager.stopTimer()
    }

    private struct CircleButton: View {
        let icon: String
        let foreground: Color
        let background: Color
        let borderColor: Color?
        let action: () -> Void
        let isEnabled: Bool
        let helpText: String

        var body: some View {
            Button(action: action) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(foreground)
                    .frame(width: 48, height: 48)
                    .background(background.opacity(isEnabled ? 1 : 0.25))
                    .clipShape(Circle())
                    .overlay {
                        if let borderColor {
                            Circle()
                                .stroke(borderColor.opacity(isEnabled ? 1 : 0.35), lineWidth: 1)
                        }
                    }
                    .shadow(color: Color.black.opacity(0.35), radius: 6, x: 0, y: 4)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .help(helpText)
            .disabled(!isEnabled)
            .opacity(isEnabled ? 1 : 0.4)
        }
    }
}

#Preview {
    LockScreenTimerWidget()
        .frame(width: LockScreenTimerWidget.preferredSize.width, height: LockScreenTimerWidget.preferredSize.height)
        .padding()
        .background(Color.black)
        .onAppear {
            TimerManager.shared.startDemoTimer(duration: 1783)
        }
}
