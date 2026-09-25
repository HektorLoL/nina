import CoreGraphics
import PDFKit
import XCTest
@testable import Nina

@MainActor
final class ChildDayTests: XCTestCase {
    private var calendar: Calendar!
    private var now: Date!
    private var pedro: HouseholdMember!
    private var heitor: HouseholdMember!
    private var nina: HouseholdMember!
    private var members: [HouseholdMember]!

    override func setUp() {
        super.setUp()
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = TimeZone(identifier: "America/Sao_Paulo") ?? .gmt
        calendar = gregorian
        now = date(2026, 9, 25, 10, 0)
        pedro = HouseholdMember(
            name: "Pedro Henrique",
            relationship: "Filho",
            role: .child,
            tone: .sky,
            taskCount: 0,
            memoryNote: ""
        )
        heitor = HouseholdMember(
            name: "Heitor",
            relationship: "Pai",
            role: .adult,
            tone: .mint,
            taskCount: 0,
            memoryNote: ""
        )
        nina = HouseholdMember(
            name: "Nina",
            relationship: "IA da casa",
            role: .assistant,
            tone: .lavender,
            taskCount: 0,
            memoryNote: ""
        )
        members = [heitor, pedro, nina]
    }

    override func tearDown() {
        calendar = nil
        now = nil
        pedro = nil
        heitor = nil
        nina = nil
        members = nil
        super.tearDown()
    }

    func testTheChildsListHoldsOnlyTheirOwnOpenTasksForTodayIncludingLateOnes() {
        let today = task("Dever de casa", owner: pedro, dueAt: date(2026, 9, 25, 16, 0))
        let lateOneOff = task("Guardar os brinquedos", owner: pedro, dueAt: date(2026, 9, 24, 19, 0))
        let missedDaily = task(
            "Escovar os dentes",
            owner: pedro,
            dueAt: date(2026, 9, 24, 21, 0),
            recurrence: .daily
        )
        var legacy = task("Regar a planta", owner: nil, dueAt: date(2026, 9, 25, 12, 0))
        legacy.owner = " pédro henrique "
        let tomorrow = task("Arrumar a mochila", owner: pedro, dueAt: date(2026, 9, 26, 8, 0))
        let done = task("Tomar banho", owner: pedro, dueAt: date(2026, 9, 25, 9, 0), isDone: true)
        let seed = task("Aprender a nadar", owner: pedro, dueAt: date(2026, 9, 25, 9, 0), kind: .seed)
        let undated = task("Ler um livro", owner: pedro, dueAt: nil)
        let heitors = task("Pagar a luz", owner: heitor, dueAt: date(2026, 9, 25, 11, 0))
        var house = task("Lavar a louça", owner: nil, dueAt: date(2026, 9, 25, 13, 0))
        house.ownerMemberID = pedro.id

        let listed = ChildDay.tasks(
            for: pedro,
            in: [today, lateOneOff, missedDaily, legacy, tomorrow, done, seed, undated, heitors, house],
            members: members,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(Set(listed.map(\.id)), [today.id, lateOneOff.id, missedDaily.id, legacy.id])
    }

    func testTheListRunsFromWhatIsLateToWhatComesLastThenByTitle() {
        let expected = orderedDay()

        let listed = ChildDay.tasks(
            for: pedro,
            in: [expected[3], expected[1], expected[2], expected[0]],
            members: members,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(listed.map(\.title), [
            "Guardar os brinquedos",
            "Escovar os dentes",
            "Dever de casa",
            "Regar a planta"
        ])
    }

    func testATaskDueTodayShowsOnlyItsHourEvenWhenItIsAlreadyLate() {
        let later = task("Dever de casa", owner: pedro, dueAt: date(2026, 9, 25, 16, 0))
        let alreadyLate = task("Tomar café", owner: pedro, dueAt: date(2026, 9, 25, 8, 0))

        XCTAssertEqual(ChildDay.timeLabel(for: later, now: now, calendar: calendar), "16:00")
        XCTAssertEqual(ChildDay.timeLabel(for: alreadyLate, now: now, calendar: calendar), "08:00")
    }

    func testAMissedDailyTaskShowsTodaysHourNotYesterdaysLateness() {
        let daily = task(
            "Escovar os dentes",
            owner: pedro,
            dueAt: date(2026, 9, 24, 21, 0),
            recurrence: .daily
        )

        XCTAssertEqual(ChildDay.timeLabel(for: daily, now: now, calendar: calendar), "21:00")
    }

    func testATaskCarriedOverFromAnEarlierDayShowsNoHour() {
        let carried = task("Guardar os brinquedos", owner: pedro, dueAt: date(2026, 9, 24, 19, 0))

        XCTAssertNil(ChildDay.timeLabel(for: carried, now: now, calendar: calendar))
    }

    func testTheDateLineReadsTheWayABrazilianFridgeListDoes() {
        XCTAssertEqual(ChildDay.dateLine(for: now, calendar: calendar), "sexta-feira, 25 de setembro")
    }

    func testTheChildIsCalledByTheFirstWordOfTheProfileName() {
        let ana = HouseholdMember(
            name: " Ana ",
            relationship: "Filha",
            role: .child,
            tone: .amber,
            taskCount: 0,
            memoryNote: ""
        )

        XCTAssertEqual(ChildDay.displayName(for: pedro, among: members), "Pedro")
        XCTAssertEqual(ChildDay.displayName(for: ana, among: members + [ana]), "Ana")
    }

    func testTwoChildrenWhoShareAFirstNameGetListsThatCanBeToldApart() {
        let mariaClara = child("Maria Clara")
        let mariaEduarda = child("Maria Eduarda")
        let household = [heitor!, mariaClara, mariaEduarda, nina!]
        let dateLine = ChildDay.dateLine(for: now, calendar: calendar)

        let clara = ChildDay.displayName(for: mariaClara, among: household)
        let eduarda = ChildDay.displayName(for: mariaEduarda, among: household)

        XCTAssertEqual(clara, "Maria Clara")
        XCTAssertEqual(eduarda, "Maria Eduarda")
        XCTAssertNotEqual(
            ChildDay.heading(name: clara, dateLine: dateLine),
            ChildDay.heading(name: eduarda, dateLine: dateLine)
        )
        XCTAssertNotEqual(
            ChildDay.shareText(name: clara, dateLine: dateLine, rows: []),
            ChildDay.shareText(name: eduarda, dateLine: dateLine, rows: [])
        )
    }

    func testAChildWhoSharesAFirstNameWithAParentIsCalledByEnoughOfTheirNameToTellThemApart() {
        let joao = HouseholdMember(
            name: "Joao",
            relationship: "Pai",
            role: .adult,
            tone: .mint,
            taskCount: 0,
            memoryNote: ""
        )
        let joaoPedro = child("João Pedro Castello")

        XCTAssertEqual(ChildDay.displayName(for: joaoPedro, among: [joao, joaoPedro, nina]), "João Pedro")
    }

    func testAChildWhoseFirstNameNoOtherPersonSharesIsCalledByItAlone() {
        let mariaEduarda = child("Maria Eduarda")
        let namedLikeNina = child("Nina Rosa")

        XCTAssertEqual(ChildDay.displayName(for: mariaEduarda, among: [heitor, mariaEduarda, nina]), "Maria")
        XCTAssertEqual(ChildDay.displayName(for: namedLikeNina, among: [heitor, namedLikeNina, nina]), "Nina")
    }

    func testMarkingAOneOffTaskDoneClosesItAndStampsWhen() {
        let oneOff = task("Dever de casa", owner: pedro, dueAt: date(2026, 9, 25, 16, 0))

        let marked = ChildDay.markedDone(oneOff, now: now, calendar: calendar)

        XCTAssertEqual(marked?.isDone, true)
        XCTAssertEqual(marked?.completedAt, now)
    }

    func testMarkingADailyTaskDoneBeforeItsTimeMovesItToTomorrowAndOffTodaysAgenda() throws {
        var daily = task(
            "Dar comida ao peixe",
            owner: pedro,
            dueAt: date(2026, 9, 25, 16, 0),
            recurrence: .daily
        )
        daily.snoozedUntil = date(2026, 9, 25, 17, 0)

        let marked = try XCTUnwrap(ChildDay.markedDone(daily, now: now, calendar: calendar))

        XCTAssertEqual(marked.dueAt, date(2026, 9, 26, 16, 0))
        XCTAssertEqual(marked.dueLabel, "Amanhã, 16:00")
        XCTAssertNil(marked.snoozedUntil)
        XCTAssertFalse(marked.isDone)
        XCTAssertFalse(marked.belongsOnAgenda(for: now, calendar: calendar))
    }

    func testMarkingAMissedDailyTaskDoneClosesTodaysOccurrenceTooSoNoAlertFiresTonight() throws {
        let early = date(2026, 9, 25, 6, 30)
        let daily = task(
            "Escovar os dentes",
            owner: pedro,
            dueAt: date(2026, 9, 24, 7, 0),
            recurrence: .daily
        )

        let marked = try XCTUnwrap(ChildDay.markedDone(daily, now: early, calendar: calendar))

        XCTAssertEqual(marked.dueAt, date(2026, 9, 26, 7, 0))
        XCTAssertEqual(
            marked.scheduledOccurrences(after: early, limit: 1, calendar: calendar).first,
            date(2026, 9, 26, 7, 0)
        )
    }

    func testMarkingAMissedWeeklyTaskOnItsDayMovesItToNextWeek() throws {
        let weekly = task(
            "Levar o lixo reciclável",
            owner: pedro,
            dueAt: date(2026, 9, 18, 21, 0),
            recurrence: .weekly
        )

        let marked = try XCTUnwrap(ChildDay.markedDone(weekly, now: now, calendar: calendar))

        XCTAssertEqual(marked.dueAt, date(2026, 10, 2, 21, 0))
    }

    func testASeedOrAClosedTaskCannotBeMarkedDone() {
        let seed = task("Aprender a nadar", owner: pedro, dueAt: nil, kind: .seed)
        let closed = task("Dever de casa", owner: pedro, dueAt: date(2026, 9, 25, 16, 0), isDone: true)

        XCTAssertNil(ChildDay.markedDone(seed, now: now, calendar: calendar))
        XCTAssertNil(ChildDay.markedDone(closed, now: now, calendar: calendar))
    }

    func testReopeningRestoresOnlyWhatTheMarkChanged() throws {
        var daily = task(
            "Escovar os dentes",
            owner: pedro,
            dueAt: date(2026, 9, 25, 8, 0),
            recurrence: .daily
        )
        daily.dueLabel = "Hoje, 08:00"
        daily.snoozedUntil = date(2026, 9, 25, 12, 0)
        var written = try XCTUnwrap(ChildDay.markedDone(daily, now: now, calendar: calendar))
        written.title = "Escovar os dentes depois do café"

        let reopenedDaily = ChildDay.reopened(written, restoring: daily)

        XCTAssertEqual(reopenedDaily.dueAt, daily.dueAt)
        XCTAssertEqual(reopenedDaily.dueLabel, daily.dueLabel)
        XCTAssertEqual(reopenedDaily.snoozedUntil, daily.snoozedUntil)
        XCTAssertEqual(reopenedDaily.title, "Escovar os dentes depois do café")

        let oneOff = task("Dever de casa", owner: pedro, dueAt: date(2026, 9, 25, 16, 0))
        let closed = try XCTUnwrap(ChildDay.markedDone(oneOff, now: now, calendar: calendar))

        let reopenedOneOff = ChildDay.reopened(closed, restoring: oneOff)

        XCTAssertFalse(reopenedOneOff.isDone)
        XCTAssertNil(reopenedOneOff.completedAt)
    }

    func testATappedTaskStaysInPlaceAsDoneInsteadOfLeavingTheList() throws {
        let first = task("Arrumar a cama", owner: pedro, dueAt: date(2026, 9, 25, 8, 0))
        let daily = task(
            "Dar comida ao peixe",
            owner: pedro,
            dueAt: date(2026, 9, 25, 12, 0),
            recurrence: .daily
        )
        let last = task("Dever de casa", owner: pedro, dueAt: date(2026, 9, 25, 16, 0))
        var tasks = [last, first, daily]
        var session = ChildDaySession(child: pedro, tasks: tasks, members: members, now: now, calendar: calendar)

        XCTAssertEqual(session.tap(on: daily.id, tasks: tasks, now: now), .markDone(daily.id))
        try markDone(daily.id, in: &tasks, session: &session, at: now)

        let rows = session.rows(child: pedro, tasks: tasks, members: members, now: now, calendar: calendar)
        XCTAssertEqual(rows.map(\.id), [first.id, daily.id, last.id])
        XCTAssertEqual(rows[1].state, .doneHere)
        XCTAssertEqual(rows[1].time, "12:00")
        XCTAssertEqual(rows[0].state, .open)
        XCTAssertEqual(rows[2].state, .open)
    }

    func testASecondTapOnADoneRepeatingRowReopensItAndNeverSkipsAnotherDay() throws {
        let daily = task(
            "Dar comida ao peixe",
            owner: pedro,
            dueAt: date(2026, 9, 25, 12, 0),
            recurrence: .daily
        )
        var tasks = [daily]
        var session = ChildDaySession(child: pedro, tasks: tasks, members: members, now: now, calendar: calendar)
        let mark = try markDone(daily.id, in: &tasks, session: &session, at: now)

        let secondTap = session.tap(on: daily.id, tasks: tasks, now: now.addingTimeInterval(5))

        XCTAssertEqual(secondTap, .reopen(mark))
        XCTAssertNotEqual(secondTap, .markDone(daily.id))
        XCTAssertEqual(ChildDay.reopened(mark.written, restoring: mark.baseline).dueAt, daily.dueAt)
    }

    func testATapWithinASecondOfTheLastChangeIsIgnoredSoADoubleTapCannotUndoItself() throws {
        let daily = task(
            "Dar comida ao peixe",
            owner: pedro,
            dueAt: date(2026, 9, 25, 12, 0),
            recurrence: .daily
        )
        var tasks = [daily]
        var session = ChildDaySession(child: pedro, tasks: tasks, members: members, now: now, calendar: calendar)
        let mark = try markDone(daily.id, in: &tasks, session: &session, at: now)

        XCTAssertEqual(session.tap(on: daily.id, tasks: tasks, now: now.addingTimeInterval(0.4)), .ignore)
        XCTAssertEqual(session.tap(on: daily.id, tasks: tasks, now: now.addingTimeInterval(1.2)), .reopen(mark))
    }

    func testATaskSomeoneElseClosedReadsDoneAndTheChildCannotReopenIt() {
        let oneOff = task("Dever de casa", owner: pedro, dueAt: date(2026, 9, 25, 16, 0))
        var tasks = [oneOff]
        let session = ChildDaySession(child: pedro, tasks: tasks, members: members, now: now, calendar: calendar)
        tasks[0].isDone = true
        tasks[0].completedAt = now
        tasks[0].version += 1

        let rows = session.rows(child: pedro, tasks: tasks, members: members, now: now, calendar: calendar)

        XCTAssertEqual(rows.map(\.state), [.doneElsewhere])
        XCTAssertEqual(session.tap(on: oneOff.id, tasks: tasks, now: now.addingTimeInterval(5)), .ignore)
    }

    func testARowReopenedOnAnotherPhoneReadsAsOpenAgain() throws {
        let oneOff = task("Dever de casa", owner: pedro, dueAt: date(2026, 9, 25, 16, 0))
        var tasks = [oneOff]
        var session = ChildDaySession(child: pedro, tasks: tasks, members: members, now: now, calendar: calendar)
        try markDone(oneOff.id, in: &tasks, session: &session, at: now)
        tasks[0].isDone = false
        tasks[0].completedAt = nil
        tasks[0].version = oneOff.version + 2

        let rows = session.rows(child: pedro, tasks: tasks, members: members, now: now, calendar: calendar)

        XCTAssertEqual(rows.map(\.state), [.open])
        XCTAssertEqual(
            session.tap(on: oneOff.id, tasks: tasks, now: now.addingTimeInterval(5)),
            .markDone(oneOff.id)
        )
    }

    func testAMarkSurvivesTheServersEchoOfTheSameWrite() throws {
        let daily = task(
            "Dar comida ao peixe",
            owner: pedro,
            dueAt: date(2026, 9, 25, 12, 0),
            recurrence: .daily
        )
        var tasks = [daily]
        var session = ChildDaySession(child: pedro, tasks: tasks, members: members, now: now, calendar: calendar)
        let mark = try markDone(daily.id, in: &tasks, session: &session, at: now)
        var echo = mark.written
        echo.version += 1
        echo.dueAt = echo.dueAt?.addingTimeInterval(0.0004)
        tasks[0] = echo

        XCTAssertTrue(mark.holds(on: echo))
        let rows = session.rows(child: pedro, tasks: tasks, members: members, now: now, calendar: calendar)
        XCTAssertEqual(rows.map(\.state), [.doneHere])
    }

    func testATaskDeletedMovedOrHandedToSomeoneElseLeavesTheListWithoutMovingTheOthers() {
        let first = task("Arrumar a cama", owner: pedro, dueAt: date(2026, 9, 25, 8, 0))
        let deleted = task("Dar comida ao peixe", owner: pedro, dueAt: date(2026, 9, 25, 9, 0))
        let handedOver = task("Guardar a louça", owner: pedro, dueAt: date(2026, 9, 25, 11, 0))
        let rescheduled = task("Ler um capítulo", owner: pedro, dueAt: date(2026, 9, 25, 14, 0))
        let last = task("Dever de casa", owner: pedro, dueAt: date(2026, 9, 25, 16, 0))
        var tasks = [first, deleted, handedOver, rescheduled, last]
        let session = ChildDaySession(child: pedro, tasks: tasks, members: members, now: now, calendar: calendar)
        XCTAssertEqual(session.order, [first.id, deleted.id, handedOver.id, rescheduled.id, last.id])

        tasks.removeAll { $0.id == deleted.id }
        if let index = tasks.firstIndex(where: { $0.id == handedOver.id }) {
            tasks[index].owner = heitor.name
            tasks[index].ownerMemberID = heitor.id
        }
        if let index = tasks.firstIndex(where: { $0.id == rescheduled.id }) {
            tasks[index].dueAt = date(2026, 9, 26, 9, 0)
            tasks[index].dueLabel = "Amanhã, 09:00"
        }

        let rows = session.rows(child: pedro, tasks: tasks, members: members, now: now, calendar: calendar)

        XCTAssertEqual(rows.map(\.id), [first.id, last.id])
    }

    func testATaskAssignedToTheChildWhileTheListIsOpenJoinsAtTheEnd() {
        let afternoon = task("Dever de casa", owner: pedro, dueAt: date(2026, 9, 25, 16, 0))
        var tasks = [afternoon]
        var session = ChildDaySession(child: pedro, tasks: tasks, members: members, now: now, calendar: calendar)
        let arrived = task("Arrumar a cama", owner: pedro, dueAt: date(2026, 9, 25, 8, 0))
        tasks.append(arrived)

        session.absorb(child: pedro, tasks: tasks, members: members, now: now, calendar: calendar)

        XCTAssertEqual(session.order, [afternoon.id, arrived.id])
        XCTAssertEqual(
            session.rows(child: pedro, tasks: tasks, members: members, now: now, calendar: calendar).map(\.id),
            [afternoon.id, arrived.id]
        )
    }

    func testTheListStartsOverWhenTheDayChanges() throws {
        let lateNight = date(2026, 9, 25, 23, 50)
        let daily = task(
            "Escovar os dentes",
            owner: pedro,
            dueAt: date(2026, 9, 24, 21, 0),
            recurrence: .daily
        )
        let tomorrowMorning = task("Levar o lanche", owner: pedro, dueAt: date(2026, 9, 26, 9, 0))
        var tasks = [daily, tomorrowMorning]
        var session = ChildDaySession(
            child: pedro,
            tasks: tasks,
            members: members,
            now: lateNight,
            calendar: calendar
        )
        XCTAssertEqual(session.order, [daily.id])
        try markDone(daily.id, in: &tasks, session: &session, at: lateNight)

        let afterMidnight = date(2026, 9, 26, 0, 10)
        session.absorb(child: pedro, tasks: tasks, members: members, now: afterMidnight, calendar: calendar)

        XCTAssertEqual(session.day, calendar.startOfDay(for: afterMidnight))
        XCTAssertTrue(session.marks.isEmpty)
        XCTAssertEqual(session.order, [tomorrowMorning.id, daily.id])
    }

    func testARowCarriesTheTitleTheHourAndTheGlyphAndNothingElse() throws {
        let homework = task(
            "Dever de casa",
            owner: pedro,
            dueAt: date(2026, 9, 25, 16, 0),
            subtitle: "Página 32",
            category: .school
        )
        let row = try XCTUnwrap(ChildDay.rows(for: [homework], now: now, calendar: calendar).first)

        XCTAssertEqual(
            Mirror(reflecting: row).children.compactMap { $0.label },
            ["id", "title", "time", "symbolName", "state"]
        )
        XCTAssertEqual(row.title, "Dever de casa")
        XCTAssertEqual(row.time, "16:00")
        XCTAssertEqual(row.symbolName, "backpack")
    }

    func testTheSharedTextNamesTheChildAndTheDayAndListsTitlesAndHours() {
        let day = Array(orderedDay().prefix(3))
        let rows = ChildDay.rows(
            for: ChildDay.tasks(for: pedro, in: day, members: members, now: now, calendar: calendar),
            now: now,
            calendar: calendar
        )

        let text = ChildDay.shareText(
            name: ChildDay.displayName(for: pedro, among: members),
            dateLine: ChildDay.dateLine(for: now, calendar: calendar),
            rows: rows
        )

        XCTAssertEqual(
            text,
            "Pedro · sexta-feira, 25 de setembro\n\n○ Guardar os brinquedos\n○ Escovar os dentes · 07:00\n○ Dever de casa · 16:00"
        )
        XCTAssertFalse(text.unicodeScalars.contains { $0.properties.isEmojiPresentation })
    }

    func testNothingFromATasksDetailReachesTheListThePrintoutOrTheSharedText() throws {
        let reading = "Linha digitável 34191.79001 01043.510047 91020.150008 5 92920026000"
        let day = orderedDay().map { task -> TaskItem in
            var withReading = task
            withReading.subtitle = reading
            return withReading
        }
        let listed = ChildDay.tasks(for: pedro, in: day, members: members, now: now, calendar: calendar)
        let rows = ChildDay.rows(for: listed, now: now, calendar: calendar)
        let session = ChildDaySession(child: pedro, tasks: day, members: members, now: now, calendar: calendar)
        let sessionRows = session.rows(child: pedro, tasks: day, members: members, now: now, calendar: calendar)
        let dateLine = ChildDay.dateLine(for: now, calendar: calendar)
        let text = ChildDay.shareText(name: "Pedro", dateLine: dateLine, rows: rows)
        let pdf = try XCTUnwrap(ChildDayPrinting.document(name: "Pedro", dateLine: dateLine, rows: rows))
        let printed = try XCTUnwrap(PDFDocument(data: pdf)?.string)

        XCTAssertFalse(text.contains("34191"))
        XCTAssertFalse(text.contains("Linha digitável"))
        for title in listed.map(\.title) {
            XCTAssertTrue(printed.contains(title), "The printout lost \(title)")
        }
        XCTAssertFalse(printed.contains("34191"))
        XCTAssertFalse(printed.contains("Linha digitável"))
        for row in rows + sessionRows {
            XCTAssertFalse(row.title.contains("34191"))
            XCTAssertFalse(row.title.contains("Linha digitável"))
        }
        XCTAssertEqual(rows.map(\.title), listed.map(\.title))
        XCTAssertEqual(sessionRows.map(\.title), listed.map(\.title))
    }

    func testAPrintedListBreaksIntoPagesOfTenWithoutLosingOrReorderingATask() {
        let rows = numberedRows(23)

        let pages = ChildDay.pages(rows)

        XCTAssertEqual(pages.map(\.count), [10, 10, 3])
        XCTAssertEqual(pages.flatMap { $0 }.map(\.id), rows.map(\.id))
        XCTAssertTrue(ChildDay.pages([]).isEmpty)
    }

    func testThePrintedDocumentIsAnA4PdfWithOnePagePerTenTasks() throws {
        let dateLine = ChildDay.dateLine(for: now, calendar: calendar)

        let data = try XCTUnwrap(ChildDayPrinting.document(name: "Pedro", dateLine: dateLine, rows: numberedRows(23)))
        let provider = try XCTUnwrap(CGDataProvider(data: data as CFData))
        let document = try XCTUnwrap(CGPDFDocument(provider))
        let firstPage = try XCTUnwrap(document.page(at: 1))
        let mediaBox = firstPage.getBoxRect(.mediaBox)

        XCTAssertEqual(document.numberOfPages, 3)
        XCTAssertEqual(mediaBox.width, 595.28, accuracy: 0.01)
        XCTAssertEqual(mediaBox.height, 841.89, accuracy: 0.01)
        XCTAssertNil(ChildDayPrinting.document(name: "Pedro", dateLine: dateLine, rows: []))
    }

    private func child(_ name: String) -> HouseholdMember {
        HouseholdMember(
            name: name,
            relationship: "Filha",
            role: .child,
            tone: .amber,
            taskCount: 0,
            memoryNote: ""
        )
    }

    private func orderedDay() -> [TaskItem] {
        [
            task("Guardar os brinquedos", owner: pedro, dueAt: date(2026, 9, 23, 19, 0)),
            task("Escovar os dentes", owner: pedro, dueAt: date(2026, 9, 24, 7, 0), recurrence: .daily),
            task("Dever de casa", owner: pedro, dueAt: date(2026, 9, 25, 16, 0), category: .school),
            task("Regar a planta", owner: pedro, dueAt: date(2026, 9, 25, 16, 0))
        ]
    }

    private func numberedRows(_ count: Int) -> [ChildDayRow] {
        (1...count).map { number in
            ChildDayRow(
                id: UUID(),
                title: "Tarefa \(number)",
                time: number.isMultiple(of: 2) ? "08:00" : nil,
                symbolName: "house",
                state: .open
            )
        }
    }

    @discardableResult
    private func markDone(
        _ id: TaskItem.ID,
        in tasks: inout [TaskItem],
        session: inout ChildDaySession,
        at date: Date
    ) throws -> ChildDayMark {
        let index = try XCTUnwrap(tasks.firstIndex { $0.id == id })
        let baseline = tasks[index]
        var written = try XCTUnwrap(ChildDay.markedDone(baseline, now: date, calendar: calendar))
        written.version = baseline.version + 1
        tasks[index] = written
        let mark = ChildDayMark(baseline: baseline, written: written, markedAt: date)
        session.record(mark)
        return mark
    }

    private func task(
        _ title: String,
        owner: HouseholdMember?,
        dueAt: Date?,
        recurrence: TaskRecurrence = .none,
        kind: TaskKind = .task,
        isDone: Bool = false,
        subtitle: String = "",
        category: TaskCategory = .home
    ) -> TaskItem {
        TaskItem(
            kind: kind,
            title: title,
            subtitle: subtitle,
            owner: owner?.name ?? "Casa",
            ownerMemberID: owner?.id,
            dueLabel: "Hoje",
            dueAt: dueAt,
            category: category,
            recurrence: recurrence,
            isDone: isDone,
            createdBy: "Manual"
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components) ?? .distantPast
    }
}
