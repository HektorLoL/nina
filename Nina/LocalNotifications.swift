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

// A guardian's settings govern a minor's phone: alerts on or off, and a quiet window the minor cannot switch off.
struct MinorNotificationPolicy: Hashable {
    var alertsEnabled: Bool
    var quietStart: Int
    var quietEnd: Int

    init(alertsEnabled: Bool, quietStart: Int, quietEnd: Int) {
        self.alertsEnabled = alertsEnabled
        self.quietStart = quietStart
        self.quietEnd = quietEnd
    }

    init(settings: MinorSupervisionSettings) {
        self.init(
            alertsEnabled: settings.alertsEnabled,
            quietStart: settings.quietStart,
            quietEnd: settings.quietEnd
        )
    }
}

struct HomeNotificationViewer: Hashable {
    var memberID: UUID?
    var name: String?
    var minorPolicy: MinorNotificationPolicy?

    init(memberID: UUID? = nil, name: String? = nil, minorPolicy: MinorNotificationPolicy? = nil) {
        self.memberID = memberID
        self.name = name
        self.minorPolicy = minorPolicy
    }

    init(member: HouseholdMember?) {
        memberID = member?.id
        name = member?.name
        minorPolicy = nil
    }
}

protocol HomeNotificationScheduling {
    func authorizationStatus() async -> HomeNotificationAuthorizationStatus
    func requestAuthorization() async -> HomeNotificationAuthorizationStatus
    func synchronize(tasks: [TaskItem], familyID: UUID, viewer: HomeNotificationViewer) async
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
    func synchronize(tasks: [TaskItem], familyID: UUID, viewer: HomeNotificationViewer) async {}
}

#if canImport(UserNotifications)
struct LocalHomeNotificationScheduler: HomeNotificationScheduling {
    static let notificationsEnabledKey = "nina.notificationsEnabled"
    static let quietHoursEnabledKey = "nina.quietHoursEnabled"
    static let quietHoursStartMinutesKey = "nina.quietHoursStartMinutes"
    static let quietHoursEndMinutesKey = "nina.quietHoursEndMinutes"
    static let defaultQuietHoursStartMinutes = 22 * 60
    static let defaultQuietHoursEndMinutes = 7 * 60

    static let pendingRequestLimit = 60
    static let taskIDKey = "task_id"
    static let missedReminderNudgeDelay: TimeInterval = 60 * 60

    static func settingsSummary(defaults: UserDefaults = .standard) -> String {
        let alertsEnabled = defaults.object(forKey: notificationsEnabledKey) as? Bool ?? true
        guard alertsEnabled else { return "Avisos desligados por aqui." }
        let quietHours = defaults.object(forKey: quietHoursEnabledKey) as? Bool ?? true
        return quietHours ? "Avisos ligados, com horário de silêncio." : "Avisos ligados."
    }

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

        _ = try? await center.requestAuthorization(options: [.alert, .sound])
        return await authorizationStatus()
    }

    func synchronize(tasks: [TaskItem], familyID: UUID, viewer: HomeNotificationViewer) async {
        let pending = await center.pendingNotificationRequests()
        let existingNinaIDs = pending.map(\.identifier).filter(Self.isNinaNotificationIdentifier)

        guard defaults.object(forKey: Self.notificationsEnabledKey) as? Bool ?? true,
              await authorizationStatus().canSchedule else {
            center.removePendingNotificationRequests(withIdentifiers: existingNinaIDs)
            return
        }

        let requests = notificationRequests(
            tasks: tasks,
            familyID: familyID,
            viewer: viewer
        )

        center.removePendingNotificationRequests(withIdentifiers: existingNinaIDs)
        for request in requests {
            try? await center.add(request)
        }
    }

    // Another adult's chore must never buzz this phone, and must never evict this phone's own
    // reminders from the 60-request tail.
    static func isForViewer(_ task: TaskItem, viewer: HomeNotificationViewer) -> Bool {
        guard !HouseholdWorkload.isSharedOwner(task.owner) else { return true }

        if let ownerMemberID = task.ownerMemberID, let viewerMemberID = viewer.memberID {
            return ownerMemberID == viewerMemberID
        }

        guard let viewerName = viewer.name,
              !viewerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return true
        }
        return HouseholdWorkload.isSameOwner(task.owner, viewerName)
    }

    static func plannedNotifications(
        tasks: [TaskItem],
        familyID: UUID,
        viewer: HomeNotificationViewer,
        now: Date = Date(),
        defaults: UserDefaults = .standard,
        calendar: Calendar = .current
    ) -> [ScheduledNotification] {
        if let minorPolicy = viewer.minorPolicy, !minorPolicy.alertsEnabled {
            return []
        }
        let quietHours = viewer.minorPolicy.map { QuietHoursConfiguration(minorPolicy: $0, calendar: calendar) }
            ?? QuietHoursConfiguration(defaults: defaults, calendar: calendar)
        var alerts: [ScheduledNotification] = []
        var nudges: [ScheduledNotification] = []

        for task in tasks where !task.isDone && isForViewer(task, viewer: viewer) {
            let moments = reminderMoments(task, after: now, calendar: calendar)

            for moment in moments {
                let isMinor = viewer.minorPolicy != nil
                alerts.append(
                    ScheduledNotification(
                        identifier: taskIdentifier(
                            task.id,
                            familyID: familyID,
                            deliveryDate: moment.alertDate
                        ),
                        taskID: task.id,
                        title: isMinor ? "" : task.title,
                        body: isMinor
                            ? minorNotificationBody(task, dueMoment: moment.dueMoment, calendar: calendar)
                            : taskNotificationBody(task),
                        deliveryDate: moment.alertDate,
                        isSilent: quietHours.contains(moment.alertDate),
                        kind: .alert
                    )
                )
            }

            // A minor's phone never repeats itself: no follow-up nudge, ever.
            guard viewer.minorPolicy == nil,
                  task.priority == .high || task.priority == .urgent,
                  let dueMoment = moments.first?.dueMoment else { continue }

            let nudgeDate = dueMoment.addingTimeInterval(missedReminderNudgeDelay)
            guard nudgeDate > now else { continue }

            nudges.append(
                ScheduledNotification(
                    identifier: nudgeIdentifier(
                        task.id,
                        familyID: familyID,
                        deliveryDate: nudgeDate
                    ),
                    taskID: task.id,
                    title: task.title,
                    body: nudgeNotificationBody(task),
                    deliveryDate: nudgeDate,
                    isSilent: quietHours.contains(nudgeDate),
                    kind: .nudge
                )
            )
        }

        // A nudge repeats something the phone already showed, so it may only spend budget that no
        // first alert claimed.
        let deliveredAlerts = alerts
            .sorted { $0.deliveryDate < $1.deliveryDate }
            .prefix(pendingRequestLimit)
        let deliveredNudges = nudges
            .sorted { $0.deliveryDate < $1.deliveryDate }
            .prefix(pendingRequestLimit - deliveredAlerts.count)

        return (deliveredAlerts + deliveredNudges).sorted { $0.deliveryDate < $1.deliveryDate }
    }

    private func notificationRequests(
        tasks: [TaskItem],
        familyID: UUID,
        viewer: HomeNotificationViewer
    ) -> [UNNotificationRequest] {
        Self.plannedNotifications(
            tasks: tasks,
            familyID: familyID,
            viewer: viewer,
            now: Date(),
            defaults: defaults,
            calendar: calendar
        )
        .compactMap { Self.request($0, calendar: calendar) }
    }

    private static func reminderMoments(
        _ task: TaskItem,
        after now: Date,
        calendar: Calendar
    ) -> [ReminderMoment] {
        let lead = TimeInterval(task.reminderLead.minutes * 60)

        func leadAdjusted(_ dueMoments: [Date]) -> [ReminderMoment] {
            dueMoments.compactMap { dueMoment in
                guard dueMoment > now else { return nil }
                // A lead longer than the time left falls back to the moment itself,
                // so a task due in three hours with "1 dia antes" still gets one alert.
                let leadDate = dueMoment.addingTimeInterval(-lead)
                let alertDate = leadDate > now ? leadDate : dueMoment
                return ReminderMoment(dueMoment: dueMoment, alertDate: alertDate)
            }
        }

        if let snoozedUntil = task.snoozedUntil, snoozedUntil > now {
            let snoozed = ReminderMoment(dueMoment: snoozedUntil, alertDate: snoozedUntil)
            guard task.recurrence != .none else { return [snoozed] }
            return [snoozed] + leadAdjusted(
                task.scheduledOccurrences(after: snoozedUntil, limit: 12, calendar: calendar)
            )
        }

        return leadAdjusted(
            task.scheduledOccurrences(
                after: now,
                limit: task.recurrence == .none ? 1 : 12,
                calendar: calendar
            )
        )
    }

    static func request(
        _ scheduled: ScheduledNotification,
        calendar: Calendar
    ) -> UNNotificationRequest? {
        let content = UNMutableNotificationContent()
        content.title = scheduled.title
        content.body = scheduled.body
        // Only the task's identifier rides along, so a tap can open it; nothing readable is added.
        content.userInfo = [taskIDKey: scheduled.taskID.uuidString]
        // Quiet hours silences the alert instead of moving it: the app must never show one time
        // and deliver another.
        content.sound = scheduled.isSilent ? nil : .default
        content.interruptionLevel = scheduled.isSilent ? .passive : .active

        // The zone pins the trigger to the instant the card shows, so a trip never moves the alert.
        var components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: scheduled.deliveryDate
        )
        components.timeZone = calendar.timeZone
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

    // The detail never reaches the lock screen. It may be a boleto, a receita or a
    // comunicado escolar, and whoever walks past the table reads it. Only the
    // title the person wrote themselves and who is holding it ever leave the app.
    // An owned alert is delivered only to the owner's phone, so it speaks to them,
    // and a nudge asks rather than asserts a household state the phone cannot see.
    private static func taskNotificationBody(_ task: TaskItem) -> String {
        guard !HouseholdWorkload.isSharedOwner(task.owner) else {
            return "É a hora, e ainda não tem dono."
        }
        return "É a hora. Ficou com você."
    }

    // Neutral on a minor's phone: the title they were given and the hour, never Nina's voice.
    static func minorNotificationBody(_ task: TaskItem, dueMoment: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.dateFormat = "HH:mm"
        return "\(task.title) · \(formatter.string(from: dueMoment))"
    }

    private static func nudgeNotificationBody(_ task: TaskItem) -> String {
        guard !HouseholdWorkload.isSharedOwner(task.owner) else {
            return "Passou da hora. Alguém pega?"
        }
        return "Passou da hora. Ainda está de pé?"
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

    private static func nudgeIdentifier(
        _ id: UUID,
        familyID: UUID,
        deliveryDate: Date
    ) -> String {
        let minute = Int(deliveryDate.timeIntervalSince1970 / 60)
        return "nina.local.nudge.\(familyID.uuidString).\(id.uuidString).\(minute)"
    }

    private static func isNinaNotificationIdentifier(_ identifier: String) -> Bool {
        identifier.hasPrefix("nina.local.")
    }
}

enum HomeNotificationKind: Hashable {
    case alert
    case nudge
}

struct ScheduledNotification: Hashable {
    var identifier: String
    var taskID: UUID
    var title: String
    var body: String
    var deliveryDate: Date
    var isSilent: Bool
    var kind: HomeNotificationKind
}

private struct ReminderMoment {
    var dueMoment: Date
    var alertDate: Date
}

private struct QuietHoursConfiguration {
    var isEnabled: Bool
    var startMinutes: Int
    var endMinutes: Int
    var calendar: Calendar

    init(minorPolicy: MinorNotificationPolicy, calendar: Calendar) {
        isEnabled = true
        startMinutes = minorPolicy.quietStart
        endMinutes = minorPolicy.quietEnd
        self.calendar = calendar
    }

    init(defaults: UserDefaults, calendar: Calendar) {
        isEnabled = defaults.object(forKey: LocalHomeNotificationScheduler.quietHoursEnabledKey) as? Bool ?? true
        startMinutes = defaults.object(forKey: LocalHomeNotificationScheduler.quietHoursStartMinutesKey) as? Int
            ?? LocalHomeNotificationScheduler.defaultQuietHoursStartMinutes
        endMinutes = defaults.object(forKey: LocalHomeNotificationScheduler.quietHoursEndMinutesKey) as? Int
            ?? LocalHomeNotificationScheduler.defaultQuietHoursEndMinutes
        self.calendar = calendar
    }

    func contains(_ scheduledDate: Date) -> Bool {
        guard isEnabled, startMinutes != endMinutes else { return false }

        let components = calendar.dateComponents([.hour, .minute], from: scheduledDate)
        let scheduledMinutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)

        if startMinutes < endMinutes {
            return scheduledMinutes >= startMinutes && scheduledMinutes < endMinutes
        }

        return scheduledMinutes >= startMinutes || scheduledMinutes < endMinutes
    }
}
// A reminder that fires while Nina is open is shown like any other, and a tap opens its task.
final class NinaNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NinaNotificationDelegate()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier,
              let raw = response.notification.request.content.userInfo[LocalHomeNotificationScheduler.taskIDKey] as? String,
              let taskID = UUID(uuidString: raw) else { return }
        await MainActor.run {
            TaskNotificationRoute.shared.pendingTaskID = taskID
        }
    }
}
#else
typealias LocalHomeNotificationScheduler = NoopHomeNotificationScheduler
#endif

@MainActor
@Observable
final class TaskNotificationRoute {
    static let shared = TaskNotificationRoute()

    var pendingTaskID: UUID?
}
