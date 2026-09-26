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

    func testEveryRowOfTheSharedDueTableResolvesToTheSameInstantOnThePhoneAsOnTheServer() {
        for (label, nowText, expected) in Self.sharedDueTable {
            XCTAssertEqual(
                dueInstant(label, at: nowText),
                expected.map { iso($0) },
                "\(label) at \(nowText)"
            )
        }
    }

    func testDiaTwentySaidOnTheTwentiethIsTodayOnlyWhileItsHourIsStillAhead() {
        XCTAssertEqual(dueInstant("dia 20", at: "2026-09-20T08:00:00-03:00"), iso("2026-09-20T09:00:00-03:00"))
        XCTAssertEqual(dueInstant("dia 20", at: "2026-09-20T10:00:00-03:00"), iso("2026-10-20T09:00:00-03:00"))
        XCTAssertEqual(
            dueInstant("dia 20 às 18h", at: "2026-09-20T10:00:00-03:00"),
            iso("2026-09-20T18:00:00-03:00")
        )
        XCTAssertEqual(
            dueInstant("dia 20 às 18h", at: "2026-09-20T19:00:00-03:00"),
            iso("2026-10-20T18:00:00-03:00")
        )
    }

    func testDayThirtyOneSkipsEveryMonthThatHasNoThirtyFirstAcrossTheYear() {
        XCTAssertEqual(dueInstant("dia 31", at: "2026-10-31T10:00:00-03:00"), iso("2026-12-31T09:00:00-03:00"))
        XCTAssertEqual(dueInstant("dia 31", at: "2026-12-31T10:00:00-03:00"), iso("2027-01-31T09:00:00-03:00"))
        XCTAssertEqual(dueInstant("dia 31", at: "2027-01-31T10:00:00-03:00"), iso("2027-03-31T09:00:00-03:00"))
        XCTAssertNil(dueInstant("dia 31 do mês que vem", at: "2026-10-10T10:15:00-03:00"))
    }

    func testAWeekdayIsTodayOnlyWhileItsHourIsStillAheadAndQueVemIsNeverToday() {
        let saturdayMorning = "2026-09-26T10:15:00-03:00"

        XCTAssertEqual(dueInstant("sábado às 18h", at: saturdayMorning), iso("2026-09-26T18:00:00-03:00"))
        XCTAssertEqual(dueInstant("sábado às 8h", at: saturdayMorning), iso("2026-10-03T08:00:00-03:00"))
        XCTAssertEqual(
            dueInstant("sábado que vem às 18h", at: saturdayMorning),
            iso("2026-10-03T18:00:00-03:00")
        )
        XCTAssertEqual(dueInstant("sexta", at: "2026-10-02T08:00:00-03:00"), iso("2026-10-02T09:00:00-03:00"))
        XCTAssertEqual(dueInstant("sexta", at: "2026-10-02T10:00:00-03:00"), iso("2026-10-09T09:00:00-03:00"))
        XCTAssertEqual(
            dueInstant("próxima sexta", at: "2026-10-02T08:00:00-03:00"),
            iso("2026-10-09T09:00:00-03:00")
        )
    }

    func testTodayWithoutATimeOnceNineHasPassedIsFiveMinutesFromConfirmation() {
        let saturdayMorning = "2026-09-26T10:15:00-03:00"

        XCTAssertEqual(dueInstant("hoje", at: saturdayMorning), iso("2026-09-26T10:20:00-03:00"))
        XCTAssertEqual(dueInstant("26/09", at: saturdayMorning), iso("2026-09-26T10:20:00-03:00"))
        XCTAssertNil(dueInstant("hoje às 8h", at: saturdayMorning))
    }

    func testEveryLabelTheAppWritesReadsBackAsTheInstantItWasWrittenFor() {
        let now = iso("2026-09-26T10:15:00-03:00")
        let written: [(instant: Date, label: String)] = [
            (iso("2026-09-26T14:30:00-03:00"), "Hoje, 14:30"),
            (iso("2026-09-27T09:00:00-03:00"), "Amanhã, 09:00"),
            (iso("2026-10-20T09:00:00-03:00"), "20 out., 09:00")
        ]

        for entry in written {
            let label = AppStore.taskDueLabel(for: entry.instant, relativeTo: now, calendar: calendar)
            XCTAssertEqual(label, entry.label)
            XCTAssertEqual(
                AppStore.inferredDueAt(from: label, now: now, calendar: calendar),
                entry.instant,
                label
            )
        }
    }

    func testAnOrdinalAFractionOrAnArticleIsNeverReadAsADate() {
        let saturdayMorning = "2026-09-26T10:15:00-03:00"
        let phrases = [
            "pegar a segunda via do boleto",
            "Segunda via do boleto chegou, me lembre de pagar",
            "reunião da sexta série",
            "tomar 1/2 comprimido",
            "Reduza a dose para 1/2 comprimido",
            "pagar as 3 contas",
            "levar as 2 crianças amanhã"
        ]

        for phrase in phrases {
            XCTAssertNil(dueInstant(phrase, at: saturdayMorning), phrase)
        }
        XCTAssertEqual(dueInstant("dia 1/2", at: saturdayMorning), iso("2027-02-01T09:00:00-03:00"))
        XCTAssertEqual(dueInstant("na segunda", at: saturdayMorning), iso("2026-09-28T09:00:00-03:00"))
    }

    func testADurationAnIntervalOrADoseScheduleIsNeverReadAsAClockTime() {
        let phrases = [
            "A cada 8 horas",
            "Tomar o remédio a cada 8 horas",
            "Tomar amoxicilina de 8/8h",
            "de 8 em 8 horas",
            "jejum de 8 horas antes do exame amanhã",
            "me lembre daqui 2 horas",
            "Reunião de 2 horas amanhã"
        ]

        for phrase in phrases {
            XCTAssertNil(dueInstant(phrase, at: "2026-09-26T10:15:00-03:00"), phrase)
        }
    }

    func testADateWordTheReaderCannotPlaceRefusesRatherThanFallingBackToToday() {
        let phrases = [
            "Me lembra amanhã às 10 de pegar o bolo",
            "às 14h reunião sexta",
            "Semana que vem, 14h",
            "ontem às 10h",
            "Sex, 14h"
        ]

        for phrase in phrases {
            XCTAssertNil(dueInstant(phrase, at: "2026-09-26T10:15:00-03:00"), phrase)
        }
    }

    func testTwoDatesOrAPartOfTheDayWithoutAClockTimeResolveToNothingRatherThanAGuess() {
        let phrases = [
            "sexta ou sábado",
            "hoje e amanhã",
            "14h ou 15h",
            "de segunda a sexta às 7h",
            "hoje à noite",
            "sexta à tarde",
            "amanhã de madrugada",
            "Sexta, 03/10, 14h"
        ]

        for phrase in phrases {
            XCTAssertNil(dueInstant(phrase, at: "2026-09-26T10:15:00-03:00"), phrase)
        }
        XCTAssertEqual(
            dueInstant("Sexta, 02/10, 14h", at: "2026-09-26T10:15:00-03:00"),
            iso("2026-10-02T14:00:00-03:00")
        )
    }

    func testAPartOfTheDayAfterANamedDateKeepsTheDateAndNeverBecomesItsHour() {
        let saturdayMorning = "2026-09-26T10:15:00-03:00"

        XCTAssertEqual(dueInstant("dia 10 de manhã", at: saturdayMorning), iso("2026-10-10T09:00:00-03:00"))
        XCTAssertEqual(dueInstant("20/10 de manhã", at: saturdayMorning), iso("2026-10-20T09:00:00-03:00"))
        XCTAssertEqual(dueInstant("8h30 da noite", at: saturdayMorning), iso("2026-09-26T20:30:00-03:00"))
        XCTAssertNil(dueInstant("dia 20 de noite", at: saturdayMorning))
        XCTAssertNil(dueInstant("dia 5 da tarde", at: saturdayMorning))
    }

    func testAnOrdinalWeekdayReadsAsThatWeekdayAndAnOrdinalNounNeverDoes() {
        let saturdayMorning = "2026-09-26T10:15:00-03:00"

        XCTAssertEqual(dueInstant("6ª feira às 14h", at: saturdayMorning), iso("2026-10-02T14:00:00-03:00"))
        XCTAssertEqual(dueInstant("5ª, 19h", at: saturdayMorning), iso("2026-10-01T19:00:00-03:00"))
        XCTAssertEqual(dueInstant("2ª-feira, 10h", at: saturdayMorning), iso("2026-09-28T10:00:00-03:00"))
        for phrase in ["2ª via do boleto", "3ª dose da vacina", "a 4ª reunião do condomínio"] {
            XCTAssertNil(dueInstant(phrase, at: saturdayMorning), phrase)
        }
    }

    func testARangeAnAlternativeOrABareHourFromOneToSevenResolvesToNothing() {
        let saturdayMorning = "2026-09-26T10:15:00-03:00"
        let phrases = [
            "dia 5 ou 6",
            "dia 20 e 21",
            "entre 14 e 16h",
            "das 10 às 12h",
            "14h 30",
            "Buscar as crianças às 5"
        ]

        for phrase in phrases {
            XCTAssertNil(dueInstant(phrase, at: saturdayMorning), phrase)
        }
        XCTAssertEqual(dueInstant("às 5 da tarde", at: saturdayMorning), iso("2026-09-26T17:00:00-03:00"))
        XCTAssertEqual(dueInstant("meio-dia e meia", at: saturdayMorning), iso("2026-09-26T12:30:00-03:00"))
        XCTAssertEqual(
            dueInstant("comprar 1 ou 2 pacotes amanhã", at: saturdayMorning),
            iso("2026-09-27T09:00:00-03:00")
        )
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

    private func dueInstant(_ label: String, at nowText: String) -> Date? {
        AppStore.inferredDueAt(from: label, now: iso(nowText), calendar: calendar)
    }

    private func iso(_ text: String) -> Date {
        ISO8601DateFormatter().date(from: text) ?? .distantPast
    }

    private static let sharedDueTable: [(String, String, String?)] = [
        ("Dia 20", "2026-09-26T10:15:00-03:00", "2026-10-20T09:00:00-03:00"),
        ("dia 26", "2026-09-26T10:15:00-03:00", "2026-10-26T09:00:00-03:00"),
        ("dia 26 às 18h", "2026-09-26T10:15:00-03:00", "2026-09-26T18:00:00-03:00"),
        ("dia 26", "2026-09-26T08:30:00-03:00", "2026-09-26T09:00:00-03:00"),
        ("dia 26 às 8h", "2026-09-26T10:15:00-03:00", "2026-10-26T08:00:00-03:00"),
        ("dia 31", "2026-09-26T10:15:00-03:00", "2026-10-31T09:00:00-03:00"),
        ("dia 31", "2026-10-31T10:00:00-03:00", "2026-12-31T09:00:00-03:00"),
        ("dia 31", "2026-12-31T10:00:00-03:00", "2027-01-31T09:00:00-03:00"),
        ("dia 30", "2027-01-31T10:00:00-03:00", "2027-03-30T09:00:00-03:00"),
        ("dia 5", "2026-12-20T10:00:00-03:00", "2027-01-05T09:00:00-03:00"),
        ("dia 20", "2026-09-20T23:59:00-03:00", "2026-10-20T09:00:00-03:00"),
        ("dia 20 do mês que vem", "2026-09-26T10:15:00-03:00", "2026-10-20T09:00:00-03:00"),
        ("sexta às 14h", "2026-09-26T10:15:00-03:00", "2026-10-02T14:00:00-03:00"),
        ("Sexta, 14h", "2026-09-26T10:15:00-03:00", "2026-10-02T14:00:00-03:00"),
        ("sexta 14h30", "2026-09-26T10:15:00-03:00", "2026-10-02T14:30:00-03:00"),
        ("sexta-feira", "2026-09-26T10:15:00-03:00", "2026-10-02T09:00:00-03:00"),
        ("me lembre sexta as 18", "2026-09-26T10:15:00-03:00", "2026-10-02T18:00:00-03:00"),
        ("Sexta, 02/10, 14h", "2026-09-26T10:15:00-03:00", "2026-10-02T14:00:00-03:00"),
        ("sábado", "2026-09-26T10:15:00-03:00", "2026-10-03T09:00:00-03:00"),
        ("sábado às 18h", "2026-09-26T10:15:00-03:00", "2026-09-26T18:00:00-03:00"),
        ("sabado 8h", "2026-09-26T10:15:00-03:00", "2026-10-03T08:00:00-03:00"),
        ("sábado que vem às 18h", "2026-09-26T10:15:00-03:00", "2026-10-03T18:00:00-03:00"),
        ("domingo", "2026-09-26T10:15:00-03:00", "2026-09-27T09:00:00-03:00"),
        ("na segunda", "2026-09-26T10:15:00-03:00", "2026-09-28T09:00:00-03:00"),
        ("deixa pra sexta", "2026-09-26T10:15:00-03:00", "2026-10-02T09:00:00-03:00"),
        ("a reunião de sexta", "2026-09-26T10:15:00-03:00", "2026-10-02T09:00:00-03:00"),
        ("às 8 de segunda-feira", "2026-09-26T10:15:00-03:00", "2026-09-28T08:00:00-03:00"),
        ("sexta", "2026-10-02T08:00:00-03:00", "2026-10-02T09:00:00-03:00"),
        ("próxima sexta", "2026-10-02T08:00:00-03:00", "2026-10-09T09:00:00-03:00"),
        ("quinta-feira que vem", "2026-10-01T08:00:00-03:00", "2026-10-08T09:00:00-03:00"),
        ("amanhã", "2026-09-26T10:15:00-03:00", "2026-09-27T09:00:00-03:00"),
        ("amanhã 9h", "2026-09-26T10:15:00-03:00", "2026-09-27T09:00:00-03:00"),
        ("Amanhã, 07:30", "2026-09-26T10:15:00-03:00", "2026-09-27T07:30:00-03:00"),
        ("amanhã de manhã", "2026-09-26T10:15:00-03:00", "2026-09-27T09:00:00-03:00"),
        ("amanhã às 10 de manhã", "2026-09-26T10:15:00-03:00", "2026-09-27T10:00:00-03:00"),
        ("às 10 amanhã", "2026-09-26T10:15:00-03:00", "2026-09-27T10:00:00-03:00"),
        ("amanhã às 8 da noite", "2026-09-26T10:15:00-03:00", "2026-09-27T20:00:00-03:00"),
        ("amanhã", "2026-12-31T23:30:00-03:00", "2027-01-01T09:00:00-03:00"),
        ("depois de amanhã", "2026-09-26T10:15:00-03:00", "2026-09-28T09:00:00-03:00"),
        ("hoje às 14h", "2026-09-26T10:15:00-03:00", "2026-09-26T14:00:00-03:00"),
        ("Hoje, 14:30", "2026-09-26T10:15:00-03:00", "2026-09-26T14:30:00-03:00"),
        ("hoje", "2026-09-26T08:00:00-03:00", "2026-09-26T09:00:00-03:00"),
        ("20/10", "2026-09-26T10:15:00-03:00", "2026-10-20T09:00:00-03:00"),
        ("20/10/2026", "2026-09-26T10:15:00-03:00", "2026-10-20T09:00:00-03:00"),
        ("20/10 às 14:30", "2026-09-26T10:15:00-03:00", "2026-10-20T14:30:00-03:00"),
        ("12/08, 09:00", "2026-09-26T10:15:00-03:00", "2027-08-12T09:00:00-03:00"),
        ("dia 1/2", "2026-09-26T10:15:00-03:00", "2027-02-01T09:00:00-03:00"),
        ("20 de outubro", "2026-09-26T10:15:00-03:00", "2026-10-20T09:00:00-03:00"),
        ("20 out., 09:00", "2026-09-26T10:15:00-03:00", "2026-10-20T09:00:00-03:00"),
        ("1º de novembro", "2026-09-26T10:15:00-03:00", "2026-11-01T09:00:00-03:00"),
        ("29 de fevereiro", "2026-09-26T10:15:00-03:00", "2028-02-29T09:00:00-03:00"),
        ("14h", "2026-09-26T10:15:00-03:00", "2026-09-26T14:00:00-03:00"),
        ("14hs", "2026-09-26T10:15:00-03:00", "2026-09-26T14:00:00-03:00"),
        ("14h30min", "2026-09-26T10:15:00-03:00", "2026-09-26T14:30:00-03:00"),
        ("9h", "2026-09-26T10:15:00-03:00", "2026-09-27T09:00:00-03:00"),
        ("14:30", "2026-09-26T10:15:00-03:00", "2026-09-26T14:30:00-03:00"),
        ("14h30", "2026-09-26T10:15:00-03:00", "2026-09-26T14:30:00-03:00"),
        ("meio-dia", "2026-09-26T10:15:00-03:00", "2026-09-26T12:00:00-03:00"),
        ("às 9", "2026-09-26T10:15:00-03:00", "2026-09-27T09:00:00-03:00"),
        ("as 9 no pediatra", "2026-09-26T10:15:00-03:00", "2026-09-27T09:00:00-03:00"),
        ("às 14 horas", "2026-09-26T10:15:00-03:00", "2026-09-26T14:00:00-03:00"),
        ("2 da tarde", "2026-09-26T10:15:00-03:00", "2026-09-26T14:00:00-03:00"),
        ("dia 20 as 18", "2026-09-26T10:15:00-03:00", "2026-10-20T18:00:00-03:00"),
        ("daqui 3 dias", "2026-09-26T10:15:00-03:00", "2026-09-29T09:00:00-03:00"),
        ("daqui a 3 dias", "2026-09-26T10:15:00-03:00", "2026-09-29T09:00:00-03:00"),
        ("Daqui 8 dias", "2026-09-26T10:15:00-03:00", "2026-10-04T09:00:00-03:00"),
        ("Me lembre de pagar o boleto dia 20", "2026-09-26T10:15:00-03:00", "2026-10-20T09:00:00-03:00"),
        ("Me lembre da consulta na sexta às 14h.", "2026-09-26T10:15:00-03:00", "2026-10-02T14:00:00-03:00"),
        ("O comunicado da escola diz reunião dia 25 às 18h.", "2026-09-26T10:15:00-03:00", "2026-10-25T18:00:00-03:00"),
        ("Crie uma tarefa para o Heitor separar os documentos amanhã às 9h.", "2026-09-26T10:15:00-03:00", "2026-09-27T09:00:00-03:00"),
        ("dia 10 de manhã", "2026-09-26T10:15:00-03:00", "2026-10-10T09:00:00-03:00"),
        ("20/10 de manhã", "2026-09-26T10:15:00-03:00", "2026-10-20T09:00:00-03:00"),
        ("dia 10 às 8 da noite", "2026-09-26T10:15:00-03:00", "2026-10-10T20:00:00-03:00"),
        ("8h30 da noite", "2026-09-26T10:15:00-03:00", "2026-09-26T20:30:00-03:00"),
        ("sexta 1h30 da tarde", "2026-09-26T10:15:00-03:00", "2026-10-02T13:30:00-03:00"),
        ("às 5 da tarde", "2026-09-26T10:15:00-03:00", "2026-09-26T17:00:00-03:00"),
        ("meio-dia e meia", "2026-09-26T10:15:00-03:00", "2026-09-26T12:30:00-03:00"),
        ("6ª feira às 14h", "2026-09-26T10:15:00-03:00", "2026-10-02T14:00:00-03:00"),
        ("5ª, 19h", "2026-09-26T10:15:00-03:00", "2026-10-01T19:00:00-03:00"),
        ("reunião na escola 5ª às 19h", "2026-09-26T10:15:00-03:00", "2026-10-01T19:00:00-03:00"),
        ("2ª-feira, 10h", "2026-09-26T10:15:00-03:00", "2026-09-28T10:00:00-03:00"),
        ("5ª feira que vem", "2026-10-01T08:00:00-03:00", "2026-10-08T09:00:00-03:00"),
        ("2ª via do boleto, pagar amanhã", "2026-09-26T10:15:00-03:00", "2026-09-27T09:00:00-03:00"),
        ("comprar 1 ou 2 pacotes amanhã", "2026-09-26T10:15:00-03:00", "2026-09-27T09:00:00-03:00"),
        ("entre em contato com a escola amanhã", "2026-09-26T10:15:00-03:00", "2026-09-27T09:00:00-03:00"),
        ("dia 31 do mês que vem", "2026-10-10T10:15:00-03:00", nil),
        ("dia 32", "2026-09-26T10:15:00-03:00", nil),
        ("dia 0", "2026-09-26T10:15:00-03:00", nil),
        ("hoje às 8h", "2026-09-26T10:15:00-03:00", nil),
        ("10/09/2026", "2026-09-26T10:15:00-03:00", nil),
        ("31/02", "2026-09-26T10:15:00-03:00", nil),
        ("tomar 1/2 comprimido", "2026-09-26T10:15:00-03:00", nil),
        ("Reduza a dose para 1/2 comprimido", "2026-09-26T10:15:00-03:00", nil),
        ("25h", "2026-09-26T10:15:00-03:00", nil),
        ("hoje à noite", "2026-09-26T10:15:00-03:00", nil),
        ("sexta à tarde", "2026-09-26T10:15:00-03:00", nil),
        ("Sem data", "2026-09-26T10:15:00-03:00", nil),
        ("Esta semana", "2026-09-26T10:15:00-03:00", nil),
        ("Semana que vem", "2026-09-26T10:15:00-03:00", nil),
        ("Semana que vem, 14h", "2026-09-26T10:15:00-03:00", nil),
        ("mais para frente", "2026-09-26T10:15:00-03:00", nil),
        ("quando der", "2026-09-26T10:15:00-03:00", nil),
        ("sexta ou sábado", "2026-09-26T10:15:00-03:00", nil),
        ("hoje e amanhã", "2026-09-26T10:15:00-03:00", nil),
        ("14h ou 15h", "2026-09-26T10:15:00-03:00", nil),
        ("de segunda a sexta às 7h", "2026-09-26T10:15:00-03:00", nil),
        ("pegar a segunda via do boleto", "2026-09-26T10:15:00-03:00", nil),
        ("Segunda via do boleto chegou, me lembre de pagar", "2026-09-26T10:15:00-03:00", nil),
        ("reunião da sexta série", "2026-09-26T10:15:00-03:00", nil),
        ("às 14h reunião sexta", "2026-09-26T10:15:00-03:00", nil),
        ("pagar as 3 contas", "2026-09-26T10:15:00-03:00", nil),
        ("levar as 2 crianças amanhã", "2026-09-26T10:15:00-03:00", nil),
        ("Me lembra amanhã às 10 de pegar o bolo", "2026-09-26T10:15:00-03:00", nil),
        ("Tomar o remédio a cada 8 horas", "2026-09-26T10:15:00-03:00", nil),
        ("Tomar amoxicilina de 8/8h", "2026-09-26T10:15:00-03:00", nil),
        ("de 8 em 8 horas", "2026-09-26T10:15:00-03:00", nil),
        ("jejum de 8 horas antes do exame amanhã", "2026-09-26T10:15:00-03:00", nil),
        ("Reunião de 2 horas amanhã", "2026-09-26T10:15:00-03:00", nil),
        ("me lembre daqui 2 horas", "2026-09-26T10:15:00-03:00", nil),
        ("ontem às 10h", "2026-09-26T10:15:00-03:00", nil),
        ("Sex, 14h", "2026-09-26T10:15:00-03:00", nil),
        ("Precisamos limpar a geladeira neste fim de semana.", "2026-09-26T10:15:00-03:00", nil),
        ("A receita diz uma dose de manhã. Pode organizar um lembrete?", "2026-09-26T10:15:00-03:00", nil),
        ("dia 20 de noite", "2026-09-26T10:15:00-03:00", nil),
        ("dia 5 da tarde", "2026-09-26T10:15:00-03:00", nil),
        ("2ª via do boleto", "2026-09-26T10:15:00-03:00", nil),
        ("3ª dose da vacina", "2026-09-26T10:15:00-03:00", nil),
        ("a 4ª reunião do condomínio", "2026-09-26T10:15:00-03:00", nil),
        ("Buscar as crianças às 5", "2026-09-26T10:15:00-03:00", nil),
        ("dia 5 ou 6", "2026-09-26T10:15:00-03:00", nil),
        ("dia 20 e 21", "2026-09-26T10:15:00-03:00", nil),
        ("entre 14 e 16h", "2026-09-26T10:15:00-03:00", nil),
        ("das 10 às 12h", "2026-09-26T10:15:00-03:00", nil),
        ("14h 30", "2026-09-26T10:15:00-03:00", nil),
    ]
}
