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

    func testALeadTimeThatWouldLandInThePastDropsTheReminderInsteadOfFiringItImmediately() {
        var task = homeTask(dueAt: date(year: 2026, month: 8, day: 8, hour: 10, minute: 20))
        task.reminderLead = .oneHour

        XCTAssertTrue(plan([task]).isEmpty)
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
        XCTAssertEqual(planned.last?.body, "Passou da hora e continua com Ana.")
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
        var task = homeTask(dueAt: date(year: 2026, month: 8, day: 8, hour: 10, minute: 20))
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
