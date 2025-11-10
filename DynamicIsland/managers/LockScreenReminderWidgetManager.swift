import Foundation
import Combine
import Defaults
import SwiftUI
import AppKit

@MainActor
final class LockScreenReminderWidgetManager: ObservableObject {
    static let shared = LockScreenReminderWidgetManager()

    @Published private(set) var snapshot: LockScreenReminderWidgetSnapshot?

    private let reminderManager = ReminderLiveActivityManager.shared
    private var cancellables = Set<AnyCancellable>()

    private let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    private init() {
        observeReminderUpdates()
        observeDefaults()
    }

    func showReminderWidget() {
        guard Defaults[.enableLockScreenReminderWidget] else {
            LockScreenReminderWidgetPanelManager.shared.hide()
            return
        }

        if let snapshot {
            LockScreenReminderWidgetPanelManager.shared.show(with: snapshot)
        } else {
            recomputeSnapshot(now: reminderManager.currentDate)
            if let snapshot {
                LockScreenReminderWidgetPanelManager.shared.show(with: snapshot)
            } else {
                LockScreenReminderWidgetPanelManager.shared.hide()
            }
        }
    }

    func hideReminderWidget() {
        LockScreenReminderWidgetPanelManager.shared.hide()
    }

    private func observeReminderUpdates() {
        reminderManager.$activeReminder
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.recomputeSnapshot(now: self.reminderManager.currentDate)
            }
            .store(in: &cancellables)

        reminderManager.$currentDate
            .receive(on: RunLoop.main)
            .sink { [weak self] now in
                guard let self else { return }
                self.recomputeSnapshot(now: now)
            }
            .store(in: &cancellables)
    }

    private func observeDefaults() {
        Defaults.publisher(.enableLockScreenReminderWidget, options: [])
            .sink { [weak self] change in
                guard let self else { return }
                if change.newValue {
                    self.recomputeSnapshot(now: self.reminderManager.currentDate)
                    self.showReminderWidgetIfPossible()
                } else {
                    self.snapshot = nil
                    LockScreenReminderWidgetPanelManager.shared.hide()
                }
            }
            .store(in: &cancellables)

        Defaults.publisher(.lockScreenReminderChipStyle, options: [])
            .sink { [weak self] _ in
                guard let self else { return }
                self.recomputeSnapshot(now: self.reminderManager.currentDate)
            }
            .store(in: &cancellables)
    }

    private func showReminderWidgetIfPossible() {
        guard LockScreenManager.shared.currentLockStatus else { return }
        guard Defaults[.enableLockScreenReminderWidget] else { return }
        if let snapshot {
            LockScreenReminderWidgetPanelManager.shared.show(with: snapshot)
        } else {
            LockScreenReminderWidgetPanelManager.shared.hide()
        }
    }

    private func recomputeSnapshot(now: Date) {
        guard Defaults[.enableLockScreenReminderWidget] else {
            snapshot = nil
            LockScreenReminderWidgetPanelManager.shared.hide()
            return
        }

        guard let entry = reminderManager.activeReminder else {
            snapshot = nil
            LockScreenReminderWidgetPanelManager.shared.hide()
            return
        }

        let snapshot = makeSnapshot(from: entry, now: now)
        if self.snapshot != snapshot {
            self.snapshot = snapshot
        }
        deliver(snapshot)
    }

    private func deliver(_ snapshot: LockScreenReminderWidgetSnapshot) {
        guard LockScreenManager.shared.currentLockStatus else { return }
        if LockScreenReminderWidgetPanelManager.shared.isVisible {
            LockScreenReminderWidgetPanelManager.shared.update(with: snapshot)
        } else {
            LockScreenReminderWidgetPanelManager.shared.show(with: snapshot)
        }
    }

    private func makeSnapshot(from entry: ReminderLiveActivityManager.ReminderEntry, now: Date) -> LockScreenReminderWidgetSnapshot {
        let title = entry.event.title.isEmpty ? "Upcoming Reminder" : entry.event.title
        let timeText = timeFormatter.string(from: entry.event.start)
        let isCritical = criticalWindowContains(entry: entry, now: now)
        let relative = relativeDescription(for: entry, now: now)
        let accent = accentColor(for: entry, isCritical: isCritical)
        let iconName = isCritical ? ReminderLiveActivityManager.criticalIconName : ReminderLiveActivityManager.standardIconName

        return LockScreenReminderWidgetSnapshot(
            title: title,
            eventTimeText: timeText,
            relativeDescription: relative,
            accent: accent,
            chipStyle: Defaults[.lockScreenReminderChipStyle],
            isCritical: isCritical,
            iconName: iconName
        )
    }

    private func accentColor(for entry: ReminderLiveActivityManager.ReminderEntry, isCritical: Bool) -> LockScreenReminderWidgetSnapshot.RGBAColor {
        if isCritical {
            return LockScreenReminderWidgetSnapshot.RGBAColor(nsColor: .systemRed)
        }

        let boosted = Color(nsColor: entry.event.calendar.color).ensureMinimumBrightness(factor: 0.7)
        return LockScreenReminderWidgetSnapshot.RGBAColor(nsColor: NSColor(boosted))
    }

    private func relativeDescription(for entry: ReminderLiveActivityManager.ReminderEntry, now: Date) -> String? {
        let remaining = entry.event.start.timeIntervalSince(now)
        if remaining <= 0 {
            return "now"
        }

        let minutes = Int(ceil(remaining / 60))
        if minutes <= 0 {
            return "now"
        }
        if minutes == 1 {
            return "in 1 min"
        }
        return "in \(minutes) min"
    }

    private func criticalWindowContains(entry: ReminderLiveActivityManager.ReminderEntry, now: Date) -> Bool {
        let window = TimeInterval(Defaults[.reminderSneakPeekDuration])
        guard window > 0 else { return false }
        let remaining = entry.event.start.timeIntervalSince(now)
        return remaining > 0 && remaining <= window
    }
}

struct LockScreenReminderWidgetSnapshot: Equatable {
    struct RGBAColor: Equatable {
        let red: Double
        let green: Double
        let blue: Double
        let alpha: Double

        init(nsColor: NSColor) {
            let color = nsColor.usingColorSpace(.sRGB) ?? nsColor
            self.red = Double(color.redComponent)
            self.green = Double(color.greenComponent)
            self.blue = Double(color.blueComponent)
            self.alpha = Double(color.alphaComponent)
        }

        var color: Color {
            Color(red: red, green: green, blue: blue, opacity: alpha)
        }
    }

    let title: String
    let eventTimeText: String
    let relativeDescription: String?
    let accent: RGBAColor
    let chipStyle: LockScreenReminderChipStyle
    let isCritical: Bool
    let iconName: String
}

