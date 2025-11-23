//
//  ReminderLiveActivityManager.swift
//  DynamicIsland
//
//  Created by GitHub Copilot on 2025-11-12.
//

import Combine
import Defaults
import EventKit
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

    private enum RefreshReason: String {
        case initialization
        case defaults
        case manual
        case eventStoreChange
        case calendarListChange
        case calendarEventsUpdate
        case fallback
        case evaluation
        case hover
        case ticker
        case other
    }

    private var nextReminder: ReminderEntry?
    private var cancellables = Set<AnyCancellable>()
    private var tickerTask: Task<Void, Never>? { didSet { oldValue?.cancel() } }
    private var evaluationTask: Task<Void, Never>?
    private var fallbackRefreshTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var pendingRefreshTask: Task<Void, Never>?
    private var pendingRefreshForce = false
    private var pendingRefreshToken = UUID()
    private var pendingRefreshReason: RefreshReason = .other
    private var lastKnownCalendarIDs = Set<String>()
    private var lastRefreshDate: Date?
    private var lastRefreshCompletionDate: Date?
    private let minimumRefreshInterval: TimeInterval = 60
    private let refreshDebounceInterval: TimeInterval = 0.3
    private var refreshTaskToken = UUID()
    private var hasShownCriticalSneakPeek = false
    private let eventStoreChangeNoiseInterval: TimeInterval = 4
    private let eventStoreForceThrottleInterval: TimeInterval = 20
    private let manualRefreshSuppressionInterval: TimeInterval = 20
    private var lastEventStoreForceRefreshDate: Date?
    private var lastManualRefreshDate: Date?
    private var pendingEventStoreChange: (date: Date, reason: RefreshReason)?
    private var reminderCompletionSuppressionDeadline: Date?
    private let reminderCompletionSuppressionInterval: TimeInterval = 15
    private var lastUpcomingSignature: [String] = []
    private var lastNoopEventStoreRefreshDate: Date?
    private let noopEventStoreSuppressionInterval: TimeInterval = 30
    private var lastCalendarEventSnapshot: [EventModel] = []
    private var lastCalendarSnapshotDate: Date?
    private var lastCalendarEventSnapshotSignature: [String] = []

    private let calendarService: CalendarServiceProviding
    private let calendarManager = CalendarManager.shared

    var isActive: Bool { activeReminder != nil }

    private init(calendarService: CalendarServiceProviding = CalendarService()) {
        self.calendarService = calendarService
        setupObservers()
        scheduleRefresh(force: true, reason: .initialization)
    }

    private func setupObservers() {
        Defaults.publisher(.enableReminderLiveActivity, options: [])
            .sink { [weak self] change in
                guard let self else { return }
                if change.newValue {
                    self.scheduleRefresh(force: true, reason: .defaults)
                } else {
                    self.deactivateReminder()
                }
            }
            .store(in: &cancellables)

        Defaults.publisher(.reminderLeadTime, options: [])
            .sink { [weak self] _ in
                guard let self else { return }
                self.scheduleRefresh(force: true, reason: .defaults)
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

        calendarManager.$allCalendars
            .sink { [weak self] calendars in
                guard let self else { return }
                let identifiers = Set(calendars.map { $0.id })
                guard identifiers != self.lastKnownCalendarIDs else { return }
                self.lastKnownCalendarIDs = identifiers
                self.handleEventStoreDrivenChange(reason: .calendarListChange)
            }
            .store(in: &cancellables)

        calendarManager.$events
            .receive(on: RunLoop.main)
            .sink { [weak self] events in
                guard let self else { return }
                self.handleCalendarEventsUpdate(events)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .EKEventStoreChanged)
            .sink { [weak self] _ in
                guard let self else { return }
                self.handleEventStoreDrivenChange(reason: .eventStoreChange)
            }
            .store(in: &cancellables)
    }

    private func cancelAllTimers() {
        tickerTask = nil
        evaluationTask?.cancel()
        evaluationTask = nil
        fallbackRefreshTask?.cancel()
        fallbackRefreshTask = nil
        pendingRefreshTask?.cancel()
        pendingRefreshTask = nil
        pendingRefreshForce = false
        refreshTask?.cancel()
        refreshTask = nil
        hasShownCriticalSneakPeek = false
        pendingEventStoreChange = nil
    }

    private func deactivateReminder() {
        nextReminder = nil
        activeReminder = nil
        upcomingEntries = []
        activeWindowReminders = []
        cancelAllTimers()
        lastUpcomingSignature = []
        lastNoopEventStoreRefreshDate = nil
    }

    private func selectedCalendarIDs() -> [String] {
        calendarManager.allCalendars
            .filter { calendarManager.getCalendarSelected($0) }
            .map { $0.id }
    }

    private func handleCalendarEventsUpdate(_ events: [EventModel]) {
        let now = Date()
        let signature = events.map { $0.id }
        if signature == lastCalendarEventSnapshotSignature,
           let snapshotDate = lastCalendarSnapshotDate,
           now.timeIntervalSince(snapshotDate) < 5 {
            return
        }

        lastCalendarEventSnapshot = events
        lastCalendarSnapshotDate = now
        lastCalendarEventSnapshotSignature = signature

        guard Defaults[.enableReminderLiveActivity] else { return }
        logger.debug("[Reminder] Applying calendar snapshot update (events=\(events.count, privacy: .public))")
        refreshFromEvents(events, referenceDate: now, reason: .calendarEventsUpdate)
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

    private func scheduleFallbackRefresh() {
        fallbackRefreshTask?.cancel()
        let delay: TimeInterval = 15 * 60
        logger.debug("[Reminder] Scheduling fallback refresh in \(delay, format: .fixed(precision: 0))s")
        fallbackRefreshTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            } catch {
                self.logger.debug("[Reminder] Cancelled pending fallback refresh before execution")
                return
            }
            await self.scheduleRefresh(force: true, reason: .fallback)
        }
    }

    private func scheduleRefresh(force: Bool, reason: RefreshReason = .other) {
        let wasPending = pendingRefreshTask != nil
        pendingRefreshForce = pendingRefreshForce || force
        pendingRefreshToken = UUID()
        pendingRefreshReason = reason
        let token = pendingRefreshToken

        logger.debug("[Reminder] scheduleRefresh reason=\(reason.rawValue, privacy: .public) force=\(force, privacy: .public) pending=\(wasPending, privacy: .public)")

        refreshTask?.cancel()
        pendingRefreshTask?.cancel()
        pendingRefreshTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(nanoseconds: UInt64(self.refreshDebounceInterval * 1_000_000_000))
            } catch {
                self.logger.debug("[Reminder] Debounced refresh for reason=\(reason.rawValue, privacy: .public) was cancelled")
                return
            }
            await self.executeScheduledRefresh(token: token)
        }
    }

    private func executeScheduledRefresh(token: UUID) async {
        guard pendingRefreshToken == token else { return }
        pendingRefreshTask = nil

        if Task.isCancelled {
            logger.debug("[Reminder] Cancelled refresh token=\(token.uuidString, privacy: .public)")
            return
        }

        let reason = pendingRefreshReason
        let now = Date()
        let force = pendingRefreshForce
        if !force, let last = lastRefreshDate {
            let elapsed = now.timeIntervalSince(last)
            if elapsed < minimumRefreshInterval {
                let remaining = max(minimumRefreshInterval - elapsed, refreshDebounceInterval)
                logger.debug("[Reminder] Deferring refresh reason=\(reason.rawValue, privacy: .public); next attempt in \(remaining, format: .fixed(precision: 2))s")
                pendingRefreshToken = UUID()
                let nextToken = pendingRefreshToken
                pendingRefreshTask = Task { [weak self] in
                    guard let self else { return }
                    do {
                        try await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
                    } catch {
                        self.logger.debug("[Reminder] Deferred refresh for reason=\(reason.rawValue, privacy: .public) was cancelled")
                        return
                    }
                    await self.executeScheduledRefresh(token: nextToken)
                }
                return
            }
        }

        pendingRefreshForce = false
        lastRefreshDate = now

        let startTime = Date()
        logger.debug("[Reminder] Starting refresh reason=\(reason.rawValue, privacy: .public) force=\(force, privacy: .public)")

        refreshTask?.cancel()
        let taskToken = UUID()
        refreshTaskToken = taskToken
        let task = Task { [weak self] in
            guard let self else { return }
            await self.refreshUpcomingReminder(force: force, reason: reason)
        }
        refreshTask = task
        defer {
            if refreshTaskToken == taskToken {
                refreshTask = nil
                lastRefreshCompletionDate = Date()
                let duration = Date().timeIntervalSince(startTime)
                logger.debug("[Reminder] Finished refresh reason=\(reason.rawValue, privacy: .public) duration=\(duration, format: .fixed(precision: 2))s upcoming=\(self.upcomingEntries.count, privacy: .public)")
                processPendingEventStoreChangeIfNeeded()
            }
        }
        _ = try? await task.value
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
        fallbackRefreshTask?.cancel()
        nextReminder = entry
        hasShownCriticalSneakPeek = false
        Task { await self.evaluateCurrentState(at: referenceDate) }
    }

    private func refreshFromEvents(_ events: [EventModel], referenceDate: Date, reason: RefreshReason) {
        let leadMinutes = Defaults[.reminderLeadTime]
        let upcoming = events
            .filter { !shouldHide($0) }
            .compactMap { makeEntry(from: $0, leadMinutes: leadMinutes, referenceDate: referenceDate) }
            .sorted { $0.triggerDate < $1.triggerDate }

        upcomingEntries = upcoming
        updateActiveWindowReminders(for: referenceDate)

        logger.debug("[Reminder] Reduced \(events.count, privacy: .public) events to \(upcoming.count, privacy: .public) upcoming reminders")

        guard let first = upcoming.first else {
            deactivateReminder()
            logger.debug("[Reminder] No upcoming reminders found; scheduling fallback refresh")
            scheduleFallbackRefresh()
            return
        }

        logger.debug("[Reminder] Next reminder ‘\(first.event.title, privacy: .public)’ at \(first.triggerDate.timeIntervalSinceReferenceDate, privacy: .public)")

        handleEntrySelection(first, referenceDate: referenceDate)

        let signature = upcoming.map { $0.event.id }
        if lastUpcomingSignature == signature {
            if reason == .eventStoreChange {
                lastNoopEventStoreRefreshDate = Date()
            }
        } else {
            lastNoopEventStoreRefreshDate = nil
        }
        lastUpcomingSignature = signature
    }

    func requestRefresh(force: Bool = false) {
        let reason: RefreshReason = force ? .manual : .other
        if force {
            let now = Date()
            if let lastManualRefreshDate,
               now.timeIntervalSince(lastManualRefreshDate) < manualRefreshSuppressionInterval {
                let delta = now.timeIntervalSince(lastManualRefreshDate)
                logger.debug("[Reminder] Skipping manual refresh; last manual was \(delta, format: .fixed(precision: 2))s ago")
                return
            }
            lastManualRefreshDate = now
        }
        scheduleRefresh(force: force, reason: reason)
    }

    private func refreshUpcomingReminder(force: Bool = false, reason: RefreshReason = .other) async {
        guard Defaults[.enableReminderLiveActivity] else {
            deactivateReminder()
            logger.debug("[Reminder] Refresh aborted (feature disabled)")
            return
        }

        guard calendarManager.hasReminderAccess else {
            deactivateReminder()
            logger.debug("[Reminder] Refresh aborted; reminder permissions missing")
            return
        }

        let now = Date()

        if !force, let entry = nextReminder, entry.event.start > now {
            logger.debug("[Reminder] Skipping fetch; cached entry \(entry.event.title, privacy: .public) still valid for reason=\(reason.rawValue, privacy: .public)")
            await evaluateCurrentState(at: now)
            return
        }

          if let snapshotDate = lastCalendarSnapshotDate,
              now.timeIntervalSince(snapshotDate) < 5,
              !lastCalendarEventSnapshot.isEmpty {
            logger.debug("[Reminder] Using calendar snapshot (age=\(now.timeIntervalSince(snapshotDate), format: .fixed(precision: 2))s) for reason=\(reason.rawValue, privacy: .public)")
            refreshFromEvents(lastCalendarEventSnapshot, referenceDate: now, reason: reason)
            return
        }

        let calendars = selectedCalendarIDs()
        guard !calendars.isEmpty else {
            deactivateReminder()
            logger.debug("[Reminder] Refresh aborted; no calendars selected")
            return
        }

        let windowEnd = Calendar.current.date(byAdding: .hour, value: 24, to: now) ?? now.addingTimeInterval(24 * 60 * 60)
        logger.debug("[Reminder] Fetching reminders (reason=\(reason.rawValue, privacy: .public), force=\(force, privacy: .public), calendars=\(calendars.count, privacy: .public))")
        let fetchStart = Date()
        let events = await calendarService.events(from: now, to: windowEnd, calendars: calendars)
        let fetchDuration = Date().timeIntervalSince(fetchStart)
        logger.debug("[Reminder] EventKit fetch completed (events=\(events.count, privacy: .public)) in \(fetchDuration, format: .fixed(precision: 2))s")
        lastCalendarEventSnapshot = events
        lastCalendarSnapshotDate = now
        lastCalendarEventSnapshotSignature = events.map { $0.id }
        await MainActor.run {
            self.refreshFromEvents(events, referenceDate: now, reason: reason)
        }
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
            if fallbackRefreshTask == nil {
                scheduleFallbackRefresh()
            }
            return
        }

        if entry.event.start <= date {
            activeReminder = nil
            nextReminder = nil
            stopTicker()
            hasShownCriticalSneakPeek = false
            logger.debug("[Reminder] Reminder reached start time; requesting evaluation refresh")
            reminderCompletionSuppressionDeadline = Date().addingTimeInterval(reminderCompletionSuppressionInterval)
            scheduleRefresh(force: true, reason: .evaluation)
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

    private func handleEventStoreDrivenChange(reason: RefreshReason) {
        processEventStoreChange(at: Date(), reason: reason)
    }

    private func processEventStoreChange(at date: Date, reason: RefreshReason) {
        if let manual = lastManualRefreshDate {
            let delta = date.timeIntervalSince(manual)
            if delta < manualRefreshSuppressionInterval {
                logger.debug("[Reminder] Ignoring \(reason.rawValue, privacy: .public) change; manual refresh cooldown \(delta, format: .fixed(precision: 2))s")
                return
            }
        }

        if let lastRefreshStart = lastRefreshDate {
            let sinceStart = date.timeIntervalSince(lastRefreshStart)
            if sinceStart >= 0 && sinceStart < eventStoreChangeNoiseInterval {
                logger.debug("[Reminder] Ignoring \(reason.rawValue, privacy: .public); \(sinceStart, format: .fixed(precision: 2))s since start")
                return
            }
        }

        if let lastCompletion = lastRefreshCompletionDate {
            let sinceCompletion = abs(date.timeIntervalSince(lastCompletion))
            if sinceCompletion < eventStoreChangeNoiseInterval {
                logger.debug("[Reminder] Ignoring \(reason.rawValue, privacy: .public); \(sinceCompletion, format: .fixed(precision: 2))s since completion")
                return
            }
        }

        if reason == .eventStoreChange,
           let suppressionDeadline = reminderCompletionSuppressionDeadline,
           date <= suppressionDeadline {
            let remaining = suppressionDeadline.timeIntervalSince(date)
            logger.debug("[Reminder] Ignoring \(reason.rawValue, privacy: .public); reminder completion suppression \(remaining, format: .fixed(precision: 2))s")
            return
        }

        if reason == .eventStoreChange,
           let noopDate = lastNoopEventStoreRefreshDate,
           date.timeIntervalSince(noopDate) < noopEventStoreSuppressionInterval {
            let remaining = noopEventStoreSuppressionInterval - date.timeIntervalSince(noopDate)
            logger.debug("[Reminder] Ignoring \(reason.rawValue, privacy: .public); identical upcoming entries \(remaining, format: .fixed(precision: 2))s window")
            return
        }

        if let lastForce = lastEventStoreForceRefreshDate {
            let sinceForce = date.timeIntervalSince(lastForce)
            if sinceForce < self.eventStoreForceThrottleInterval {
                logger.debug("[Reminder] Ignoring \(reason.rawValue, privacy: .public); throttle window remaining \(self.eventStoreForceThrottleInterval - sinceForce, format: .fixed(precision: 2))s")
                return
            }
        }

        if refreshTask != nil {
            pendingEventStoreChange = (date, reason)
            logger.debug("[Reminder] Queued \(reason.rawValue, privacy: .public) change while refresh is running")
            return
        }

        triggerEventStoreForcedRefresh(at: date, reason: reason)
    }

    private func processPendingEventStoreChangeIfNeeded() {
        guard let pendingChange = pendingEventStoreChange else { return }
        pendingEventStoreChange = nil
        processEventStoreChange(at: pendingChange.date, reason: pendingChange.reason)
    }

    private func triggerEventStoreForcedRefresh(at date: Date = Date(), reason: RefreshReason) {
        lastEventStoreForceRefreshDate = date
        if reason == .eventStoreChange, reminderCompletionSuppressionDeadline != nil {
            reminderCompletionSuppressionDeadline = nil
        }
        logger.debug("[Reminder] Triggering event-store refresh for \(reason.rawValue, privacy: .public)")
        scheduleRefresh(force: true, reason: reason)
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
