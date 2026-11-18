//
//  NotificationManager.swift
//  DailyReadings
//
//  Created for DailyReadings Catholic Daily Readings App.
//  iOS 17+ | Swift 6+ | UserNotifications
//

import Foundation
import UserNotifications
import Observation

/// The parts of `UNUserNotificationCenter` the app uses, so tests can stand in for the system.
@MainActor
public protocol NotificationCenterClient: AnyObject {
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
    func add(_ request: UNNotificationRequest) async throws
    func pendingRequestIdentifiers() async -> [String]
    func removePendingRequests(withIdentifiers identifiers: [String])
}

/// The real notification center.
@MainActor
public final class SystemNotificationCenter: NotificationCenterClient {
    private var center: UNUserNotificationCenter { .current() }

    public nonisolated init() {}

    public func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    public func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        try await center.requestAuthorization(options: options)
    }

    public func add(_ request: UNNotificationRequest) async throws {
        try await center.add(request)
    }

    public func pendingRequestIdentifiers() async -> [String] {
        await center.pendingNotificationRequests().map(\.identifier)
    }

    public func removePendingRequests(withIdentifiers identifiers: [String]) {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }
}

/// Service managing the daily morning reminder and the Holy Day vigil alerts.
///
/// Every change goes through `refreshScheduledNotifications()`, which reads the saved settings and
/// brings the pending notifications in line with them. Refreshes run one at a time: a new one
/// cancels the one in progress and waits for it to stop, so a slow pass can never add reminders
/// after a later pass has removed them. A refresh never asks for permission; only the Settings
/// toggles do, through `requestAuthorization()`.
@Observable
@MainActor
public final class NotificationManager {

    /// Shared singleton instance.
    public static let shared = NotificationManager()

    /// Notification identifier prefix for scheduled daily reminders.
    static let identifierPrefix = "com.ridepro.DailyReadings.reminder."
    private static let fallbackIdentifier = "com.ridepro.DailyReadings.reminder.recurring"
    static let holyDayIdentifierPrefix = "com.ridepro.DailyReadings.holyday."

    /// Saved notification settings. `SettingsView` writes the same keys through `@AppStorage`.
    public enum Preference {
        public static let reminderEnabled = "reminderEnabled"
        public static let reminderTimeInterval = "reminderTimeInterval"
        public static let holyDayAlertsEnabled = "holyDayAlertsEnabled"

        /// 7:00 AM, in seconds after midnight.
        public static let defaultReminderTimeInterval: Double = 25200
        /// Vigil alerts are on until the user turns them off.
        public static let defaultHolyDayAlertsEnabled = true
    }

    /// Current notification authorization status.
    public var authorizationStatus: UNAuthorizationStatus = .notDetermined

    /// Whether notifications are currently authorized by the user.
    public var isAuthorized: Bool {
        authorizationStatus == .authorized || authorizationStatus == .provisional
    }

    private let center: NotificationCenterClient
    private let defaults: UserDefaults
    private let now: () -> Date
    private let readingsRepository: ReadingsRepository
    /// The refresh in progress, if any.
    private var refreshTask: Task<Void, Never>?
    /// The day the last refresh started, so a return to the app on a later day extends the 30 days.
    @ObservationIgnored private var lastRefreshDay: Date?

    // MARK: - Initialization

    public init(
        center: NotificationCenterClient = SystemNotificationCenter(),
        defaults: UserDefaults = .standard,
        readingsRepository: ReadingsRepository = .shared,
        now: @escaping () -> Date = { .now }
    ) {
        self.center = center
        self.defaults = defaults
        self.readingsRepository = readingsRepository
        self.now = now
        Task {
            await checkAuthorization()
        }
    }

    // MARK: - Saved Settings

    var reminderEnabled: Bool {
        defaults.bool(forKey: Preference.reminderEnabled)
    }

    var holyDayAlertsEnabled: Bool {
        defaults.object(forKey: Preference.holyDayAlertsEnabled) as? Bool ?? Preference.defaultHolyDayAlertsEnabled
    }

    /// Hour and minute of the daily reminder.
    var reminderTime: (hour: Int, minute: Int) {
        let stored = defaults.double(forKey: Preference.reminderTimeInterval)
        let interval = Int(stored > 0 ? stored : Preference.defaultReminderTimeInterval)
        return (interval / 3600, (interval % 3600) / 60)
    }

    // MARK: - Authorization

    /// Checks the current system notification settings.
    public func checkAuthorization() async {
        self.authorizationStatus = await center.authorizationStatus()
    }

    /// Requests notification permissions (alert, sound, badge) from the user.
    @discardableResult
    public func requestAuthorization() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            await checkAuthorization()
            return granted
        } catch {
            await checkAuthorization()
            return false
        }
    }

    // MARK: - Refresh

    /// Brings the pending reminders and vigil alerts in line with the saved settings: schedules
    /// what is turned on, removes what is turned off. Call it at launch and after any change to the
    /// reminder settings, the translation, or the calendar.
    ///
    /// - Returns: The refresh, for callers that want to wait for it.
    @discardableResult
    public func refreshScheduledNotifications() -> Task<Void, Never> {
        lastRefreshDay = Calendar.current.startOfDay(for: now())
        let previous = refreshTask
        previous?.cancel()
        let task = Task {
            // Let the earlier pass stop before touching the pending requests, so its last
            // additions cannot land after this pass has decided what should be pending.
            await previous?.value
            guard !Task.isCancelled else { return }
            await performRefresh()
        }
        refreshTask = task
        return task
    }

    /// Refreshes if the last refresh was on an earlier day (or never), so the 30 days of reminders
    /// move forward even when the app stays in memory and is not launched again. Called whenever the
    /// app comes to the foreground.
    ///
    /// - Returns: The refresh, or nil when the schedule was already refreshed today.
    @discardableResult
    public func refreshIfStale() -> Task<Void, Never>? {
        let today = Calendar.current.startOfDay(for: now())
        if let lastRefreshDay, lastRefreshDay >= today { return nil }
        return refreshScheduledNotifications()
    }

    private func performRefresh() async {
        await checkAuthorization()
        guard !Task.isCancelled else { return }

        if reminderEnabled && isAuthorized {
            await scheduleDailyReminders()
        } else {
            await cancelDailyReminders()
        }
        guard !Task.isCancelled else { return }

        if holyDayAlertsEnabled && isAuthorized {
            await scheduleHolyDayVigilAlerts()
        } else {
            await cancelHolyDayAlerts()
        }
    }

    // MARK: - Content

    /// Constructs the rich liturgical notification content for a daily reminder,
    /// featuring the liturgical feast or saint in the subtitle and the Verse of the Day in the body.
    nonisolated public static func makeDailyReminderContent(for liturgicalDay: LiturgicalDay, verse: VerseOfTheDay) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        if liturgicalDay.isNonSundayHolyDayOfObligation {
            content.title = "Holy Day of Obligation 🔔"
        } else if liturgicalDay.isSunday {
            content.title = "Sunday Mass Readings 📖"
        } else {
            content.title = "DailyReadings 📖"
        }
        content.subtitle = liturgicalDay.title

        let cleanText = verse.text.trimmingCharacters(in: CharacterSet(charactersIn: "\"“”'"))
        let formattedVerse: String
        if cleanText.count > 180 {
            let truncated = cleanText.prefix(175).trimmingCharacters(in: .whitespaces)
            formattedVerse = "\(truncated)…"
        } else {
            formattedVerse = cleanText
        }

        if !formattedVerse.isEmpty {
            let citationSuffix = verse.citation.isEmpty ? "" : " — \(verse.citation)"
            content.body = "“\(formattedVerse)”\(citationSuffix)"
        } else {
            content.body = "Today's Mass readings and scripture reflection are ready for your prayer."
        }
        content.sound = .default
        return content
    }

    // MARK: - Scheduling

    /// Replaces the daily reminders with one for each of the next 30 days at the saved time,
    /// each carrying that day's feast or saint and its Verse of the Day.
    /// Stops without adding anything further once the refresh is cancelled.
    private func scheduleDailyReminders() async {
        await cancelDailyReminders()

        let calendar = Calendar.current
        let (targetHour, targetMinute) = reminderTime
        let translationPref = defaults.string(forKey: "bibleTranslation") ?? "World English Bible (WEB-C)"
        let start = now()

        for dayOffset in 0..<30 {
            guard let targetDate = calendar.date(byAdding: .day, value: dayOffset, to: start) else { continue }

            var components = calendar.dateComponents([.year, .month, .day], from: targetDate)
            components.hour = targetHour
            components.minute = targetMinute
            components.second = 0

            guard let fireDate = calendar.date(from: components), fireDate > start else {
                continue // Skip times in the past for today
            }

            let liturgicalDay = LiturgicalCalendar.shared.liturgicalDay(for: targetDate)
            let verseOfTheDay = await readingsRepository.verseOfTheDay(for: targetDate, preferredTranslation: translationPref)
            let content = Self.makeDailyReminderContent(for: liturgicalDay, verse: verseOfTheDay)

            let triggerComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: triggerComponents, repeats: false)
            let request = UNNotificationRequest(
                identifier: "\(Self.identifierPrefix)\(dayOffset)",
                content: content,
                trigger: trigger
            )

            // Checked right before adding: a later refresh may have turned the reminder off
            // while this day's readings were being prepared.
            guard !Task.isCancelled else { return }
            try? await center.add(request)
        }
    }

    /// Replaces the vigil alerts with one at 7:00 PM the evening before each Holy Day of
    /// Obligation in the next 30 days.
    private func scheduleHolyDayVigilAlerts() async {
        await cancelHolyDayAlerts()

        let calendar = Calendar.current
        let start = now()

        for offset in 1...30 {
            guard let targetDate = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
            let day = LiturgicalCalendar.shared.liturgicalDay(for: targetDate)
            guard day.isNonSundayHolyDayOfObligation else { continue }

            guard let vigilDate = calendar.date(byAdding: .day, value: -1, to: targetDate) else { continue }
            var vigilComponents = calendar.dateComponents([.year, .month, .day], from: vigilDate)
            vigilComponents.hour = 19
            vigilComponents.minute = 0
            vigilComponents.second = 0

            guard let fireDate = calendar.date(from: vigilComponents), fireDate > start else { continue }

            let content = UNMutableNotificationContent()
            content.title = "Tomorrow is a Holy Day of Obligation 🔔"
            content.subtitle = day.title
            content.body = "Catholics are obliged to assist at Mass for this solemn feast. Remember to plan for Mass."
            content.sound = .default

            let triggerComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: triggerComponents, repeats: false)
            let request = UNNotificationRequest(
                identifier: "\(Self.holyDayIdentifierPrefix)\(day.id)",
                content: content,
                trigger: trigger
            )
            guard !Task.isCancelled else { return }
            try? await center.add(request)
        }
    }

    /// Removes pending Holy Day vigil alerts.
    private func cancelHolyDayAlerts() async {
        let toRemove = await center.pendingRequestIdentifiers()
            .filter { $0.hasPrefix(Self.holyDayIdentifierPrefix) }
        center.removePendingRequests(withIdentifiers: toRemove)
    }

    /// Removes pending daily reminders, including the recurring alert older builds scheduled.
    private func cancelDailyReminders() async {
        let toRemove = await center.pendingRequestIdentifiers()
            .filter { $0.hasPrefix(Self.identifierPrefix) || $0 == Self.fallbackIdentifier }
        center.removePendingRequests(withIdentifiers: toRemove)
    }
}
