import SwiftUI
import XCTest
@testable import Nina

@MainActor
final class OnboardingTourTests: XCTestCase {
    private var calendar: Calendar!

    override func setUp() {
        super.setUp()
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = TimeZone(identifier: "America/Sao_Paulo") ?? .gmt
        calendar = gregorian
    }

    override func tearDown() {
        calendar = nil
        super.tearDown()
    }

    func testTheTourGreetsThenVisitsTheFourTabsInTheOrderOfTheBarThenCloses() {
        XCTAssertEqual(OnboardingTour.Step.allCases, [.hello, .nina, .today, .tasks, .house, .done])
        XCTAssertEqual(OnboardingTour.Step.allCases.compactMap(\.tab), AppTab.allCases)
    }

    func testEveryLineNinaSaysIsAtMostTwoSentencesOfTwentyFourWordsWithoutExclamationOrEmoji() {
        for context in allContexts() {
            for step in OnboardingTour.Step.allCases {
                let line = OnboardingTour.line(for: step, context: context)
                XCTAssertTrue(line.hasSuffix("."), line)
                XCTAssertLessThanOrEqual(sentenceEnds(in: line), 2, line)
                XCTAssertLessThanOrEqual(wordCount(line, leavingOut: context.name), 24, line)
                XCTAssertFalse(line.contains("!"), line)
                XCTAssertFalse(line.unicodeScalars.contains { $0.properties.isEmojiPresentation }, line)
            }
        }
    }

    func testNinaNeverCallsHerselfAnAssistantNeverSaysSheDidSomethingAndNeverSaysNothingIsKept() {
        let forbidden = ["assistente", "amiga", "criei", "anotei", "salvei", "guardei", "marquei"]
        let retentionClaims = [
            "fica guardado lá",
            "servidor nenhum",
            "usado só para responder",
            "não guarde o que recebe"
        ]

        for context in allContexts() {
            for step in OnboardingTour.Step.allCases {
                let line = OnboardingTour.line(for: step, context: context)
                let tokens = words(in: line)
                XCTAssertFalse(tokens.contains("IA"), line)
                for word in forbidden {
                    XCTAssertFalse(tokens.map { $0.lowercased() }.contains(word), "\(word): \(line)")
                }
                for claim in retentionClaims {
                    XCTAssertFalse(line.contains(claim), "\(claim): \(line)")
                }
            }
        }
    }

    func testTheTourOpensByCallingItExamplesAndClosesBySayingNothingEnteredTheHouse() {
        for context in allContexts() {
            XCTAssertTrue(OnboardingTour.line(for: .hello, context: context).contains("só com exemplos"))
            XCTAssertEqual(
                OnboardingTour.line(for: .done, context: context),
                "Pronto, agora é com você. Nada do que você viu entrou na sua casa."
            )
        }
    }

    func testTheChatStepNeverPromisesAConversationTheAccountCannotHaveYet() {
        let awaiting = OnboardingTour.line(for: .nina, context: context(chat: .awaitingAge))
        let consent = OnboardingTour.line(for: .nina, context: context(chat: .needsConsent))
        let closed = OnboardingTour.line(for: .nina, context: context(chat: .closed))

        XCTAssertTrue(awaiting.contains("quando a Apple confirmar sua idade"))
        XCTAssertTrue(consent.contains("você decide se eu posso ler"))
        XCTAssertTrue(closed.contains("não abre nesta conta"))
        XCTAssertFalse(closed.contains("me conta"))
        XCTAssertFalse(closed.contains("proponho"))
    }

    func testTheChatStateIsReadInTheSameOrderAsTheChatScreen() {
        XCTAssertEqual(chatState(canUse: true, requiresConsent: true, hasConsent: false), .needsConsent)
        XCTAssertEqual(chatState(canUse: true, requiresConsent: true, hasConsent: true), .open)
        XCTAssertEqual(chatState(canUse: true, requiresConsent: false, hasConsent: false), .open)
        XCTAssertEqual(chatState(isBlocked: true, isAdult: true, needsConfirmedAge: true), .closed)
        XCTAssertEqual(chatState(isAdult: true, needsConfirmedAge: true), .awaitingAge)
        XCTAssertEqual(chatState(isAdult: true), .closed)
        XCTAssertEqual(chatState(isBlocked: true, isAdult: false), .closed)
    }

    func testOnlySomeoneWhoCanTalkToNinaLandsOnHerTab() {
        XCTAssertEqual(TourChatState.open.landingTab, .nina)
        XCTAssertEqual(TourChatState.needsConsent.landingTab, .nina)
        XCTAssertEqual(TourChatState.awaitingAge.landingTab, .today)
        XCTAssertEqual(TourChatState.closed.landingTab, .today)

        for chat in TourChatState.allCases {
            XCTAssertEqual(OnboardingTour.pillTab(for: .done, context: context(chat: chat)), chat.landingTab)
            XCTAssertNil(OnboardingTour.pillTab(for: .done, context: context(chat: chat, isReplay: true)))
        }
        XCTAssertNil(OnboardingTour.pillTab(for: .hello, context: context(chat: .open)))
    }

    func testAnAccountWhoseChatIsClosedIsShownNoExampleProposal() {
        XCTAssertNil(
            OnboardingTour.exampleDescription(for: .nina, context: context(chat: .closed), calendar: calendar)
        )
        XCTAssertFalse(TourChatState.closed.showsChatExample)

        for chat in TourChatState.allCases where chat != .closed {
            let description = OnboardingTour.exampleDescription(
                for: .nina,
                context: context(chat: chat),
                calendar: calendar
            )
            XCTAssertTrue(description?.hasPrefix("Exemplo da aba Nina:") == true, description ?? "nil")
            XCTAssertTrue(description?.hasSuffix(NinaProposalCopy.disclaimer) == true, description ?? "nil")
            XCTAssertTrue(description?.contains("\(NinaProposalCopy.pending).") == true, description ?? "nil")
        }
    }

    func testNinaGreetsThePersonByTheirChosenFirstNameAndNeverByThePlaceholder() {
        XCTAssertEqual(OnboardingTour.greetingName(displayName: "Ana Paula", sharedGivenName: nil), "Ana")
        XCTAssertEqual(OnboardingTour.greetingName(displayName: "Família", sharedGivenName: "Bia"), "Bia")
        XCTAssertNil(OnboardingTour.greetingName(displayName: "Família", sharedGivenName: nil))
        XCTAssertNil(OnboardingTour.greetingName(displayName: "Você", sharedGivenName: nil))
        XCTAssertNil(OnboardingTour.greetingName(displayName: "", sharedGivenName: "Família"))
        XCTAssertNil(OnboardingTour.greetingName(displayName: nil, sharedGivenName: nil))

        XCTAssertTrue(
            OnboardingTour.line(for: .hello, context: context(chat: .open, name: nil))
                .hasPrefix("Oi, eu sou a Nina.")
        )
        XCTAssertTrue(
            OnboardingTour.line(for: .hello, context: context(chat: .open, name: nil, isReplay: true))
                .hasPrefix("Oi de novo.")
        )
        XCTAssertTrue(
            OnboardingTour.line(for: .hello, context: context(chat: .open, name: "Ana"))
                .hasPrefix("Oi, Ana, eu sou a Nina.")
        )
        XCTAssertTrue(
            OnboardingTour.line(for: .hello, context: context(chat: .open, name: "Ana", isReplay: true))
                .hasPrefix("Oi de novo, Ana.")
        )
    }

    func testTheExampleHouseNeverUsesThePersonsOwnName() {
        for name in ["Dani", "dani", "Daní", "Pacoca", "LIA", "cris"] {
            let cast = TourSample.cast(avoiding: [name])
            XCTAssertEqual(cast, TourSample.otherCast, name)
            XCTAssertFalse(
                cast.names.contains { HouseholdWorkload.normalized($0) == HouseholdWorkload.normalized(name) },
                name
            )
            let house = TourSample.house(avoiding: [name], now: instant(2026, 10, 14, 9, 0), calendar: calendar)
            XCTAssertFalse(
                house.members.contains { HouseholdWorkload.normalized($0.name) == HouseholdWorkload.normalized(name) },
                name
            )
        }

        for names in [["Rafa"], ["Ana"], []] {
            XCTAssertEqual(TourSample.cast(avoiding: names), TourSample.primaryCast, "\(names)")
        }
    }

    func testTheExampleHouseNeverDrawsAnyoneWhoLivesInTheRealHouseInABand() {
        let now = instant(2026, 10, 14, 9, 0)
        let joiner = TourContext(
            name: "Ana",
            houseNames: ["Ana Souza", "Cris Lima", "Bia", "Totó"],
            chat: .open,
            isReplay: false,
            now: now
        )
        XCTAssertEqual(TourSample.house(for: joiner, calendar: calendar).cast, TourSample.otherCast)
        XCTAssertEqual(TourSample.cast(avoiding: ["Ana", "Paçoca"]), TourSample.otherCast)
        XCTAssertEqual(TourSample.cast(avoiding: ["Maria Cristina", "Danilo"]), TourSample.primaryCast)
        XCTAssertEqual(TourSample.cast(avoiding: ["Ana", "Pedro Lia"]), TourSample.otherCast)
        XCTAssertEqual(TourSample.cast(avoiding: ["Cris", "alex"]), TourSample.thirdCast)
        XCTAssertEqual(TourSample.cast(avoiding: ["Paçoca", "Nico", "Farofa"]), TourSample.roleCast)

        let crowded = ["Dani", "Rafa", "Tati", "Ana", "Cris", "Alex", "Juca"]
        let house = TourSample.house(avoiding: crowded, now: now, calendar: calendar)
        let taken = Set(crowded.flatMap(TourSample.foldedWords(in:)))
        XCTAssertEqual(house.cast, TourSample.roleCast)
        for member in house.members where member.role != .assistant {
            XCTAssertTrue(taken.isDisjoint(with: TourSample.foldedWords(in: member.name)), member.name)
        }
        for entry in house.portraitRows {
            XCTAssertTrue(taken.isDisjoint(with: TourSample.foldedWords(in: entry.name)), entry.name)
        }
        XCTAssertEqual(house.portraitRows.map(\.band), [.heavier, .light])
    }

    func testTheExamplePortraitIsDrawnByTheLiveRuleAndShowsTwoAdultsInDifferentBandsAndNeverTheChild() {
        let house = TourSample.house(avoiding: ["Ana"], now: instant(2026, 10, 14, 9, 0), calendar: calendar)
        let portrait = house.portrait
        let childIDs = Set(house.members.filter { $0.role == .child }.map(\.id))

        XCTAssertEqual(portrait, HouseholdWorkload.snapshot(tasks: house.tasks, members: house.members))
        XCTAssertTrue(portrait.isConclusive)
        XCTAssertFalse(portrait.isBalanced)
        XCTAssertFalse(portrait.entries.contains { entry in entry.memberID.map(childIDs.contains) ?? false })
        XCTAssertEqual(house.portraitRows.map(\.name), house.cast.adults)
        XCTAssertEqual(house.portraitRows.map(\.band), [.heavier, .light])
    }

    func testOnlyTheLateExampleRowReadsLateAtAnyHourAndEveryDateUsesTheLiveFormat() {
        let cases: [(hour: Int, minute: Int, first: (Int, Int), second: (Int, Int))] = [
            (9, 0, (20, 0), (21, 0)),
            (20, 30, (21, 0), (22, 0)),
            (23, 40, (23, 50), (23, 55))
        ]

        for sample in cases {
            let now = instant(2026, 10, 14, sample.hour, sample.minute)
            let house = TourSample.house(avoiding: [], now: now, calendar: calendar)
            let (first, second) = TourSample.onTimeInstants(now: now, calendar: calendar)

            XCTAssertEqual(first, instant(2026, 10, 14, sample.first.0, sample.first.1))
            XCTAssertEqual(second, instant(2026, 10, 14, sample.second.0, sample.second.1))
            XCTAssertEqual(house.agenda.count, 3)
            XCTAssertEqual(
                house.agenda.count { $0.isOverdue(relativeTo: house.sampleNow, calendar: calendar) },
                1
            )
            XCTAssertEqual(house.agenda.first?.id, house.lateBill.id)

            for task in house.agenda {
                let label = house.label(for: task)
                if let dueAt = task.dueAt {
                    XCTAssertEqual(label, AppStore.taskDueLabel(for: dueAt, relativeTo: now, calendar: calendar))
                } else {
                    XCTFail("Every agenda row carries a date.")
                }
                if !house.isLate(task) {
                    XCTAssertTrue(label.hasPrefix("Hoje, "), label)
                }
            }
        }
    }

    func testTheExampleProposalIsDatedByTheLiveReaderAndUsesTheLiveChip() throws {
        let thursday = instant(2026, 10, 1, 10, 0)
        let fridayEarly = instant(2026, 10, 2, 8, 0)
        let fridayLate = instant(2026, 10, 2, 10, 0)

        for now in [thursday, fridayEarly, fridayLate] {
            XCTAssertEqual(
                TourSample.proposalDate(now: now, calendar: calendar),
                AppStore.inferredDueAt(from: "sexta", now: now, calendar: calendar)
            )
        }

        let early = try XCTUnwrap(TourSample.proposalDate(now: fridayEarly, calendar: calendar))
        XCTAssertEqual(AppStore.taskDueLabel(for: early, relativeTo: fridayEarly, calendar: calendar), "Hoje, 09:00")
        XCTAssertEqual(
            TourSample.house(avoiding: [], now: fridayEarly, calendar: calendar).proposalLabel,
            "Hoje, 09:00"
        )
        XCTAssertEqual(TourSample.proposalDate(now: fridayLate, calendar: calendar), instant(2026, 10, 9, 9, 0))
        XCTAssertTrue(NinaChatView.captureExamples.contains(TourSample.message))
    }

    func testTheExampleCountsAgreeAcrossHojeTarefasAndCasaAndTarefasShowsWhatHojeDoesNot() {
        let house = TourSample.house(avoiding: ["Ana"], now: instant(2026, 10, 14, 15, 0), calendar: calendar)

        XCTAssertEqual(house.agenda.count, 3)
        XCTAssertEqual(house.lateCount, 1)
        XCTAssertEqual(house.pendingShopping.count, 1)
        XCTAssertEqual(house.openSeeds.count, 1)
        XCTAssertEqual(house.groupTasks.count, 1)
        XCTAssertEqual(house.people.count, 4)
        XCTAssertEqual(house.agenda.first { house.isLate($0) }?.id, house.lateBill.id)

        let openTasks = house.tasks.filter { $0.kind == .task && !$0.isDone }
        XCTAssertEqual(house.groupTasks, openTasks.filter { $0.category == TourSample.groupCategory })
        XCTAssertTrue(house.groupTasks.allSatisfy { !house.isLate($0) })

        let agendaTitles = Set(house.agenda.map(\.title))
        XCTAssertFalse(house.groupTasks.contains { agendaTitles.contains($0.title) })
        XCTAssertFalse(house.pendingShopping.contains { agendaTitles.contains($0.title) })
        XCTAssertFalse(house.openSeeds.contains { agendaTitles.contains($0.title) })
        XCTAssertTrue(house.pendingShopping.allSatisfy { !$0.amount.isEmpty })
    }

    func testEveryExampleIsSpokenAsOneLineThatNamesItsTab() {
        let open = context(chat: .open)
        for step in OnboardingTour.Step.allCases {
            let description = OnboardingTour.exampleDescription(for: step, context: open, calendar: calendar)
            guard let tab = step.tab else {
                XCTAssertNil(description, "\(step)")
                continue
            }
            XCTAssertTrue(description?.hasPrefix("Exemplo da aba \(tab.title):") == true, description ?? "nil")
        }

        let today = OnboardingTour.exampleDescription(for: .today, context: open, calendar: calendar) ?? ""
        let tasks = OnboardingTour.exampleDescription(for: .tasks, context: open, calendar: calendar) ?? ""
        let house = OnboardingTour.exampleDescription(for: .house, context: open, calendar: calendar) ?? ""
        XCTAssertTrue(today.contains("atrasadas, 1."), today)
        XCTAssertTrue(today.contains("Pagar a luz, atrasada, "), today)
        XCTAssertTrue(tasks.hasPrefix("Exemplo da aba Tarefas: categoria Pet, 1. Vacina, "), tasks)
        XCTAssertTrue(tasks.hasSuffix("Listas Sementes, 1, e Compras, 1. Pintar a sala, plante depois."), tasks)
        XCTAssertTrue(house.contains("Dani e Cris, adultos; Lia, criança; Paçoca, pet; e a Nina."), house)
        XCTAssertTrue(house.hasSuffix("Sinal de sobrecarga: Dani, mais pesado. Cris, leve."), house)
    }

    func testNoBubbleEndsOnOneWordOrBreaksAfterAWordThatLeansOnTheNextAndOnlyTheGreetingAndTheCloseBreakBySentence() {
        let noBreak: Character = "\u{00A0}"
        for context in allContexts() {
            for step in OnboardingTour.Step.allCases {
                let line = OnboardingTour.line(for: step, context: context)
                let drawn = OnboardingTour.drawnLine(for: step, context: context)
                let spoken = drawn
                    .replacingOccurrences(of: "\n", with: " ")
                    .replacingOccurrences(of: String(noBreak), with: " ")
                XCTAssertEqual(spoken, line)
                XCTAssertEqual(drawn.contains("\n"), step.isCentred && sentenceEnds(in: line) > 1, drawn)

                for row in drawn.components(separatedBy: "\n") {
                    XCTAssertEqual(row.last { $0 == " " || $0 == noBreak }, noBreak, row)
                }
                for chunk in drawn.components(separatedBy: CharacterSet(charactersIn: " \n")) {
                    let lastWord = String(chunk.split(separator: noBreak).last ?? "")
                    XCTAssertFalse(OnboardingTour.bindsToTheNextWord(lastWord), drawn)
                }
            }
            XCTAssertEqual(
                OnboardingTour.drawnLine(for: .done, context: context),
                "Pronto, agora é\u{00A0}com\u{00A0}você.\nNada do\u{00A0}que você viu entrou na\u{00A0}sua\u{00A0}casa."
            )
        }

        for word in ["O", "é", "e", "a", "Eu", "eu", "na", "no", "de", "da", "do", "um"] {
            XCTAssertTrue(OnboardingTour.bindsToTheNextWord(word), word)
        }
        for word in ["em", "Em", "abas", "com", "se", "Oi,", "1"] {
            XCTAssertFalse(OnboardingTour.bindsToTheNextWord(word), word)
        }
        let open = OnboardingTour.drawnLine(for: .nina, context: context(chat: .open))
        XCTAssertTrue(open.contains("vier. Eu\u{00A0}leio"), open)
    }

    func testOnTheCloseATapOnTheMapOpensThatTabAndBeforeItShowsThatTabsExample() {
        for tab in AppTab.allCases {
            XCTAssertEqual(OnboardingTour.mapAction(for: tab, on: .done), .open(tab))
            for step in OnboardingTour.Step.allCases where step != .done {
                XCTAssertEqual(OnboardingTour.mapAction(for: tab, on: step), .show(OnboardingTour.Step(tab: tab)))
            }
        }
        XCTAssertEqual(OnboardingTour.Step.allCases.compactMap(\.tab).map(OnboardingTour.Step.init(tab:)), [
            .nina, .today, .tasks, .house
        ])
        XCTAssertEqual(OnboardingTour.mapHint(on: .done), "Abre esta aba.")
        for step in OnboardingTour.Step.allCases where step != .done {
            XCTAssertEqual(OnboardingTour.mapHint(on: step), "Mostra esta aba na demonstração.")
        }
    }

    func testNinaStopsReadingBeforeHerProposalAppearsSoTheTwoNeverShareTheSlot() throws {
        let motion = OnboardingTour.beats(for: .nina, reduceMotion: false)
        let readingEnds = try XCTUnwrap(motion.first { $0.moment == .readingEnds })
        let proposal = try XCTUnwrap(motion.first { $0.moment == .proposal })

        XCTAssertLessThanOrEqual(readingEnds.delay + readingEnds.duration, proposal.delay)
        let finalPhase = OnboardingTour.phaseCount(for: .nina)
        XCTAssertTrue(OnboardingTour.isReached(.readingEnds, on: .nina, phase: finalPhase))
    }

    func testUnderReduceMotionEveryStepOpensOnItsFinalFrame() {
        for step in OnboardingTour.Step.allCases {
            let motion = OnboardingTour.beats(for: step, reduceMotion: false)
            XCTAssertEqual(OnboardingTour.beats(for: step, reduceMotion: true), [])
            XCTAssertEqual(OnboardingTour.phaseCount(for: step), motion.count)
            XCTAssertEqual(motion.map(\.delay), motion.map(\.delay).sorted(), "\(step)")

            let finalPhase = OnboardingTour.phaseCount(for: step)
            for beat in motion {
                XCTAssertTrue(OnboardingTour.isReached(beat.moment, on: step, phase: finalPhase), "\(step)")
            }
        }
    }

    func testTheTourAnimatesForLessThanFifteenSecondsInAll() {
        let total = OnboardingTour.Step.allCases.reduce(0.0) { sum, step in
            sum + (OnboardingTour.beats(for: step, reduceMotion: false).map { $0.delay + $0.duration }.max() ?? 0)
        }

        XCTAssertGreaterThan(total, 0)
        XCTAssertLessThan(total, 15)
    }

    func testTheTourStaysWithinItsWordBudget() {
        for chat in TourChatState.allCases {
            let firstRun = context(chat: chat, name: "Ana")
            let lines = OnboardingTour.Step.allCases.map { OnboardingTour.line(for: $0, context: firstRun) }
            let chrome = [
                OnboardingTour.header,
                OnboardingTour.skipTitle(isReplay: false),
                "Continuar",
                "Começar",
                OnboardingTour.exampleLegend
            ]
            let total = lines.reduce(0) { $0 + wordCount($1, leavingOut: "Ana") }
                + chrome.reduce(0) { $0 + wordCount($1, leavingOut: nil) }

            XCTAssertLessThanOrEqual(total, 120, "\(chat)")
        }
    }

    func testTheButtonsAndTheSkipSayWhatTheyDoOnAFirstRunAndOnAReplay() {
        for step in OnboardingTour.Step.allCases where step != .done {
            XCTAssertEqual(OnboardingTour.advanceTitle(for: step, isReplay: false), "Continuar")
            XCTAssertEqual(OnboardingTour.advanceTitle(for: step, isReplay: true), "Continuar")
        }
        XCTAssertEqual(OnboardingTour.advanceTitle(for: .done, isReplay: false), "Começar")
        XCTAssertEqual(OnboardingTour.advanceTitle(for: .done, isReplay: true), "Fechar")
        XCTAssertEqual(OnboardingTour.skipTitle(isReplay: false), "Pular")
        XCTAssertEqual(OnboardingTour.skipTitle(isReplay: true), "Fechar")
        XCTAssertEqual(OnboardingTour.skipLabel(isReplay: false), "Pular a demonstração")
        XCTAssertEqual(OnboardingTour.skipLabel(isReplay: true), "Fechar a demonstração")
        XCTAssertEqual(
            OnboardingTour.Step.allCases.map(OnboardingTour.progressValue(for:)),
            (1...6).map { "Etapa \($0) de 6" }
        )
    }

    func testVoiceOverHearsWhichTabTheCloseOpensAndAReplayNamesNone() {
        XCTAssertEqual(OnboardingTour.advanceHint(for: .done, context: context(chat: .open)), "Abre a aba Nina.")
        XCTAssertEqual(OnboardingTour.advanceHint(for: .done, context: context(chat: .needsConsent)), "Abre a aba Nina.")
        XCTAssertEqual(OnboardingTour.advanceHint(for: .done, context: context(chat: .awaitingAge)), "Abre a aba Hoje.")
        XCTAssertEqual(OnboardingTour.advanceHint(for: .done, context: context(chat: .closed)), "Abre a aba Hoje.")

        for chat in TourChatState.allCases {
            XCTAssertNil(OnboardingTour.advanceHint(for: .done, context: context(chat: chat, isReplay: true)))
            for step in OnboardingTour.Step.allCases where step != .done {
                XCTAssertNil(OnboardingTour.advanceHint(for: step, context: context(chat: chat)))
            }
        }
    }

    func testTheSkipAnswersToAFortyFourPointFingerAcrossAndDown() {
        for isReplay in [false, true] {
            let title = OnboardingTour.skipTitle(isReplay: isReplay)
            let size = UIHostingController(rootView: NinaButtonFace(title: title, kind: .quiet))
                .sizeThatFits(in: CGSize(width: 400, height: 400))
            XCTAssertGreaterThanOrEqual(size.width, 44, title)
            XCTAssertGreaterThanOrEqual(size.height, 44, title)
        }
    }

    func testTheMapsPillEndsAtLeastFourPointsAboveADisplayEdgeAndNeverPastTheBarAboveAHomeIndicator() {
        let reach = TabBarClearance.tourPillReachBelowTitle
        XCTAssertGreaterThanOrEqual(TabBarClearance.bottomPadding(meetsDisplayEdge: true) - reach, 4)
        XCTAssertGreaterThanOrEqual(TabBarClearance.bottomPadding(meetsDisplayEdge: false), reach)
    }

    private func context(
        chat: TourChatState,
        name: String? = "Ana",
        isReplay: Bool = false
    ) -> TourContext {
        TourContext(name: name, chat: chat, isReplay: isReplay, now: instant(2026, 10, 14, 15, 0))
    }

    private func allContexts() -> [TourContext] {
        TourChatState.allCases.flatMap { chat in
            [false, true].flatMap { isReplay in
                ["Ana", nil].map { name in context(chat: chat, name: name, isReplay: isReplay) }
            }
        }
    }

    private func chatState(
        canUse: Bool = false,
        requiresConsent: Bool = false,
        hasConsent: Bool = false,
        isBlocked: Bool = false,
        isAdult: Bool = false,
        needsConfirmedAge: Bool = false
    ) -> TourChatState {
        TourChatState(
            canUseNinaAI: canUse,
            requiresConsent: requiresConsent,
            hasConsent: hasConsent,
            isBlocked: isBlocked,
            isAdult: isAdult,
            needsConfirmedAge: needsConfirmedAge
        )
    }

    private func words(in text: String) -> [String] {
        text
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    private func wordCount(_ text: String, leavingOut name: String?) -> Int {
        let tokens = words(in: text)
        guard let name else { return tokens.count }
        return tokens.count { $0 != name }
    }

    private func sentenceEnds(in text: String) -> Int {
        text.count { ".?!".contains($0) }
    }

    private func instant(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        calendar.date(
            from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
        ) ?? .distantPast
    }
}
