//
//  ReminderRefreshTask.swift
//  DailyReadings
//
//  Keeps the daily reminders going for someone who does not open the app. Reminders are
//  scheduled 30 days ahead; a background app refresh moves that window forward, so they do not
//  stop after 30 days.
//

import BackgroundTasks
import Foundation

enum ReminderRefreshTask {
    /// Must be listed under BGTaskSchedulerPermittedIdentifiers in Info.plist, or registering crashes.
    static let identifier = "com.ridepro.DailyReadings.refreshReminders"

    /// The earliest the next refresh may run. iOS picks the actual time.
    static let interval: TimeInterval = 12 * 60 * 60

    /// Registers the handler. Call before the app finishes launching (from the App's init).
    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            handle(TaskBox(task: task))
        }
    }

    /// Asks iOS for the next refresh. Called when the app goes to the background and after each run.
    static func schedule(from now: Date = .now) {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = now.addingTimeInterval(interval)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Not available in the simulator, or background refresh is off for the app.
            print("Reminder refresh not scheduled: \(error)")
        }
    }

    private static func handle(_ box: TaskBox) {
        schedule()
        let work = Task { @MainActor in
            await NotificationManager.shared.refreshScheduledNotifications().value
            box.task.setTaskCompleted(success: !Task.isCancelled)
        }
        box.task.expirationHandler = { work.cancel() }
    }

    /// BGTask is not Sendable; iOS allows completing it from any thread.
    private struct TaskBox: @unchecked Sendable {
        let task: BGTask
    }
}
