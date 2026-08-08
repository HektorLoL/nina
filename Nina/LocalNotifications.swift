import Foundation
#if canImport(UserNotifications)
import UserNotifications
#endif

enum HomeNotificationAuthorizationStatus: Hashable {
    case notDetermined
    case denied
    case authorized
    case provisional
    case ephemeral
    case unavailable

    var canSchedule: Bool {
        switch self {
        case .authorized, .provisional, .ephemeral:
            true
        case .notDetermined, .denied, .unavailable:
            false
        }
    }
}

protocol HomeNotificationScheduling {
    func authorizationStatus() async -> HomeNotificationAuthorizationStatus
    func requestAuthorization() async -> HomeNotificationAuthorizationStatus
    func synchronize(tasks: [TaskItem], familyID: UUID) async
}

extension HomeNotificationScheduling {
    func authorizationStatus() async -> HomeNotificationAuthorizationStatus {
        .unavailable
    }

    func requestAuthorization() async -> HomeNotificationAuthorizationStatus {
        .unavailable
    }
}

struct NoopHomeNotificationScheduler: HomeNotificationScheduling {
    func synchronize(tasks: [TaskItem], familyID: UUID) async {}
}

#if canImport(UserNotifications)
struct LocalHomeNotificationScheduler: HomeNotificationScheduling {
    static let notificationsEnabledKey = "nina.notificationsEnabled"
    static let quietHoursEnabledKey = "nina.quietHoursEnabled"
    static let quietHoursStartMinutesKey = "nina.quietHoursStartMinutes"
    static let quietHoursEndMinutesKey = "nina.quietHoursEndMinutes"
    static let defaultQuietHoursStartMinutes = 22 * 60
    static let defaultQuietHoursEndMinutes = 7 * 60

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

    func authorizationStatus() async -> HomeNotificationAuthorizationStatus {
        Self.domainStatus(from: await center.notificationSettings().authorizationStatus)
    }

    func requestAuthorization() async -> HomeNotificationAuthorizationStatus {
        let currentStatus = await authorizationStatus()
        guard currentStatus == .notDetermined else { return currentStatus }

        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        return await authorizationStatus()
    }

    func synchronize(tasks: [TaskItem], familyID: UUID) async {
        let pending = await center.pendingNotificationRequests()
        let existingNinaIDs = pending.map(\.identifier).filter(Self.isNinaNotificationIdentifier)

        guard defaults.object(forKey: Self.notificationsEnabledKey) as? Bool ?? true,
              await authorizationStatus().canSchedule else {
            center.removePendingNotificationRequests(withIdentifiers: existingNinaIDs)
            return
        }

        let requests = notificationRequests(
            tasks: tasks,
            familyID: familyID
        )

        center.removePendingNotificationRequests(withIdentifiers: existingNinaIDs)
        for request in requests {
            try? await center.add(request)
        }
    }

    private func notificationRequests(
        tasks: [TaskItem],
        familyID: UUID
    ) -> [UNNotificationRequest] {
        let now = Date()
        let quietHours = QuietHoursConfiguration(defaults: defaults, calendar: calendar)
        var scheduled: [ScheduledNotification] = []

        for task in tasks where !task.isDone {
            let dates = taskDeliveryDates(task, after: now)
            for date in dates {
                let deliveryDate = quietHours.deliveryDate(for: date)
                scheduled.append(
                    ScheduledNotification(
                        identifier: Self.taskIdentifier(
                            task.id,
                            familyID: familyID,
                            deliveryDate: deliveryDate
                        ),
                        title: task.title,
                        body: taskNotificationBody(task),
                        deliveryDate: deliveryDate
                    )
                )
            }
        }

        return scheduled
            .filter { $0.deliveryDate > now }
            .sorted { $0.deliveryDate < $1.deliveryDate }
            .prefix(60)
            .compactMap(request)
    }

    private func taskDeliveryDates(_ task: TaskItem, after now: Date) -> [Date] {
        if let snoozedUntil = task.snoozedUntil, snoozedUntil > now {
            guard task.recurrence != .none else { return [snoozedUntil] }
            return [snoozedUntil] + task.scheduledOccurrences(
                after: snoozedUntil,
                limit: 12,
                calendar: calendar
            )
        }

        return task.scheduledOccurrences(
            after: now,
            limit: task.recurrence == .none ? 1 : 12,
            calendar: calendar
        )
    }

    private func request(_ scheduled: ScheduledNotification) -> UNNotificationRequest? {
        let content = UNMutableNotificationContent()
        content.title = scheduled.title
        content.body = scheduled.body
        content.sound = .default

        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: scheduled.deliveryDate
        )
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: components,
            repeats: false
        )

        return UNNotificationRequest(
            identifier: scheduled.identifier,
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

    private static func domainStatus(
        from status: UNAuthorizationStatus
    ) -> HomeNotificationAuthorizationStatus {
        switch status {
        case .notDetermined:
            .notDetermined
        case .denied:
            .denied
        case .authorized:
            .authorized
        case .provisional:
            .provisional
        case .ephemeral:
            .ephemeral
        @unknown default:
            .unavailable
        }
    }

    private static func taskIdentifier(
        _ id: UUID,
        familyID: UUID,
        deliveryDate: Date
    ) -> String {
        let minute = Int(deliveryDate.timeIntervalSince1970 / 60)
        return "nina.local.task.\(familyID.uuidString).\(id.uuidString).\(minute)"
    }

    private static func isNinaNotificationIdentifier(_ identifier: String) -> Bool {
        identifier.hasPrefix("nina.local.")
    }
}

private struct ScheduledNotification {
    var identifier: String
    var title: String
    var body: String
    var deliveryDate: Date
}

private struct QuietHoursConfiguration {
    var isEnabled: Bool
    var startMinutes: Int
    var endMinutes: Int
    var calendar: Calendar

    init(defaults: UserDefaults, calendar: Calendar) {
        isEnabled = defaults.object(forKey: LocalHomeNotificationScheduler.quietHoursEnabledKey) as? Bool ?? true
        startMinutes = defaults.object(forKey: LocalHomeNotificationScheduler.quietHoursStartMinutesKey) as? Int
            ?? LocalHomeNotificationScheduler.defaultQuietHoursStartMinutes
        endMinutes = defaults.object(forKey: LocalHomeNotificationScheduler.quietHoursEndMinutesKey) as? Int
            ?? LocalHomeNotificationScheduler.defaultQuietHoursEndMinutes
        self.calendar = calendar
    }

    func deliveryDate(for scheduledDate: Date) -> Date {
        guard isEnabled, startMinutes != endMinutes else { return scheduledDate }

        let components = calendar.dateComponents([.hour, .minute], from: scheduledDate)
        let scheduledMinutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)

        if startMinutes < endMinutes {
            guard scheduledMinutes >= startMinutes, scheduledMinutes < endMinutes else {
                return scheduledDate
            }
            return date(at: endMinutes, on: scheduledDate)
        }

        if scheduledMinutes < endMinutes {
            return date(at: endMinutes, on: scheduledDate)
        }

        guard scheduledMinutes >= startMinutes,
              let nextDay = calendar.date(byAdding: .day, value: 1, to: scheduledDate) else {
            return scheduledDate
        }
        return date(at: endMinutes, on: nextDay)
    }

    private func date(at minutes: Int, on date: Date) -> Date {
        calendar.date(
            bySettingHour: minutes / 60,
            minute: minutes % 60,
            second: 0,
            of: date
        ) ?? date
    }
}
#else
typealias LocalHomeNotificationScheduler = NoopHomeNotificationScheduler
#endif
