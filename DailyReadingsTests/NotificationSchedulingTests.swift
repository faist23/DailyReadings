//
//  NotificationSchedulingTests.swift
//  DailyReadingsTests
//
//  Drives NotificationManager against a fake notification center: which alerts are pending after
//  each settings change, and that a refresh in progress cannot outlive a later one.
//

import XCTest
import UserNotifications
@testable import DailyReadings

@MainActor
final class FakeNotificationCenter: NotificationCenterClient {
    var status: UNAuthorizationStatus = .authorized
    var pending: [String: UNNotificationRequest] = [:]
    var addCount = 0
    var permissionRequested = false

    func authorizationStatus() async -> UNAuthorizationStatus { status }

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        permissionRequested = true
        return status == .authorized
    }

    func add(_ request: UNNotificationRequest) async throws {
        await Task.yield()
        addCount += 1
        pending[request.identifier] = request
    }

    func pendingRequestIdentifiers() async -> [String] {
        await Task.yield()
        return Array(pending.keys)
    }

    func removePendingRequests(withIdentifiers identifiers: [String]) {
        identifiers.forEach { pending[$0] = nil }
    }

    var reminders: [String] { pending.keys.filter { $0.hasPrefix(NotificationManager.identifierPrefix) } }
    var vigils: [UNNotificationRequest] {
        pending.filter { $0.key.hasPrefix(NotificationManager.holyDayIdentifierPrefix) }.map(\.value)
    }
}

@MainActor
final class NotificationSchedulingTests: XCTestCase {

    private var center: FakeNotificationCenter!
    private var defaults: UserDefaults!
    private var manager: NotificationManager!
    /// The manager's clock; tests move it forward.
    private var clock = Clock()

    final class Clock: @unchecked Sendable {
        var now = Date()
    }

    override func setUp() async throws {
        center = FakeNotificationCenter()
        defaults = UserDefaults(suiteName: "NotificationSchedulingTests-\(UUID().uuidString)")!
        // Saturday 14 November 2026, 9:00 AM. The next Holy Day is the Immaculate Conception (Tuesday 8 December).
        clock = Clock()
        clock.now = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 14, hour: 9))!
        let clock = clock
        manager = NotificationManager(center: center, defaults: defaults, readingsRepository: ReadingsRepository(), now: { clock.now })
    }

    func testVigilAlertsAreOnWhenTheSettingWasNeverSaved() async {
        // Settings shows the toggle on by default; nothing has been written to UserDefaults yet.
        await manager.refreshScheduledNotifications().value

        XCTAssertEqual(center.vigils.count, 1)
        XCTAssertTrue(center.vigils.first?.content.subtitle.contains("Immaculate Conception") ?? false)
        XCTAssertTrue(center.reminders.isEmpty, "The daily reminder is off by default")
    }

    func testTurningOffTheDailyReminderKeepsVigilAlerts() async {
        defaults.set(true, forKey: NotificationManager.Preference.reminderEnabled)
        await manager.refreshScheduledNotifications().value
        XCTAssertEqual(center.reminders.count, 29, "30 days from 9:00 AM; today's 7:00 AM reminder has passed")
        XCTAssertEqual(center.vigils.count, 1)

        defaults.set(false, forKey: NotificationManager.Preference.reminderEnabled)
        await manager.refreshScheduledNotifications().value
        XCTAssertTrue(center.reminders.isEmpty)
        XCTAssertEqual(center.vigils.count, 1, "Vigil alerts have their own toggle")
    }

    func testTurningOffVigilAlertsRemovesThem() async {
        await manager.refreshScheduledNotifications().value
        XCTAssertEqual(center.vigils.count, 1)

        defaults.set(false, forKey: NotificationManager.Preference.holyDayAlertsEnabled)
        await manager.refreshScheduledNotifications().value
        XCTAssertTrue(center.vigils.isEmpty)
    }

    func testRefreshNeverAsksForPermissionOrSchedulesWithoutIt() async {
        center.status = .notDetermined
        defaults.set(true, forKey: NotificationManager.Preference.reminderEnabled)
        await manager.refreshScheduledNotifications().value

        XCTAssertFalse(center.permissionRequested, "Only the Settings toggles ask")
        XCTAssertTrue(center.pending.isEmpty)
    }

    func testTurningTheReminderOffWhileSchedulingLeavesNoReminders() async {
        defaults.set(true, forKey: NotificationManager.Preference.reminderEnabled)
        let first = manager.refreshScheduledNotifications()

        // Wait until the first pass is adding reminders, then turn the reminder off.
        var spins = 0
        while center.addCount == 0 && spins < 10_000 {
            await Task.yield()
            spins += 1
        }
        XCTAssertGreaterThan(center.addCount, 0, "The first pass should be under way")
        defaults.set(false, forKey: NotificationManager.Preference.reminderEnabled)
        await manager.refreshScheduledNotifications().value
        await first.value

        XCTAssertTrue(center.reminders.isEmpty, "Reminders left behind by the earlier pass: \(center.reminders.count)")
        XCTAssertEqual(center.vigils.count, 1)
    }

    // MARK: - Reminder verse

    func testReminderVerseIsTheVerseTheTodayScreenShows() async {
        // The reminder reads only the Gospel Acclamation when it can; it must still give the verse the
        // full readings would give, every day.
        let repository = ReadingsRepository()
        let start = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 14, hour: 12))!
        var mismatches: [String] = []
        var quick = Duration.zero, full = Duration.zero
        let clock = ContinuousClock()
        for offset in 0..<120 {
            let date = Calendar.current.date(byAdding: .day, value: offset, to: start)!
            for (preference, translation) in [("World English Bible (WEB-C)", "WEBC"), ("Douay-Rheims", "DRB"), ("New American Bible (NAB)", "WEBC")] {
                var verse: VerseOfTheDay!
                quick += await clock.measure { verse = await repository.verseOfTheDay(for: date, preferredTranslation: preference) }
                var expected: VerseOfTheDay!
                full += await clock.measure {
                    expected = VerseOfTheDayProvider.verse(from: await repository.getOfflineReadings(for: date, translation: translation), date: date)
                }
                if verse.text != expected.text || verse.citation != expected.citation || verse.theme != expected.theme {
                    mismatches.append("\(offset) \(preference): \(verse.citation) vs \(expected.citation)")
                }
            }
        }
        print("Reminder verse for 360 day-translations: verse only \(quick), full readings \(full)")
        XCTAssertEqual(mismatches, [])
    }

    // MARK: - Moving the 30 days forward

    /// The day of the last pending reminder.
    private func lastReminderDay() -> Date? {
        center.pending.values
            .filter { $0.identifier.hasPrefix(NotificationManager.identifierPrefix) }
            .compactMap { ($0.trigger as? UNCalendarNotificationTrigger).flatMap { Calendar.current.date(from: $0.dateComponents) } }
            .max()
            .map { Calendar.current.startOfDay(for: $0) }
    }

    func testReturningOnALaterDayMovesTheRemindersForward() async throws {
        defaults.set(true, forKey: NotificationManager.Preference.reminderEnabled)
        await manager.refreshScheduledNotifications().value
        let firstLast = try XCTUnwrap(lastReminderDay())
        XCTAssertNil(manager.refreshIfStale(), "Already refreshed today")

        // The app stays in memory and comes back the next morning.
        clock.now = Calendar.current.date(byAdding: .day, value: 1, to: clock.now)!
        let refresh = try XCTUnwrap(manager.refreshIfStale(), "A new day refreshes")
        await refresh.value

        XCTAssertEqual(lastReminderDay(), Calendar.current.date(byAdding: .day, value: 1, to: firstLast))
        XCTAssertEqual(center.reminders.count, 29)
    }

    func testBackgroundRefreshIsPermittedInInfoPlist() {
        // Registering a task identifier Info.plist does not list crashes the app at launch.
        let info = Bundle.main.infoDictionary ?? [:]
        let permitted = info["BGTaskSchedulerPermittedIdentifiers"] as? [String] ?? []
        XCTAssertTrue(permitted.contains(ReminderRefreshTask.identifier), "\(permitted)")
        let modes = info["UIBackgroundModes"] as? [String] ?? []
        XCTAssertTrue(modes.contains("fetch"), "background refresh needs the fetch mode: \(modes)")
    }

    func testFirstReturnRefreshesWhenNothingWasScheduledYet() async throws {
        defaults.set(true, forKey: NotificationManager.Preference.reminderEnabled)
        let refresh = try XCTUnwrap(manager.refreshIfStale())
        await refresh.value
        XCTAssertEqual(center.reminders.count, 29)
    }
}
