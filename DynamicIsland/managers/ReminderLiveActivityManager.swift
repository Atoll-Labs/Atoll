//
//  ReminderLiveActivityManager.swift
//  DynamicIsland
//
//  Created by GitHub Copilot on 2025-11-12.
//

import Combine
import Defaults
import Foundation
import CoreGraphics
import os

@MainActor
final class ReminderLiveActivityManager: ObservableObject {
    struct ReminderEntry: Equatable {
        let event: EventModel
        let triggerDate: Date
        let leadTime: TimeInterval
    }

    static let shared = ReminderLiveActivityManager()
    static let standardIconName = "calendar.badge.clock"
    static let criticalIconName = "calendar.badge.exclamationmark"
    static let listRowHeight: CGFloat = 30
    static let listRowSpacing: CGFloat = 8
    static let listTopPadding: CGFloat = 14
    static let listBottomPadding: CGFloat = 10
    static let baselineMinimalisticBottomPadding: CGFloat = 3

    @Published private(set) var activeReminder: ReminderEntry?
    @Published private(set) var currentDate: Date = Date()
    @Published private(set) var upcomingEntries: [ReminderEntry] = []
    @Published private(set) var activeWindowReminders: [ReminderEntry] = []

    private let logger: os.Logger = os.Logger(subsystem: "com.ebullioscopic.Atoll", category: "ReminderLiveActivity")

    private var nextReminder: ReminderEntry?
    private var cancellables = Set<AnyCancellable>()
    private var tickerTask: Task<Void, Never>? { didSet { oldValue?.cancel() } }
    private var evaluationTask: Task<Void, Never>?
    private var hasShownCriticalSneakPeek = false
    private var latestEvents: [EventModel] = []

    private let calendarManager = CalendarManager.shared

    var isActive: Bool { activeReminder != nil }

    private init() {
        latestEvents = calendarManager.events
        setupObservers()
        if !latestEvents.isEmpty {
            recalculateUpcomingEntries(reason: "initialization")
        }
    }

    private func setupObservers() {
        Defaults.publisher(.enableReminderLiveActivity, options: [])
            .sink { [weak self] change in
                guard let self else { return }
                if change.newValue {
                    self.recalculateUpcomingEntries(reason: "defaults-toggle")
                } else {
                    self.deactivateReminder()
                }
            }
            .store(in: &cancellables)

        Defaults.publisher(.reminderLeadTime, options: [])
            .sink { [weak self] _ in
                guard let self else { return }
                self.recalculateUpcomingEntries(reason: "lead-time")
            }
            .store(in: &cancellables)

        Defaults.publisher(.hideAllDayEvents, options: [])
            .sink { [weak self] _ in
                self?.recalculateUpcomingEntries(reason: "hide-all-day")
            }
            .store(in: &cancellables)

        Defaults.publisher(.hideCompletedReminders, options: [])
            .sink { [weak self] _ in
                self?.recalculateUpcomingEntries(reason: "hide-completed")
            }
            .store(in: &cancellables)

        Defaults.publisher(.reminderPresentationStyle, options: [])
            .sink { [weak self] _ in
                guard let self else { return }
                // Presentation change does not alter scheduling, but ensure state publishes for UI updates.
                if let reminder = self.activeReminder {
                    self.activeReminder = reminder
                }
            }
            .store(in: &cancellables)

        calendarManager.$events
            .receive(on: RunLoop.main)
            .sink { [weak self] events in
                guard let self else { return }
                self.handleCalendarEventsUpdate(events)
            }
            .store(in: &cancellables)
    }

    private func cancelAllTimers() {
        tickerTask = nil
        evaluationTask?.cancel()
        evaluationTask = nil
        hasShownCriticalSneakPeek = false
    }

    private func deactivateReminder() {
        nextReminder = nil
        activeReminder = nil
        upcomingEntries = []
        activeWindowReminders = []
        cancelAllTimers()
    }

    private func handleCalendarEventsUpdate(_ events: [EventModel]) {
        latestEvents = events
        guard Defaults[.enableReminderLiveActivity] else { return }
        logger.debug("[Reminder] Applying calendar snapshot update (events=\(events.count, privacy: .public))")
        recalculateUpcomingEntries(reason: "calendar-events")
    }

    private func shouldHide(_ event: EventModel) -> Bool {
        if event.isAllDay && Defaults[.hideAllDayEvents] {
            return true
        }
        if case let .reminder(completed) = event.type,
           completed && Defaults[.hideCompletedReminders] {
            return true
        }
        return false
    }

    private func makeEntry(from event: EventModel, leadMinutes: Int, referenceDate: Date) -> ReminderEntry? {
        guard event.start > referenceDate else { return nil }
        let leadSeconds = max(1, leadMinutes) * 60
        let trigger = event.start.addingTimeInterval(TimeInterval(-leadSeconds))
        return ReminderEntry(event: event, triggerDate: trigger, leadTime: TimeInterval(leadSeconds))
    }

    private func recalculateUpcomingEntries(referenceDate: Date = Date(), reason: String) {
        guard Defaults[.enableReminderLiveActivity] else {
            deactivateReminder()
            return
        }

        guard calendarManager.hasReminderAccess else {
            deactivateReminder()
            return
        }

        let leadMinutes = Defaults[.reminderLeadTime]
        let upcoming = latestEvents
            .filter { !shouldHide($0) }
            .compactMap { makeEntry(from: $0, leadMinutes: leadMinutes, referenceDate: referenceDate) }
            .sorted { $0.triggerDate < $1.triggerDate }

        upcomingEntries = upcoming
        updateActiveWindowReminders(for: referenceDate)

        guard let first = upcoming.first else {
            clearActiveReminderState()
            logger.debug("[Reminder] No upcoming reminders found (reason=\(reason, privacy: .public))")
            return
        }

        logger.debug("[Reminder] Next reminder ‘\(first.event.title, privacy: .public)’ (reason=\(reason, privacy: .public))")
        handleEntrySelection(first, referenceDate: referenceDate)
    }

    private func clearActiveReminderState() {
        nextReminder = nil
        if activeReminder != nil {
            activeReminder = nil
        }
        activeWindowReminders = []
        cancelAllTimers()
    }

    private func scheduleEvaluation(at date: Date) {
        evaluationTask?.cancel()
        let delay = date.timeIntervalSinceNow
        guard delay > 0 else {
            Task { await self.evaluateCurrentState(at: Date()) }
            return
        }

        evaluationTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            await self.evaluateCurrentState(at: Date())
        }
    }

    private func startTickerIfNeeded() {
        guard tickerTask == nil else { return }
        tickerTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                await self.handleTick()
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    break
                }
            }
        }
    }

    private func stopTicker() {
        tickerTask?.cancel()
        tickerTask = nil
    }

    private func handleEntrySelection(_ entry: ReminderEntry?, referenceDate: Date) {
        guard nextReminder != entry else {
            Task { await self.evaluateCurrentState(at: referenceDate) }
            return
        }

        nextReminder = entry
        hasShownCriticalSneakPeek = false
        Task { await self.evaluateCurrentState(at: referenceDate) }
    }

    func evaluateCurrentState(at date: Date) async {
        guard Defaults[.enableReminderLiveActivity] else {
            deactivateReminder()
            return
        }

        currentDate = date
        updateActiveWindowReminders(for: date)

        guard var entry = nextReminder else {
            if activeReminder != nil {
                activeReminder = nil
            }
            stopTicker()
            hasShownCriticalSneakPeek = false
            return
        }

        if entry.event.start <= date {
            clearActiveReminderState()
            logger.debug("[Reminder] Reminder reached start time; reevaluating reminders from cache")
            recalculateUpcomingEntries(referenceDate: date, reason: "evaluation-complete")
            return
        }

        if entry.triggerDate <= date {
            if entry.triggerDate > entry.event.start {
                entry = ReminderEntry(event: entry.event, triggerDate: entry.event.start, leadTime: entry.leadTime)
                nextReminder = entry
            }
            if activeReminder != entry {
                activeReminder = entry
                DynamicIslandViewCoordinator.shared.toggleSneakPeek(
                    status: true,
                    type: .reminder,
                    duration: Defaults[.reminderSneakPeekDuration],
                    value: 0,
                    icon: ReminderLiveActivityManager.standardIconName
                )
                hasShownCriticalSneakPeek = false
            }

            let criticalWindow = TimeInterval(Defaults[.reminderSneakPeekDuration])
            let timeRemaining = entry.event.start.timeIntervalSince(date)
            if criticalWindow > 0 && timeRemaining > 0 {
                if timeRemaining <= criticalWindow {
                    if !hasShownCriticalSneakPeek {
                        let displayDuration = min(criticalWindow, max(timeRemaining - 2, 0))
                        if displayDuration > 0 {
                            DynamicIslandViewCoordinator.shared.toggleSneakPeek(
                                status: true,
                                type: .reminder,
                                duration: displayDuration,
                                value: 0,
                                icon: ReminderLiveActivityManager.criticalIconName
                            )
                            hasShownCriticalSneakPeek = true
                        }
                    }
                } else {
                    hasShownCriticalSneakPeek = false
                }
            }
            startTickerIfNeeded()
        } else {
            if activeReminder != nil {
                activeReminder = nil
            }
            stopTicker()
            hasShownCriticalSneakPeek = false
            scheduleEvaluation(at: entry.triggerDate)
        }
    }

    @MainActor
    private func handleTick() async {
        let now = Date()
        if abs(currentDate.timeIntervalSince(now)) >= 0.5 {
            currentDate = now
        }
        await evaluateCurrentState(at: now)
    }

    private func updateActiveWindowReminders(for date: Date) {
        let filtered = upcomingEntries.filter { entry in
            entry.triggerDate <= date && entry.event.start >= date
        }
        if filtered != activeWindowReminders {
            logger.debug("[Reminder] Active window reminder count -> \(filtered.count, privacy: .public)")
            activeWindowReminders = filtered
        }
    }

    static func additionalHeight(forRowCount rowCount: Int) -> CGFloat {
        guard rowCount > 0 else { return 0 }
        let rows = CGFloat(rowCount)
        let spacing = CGFloat(max(rowCount - 1, 0)) * listRowSpacing
        let bottomDelta = max(listBottomPadding - baselineMinimalisticBottomPadding, 0)
        return listTopPadding + rows * listRowHeight + spacing + bottomDelta
    }

}

extension ReminderLiveActivityManager.ReminderEntry: Identifiable {
    var id: String { event.id }
}
