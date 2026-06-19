import Foundation
#if canImport(UserNotifications)
import UserNotifications
#endif

protocol HomeNotificationScheduling {
    func synchronize(tasks: [TaskItem], reminders: [ReminderItem], familyID: UUID) async
}

struct NoopHomeNotificationScheduler: HomeNotificationScheduling {
    func synchronize(tasks: [TaskItem], reminders: [ReminderItem], familyID: UUID) async {}
}

#if canImport(UserNotifications)
struct LocalHomeNotificationScheduler: HomeNotificationScheduling {
    static let notificationsEnabledKey = "nina.notificationsEnabled"

    private let center: UNUserNotificationCenter
    private let defaults: UserDefaults
    private let calendar: Calendar

    init(
        center: UNUserNotificationCenter = .current(),
        defaults: UserDefaults = .standard,
        calendar: Calendar = .current
    ) {
        self.center = center
        self.defaults = defaults
        self.calendar = calendar
    }

    func synchronize(tasks: [TaskItem], reminders: [ReminderItem], familyID: UUID) async {
        let pending = await center.pendingNotificationRequests()
        let existingNinaIDs = pending.map(\.identifier).filter(Self.isNinaNotificationIdentifier)

        guard defaults.object(forKey: Self.notificationsEnabledKey) as? Bool ?? true else {
            center.removePendingNotificationRequests(withIdentifiers: existingNinaIDs)
            return
        }

        let requests = notificationRequests(
            tasks: tasks,
            reminders: reminders,
            familyID: familyID
        )
        let requestIDs = Set(requests.map(\.identifier))
        let staleIDs = existingNinaIDs.filter { !requestIDs.contains($0) }
        if !staleIDs.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: staleIDs)
        }

        guard !requests.isEmpty, await ensureAuthorization() else { return }

        for request in requests {
            try? await center.add(request)
        }
    }

    private func notificationRequests(
        tasks: [TaskItem],
        reminders: [ReminderItem],
        familyID: UUID
    ) -> [UNNotificationRequest] {
        let now = Date()
        let taskRequests = tasks.compactMap { task -> UNNotificationRequest? in
            guard !task.isDone, let dueAt = task.dueAt, dueAt > now else { return nil }
            return request(
                identifier: Self.taskIdentifier(task.id, familyID: familyID),
                title: "Tarefa: \(task.title)",
                body: taskNotificationBody(task),
                dueAt: dueAt
            )
        }

        let reminderRequests = reminders.compactMap { reminder -> UNNotificationRequest? in
            guard let dueAt = reminder.dueAt, dueAt > now else { return nil }
            return request(
                identifier: Self.reminderIdentifier(reminder.id, familyID: familyID),
                title: "Lembrete: \(reminder.title)",
                body: reminderNotificationBody(reminder),
                dueAt: dueAt
            )
        }

        return taskRequests + reminderRequests
    }

    private func request(
        identifier: String,
        title: String,
        body: String,
        dueAt: Date
    ) -> UNNotificationRequest? {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: dueAt
        )
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: components,
            repeats: false
        )

        return UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        )
    }

    private func taskNotificationBody(_ task: TaskItem) -> String {
        let detail = task.subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if detail.isEmpty {
            return "\(task.owner) - \(task.dueLabel)"
        }
        return "\(task.owner) - \(detail)"
    }

    private func reminderNotificationBody(_ reminder: ReminderItem) -> String {
        let detail = reminder.detail.trimmingCharacters(in: .whitespacesAndNewlines)
        return detail.isEmpty ? reminder.dateLabel : detail
    }

    private func ensureAuthorization() async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) == true
        case .denied:
            return false
        @unknown default:
            return false
        }
    }

    private static func taskIdentifier(_ id: UUID, familyID: UUID) -> String {
        "nina.local.task.\(familyID.uuidString).\(id.uuidString)"
    }

    private static func reminderIdentifier(_ id: UUID, familyID: UUID) -> String {
        "nina.local.reminder.\(familyID.uuidString).\(id.uuidString)"
    }

    private static func isNinaNotificationIdentifier(_ identifier: String) -> Bool {
        identifier.hasPrefix("nina.local.")
    }
}
#else
typealias LocalHomeNotificationScheduler = NoopHomeNotificationScheduler
#endif
