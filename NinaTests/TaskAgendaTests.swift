import XCTest
@testable import Nina

@MainActor
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

    func testAMissedDailyTaskReadsAsLateSinceItsLastOccurrence() {
        var daily = task(dueAt: date(year: 2026, month: 8, day: 5, hour: 21, minute: 0))
        daily.recurrence = .daily

        let displayed = daily.displayDate(relativeTo: now, calendar: calendar)

        XCTAssertEqual(displayed, date(year: 2026, month: 8, day: 7, hour: 21, minute: 0))
        XCTAssertFalse(daily.isDue(on: now, calendar: calendar))
        XCTAssertTrue(daily.belongsOnAgenda(for: now, calendar: calendar))
        XCTAssertTrue(daily.isOverdue(relativeTo: now, calendar: calendar))
    }

    func testAMissedWeeklyTaskReadsAsLateSinceThisWeeksOccurrenceNotTheFirstMissedOne() {
        var weekly = task(dueAt: date(year: 2026, month: 7, day: 13, hour: 9, minute: 0))
        weekly.recurrence = .weekly

        XCTAssertEqual(
            weekly.displayDate(relativeTo: now, calendar: calendar),
            date(year: 2026, month: 8, day: 3, hour: 9, minute: 0)
        )
        XCTAssertTrue(weekly.isOverdue(relativeTo: now, calendar: calendar))
    }

    func testARecurringTaskMarkedDoneForTodayShowsTheNextOccurrenceAndIsNotLate() {
        var daily = task(dueAt: date(year: 2026, month: 8, day: 8, hour: 21, minute: 0))
        daily.recurrence = .daily

        XCTAssertEqual(
            daily.displayDate(relativeTo: now, calendar: calendar),
            date(year: 2026, month: 8, day: 8, hour: 21, minute: 0)
        )
        XCTAssertTrue(daily.isDue(on: now, calendar: calendar))
        XCTAssertFalse(daily.isOverdue(relativeTo: now, calendar: calendar))
    }

    func testTheScreenAndTheNotificationSchedulerAgreeOnACurrentRecurringTask() {
        var daily = task(dueAt: date(year: 2026, month: 8, day: 8, hour: 21, minute: 0))
        daily.recurrence = .daily

        let displayed = daily.displayDate(relativeTo: now, calendar: calendar)
        let nextScheduled = daily.scheduledOccurrences(after: now, limit: 1, calendar: calendar).first

        XCTAssertEqual(displayed, nextScheduled)
    }

    func testAMissedRecurringTaskStillSchedulesItsNextOccurrenceWhileTheScreenShowsTheMissedOne() {
        var daily = task(dueAt: date(year: 2026, month: 8, day: 5, hour: 21, minute: 0))
        daily.recurrence = .daily

        let nextScheduled = daily.scheduledOccurrences(after: now, limit: 1, calendar: calendar).first

        XCTAssertEqual(nextScheduled, date(year: 2026, month: 8, day: 8, hour: 21, minute: 0))
        XCTAssertNotEqual(daily.displayDate(relativeTo: now, calendar: calendar), nextScheduled)
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

    func testClosingATaskStampsWhenItClosedAndReopeningClearsIt() {
        let store = AppStore(remoteHomeBackend: nil, ninaEngine: MockNinaEngine())
        guard let open = store.tasks.first(where: { !$0.isDone && $0.recurrence == .none }) else {
            return XCTFail("PreviewData should seed at least one open non-recurring task.")
        }

        store.toggleTask(open)
        let closed = store.tasks.first { $0.id == open.id }
        // Nothing else in the app knows when a task closed: the completed list and
        // the day-cleared count both read this field.
        XCTAssertNotNil(closed?.completedAt)
        XCTAssertEqual(closed?.isDone, true)

        if let closed { store.toggleTask(closed) }
        let reopened = store.tasks.first { $0.id == open.id }
        XCTAssertNil(reopened?.completedAt)
        XCTAssertEqual(reopened?.isDone, false)
    }

    func testCompletingOffersAnUndoAndUndoingReopensTheTask() {
        let store = AppStore(remoteHomeBackend: nil, ninaEngine: MockNinaEngine())
        guard let open = store.tasks.first(where: { !$0.isDone && $0.recurrence == .none }) else {
            return XCTFail("PreviewData should seed at least one open non-recurring task.")
        }

        store.toggleTask(open)
        XCTAssertEqual(store.undoableCompletionID, open.id)

        store.undoLastCompletion()

        // Closing something is the action people take by accident on a list.
        XCTAssertEqual(store.tasks.first { $0.id == open.id }?.isDone, false)
        XCTAssertNil(store.undoableCompletionID)
    }

    func testReopeningATaskOffersNoUndoBecauseNothingWasClosed() {
        let store = AppStore(remoteHomeBackend: nil, ninaEngine: MockNinaEngine())
        guard let open = store.tasks.first(where: { !$0.isDone && $0.recurrence == .none }) else {
            return XCTFail("PreviewData should seed at least one open non-recurring task.")
        }

        store.toggleTask(open)
        guard let closed = store.tasks.first(where: { $0.id == open.id }) else { return XCTFail() }
        store.toggleTask(closed)

        XCTAssertNil(store.undoableCompletionID)
    }

    func testMarkingAChildsTaskDoneNeitherOffersNorWithdrawsTheAppWideUndo() throws {
        try withIsolatedStore { store in
            let other = task(dueAt: date(year: 2026, month: 8, day: 8, hour: 18, minute: 0))
            var childs = task(dueAt: date(year: 2026, month: 8, day: 8, hour: 16, minute: 0))
            childs.title = "Dever de casa"
            store.tasks = [other, childs]

            store.toggleTask(other)
            XCTAssertEqual(store.undoableCompletionID, other.id)

            let mark = store.markChildTaskDone(childs.id, now: now, calendar: calendar)

            XCTAssertNotNil(mark)
            XCTAssertEqual(store.tasks.first { $0.id == childs.id }?.isDone, true)
            // The undo toast sits under the child's cover; the adult's own undo must survive it.
            XCTAssertEqual(store.undoableCompletionID, other.id)
        }
    }

    func testReopeningAChildsRepeatingTaskPutsItBackOnTheOccurrenceItLeft() throws {
        try withIsolatedStore { store in
            var daily = task(dueAt: now.addingTimeInterval(2 * 60 * 60))
            daily.recurrence = .daily
            daily.dueLabel = "Hoje, 12:00"
            store.tasks = [daily]

            let mark = try XCTUnwrap(store.markChildTaskDone(daily.id, now: now, calendar: calendar))
            XCTAssertTrue(store.reopenChildTask(mark))

            let reopened = try XCTUnwrap(store.tasks.first { $0.id == daily.id })
            XCTAssertEqual(reopened.dueAt, daily.dueAt)
            XCTAssertEqual(reopened.dueLabel, daily.dueLabel)
            XCTAssertEqual(reopened.snoozedUntil, daily.snoozedUntil)
            XCTAssertTrue(reopened.belongsOnAgenda(for: now, calendar: calendar))
            XCTAssertEqual(reopened.version, daily.version + 2)
        }
    }

    func testReopeningAChildsTaskIsRefusedOnceTheTaskChangedElsewhere() throws {
        try withIsolatedStore { store in
            let oneOff = task(dueAt: date(year: 2026, month: 8, day: 8, hour: 16, minute: 0))
            store.tasks = [oneOff]

            let staleMark = try XCTUnwrap(store.markChildTaskDone(oneOff.id, now: now, calendar: calendar))
            store.tasks[0].isDone = false
            let changedElsewhere = store.tasks[0]

            XCTAssertFalse(store.reopenChildTask(staleMark))
            XCTAssertEqual(store.tasks[0], changedElsewhere)

            let mark = try XCTUnwrap(store.markChildTaskDone(oneOff.id, now: now, calendar: calendar))
            XCTAssertTrue(store.reopenChildTask(mark))
            XCTAssertFalse(store.reopenChildTask(mark))
        }
    }

    private func withIsolatedStore(_ body: (AppStore) throws -> Void) throws {
        let suiteName = "TaskAgendaTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "nina-task-agenda-tests-\(UUID().uuidString)",
            isDirectory: true
        )
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: directory)
        }
        let store = AppStore(
            defaults: defaults,
            privateDataStore: ProtectedLocalDataStore(directoryURL: directory),
            remoteHomeBackend: nil,
            ninaEngine: MockNinaEngine(),
            notificationScheduler: NoopHomeNotificationScheduler()
        )
        try body(store)
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
