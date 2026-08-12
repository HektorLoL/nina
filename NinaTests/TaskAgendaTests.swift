import XCTest
@testable import Nina

final class TaskAgendaTests: XCTestCase {
    private var calendar: Calendar!
    private var now: Date!

    override func setUp() {
        super.setUp()
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = TimeZone(identifier: "America/Sao_Paulo") ?? .gmt
        calendar = gregorian
        now = date(year: 2026, month: 8, day: 8, hour: 10, minute: 0)
    }

    override func tearDown() {
        calendar = nil
        now = nil
        super.tearDown()
    }

    func testABoletoOverdueSinceYesterdayStaysOnTodaysAgenda() {
        let task = task(dueAt: date(year: 2026, month: 8, day: 7, hour: 18, minute: 0))

        XCTAssertTrue(task.belongsOnAgenda(for: now, calendar: calendar))
        XCTAssertTrue(task.isOverdue(relativeTo: now, calendar: calendar))
        XCTAssertFalse(task.isDue(on: now, calendar: calendar))
    }

    func testATaskOverdueByWeeksIsStillOnTheAgenda() {
        let task = task(dueAt: date(year: 2026, month: 7, day: 12, hour: 9, minute: 0))

        XCTAssertTrue(task.belongsOnAgenda(for: now, calendar: calendar))
        XCTAssertTrue(task.isOverdue(relativeTo: now, calendar: calendar))
    }

    func testATaskDueLaterTodayIsOnTheAgendaButNotYetOverdue() {
        let task = task(dueAt: date(year: 2026, month: 8, day: 8, hour: 18, minute: 0))

        XCTAssertTrue(task.belongsOnAgenda(for: now, calendar: calendar))
        XCTAssertTrue(task.isDue(on: now, calendar: calendar))
        XCTAssertFalse(task.isOverdue(relativeTo: now, calendar: calendar))
    }

    func testATaskDueTomorrowIsNotOnTodaysAgenda() {
        let task = task(dueAt: date(year: 2026, month: 8, day: 9, hour: 9, minute: 0))

        XCTAssertFalse(task.belongsOnAgenda(for: now, calendar: calendar))
        XCTAssertFalse(task.isOverdue(relativeTo: now, calendar: calendar))
    }

    func testACompletedTaskNeverReturnsToTheAgenda() {
        var task = task(dueAt: date(year: 2026, month: 8, day: 7, hour: 18, minute: 0))
        task.isDone = true

        XCTAssertFalse(task.belongsOnAgenda(for: now, calendar: calendar))
        XCTAssertFalse(task.isOverdue(relativeTo: now, calendar: calendar))
    }

    func testASeedIsNeverPulledOntoTheAgendaByADate() {
        var seed = task(dueAt: date(year: 2026, month: 8, day: 7, hour: 18, minute: 0))
        seed.kind = .seed

        XCTAssertFalse(seed.belongsOnAgenda(for: now, calendar: calendar))
    }

    func testATaskWithNoDateIsNeverOverdueAndNeverOnTheAgenda() {
        let task = task(dueAt: nil)

        XCTAssertFalse(task.belongsOnAgenda(for: now, calendar: calendar))
        XCTAssertFalse(task.isOverdue(relativeTo: now, calendar: calendar))
        XCTAssertNil(task.displayDate(relativeTo: now, calendar: calendar))
    }

    func testAMissedDailyTaskShowsTodaysOccurrenceRatherThanTheStaleStoredDate() {
        var daily = task(dueAt: date(year: 2026, month: 8, day: 5, hour: 21, minute: 0))
        daily.recurrence = .daily

        let displayed = daily.displayDate(relativeTo: now, calendar: calendar)

        XCTAssertEqual(displayed, date(year: 2026, month: 8, day: 8, hour: 21, minute: 0))
        XCTAssertTrue(daily.isDue(on: now, calendar: calendar))
        XCTAssertTrue(daily.belongsOnAgenda(for: now, calendar: calendar))
        XCTAssertFalse(daily.isOverdue(relativeTo: now, calendar: calendar))
    }

    func testTheScreenAndTheNotificationSchedulerAgreeOnARecurringTask() {
        var daily = task(dueAt: date(year: 2026, month: 8, day: 5, hour: 21, minute: 0))
        daily.recurrence = .daily

        let displayed = daily.displayDate(relativeTo: now, calendar: calendar)
        let nextScheduled = daily.scheduledOccurrences(after: now, limit: 1, calendar: calendar).first

        XCTAssertEqual(displayed, nextScheduled)
    }

    func testARecurringTaskPastTodaysOccurrenceReadsAsOverdueToday() {
        var daily = task(dueAt: date(year: 2026, month: 8, day: 5, hour: 7, minute: 0))
        daily.recurrence = .daily

        XCTAssertEqual(
            daily.displayDate(relativeTo: now, calendar: calendar),
            date(year: 2026, month: 8, day: 8, hour: 7, minute: 0)
        )
        XCTAssertTrue(daily.isOverdue(relativeTo: now, calendar: calendar))
        XCTAssertTrue(daily.belongsOnAgenda(for: now, calendar: calendar))
    }

    func testAFutureSnoozeWinsOverTheStoredDueDate() {
        var task = task(dueAt: date(year: 2026, month: 8, day: 7, hour: 18, minute: 0))
        task.snoozedUntil = date(year: 2026, month: 8, day: 9, hour: 8, minute: 0)

        XCTAssertEqual(
            task.displayDate(relativeTo: now, calendar: calendar),
            date(year: 2026, month: 8, day: 9, hour: 8, minute: 0)
        )
        XCTAssertFalse(task.belongsOnAgenda(for: now, calendar: calendar))
        XCTAssertFalse(task.isOverdue(relativeTo: now, calendar: calendar))
    }

    func testAnExpiredSnoozeFallsBackToTheDueDateAndStaysOverdue() {
        var task = task(dueAt: date(year: 2026, month: 8, day: 6, hour: 18, minute: 0))
        task.snoozedUntil = date(year: 2026, month: 8, day: 8, hour: 7, minute: 0)

        XCTAssertTrue(task.isOverdue(relativeTo: now, calendar: calendar))
        XCTAssertTrue(task.belongsOnAgenda(for: now, calendar: calendar))
    }

    func testTheCompletedListSaysItOnlyShowsTheWindowRetentionActuallyKeeps() {
        XCTAssertTrue(
            CompletedTaskRetention.disclosureNote
                .contains("\(CompletedTaskRetention.visibleDays) dias")
        )
        XCTAssertTrue(CompletedTaskRetention.disclosureNote.contains("guardadas"))
        XCTAssertFalse(CompletedTaskRetention.disclosureNote.contains("!"))
    }

    func testASnoozedTaskShowsTheDateItWasMovedToAndNotTheOneItWasWrittenWith() {
        let due = date(year: 2026, month: 8, day: 8, hour: 9, minute: 0)
        let snoozedTo = date(year: 2026, month: 8, day: 20, hour: 9, minute: 0)
        var moved = task(dueAt: due)
        moved.dueLabel = "hoje"
        moved.snoozedUntil = snoozedTo

        let reference = date(year: 2026, month: 8, day: 12, hour: 10, minute: 0)
        let label = moved.effectiveDueLabel(relativeTo: reference, calendar: calendar)

        // dueLabel is stamped at write time and never recomputed, while lateness
        // colour is derived from displayDate. Rendering the stored string made the
        // two disagree: a rescheduled task came back wearing its old late date.
        XCTAssertNotEqual(label, "hoje")
        XCTAssertFalse(moved.isOverdue(relativeTo: reference, calendar: calendar))
    }

    func testASeedKeepsItsWrittenLabelBecauseItHasNoDateToDeriveOneFrom() {
        var seed = task(dueAt: nil)
        seed.kind = .seed
        seed.dueLabel = "Sem data"

        XCTAssertEqual(seed.effectiveDueLabel(), "Sem data")
    }

    private func task(dueAt: Date?) -> TaskItem {
        TaskItem(
            title: "Pagar a conta de luz",
            subtitle: "",
            owner: "Casa",
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
}
