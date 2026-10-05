import UserNotifications
import XCTest
@testable import Nina

final class NotificationTargetingTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var calendar: Calendar!
    private var now: Date!
    private var familyID: UUID!

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "nina.tests.notifications.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.set(false, forKey: LocalHomeNotificationScheduler.quietHoursEnabledKey)
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = TimeZone(identifier: "America/Sao_Paulo") ?? .gmt
        calendar = gregorian
        now = date(year: 2026, month: 8, day: 8, hour: 10, minute: 0)
        familyID = UUID()
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        calendar = nil
        now = nil
        familyID = nil
        try super.tearDownWithError()
    }

    func testAnotherAdultsTaskNeverSchedulesOnThisPhone() {
        let task = task(owner: "Bruno")

        XCTAssertFalse(
            LocalHomeNotificationScheduler.isForViewer(task, viewer: HomeNotificationViewer(name: "Ana"))
        )
    }

    func testYourOwnTaskSchedulesOnYourPhone() {
        let task = task(owner: "Ana")

        XCTAssertTrue(
            LocalHomeNotificationScheduler.isForViewer(task, viewer: HomeNotificationViewer(name: "Ana"))
        )
    }

    func testAHouseholdTaskWithNoOwnerReachesEveryone() {
        let ana = HomeNotificationViewer(name: "Ana")
        let bruno = HomeNotificationViewer(name: "Bruno")

        XCTAssertTrue(LocalHomeNotificationScheduler.isForViewer(task(owner: "Casa"), viewer: ana))
        XCTAssertTrue(LocalHomeNotificationScheduler.isForViewer(task(owner: "Casa"), viewer: bruno))
        XCTAssertTrue(LocalHomeNotificationScheduler.isForViewer(task(owner: ""), viewer: ana))
    }

    func testOwnerMatchingIgnoresCasingAndAccents() {
        XCTAssertTrue(
            LocalHomeNotificationScheduler.isForViewer(
                task(owner: "mônica"),
                viewer: HomeNotificationViewer(name: "Monica")
            )
        )
        XCTAssertTrue(
            LocalHomeNotificationScheduler.isForViewer(
                task(owner: "MONICA"),
                viewer: HomeNotificationViewer(name: "Mônica")
            )
        )
    }

    func testAChildsTaskDoesNotBuzzAnAdultsPhone() {
        let task = task(owner: "Pedro")

        XCTAssertFalse(
            LocalHomeNotificationScheduler.isForViewer(task, viewer: HomeNotificationViewer(name: "Ana"))
        )
    }

    func testAnUnknownViewerFallsOpenSoRemindersAreNeverSilentlyLost() {
        XCTAssertTrue(
            LocalHomeNotificationScheduler.isForViewer(task(owner: "Bruno"), viewer: HomeNotificationViewer())
        )
        XCTAssertTrue(
            LocalHomeNotificationScheduler.isForViewer(
                task(owner: "Bruno"),
                viewer: HomeNotificationViewer(name: "   ")
            )
        )
    }

    func testARenamedMemberKeepsReceivingTheirOwnReminders() {
        let anaMemberID = UUID()
        let staleLabel = task(owner: "Ana", ownerMemberID: anaMemberID)

        XCTAssertTrue(
            LocalHomeNotificationScheduler.isForViewer(
                staleLabel,
                viewer: HomeNotificationViewer(memberID: anaMemberID, name: "Ana Castello")
            )
        )
    }

    func testTwoMembersSharingANameDoNotReceiveEachOthersReminders() {
        let marinaMae = UUID()
        let marinaPrima = UUID()
        let maeTask = task(owner: "Marina", ownerMemberID: marinaMae)

        XCTAssertTrue(
            LocalHomeNotificationScheduler.isForViewer(
                maeTask,
                viewer: HomeNotificationViewer(memberID: marinaMae, name: "Marina")
            )
        )
        XCTAssertFalse(
            LocalHomeNotificationScheduler.isForViewer(
                maeTask,
                viewer: HomeNotificationViewer(memberID: marinaPrima, name: "Marina")
            )
        )
    }

    func testHouseWorkStillReachesAnIdentifiedViewer() {
        XCTAssertTrue(
            LocalHomeNotificationScheduler.isForViewer(
                task(owner: "Casa"),
                viewer: HomeNotificationViewer(memberID: UUID(), name: "Ana")
            )
        )
    }

    func testAReminderFiresTheChosenLeadTimeBeforeTheTaskIsDue() {
        var task = homeTask(dueAt: date(year: 2026, month: 8, day: 8, hour: 18, minute: 0))
        task.reminderLead = .thirtyMinutes

        let planned = plan([task])

        XCTAssertEqual(planned.map(\.kind), [.alert])
        XCTAssertEqual(
            planned.first?.deliveryDate,
            date(year: 2026, month: 8, day: 8, hour: 17, minute: 30)
        )
    }

    func testALeadTimeThatWouldLandInThePastFallsBackToTheDueMomentInsteadOfDroppingTheAlert() {
        var task = homeTask(dueAt: date(year: 2026, month: 8, day: 8, hour: 10, minute: 20))
        task.reminderLead = .oneHour

        XCTAssertEqual(
            plan([task]).map(\.deliveryDate),
            [date(year: 2026, month: 8, day: 8, hour: 10, minute: 20)]
        )
    }

    func testALeadTimeMovesEveryOccurrenceOfARecurringTask() {
        var task = homeTask(dueAt: date(year: 2026, month: 8, day: 8, hour: 21, minute: 0))
        task.recurrence = .daily
        task.reminderLead = .thirtyMinutes

        let planned = plan([task])

        XCTAssertEqual(planned.count, 12)
        XCTAssertEqual(
            planned.first?.deliveryDate,
            date(year: 2026, month: 8, day: 8, hour: 20, minute: 30)
        )
        XCTAssertEqual(
            planned.dropFirst().first?.deliveryDate,
            date(year: 2026, month: 8, day: 9, hour: 20, minute: 30)
        )
    }

    func testASnoozeFiresAtTheHourThePersonPickedRatherThanALeadTimeBeforeIt() {
        var task = homeTask(dueAt: date(year: 2026, month: 8, day: 8, hour: 9, minute: 0))
        task.reminderLead = .oneHour
        task.snoozedUntil = date(year: 2026, month: 8, day: 8, hour: 10, minute: 30)

        let planned = plan([task])

        XCTAssertEqual(
            planned.map(\.deliveryDate),
            [date(year: 2026, month: 8, day: 8, hour: 10, minute: 30)]
        )
    }

    func testQuietHoursIsJudgedOnTheHourTheAlertActuallyFires() {
        defaults.set(true, forKey: LocalHomeNotificationScheduler.quietHoursEnabledKey)
        var task = homeTask(dueAt: date(year: 2026, month: 8, day: 9, hour: 7, minute: 30))
        task.reminderLead = .oneHour

        let planned = plan([task])

        XCTAssertEqual(
            planned.first?.deliveryDate,
            date(year: 2026, month: 8, day: 9, hour: 6, minute: 30)
        )
        XCTAssertEqual(planned.first?.isSilent, true)
    }

    func testTheEditorKnowsWhenAReminderWillRingWithoutSound() {
        defaults.set(true, forKey: LocalHomeNotificationScheduler.quietHoursEnabledKey)
        let earlyMedicine = date(year: 2026, month: 8, day: 9, hour: 6, minute: 30)
        let breakfast = date(year: 2026, month: 8, day: 9, hour: 8, minute: 0)

        func silent(_ dueAt: Date, _ lead: TaskReminderLead) -> Bool {
            LocalHomeNotificationScheduler.ringsSilently(
                dueAt: dueAt,
                lead: lead,
                now: now,
                defaults: defaults,
                calendar: calendar
            )
        }

        XCTAssertTrue(silent(earlyMedicine, .atTime))
        XCTAssertFalse(silent(breakfast, .oneHour), "Quiet hours end at 07:00, so a 07:00 alert rings.")
        XCTAssertTrue(silent(breakfast, .twoHours))

        defaults.set(false, forKey: LocalHomeNotificationScheduler.quietHoursEnabledKey)
        XCTAssertFalse(silent(earlyMedicine, .atTime))

        defaults.set(true, forKey: LocalHomeNotificationScheduler.quietHoursEnabledKey)
        defaults.set(false, forKey: LocalHomeNotificationScheduler.notificationsEnabledKey)
        XCTAssertFalse(silent(earlyMedicine, .atTime), "A phone with alerts off rings nothing to warn about.")
    }

    func testAnUrgentTaskIsFollowedUpAnHourAfterItWasDue() {
        var task = homeTask(
            owner: "Ana",
            dueAt: date(year: 2026, month: 8, day: 8, hour: 18, minute: 0)
        )
        task.priority = .urgent

        let planned = plan([task])

        XCTAssertEqual(planned.map(\.kind), [.alert, .nudge])
        XCTAssertEqual(
            planned.last?.deliveryDate,
            date(year: 2026, month: 8, day: 8, hour: 19, minute: 0)
        )
        XCTAssertEqual(planned.last?.body, "Passou da hora. Ainda está de pé?")
    }

    func testTheTaskDetailNeverReachesTheLockScreen() {
        var task = homeTask(
            owner: "Ana",
            dueAt: date(year: 2026, month: 8, day: 8, hour: 18, minute: 0)
        )
        task.subtitle = "Vencimento salvo a partir do boleto"
        task.priority = .urgent

        let planned = plan([task])

        XCTAssertFalse(planned.isEmpty)
        for notification in planned {
            XCTAssertFalse(
                notification.body.contains("boleto"),
                "A photographed document's reading must never leave the app: whoever walks past the table reads the lock screen."
            )
            XCTAssertFalse(notification.body.contains(task.subtitle))
        }
    }

    func testAReminderCarriesOnlyItsTaskIdentifierAndDueInstantSoATapCanOpenTheTask() throws {
        let dueAt = date(year: 2026, month: 8, day: 8, hour: 18, minute: 0)
        var task = homeTask(owner: "Ana", dueAt: dueAt)
        task.subtitle = "Vencimento salvo a partir do boleto"

        let planned = try XCTUnwrap(plan([task]).first)
        let request = try XCTUnwrap(LocalHomeNotificationScheduler.request(planned, calendar: calendar))

        XCTAssertEqual(planned.taskID, task.id)
        XCTAssertEqual(request.content.userInfo.count, 2)
        XCTAssertEqual(
            request.content.userInfo[LocalHomeNotificationScheduler.taskIDKey] as? String,
            task.id.uuidString
        )
        XCTAssertEqual(
            request.content.userInfo[LocalHomeNotificationScheduler.dueInstantKey] as? Double,
            dueAt.timeIntervalSince1970
        )
        XCTAssertFalse(request.content.body.contains("boleto"))
    }

    func testAnAdultsReminderOffersAdiarOnlyWhenItFiresAtOrAfterTheDueHour() throws {
        var onTime = homeTask(owner: "Ana", dueAt: date(year: 2026, month: 8, day: 8, hour: 18, minute: 0))
        onTime.priority = .urgent
        var early = homeTask(owner: "Ana", dueAt: date(year: 2026, month: 8, day: 9, hour: 9, minute: 0))
        early.reminderLead = .oneHour
        var daily = homeTask(owner: "Ana", dueAt: date(year: 2026, month: 8, day: 8, hour: 21, minute: 0))
        daily.recurrence = .daily

        let planned = plan([onTime, early, daily])

        let onTimeAlert = try XCTUnwrap(planned.first { $0.taskID == onTime.id && $0.kind == .alert })
        let followUp = try XCTUnwrap(planned.first { $0.taskID == onTime.id && $0.kind == .nudge })
        let earlyAlert = try XCTUnwrap(planned.first { $0.taskID == early.id })
        let dailyAlert = try XCTUnwrap(planned.first { $0.taskID == daily.id })
        XCTAssertEqual(onTimeAlert.actions, .completeOrSnooze)
        XCTAssertEqual(followUp.actions, .completeOrSnooze)
        XCTAssertEqual(earlyAlert.actions, .complete)
        XCTAssertEqual(dailyAlert.actions, .finishTodayOrSnooze)
        XCTAssertEqual(onTimeAlert.actions?.completionTitle, onTime.completionActionTitle)
        XCTAssertEqual(dailyAlert.actions?.completionTitle, daily.completionActionTitle)

        let request = try XCTUnwrap(LocalHomeNotificationScheduler.request(earlyAlert, calendar: calendar))
        XCTAssertEqual(request.content.categoryIdentifier, ReminderActionSet.complete.rawValue)
    }

    func testEveryReminderButtonOpensTheAppSoNothingChangesOnALockedPhone() {
        let categories = LocalHomeNotificationScheduler.reminderCategories

        XCTAssertEqual(Set(categories.map(\.identifier)), Set(ReminderActionSet.allCases.map(\.rawValue)))
        for category in categories {
            XCTAssertFalse(category.actions.isEmpty)
            for action in category.actions {
                XCTAssertTrue(action.options.contains(.foreground), action.identifier)
                XCTAssertFalse(action.options.contains(.destructive), action.identifier)
            }
        }
        let snoozeTitles = categories.flatMap(\.actions)
            .filter { $0.identifier == LocalHomeNotificationScheduler.snoozeActionIdentifier }
            .map(\.title)
        XCTAssertEqual(Set(snoozeTitles), ["Adiar 1 hora"])
    }

    func testFinishingFromAReminderNeverSkipsTheNextOccurrenceOfARepeatingTask() {
        let announced = date(year: 2026, month: 8, day: 8, hour: 21, minute: 0)
        var daily = homeTask(dueAt: announced)
        daily.recurrence = .daily
        let route = ReminderRoute(taskID: daily.id, action: .complete, dueMoment: announced)

        XCTAssertTrue(route.completes(daily))

        var alreadyRolled = daily
        alreadyRolled.dueAt = date(year: 2026, month: 8, day: 9, hour: 21, minute: 0)
        XCTAssertFalse(route.completes(alreadyRolled))

        var missedEarlier = daily
        missedEarlier.dueAt = date(year: 2026, month: 8, day: 6, hour: 21, minute: 0)
        XCTAssertTrue(route.completes(missedEarlier))

        var oneOff = homeTask(dueAt: announced)
        XCTAssertTrue(route.completes(oneOff))
        oneOff.isDone = true
        XCTAssertFalse(route.completes(oneOff))
    }

    func testAdiarFromAReminderNeverPullsATaskEarlierThanItsCard() {
        let route = ReminderRoute(taskID: UUID(), action: .snooze, dueMoment: nil)
        let dueNow = homeTask(dueAt: now)
        let dueTomorrow = homeTask(dueAt: date(year: 2026, month: 8, day: 9, hour: 9, minute: 0))
        var done = homeTask(dueAt: now)
        done.isDone = true

        XCTAssertEqual(
            route.snoozeTarget(for: dueNow, now: now, calendar: calendar),
            now.addingTimeInterval(60 * 60)
        )
        XCTAssertNil(route.snoozeTarget(for: dueTomorrow, now: now, calendar: calendar))
        XCTAssertNil(route.snoozeTarget(for: done, now: now, calendar: calendar))
    }

    func testAReminderIsPinnedToTheInstantTheCardShowsSoATripNeverMovesIt() throws {
        let deliveryDate = Date().addingTimeInterval(3 * 24 * 60 * 60).rounded(toMinute: calendar)
        let planned = ScheduledNotification(
            identifier: "nina.local.test",
            taskID: UUID(),
            title: "Levar o Pedro ao dentista",
            body: "É a hora. Ficou com você.",
            deliveryDate: deliveryDate,
            isSilent: false,
            kind: .alert
        )

        let request = try XCTUnwrap(LocalHomeNotificationScheduler.request(planned, calendar: calendar))
        let trigger = try XCTUnwrap(request.trigger as? UNCalendarNotificationTrigger)

        XCTAssertEqual(trigger.dateComponents.timeZone, calendar.timeZone)
        XCTAssertEqual(trigger.nextTriggerDate(), deliveryDate)
    }

    func testAHighPriorityTaskIsFollowedUpAndANormalOneIsNot() {
        var high = homeTask(dueAt: date(year: 2026, month: 8, day: 8, hour: 18, minute: 0))
        high.priority = .high
        let normal = homeTask(dueAt: date(year: 2026, month: 8, day: 8, hour: 18, minute: 0))

        XCTAssertEqual(plan([high]).map(\.kind), [.alert, .nudge])
        XCTAssertEqual(plan([normal]).map(\.kind), [.alert])
    }

    func testTheFollowUpCountsFromTheDueHourAndNotFromTheLeadTime() {
        var task = homeTask(dueAt: date(year: 2026, month: 8, day: 8, hour: 18, minute: 0))
        task.priority = .urgent
        task.reminderLead = .oneHour

        let planned = plan([task])

        XCTAssertEqual(
            planned.map(\.deliveryDate),
            [
                date(year: 2026, month: 8, day: 8, hour: 17, minute: 0),
                date(year: 2026, month: 8, day: 8, hour: 19, minute: 0)
            ]
        )
    }

    func testATaskWhoseFirstAlertWasDroppedIsNeverFollowedUpAlone() {
        // Due forty minutes ago: the first alert is gone, the nudge would still be ahead.
        var task = homeTask(dueAt: date(year: 2026, month: 8, day: 8, hour: 9, minute: 20))
        task.priority = .urgent
        task.reminderLead = .oneHour

        XCTAssertTrue(plan([task]).isEmpty)
    }

    func testAFirstAlertIsNeverEvictedByAnotherTasksFollowUp() {
        var urgent = homeTask(dueAt: date(year: 2026, month: 8, day: 8, hour: 11, minute: 0))
        urgent.priority = .urgent
        let firstOfMany = date(year: 2026, month: 8, day: 8, hour: 13, minute: 0)
        let others = (1...59).map { index in
            homeTask(dueAt: firstOfMany.addingTimeInterval(TimeInterval(index) * 3_600))
        }

        let planned = plan([urgent] + others)

        XCTAssertEqual(planned.count, LocalHomeNotificationScheduler.pendingRequestLimit)
        XCTAssertTrue(planned.filter { $0.kind == .nudge }.isEmpty)
        XCTAssertEqual(
            planned.last?.deliveryDate,
            firstOfMany.addingTimeInterval(59 * 3_600)
        )
    }

    func testAFollowUpTakesOnlyTheBudgetFirstAlertsLeftOver() {
        var urgent = homeTask(dueAt: date(year: 2026, month: 8, day: 8, hour: 11, minute: 0))
        urgent.priority = .urgent
        let firstOfMany = date(year: 2026, month: 8, day: 8, hour: 13, minute: 0)
        let others = (1...58).map { index in
            homeTask(dueAt: firstOfMany.addingTimeInterval(TimeInterval(index) * 3_600))
        }

        let planned = plan([urgent] + others)

        XCTAssertEqual(planned.count, LocalHomeNotificationScheduler.pendingRequestLimit)
        XCTAssertEqual(planned.filter { $0.kind == .nudge }.count, 1)
        XCTAssertEqual(
            planned.first(where: { $0.kind == .nudge })?.deliveryDate,
            date(year: 2026, month: 8, day: 8, hour: 12, minute: 0)
        )
    }

    func testAMinorsDeviceGetsNoNudgesANeutralBodyAndForcedQuietHours() {
        let memberID = UUID()
        var urgent = homeTask(owner: "Bia", dueAt: date(year: 2026, month: 8, day: 8, hour: 22, minute: 15))
        urgent.title = "Guardar a mochila"
        urgent.ownerMemberID = memberID
        urgent.priority = .urgent
        var afternoon = homeTask(owner: "Bia", dueAt: date(year: 2026, month: 8, day: 8, hour: 15, minute: 0))
        afternoon.title = "Regar as plantas"
        afternoon.ownerMemberID = memberID
        let viewer = HomeNotificationViewer(
            memberID: memberID,
            name: "Bia",
            minorPolicy: MinorNotificationPolicy(alertsEnabled: true, quietStart: 21 * 60, quietEnd: 7 * 60)
        )

        let planned = LocalHomeNotificationScheduler.plannedNotifications(
            tasks: [urgent, afternoon],
            familyID: familyID,
            viewer: viewer,
            now: now,
            defaults: defaults,
            calendar: calendar
        )

        XCTAssertEqual(planned.count, 2)
        XCTAssertTrue(planned.allSatisfy { $0.kind == .alert })
        XCTAssertEqual(planned.map(\.body), ["Regar as plantas · 15:00", "Guardar a mochila · 22:15"])
        XCTAssertTrue(planned.allSatisfy { $0.title.isEmpty })
        XCTAssertTrue(planned.allSatisfy { $0.actions == nil }, "A minor's reminder carries no buttons.")
        XCTAssertFalse(planned.contains { $0.body.contains("Ficou com você") || $0.body.contains("dono") })
        XCTAssertEqual(planned.map(\.isSilent), [false, true])

        let silenced = LocalHomeNotificationScheduler.plannedNotifications(
            tasks: [urgent, afternoon],
            familyID: familyID,
            viewer: HomeNotificationViewer(
                memberID: memberID,
                name: "Bia",
                minorPolicy: MinorNotificationPolicy(alertsEnabled: false, quietStart: 21 * 60, quietEnd: 7 * 60)
            ),
            now: now,
            defaults: defaults,
            calendar: calendar
        )
        XCTAssertTrue(silenced.isEmpty)
    }

    private func plan(_ tasks: [TaskItem]) -> [ScheduledNotification] {
        LocalHomeNotificationScheduler.plannedNotifications(
            tasks: tasks,
            familyID: familyID,
            viewer: HomeNotificationViewer(name: "Ana"),
            now: now,
            defaults: defaults,
            calendar: calendar
        )
    }

    private func homeTask(owner: String = "Casa", dueAt: Date) -> TaskItem {
        TaskItem(
            title: "Pagar a conta de luz",
            subtitle: "",
            owner: owner,
            dueLabel: "hoje",
            dueAt: dueAt,
            category: .bills,
            isDone: false,
            createdBy: "Manual"
        )
    }

    private func date(year: Int, month: Int, day: Int, hour: Int, minute: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components) ?? .distantPast
    }

    private func task(owner: String, ownerMemberID: UUID? = nil) -> TaskItem {
        TaskItem(
            title: "Levar o Pedro ao dentista",
            subtitle: "Consultório na Vila",
            owner: owner,
            ownerMemberID: ownerMemberID,
            dueLabel: "hoje, 14:00",
            dueAt: Date().addingTimeInterval(3_600),
            category: .health,
            isDone: false,
            createdBy: "Manual"
        )
    }
}

private extension Date {
    func rounded(toMinute calendar: Calendar) -> Date {
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: self)
        return calendar.date(from: components) ?? self
    }
}
