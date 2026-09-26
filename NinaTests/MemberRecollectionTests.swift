import XCTest
@testable import Nina

@MainActor
final class MemberRecollectionTests: XCTestCase {
    private var calendar: Calendar!
    private var now: Date!
    private var familyID: UUID!
    private var viewerID: UUID!
    private var otherAdultID: UUID!
    private var pedro: HouseholdMember!
    private var thor: HouseholdMember!
    private var heitor: HouseholdMember!
    private var nina: HouseholdMember!
    private var members: [HouseholdMember]!

    override func setUp() {
        super.setUp()
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = TimeZone(identifier: "America/Sao_Paulo") ?? .gmt
        calendar = gregorian
        now = date(2026, 9, 25, 10, 0)
        familyID = UUID()
        viewerID = UUID()
        otherAdultID = UUID()
        pedro = child("Pedro Henrique")
        thor = pet("Thor")
        heitor = adult("Heitor")
        nina = HouseholdMember(
            name: "Nina",
            relationship: "IA da casa",
            role: .assistant,
            tone: .lavender,
            taskCount: 0,
            memoryNote: ""
        )
        members = [heitor, pedro, thor, nina]
    }

    override func tearDown() {
        calendar = nil
        now = nil
        familyID = nil
        viewerID = nil
        otherAdultID = nil
        pedro = nil
        thor = nil
        heitor = nil
        nina = nil
        members = nil
        super.tearDown()
    }

    func testAMemoryThatNamesTheChildInItsTitleOrItsBodyIsRemembered() {
        let byTitle = memory("Pedro gosta de natação", updatedAt: date(2026, 9, 20, 9, 0))
        let byBody = memory(
            "Mochila da escola",
            body: "O Pedro leva a lancheira às segundas.",
            updatedAt: date(2026, 9, 21, 9, 0)
        )
        let unrelated = memory("Feira de sábado", body: "Comprar banana e pão.", updatedAt: date(2026, 9, 22, 9, 0))

        let summary = recollection(for: pedro, memories: [byTitle, byBody, unrelated])

        XCTAssertEqual(summary.memories.map(\.text), ["Mochila da escola", "Pedro gosta de natação"])
        XCTAssertFalse(summary.isEmpty)
    }

    func testANameMatchesWithoutItsAccentsOrCapitals() {
        let joao = child("João Pedro")
        let house: [HouseholdMember] = [heitor, joao, nina]

        XCTAssertTrue(MemberRecollection.mentions(joao, in: "joao pedro tem judô", among: house))
        XCTAssertTrue(MemberRecollection.mentions(joao, in: "JOÃO PEDRO TEM JUDÔ", among: house))
        XCTAssertTrue(MemberRecollection.mentions(joao, in: "Joao-Pedro tem judô", among: house))
    }

    func testAShortNameInsideALongerWordNamesNobody() {
        let ana = child("Ana")
        let house: [HouseholdMember] = [heitor, ana, nina]

        XCTAssertFalse(MemberRecollection.mentions(ana, in: "Mariana vem jantar", among: house))
        XCTAssertFalse(MemberRecollection.mentions(ana, in: "Na semana que vem", among: house))
        XCTAssertFalse(MemberRecollection.mentions(ana, in: "Comprar banana", among: house))
        XCTAssertTrue(MemberRecollection.mentions(ana, in: "Ana, mochila", among: house))
    }

    func testTwoChildrenWhoShareAFirstNameAreRememberedOnlyByTheNameThatTellsThemApart() {
        let mariaClara = child("Maria Clara")
        let mariaEduarda = child("Maria Eduarda")
        let house: [HouseholdMember] = [heitor, mariaClara, mariaEduarda, nina]
        let loose = memory("Maria tem balé", updatedAt: date(2026, 9, 20, 9, 0))
        let named = memory("Maria Clara tem balé", updatedAt: date(2026, 9, 21, 9, 0))

        let clara = recollection(for: mariaClara, members: house, memories: [loose, named])
        let eduarda = recollection(for: mariaEduarda, members: house, memories: [loose, named])

        XCTAssertEqual(clara.memories.map(\.text), ["Maria Clara tem balé"])
        XCTAssertTrue(eduarda.memories.isEmpty)
        XCTAssertEqual(clara.name, "Maria Clara")
        XCTAssertEqual(eduarda.name, "Maria Eduarda")
    }

    func testWhatWasWrittenAboutAParentIsNeverCreditedToAChildWhoCarriesTheParentsName() {
        let father = adult("João")
        let son = child("João Pedro Castello")
        let pedroChild = child("Pedro")
        let house: [HouseholdMember] = [father, son, pedroChild, nina]

        let aboutSon = "João Pedro tem natação"
        XCTAssertTrue(MemberRecollection.mentions(son, in: aboutSon, among: house))
        XCTAssertFalse(MemberRecollection.mentions(father, in: aboutSon, among: house))
        XCTAssertFalse(MemberRecollection.mentions(pedroChild, in: aboutSon, among: house))

        let aboutFather = "João buscou a receita"
        XCTAssertTrue(MemberRecollection.mentions(father, in: aboutFather, among: house))
        XCTAssertFalse(MemberRecollection.mentions(son, in: aboutFather, among: house))
        XCTAssertFalse(MemberRecollection.mentions(pedroChild, in: aboutFather, among: house))

        XCTAssertEqual(MemberRecollection.distinguishingName(for: father, among: house), "João")
        XCTAssertEqual(MemberRecollection.distinguishingName(for: son, among: house), "João Pedro")
    }

    func testWhatWasWrittenAboutAParentByMoreOfTheirNameIsNeverCreditedToAChildWhoseNameItContains() {
        let father = adult("João Pedro Silva")
        let son = child("Pedro")
        let house: [HouseholdMember] = [father, son, nina]

        let aboutFather = "João Pedro buscou a receita"
        XCTAssertFalse(MemberRecollection.mentions(son, in: aboutFather, among: house))
        XCTAssertTrue(MemberRecollection.mentions(father, in: aboutFather, among: house))
        XCTAssertFalse(MemberRecollection.mentions(son, in: "João Pedro Silva buscou a receita", among: house))

        let aboutSon = "Pedro tem natação"
        XCTAssertTrue(MemberRecollection.mentions(son, in: aboutSon, among: house))
        XCTAssertFalse(MemberRecollection.mentions(father, in: aboutSon, among: house))

        let memories = [
            memory("João Pedro buscou a receita", updatedAt: date(2026, 9, 21, 9, 0)),
            memory("Pedro tem natação", updatedAt: date(2026, 9, 20, 9, 0))
        ]
        XCTAssertEqual(
            recollection(for: son, members: house, memories: memories).memories.map(\.text),
            ["Pedro tem natação"]
        )
        XCTAssertEqual(MemberRecollection.distinguishingName(for: father, among: house), "João")
    }

    func testWhatWasWrittenAboutAMotherByHerFullNameIsNeverCreditedToADaughterNamedLikeHerSecondName() {
        let mother = adult("Ana Clara")
        let daughter = child("Clara")
        let house: [HouseholdMember] = [mother, daughter, nina]

        XCTAssertFalse(MemberRecollection.mentions(daughter, in: "Ana Clara levou o bolo", among: house))
        XCTAssertTrue(MemberRecollection.mentions(mother, in: "Ana Clara levou o bolo", among: house))
        XCTAssertTrue(MemberRecollection.mentions(mother, in: "Ana levou o bolo", among: house))
        XCTAssertTrue(MemberRecollection.mentions(daughter, in: "Clara tem balé", among: house))
        XCTAssertFalse(MemberRecollection.mentions(mother, in: "Clara tem balé", among: house))

        let anaMaria = adult("Ana Maria")
        let maria = child("Maria")
        let otherHouse: [HouseholdMember] = [anaMaria, maria, nina]

        XCTAssertFalse(MemberRecollection.mentions(maria, in: "Ana Maria marcou o dentista", among: otherHouse))
        XCTAssertTrue(MemberRecollection.mentions(maria, in: "Maria marcou o dentista", among: otherHouse))
    }

    func testTwoPeopleWithTheSameNameAreNeitherCreditedWithAMemory() {
        let firstAna = child("Ana")
        let secondAna = child("Ana")
        let namesakes: [HouseholdMember] = [heitor, firstAna, secondAna, nina]
        let swimming = memory("Ana tem natação")

        XCTAssertTrue(recollection(for: firstAna, members: namesakes, memories: [swimming]).memories.isEmpty)
        XCTAssertTrue(recollection(for: secondAna, members: namesakes, memories: [swimming]).memories.isEmpty)

        let spaced = child("Ana Clara")
        let hyphenated = child("Ana-Clara")
        let spellings: [HouseholdMember] = [heitor, spaced, hyphenated, nina]
        let ballet = memory("Ana Clara tem balé")

        XCTAssertTrue(recollection(for: spaced, members: spellings, memories: [ballet]).memories.isEmpty)
        XCTAssertTrue(recollection(for: hyphenated, members: spellings, memories: [ballet]).memories.isEmpty)
        XCTAssertEqual(MemberRecollection.distinguishingName(for: spaced, among: spellings), "Ana Clara")
        XCTAssertEqual(MemberRecollection.distinguishingName(for: hyphenated, among: spellings), "Ana-Clara")
    }

    func testNinasOwnNameInAMemoryIsNeverCreditedToAChildWhoSharesIt() {
        let ninaRosa = child("Nina Rosa")
        let house: [HouseholdMember] = [heitor, ninaRosa, nina]

        XCTAssertFalse(MemberRecollection.mentions(ninaRosa, in: "A Nina lembrou do lanche", among: house))
        XCTAssertTrue(MemberRecollection.mentions(ninaRosa, in: "Nina Rosa tem balé", among: house))

        let namesake = child("Nina")
        let namesakeHouse: [HouseholdMember] = [heitor, namesake, nina]
        let memories = [memory("A Nina lembrou do lanche"), memory("Nina tem balé")]

        XCTAssertTrue(recollection(for: namesake, members: namesakeHouse, memories: memories).memories.isEmpty)
    }

    func testADistinguishingNameNeverStopsOnDeOrDa() {
        let lourdes = child("Maria de Lourdes")
        let eduarda = child("Maria Eduarda")
        let house: [HouseholdMember] = [heitor, lourdes, eduarda, nina]

        XCTAssertEqual(MemberRecollection.distinguishingName(for: lourdes, among: house), "Maria de Lourdes")
        XCTAssertEqual(MemberRecollection.distinguishingName(for: eduarda, among: house), "Maria Eduarda")
        XCTAssertFalse(MemberRecollection.mentions(lourdes, in: "Maria de novo esqueceu", among: house))
        XCTAssertFalse(MemberRecollection.mentions(eduarda, in: "Maria de novo esqueceu", among: house))
    }

    func testANameTooShortToBeAWordMatchesNothing() {
        let letter = child("E")
        let house: [HouseholdMember] = [heitor, letter, nina]

        XCTAssertFalse(MemberRecollection.mentions(letter, in: "Pão e leite", among: house))
        XCTAssertTrue(recollection(for: letter, members: house, memories: [memory("Pão e leite")]).memories.isEmpty)
    }

    func testTheAssistantRowHasNoRecollection() {
        let summary = recollection(
            for: nina,
            memories: [memory("Nina guarda o horário")],
            tasks: [task("Regar a planta", owner: nina, dueAt: date(2026, 9, 25, 8, 0), recurrence: .daily)]
        )

        XCTAssertTrue(summary.isEmpty)
        XCTAssertFalse(MemberRecollection.mentions(nina, in: "Nina guarda o horário", among: members))
    }

    func testASharedMemoryAndTheViewersOwnPrivateMemoryAreBothRememberedAndOnlyThePrivateOneIsMarked() {
        let shared = memory(
            "Pedro tem natação",
            visibility: .shared,
            owner: otherAdultID,
            updatedAt: date(2026, 9, 20, 9, 0)
        )
        let own = memory(
            "Pedro não come camarão",
            visibility: .privateMemory,
            owner: viewerID,
            updatedAt: date(2026, 9, 21, 9, 0)
        )

        let summary = recollection(for: pedro, memories: [shared, own])

        XCTAssertEqual(summary.memories.map(\.text), ["Pedro não come camarão", "Pedro tem natação"])
        XCTAssertEqual(summary.memories.map(\.isPrivate), [true, false])
    }

    func testAnotherAdultsPrivateMemoryNeverReachesTheSummaryEvenWhenItIsOnTheDevice() {
        let theirs = memory(
            "Pedro vai ao psicólogo",
            visibility: .privateMemory,
            owner: otherAdultID
        )
        let unowned = memory("Pedro tem consulta", visibility: .privateMemory, owner: nil)

        let summary = recollection(for: pedro, memories: [theirs, unowned])

        XCTAssertTrue(summary.memories.isEmpty)
        XCTAssertFalse(summary.lines.contains { $0.text.contains("psicólogo") })
    }

    func testWithoutAKnownViewerOnlySharedMemoriesAreRemembered() {
        let shared = memory("Pedro tem natação", visibility: .shared, owner: otherAdultID)
        let own = memory("Pedro não come camarão", visibility: .privateMemory, owner: viewerID)

        let summary = recollection(for: pedro, memories: [shared, own], knowsViewer: false)

        XCTAssertEqual(summary.memories.map(\.text), ["Pedro tem natação"])
    }

    func testAMemoryShowsItsTitleAndNeverItsBody() {
        let dose = memory(
            "Natação às terças",
            body: "Pedro toma 5 ml de 8 em 8 horas antes da aula.",
            updatedAt: date(2026, 9, 21, 9, 0)
        )
        let untitled = memory(
            "  \n ",
            body: "Pedro toma o xarope às 20h.",
            updatedAt: date(2026, 9, 22, 9, 0)
        )

        let summary = recollection(for: pedro, memories: [dose, untitled])

        XCTAssertEqual(summary.memories.map(\.text), ["Natação às terças"])
        XCTAssertFalse(summary.lines.contains { $0.text.contains("5 ml") || $0.text.contains("xarope") })
    }

    func testMemoriesRunNewestFirstAndStopAtThree() {
        let memories = (1...4).map { number in
            memory("Lembrança \(number)", body: "Sobre o Pedro.", updatedAt: date(2026, 9, 20 + number, 9, 0))
        }

        let summary = recollection(for: pedro, memories: memories.shuffled())

        XCTAssertEqual(summary.memories.map(\.text), ["Lembrança 4", "Lembrança 3", "Lembrança 2"])
    }

    func testTheRoutineHoldsOnlyTheMembersOpenRepeatingTasks() {
        let teeth = task("Escovar os dentes", owner: pedro, dueAt: date(2026, 9, 25, 7, 0), recurrence: .daily)
        let walk = task(
            "Passear",
            owner: thor,
            byNameOnly: true,
            dueAt: date(2026, 9, 29, 18, 0),
            recurrence: .weekly
        )
        let oneOff = task("Dever de casa", owner: pedro, dueAt: date(2026, 9, 25, 16, 0))
        let done = task(
            "Tomar vacina",
            owner: pedro,
            dueAt: date(2026, 9, 25, 9, 0),
            recurrence: .yearly,
            isDone: true
        )
        let seed = task("Aprender a nadar", owner: pedro, dueAt: nil, recurrence: .weekly, kind: .seed)
        let heitors = task("Pagar a luz", owner: heitor, dueAt: date(2026, 9, 25, 8, 0), recurrence: .daily)
        let house = task("Lavar a louça", owner: nil, dueAt: date(2026, 9, 25, 20, 0), recurrence: .daily)
        let tasks = [teeth, walk, oneOff, done, seed, heitors, house]

        XCTAssertEqual(
            recollection(for: pedro, tasks: tasks).routine.map(\.text),
            ["Escovar os dentes · todos os dias, 07:00"]
        )
        XCTAssertEqual(
            recollection(for: thor, tasks: tasks).routine.map(\.text),
            ["Passear · toda terça, 18:00"]
        )
    }

    func testEachRhythmReadsTheWayABrazilianHouseSaysIt() {
        func rhythm(_ recurrence: TaskRecurrence, _ dueAt: Date?) -> String {
            MemberRecollection.rhythm(
                of: task("Rotina", owner: pedro, dueAt: dueAt, recurrence: recurrence),
                calendar: calendar
            )
        }

        XCTAssertEqual(rhythm(.daily, date(2026, 9, 25, 7, 0)), "todos os dias, 07:00")
        XCTAssertEqual(rhythm(.weekly, date(2026, 9, 29, 18, 0)), "toda terça, 18:00")
        XCTAssertEqual(rhythm(.weekly, date(2026, 9, 26, 9, 30)), "todo sábado, 09:30")
        XCTAssertEqual(rhythm(.weekly, date(2026, 9, 27, 10, 0)), "todo domingo, 10:00")
        XCTAssertEqual(rhythm(.monthly, date(2026, 10, 5, 9, 0)), "todo mês, dia 5")
        XCTAssertEqual(rhythm(.yearly, date(2027, 3, 12, 9, 0)), "todo ano, 12 de março")
        XCTAssertEqual(rhythm(.weekly, nil), "toda semana")

        let teeth = task("Escovar os dentes", owner: pedro, dueAt: date(2026, 9, 25, 7, 0), recurrence: .daily)
        XCTAssertEqual(
            recollection(for: pedro, tasks: [teeth]).routine.map(\.text),
            ["Escovar os dentes · todos os dias, 07:00"]
        )
    }

    func testTheRoutineRunsFromDailyToYearlyThenThroughTheDayAndWeekAndStopsAtThree() {
        let evening = task("Tomar banho", owner: pedro, dueAt: date(2026, 9, 25, 19, 0), recurrence: .daily)
        let vaccine = task("Vacina", owner: pedro, dueAt: date(2027, 3, 12, 9, 0), recurrence: .yearly)
        let tuesday = task("Natação", owner: pedro, dueAt: date(2026, 9, 29, 18, 0), recurrence: .weekly)
        let morning = task("Escovar os dentes", owner: pedro, dueAt: date(2026, 9, 25, 7, 0), recurrence: .daily)
        let haircut = task("Cortar o cabelo", owner: pedro, dueAt: date(2026, 10, 5, 9, 0), recurrence: .monthly)
        let saturday = task("Futebol", owner: pedro, dueAt: date(2026, 9, 26, 9, 30), recurrence: .weekly)
        let undated = task("Arrumar o quarto", owner: pedro, dueAt: nil, recurrence: .weekly)

        let all = [evening, vaccine, tuesday, morning, haircut, saturday, undated]
        XCTAssertEqual(
            recollection(for: pedro, tasks: all).routine.map(\.source),
            [.routine(morning.id), .routine(evening.id), .routine(tuesday.id)]
        )

        let weeklyOnward = [vaccine, undated, haircut, saturday, tuesday]
        XCTAssertEqual(
            recollection(for: pedro, tasks: weeklyOnward).routine.map(\.source),
            [.routine(tuesday.id), .routine(saturday.id), .routine(undated.id)]
        )

        XCTAssertEqual(
            recollection(for: pedro, tasks: [vaccine, haircut]).routine.map(\.source),
            [.routine(haircut.id), .routine(vaccine.id)]
        )
    }

    func testNothingFromATasksDetailReachesTheSummary() {
        let reading = "Linha digitável 23793.38128 60000.000003 Pedro"
        let fee = task(
            "Pagar a escola",
            owner: pedro,
            dueAt: date(2026, 10, 5, 9, 0),
            recurrence: .monthly,
            subtitle: reading
        )

        let summary = recollection(for: pedro, tasks: [fee])

        XCTAssertEqual(summary.lines.map(\.text), ["Pagar a escola · todo mês, dia 5"])
        for fragment in ["Linha digitável", "23793", "38128", "60000", "000003"] {
            XCTAssertFalse(summary.lines.contains { $0.text.contains(fragment) })
            XCTAssertFalse(summary.emptyLine.contains(fragment))
        }
    }

    func testWithNothingFoundTheCardSaysNinaLearnsAboutThePersonInConversations() {
        let child = recollection(for: pedro)
        let animal = recollection(for: thor)

        XCTAssertTrue(child.isEmpty)
        XCTAssertTrue(animal.isEmpty)
        XCTAssertEqual(child.emptyLine, "A Nina aprende sobre Pedro nas conversas.")
        XCTAssertEqual(animal.emptyLine, "A Nina aprende sobre Thor nas conversas.")
    }

    func testTheEmptyLineCallsAChildNamedLikeNinaByEnoughOfTheirName() {
        let ninaRosa = child("Nina Rosa")
        let summary = recollection(for: ninaRosa, members: [heitor, ninaRosa, nina])

        XCTAssertTrue(summary.isEmpty)
        XCTAssertEqual(summary.emptyLine, "A Nina aprende sobre Nina Rosa nas conversas.")
    }

    func testOnlyAChildOrAPetTradesTheTypedNoteForWhatNinaRemembers() {
        XCTAssertTrue(MemberRecollection.replacesNote(for: .child))
        XCTAssertTrue(MemberRecollection.replacesNote(for: .pet))
        XCTAssertFalse(MemberRecollection.replacesNote(for: .adult))
        XCTAssertFalse(MemberRecollection.replacesNote(for: .assistant))
    }

    func testSavingAChildOrAPetClearsTheNoteAndAnAdultsNoteIsSavedAsTyped() {
        XCTAssertEqual(MemberRecollection.storedNote("Escola de manhã", for: .child), "")
        XCTAssertEqual(MemberRecollection.storedNote("Ração às 7h", for: .pet), "")
        XCTAssertEqual(MemberRecollection.storedNote(" Horários ", for: .adult), " Horários ")
    }

    private func recollection(
        for member: HouseholdMember,
        members house: [HouseholdMember]? = nil,
        memories: [NinaMemory] = [],
        tasks: [TaskItem] = [],
        knowsViewer: Bool = true
    ) -> MemberRecollectionSummary {
        MemberRecollection.summary(
            for: member,
            members: house ?? members,
            memories: memories,
            tasks: tasks,
            viewerUserID: knowsViewer ? viewerID : nil,
            calendar: calendar
        )
    }

    private func child(_ name: String) -> HouseholdMember {
        HouseholdMember(
            name: name,
            relationship: "Criança",
            role: .child,
            tone: .amber,
            taskCount: 0,
            memoryNote: ""
        )
    }

    private func pet(_ name: String) -> HouseholdMember {
        HouseholdMember(
            name: name,
            relationship: "Cachorro",
            role: .pet,
            tone: .lavender,
            taskCount: 0,
            memoryNote: ""
        )
    }

    private func adult(_ name: String) -> HouseholdMember {
        HouseholdMember(
            userID: UUID().uuidString,
            name: name,
            relationship: "Pai",
            role: .adult,
            tone: .mint,
            taskCount: 0,
            memoryNote: ""
        )
    }

    private func memory(
        _ title: String,
        body: String = "",
        visibility: NinaMemoryVisibility = .shared,
        owner: UUID? = nil,
        updatedAt: Date? = nil
    ) -> NinaMemory {
        let stamp = updatedAt ?? now ?? .distantPast
        return NinaMemory(
            id: UUID(),
            familyID: familyID,
            ownerUserID: owner,
            title: title,
            body: body,
            visibility: visibility,
            confidence: 1,
            createdAt: stamp,
            updatedAt: stamp
        )
    }

    private func task(
        _ title: String,
        owner: HouseholdMember?,
        byNameOnly: Bool = false,
        dueAt: Date?,
        recurrence: TaskRecurrence = .none,
        kind: TaskKind = .task,
        isDone: Bool = false,
        subtitle: String = ""
    ) -> TaskItem {
        TaskItem(
            kind: kind,
            title: title,
            subtitle: subtitle,
            owner: owner?.name ?? "Casa",
            ownerMemberID: byNameOnly ? nil : owner?.id,
            dueLabel: "Hoje",
            dueAt: dueAt,
            category: .home,
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
