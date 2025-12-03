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
    private var pendingEventsSnapshot: [EventModel]? = nil
    private var eventsUpdateDebounceTask: Task<Void, Never>? { didSet { oldValue?.cancel() } }
    private var upcomingComputationTask: Task<Void, Never>? { didSet { oldValue?.cancel() } }
    private let eventsDebounceInterval: TimeInterval = 0.35
    private var settingsUpdateTask: Task<Void, Never>? { didSet { oldValue?.cancel() } }
    private var pendingSettingsAction: (() -> Void)?
    private var pendingSettingsReason: String?
    private let settingsUpdateDebounceInterval: TimeInterval = 0.2
    private var suppressUpdatesForLock = false

    private var lastAppliedLeadTime = Defaults[.reminderLeadTime]
    private var lastAppliedHideAllDay = Defaults[.hideAllDayEvents]
    private var lastAppliedHideCompleted = Defaults[.hideCompletedReminders]

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
            .map(\.newValue)
            .sink { [weak self] newValue in
                guard let self else { return }
                guard newValue != self.lastAppliedLeadTime else { return }
                self.scheduleSettingsRecalculation(reason: "lead-time") {
                    self.lastAppliedLeadTime = newValue
                }
            }
            .store(in: &cancellables)

        Defaults.publisher(.hideAllDayEvents, options: [])
            .map(\.newValue)
            .sink { [weak self] newValue in
                guard let self else { return }
                guard newValue != self.lastAppliedHideAllDay else { return }
                self.scheduleSettingsRecalculation(reason: "hide-all-day") {
                    self.lastAppliedHideAllDay = newValue
                }
            }
            .store(in: &cancellables)

        Defaults.publisher(.hideCompletedReminders, options: [])
            .map(\.newValue)
            .sink { [weak self] newValue in
                guard let self else { return }
                guard newValue != self.lastAppliedHideCompleted else { return }
                self.scheduleSettingsRecalculation(reason: "hide-completed") {
                    self.lastAppliedHideCompleted = newValue
                }
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
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] events in
                self?.handleCalendarEventsUpdate(events)
            }
            .store(in: &cancellables)

        LockScreenManager.shared.$isLocked
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] locked in
                self?.handleLockStateChange(isLocked: locked)
            }
            .store(in: &cancellables)
    }

    private func scheduleSettingsRecalculation(reason: String, action: @escaping () -> Void) {
        pendingSettingsAction = action
        pendingSettingsReason = reason
        settingsUpdateTask = Task { [weak self] in
            guard let self else { return }
            let delay = UInt64(settingsUpdateDebounceInterval * 1_000_000_000)
            try? await Task.sleep(nanoseconds: delay)
            await self.applyPendingSettingsRecalculation()
        }
    }

    @MainActor
    private func applyPendingSettingsRecalculation() {
        guard let action = pendingSettingsAction, let reason = pendingSettingsReason else { return }
        pendingSettingsAction = nil
        pendingSettingsReason = nil
        action()
        recalculateUpcomingEntries(reason: reason)
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
        pendingEventsSnapshot = events
        guard !suppressUpdatesForLock else { return }
        schedulePendingEventsSnapshotApplication()
    }

    private func schedulePendingEventsSnapshotApplication() {
        eventsUpdateDebounceTask = Task { [weak self] in
            guard let self else { return }
            let delay = UInt64(eventsDebounceInterval * 1_000_000_000)
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            await self.applyPendingEventsSnapshot()
        }
    }

    @MainActor
    private func applyPendingEventsSnapshot() {
        guard !suppressUpdatesForLock else { return }
        guard let snapshot = pendingEventsSnapshot else { return }
        pendingEventsSnapshot = nil
        guard snapshot != latestEvents else { return }

        latestEvents = snapshot
        guard Defaults[.enableReminderLiveActivity] else { return }
        logger.debug("[Reminder] Applying calendar snapshot update (events=\(snapshot.count, privacy: .public))")
        recalculateUpcomingEntries(reason: "calendar-events")
    }

    private func handleLockStateChange(isLocked: Bool) {
        suppressUpdatesForLock = isLocked
        if isLocked {
            eventsUpdateDebounceTask = nil
            upcomingComputationTask = nil
            settingsUpdateTask = nil
            pendingSettingsAction = nil
            pendingSettingsReason = nil
            pauseReminderActivityForLock()
        } else {
            if pendingEventsSnapshot != nil {
                schedulePendingEventsSnapshotApplication()
            } else {
                recalculateUpcomingEntries(reason: "lock-resume")
            }
        }
    }

    private func pauseReminderActivityForLock() {
        tickerTask = nil
        evaluationTask?.cancel()
        evaluationTask = nil
    }

    private func recalculateUpcomingEntries(referenceDate: Date = Date(), reason: String) {
        guard Defaults[.enableReminderLiveActivity] else {
            deactivateReminder()
            return
        }
        let snapshot = latestEvents
        let leadMinutes = Defaults[.reminderLeadTime]
        let hideAllDay = Defaults[.hideAllDayEvents]
        let hideCompleted = Defaults[.hideCompletedReminders]

        upcomingComputationTask = Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            guard !Task.isCancelled else { return }
            let upcoming = Self.buildUpcomingEntries(
                events: snapshot,
                leadMinutes: leadMinutes,
                referenceDate: referenceDate,
                hideAllDayEvents: hideAllDay,
                hideCompletedReminders: hideCompleted
            )
            guard !Task.isCancelled else { return }
            await self.publishUpcomingEntries(upcoming, referenceDate: referenceDate, reason: reason)
        }
    }

    @MainActor
    private func publishUpcomingEntries(_ upcoming: [ReminderEntry], referenceDate: Date, reason: String) {
        guard Defaults[.enableReminderLiveActivity] else {
            deactivateReminder()
            return
        }

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

    nonisolated private static func buildUpcomingEntries(
        events: [EventModel],
        leadMinutes: Int,
        referenceDate: Date,
        hideAllDayEvents: Bool,
        hideCompletedReminders: Bool
    ) -> [ReminderEntry] {
        guard !Task.isCancelled else { return [] }
        let leadSeconds = max(1, leadMinutes) * 60
        var entries: [ReminderEntry] = []
        entries.reserveCapacity(events.count)
        for event in events {
            if Task.isCancelled { return [] }
            if hideAllDayEvents && event.isAllDay {
                continue
            }
            if hideCompletedReminders,
               case let .reminder(completed) = event.type,
               completed {
                continue
            }
            guard event.start > referenceDate else { continue }
            let trigger = event.start.addingTimeInterval(TimeInterval(-leadSeconds))
            entries.append(.init(event: event, triggerDate: trigger, leadTime: TimeInterval(leadSeconds)))
        }
        return entries.sorted { $0.triggerDate < $1.triggerDate }
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
