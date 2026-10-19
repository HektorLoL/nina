import SwiftUI
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

    func testAFittedSheetIsExactlyAsTallAsItsHeaderFieldsAndBarRoundedUpToAWholePoint() {
        let parts = SheetFit.Parts(header: 59.6, content: 160.2, bar: 118.1)

        XCTAssertEqual(SheetFit.height(parts), 338)
        XCTAssertEqual(SheetFit.detent(parts), .height(338))
        XCTAssertEqual(SheetFit.height(SheetFit.Parts(header: 60, content: 156, bar: 118)), 334)
    }

    func testASheetNotYetMeasuredOpensAtMediumAndNeverAtZeroHeight() {
        XCTAssertEqual(SheetFit.detent(SheetFit.Parts()), .medium)
        XCTAssertEqual(SheetFit.detent(SheetFit.Parts(header: 60, content: 0, bar: 118)), .medium)
        XCTAssertFalse(SheetFit.isChange(from: 156, to: 156.4))
        XCTAssertTrue(SheetFit.isChange(from: 156, to: 156.5))
        XCTAssertTrue(SheetFit.isChange(from: 222.3, to: 156))
    }

    func testAFittedSheetThatReachesFullHeightKeepsItsCardHeightSoItNeverFlipsBackAndForth() {
        let card = SheetFit.content(after: SheetFit.ContentReading(), height: 500, width: 346)
        XCTAssertEqual(card.height, 500)

        let full = SheetFit.content(after: card, height: 480, width: 362)
        XCTAssertEqual(full.height, 500)
        XCTAssertEqual(full.width, 362)

        let typed = SheetFit.content(after: full, height: 490, width: 362)
        XCTAssertEqual(typed.height, 510)

        let cleared = SheetFit.content(after: typed, height: 380, width: 362)
        XCTAssertEqual(cleared.height, 400)

        let cardAgain = SheetFit.content(after: cleared, height: 401, width: 346)
        XCTAssertEqual(cardAgain, SheetFit.ContentReading(height: 401, width: 346, widening: 0))

        let edited = SheetFit.content(after: cardAgain, height: 420, width: 346)
        XCTAssertEqual(edited.height, 420)
    }

    func testWithTheKeyboardUpAFittedCardGivesBackTheHeightItsHomeIndicatorAddedSoNoGlazeOpensAboveTheChips() {
        let parts = SheetFit.Parts(header: 60, content: 160, bar: 119)

        let surplus = SheetFit.keyboardSurplus(container: 369.3, parts: parts, previous: 0)
        XCTAssertEqual(surplus, 30)
        XCTAssertEqual(SheetFit.detent(parts, keyboardSurplus: surplus), .height(309))
        XCTAssertEqual(SheetFit.keyboardSurplus(container: 339.3, parts: parts, previous: surplus), 30)

        XCTAssertEqual(SheetFit.keyboardSurplus(container: 300, parts: parts, previous: 0), 0)
        XCTAssertEqual(SheetFit.keyboardSurplus(container: 600, parts: parts, previous: 0), 44)
        XCTAssertEqual(SheetFit.keyboardSurplus(container: 400, parts: SheetFit.Parts(), previous: 0), 0)
        XCTAssertEqual(SheetFit.detent(parts), .height(339))
    }

    func testTheFirstKeyboardOfALaunchLandsTheCardInOneMoveBecauseItsSurplusIsKnownBeforeTheKeyboard() {
        let homeIndicator: CGFloat = 34
        let seed = SheetFit.keyboardSurplus(learned: nil, bottomInset: homeIndicator)
        XCTAssertEqual(seed, 28)

        let parts = SheetFit.Parts(header: 60, content: 156, bar: 143)
        let landed = SheetFit.keyboardSurplus(container: 359.3, parts: parts, previous: seed)
        XCTAssertLessThan(abs(landed - seed), 2, "the card would settle again once the keyboard landed")

        XCTAssertEqual(SheetFit.keyboardSurplus(learned: nil, bottomInset: 0), 0)
        XCTAssertEqual(SheetFit.keyboardSurplus(learned: 30, bottomInset: homeIndicator), 30)
        XCTAssertEqual(SheetFit.keyboardSurplus(learned: nil, bottomInset: 120), SheetFit.maximumKeyboardSurplus)

        XCTAssertEqual(SheetFit.restingBottomInset(34), 34)
        XCTAssertEqual(SheetFit.restingBottomInset(0), 0)
        XCTAssertNil(SheetFit.restingBottomInset(271.3), "a keyboard's inset is never read as the card's resting one")

        XCTAssertTrue(SheetFit.learnsKeyboardSurplus(measured: 28, applied: 0))
        XCTAssertFalse(SheetFit.learnsKeyboardSurplus(measured: 28, applied: 28))
        XCTAssertFalse(
            SheetFit.learnsKeyboardSurplus(measured: 11, applied: 28),
            "a card clamped under the status bar never teaches a smaller surplus"
        )
    }

    func testAHardwareKeyboardsOffScreenFrameNeverShrinksAFittedCard() throws {
        let screen = try XCTUnwrap(
            UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.screen }.first
        )
        let bottom = screen.bounds.maxY

        func note(_ frame: CGRect?) -> Notification {
            Notification(
                name: UIResponder.keyboardWillShowNotification,
                object: screen,
                userInfo: frame.map { [UIResponder.keyboardFrameEndUserInfoKey: NSValue(cgRect: $0)] }
            )
        }

        XCTAssertTrue(SheetFit.keyboardIsOnScreen(note(CGRect(x: 0, y: bottom - 335, width: 402, height: 335))))
        XCTAssertFalse(SheetFit.keyboardIsOnScreen(note(CGRect(x: 0, y: bottom, width: 402, height: 335))))
        XCTAssertFalse(SheetFit.keyboardIsOnScreen(note(nil)))
    }

    func testAFirstLayoutAtAPassingNarrowWidthNeverSetsTheSheetsHeight() {
        let passing = SheetFit.content(after: SheetFit.ContentReading(), height: 222, width: 148)
        let settled = SheetFit.content(after: passing, height: 156, width: 346)

        XCTAssertEqual(settled, SheetFit.ContentReading(height: 156, width: 346, widening: 0))
    }

    func testTheSelectionBarHoldsOneRowShortOfAccessibilitySizesByDroppingItsGlyphsAndStacksOnlyThere() {
        for size in [DynamicTypeSize.large, .xLarge, .xxLarge, .xxxLarge] {
            let face = fittedSize(
                NinaButtonFace(title: "Passar", kind: .outline),
                width: 1_000,
                dynamicTypeSize: size
            ).height

            for width in [CGFloat(335), 362] {
                let bar = fittedSize(selectionBar(), width: width, dynamicTypeSize: size)

                XCTAssertLessThanOrEqual(bar.width, width + 0.5, "\(size) at \(width)")
                XCTAssertEqual(
                    bar.height,
                    max(face, 48),
                    accuracy: 0.5,
                    "the bar stacked or a label wrapped at \(size), \(width)"
                )
            }
        }

        for size in [DynamicTypeSize.accessibility1, .accessibility3] {
            let face = fittedSize(
                NinaButtonFace(title: "Passar", kind: .outline, fillsWidth: true),
                width: 335,
                dynamicTypeSize: size
            ).height

            XCTAssertEqual(
                fittedSize(selectionBar(), width: 335, dynamicTypeSize: size).height,
                face * 2 + 48 + 20,
                accuracy: 0.5,
                "\(size)"
            )
        }
    }

    func testAFittedSheetDrawsAnEdgeOnlyWhereItsFieldsRunUnderTheHeaderOrTheBar() {
        XCTAssertEqual(SheetFit.slicedEdges(content: 300, visible: 300.5, scrolled: 0), SheetFit.SlicedEdges())
        XCTAssertEqual(SheetFit.slicedEdges(content: 300.8, visible: 300, scrolled: 0), SheetFit.SlicedEdges())
        XCTAssertEqual(
            SheetFit.slicedEdges(content: 300, visible: 300, scrolled: 12),
            SheetFit.SlicedEdges(),
            "a card at rest that only bounces never draws an edge"
        )
        XCTAssertEqual(SheetFit.slicedEdges(content: 640, visible: 0, scrolled: 0), SheetFit.SlicedEdges())

        XCTAssertEqual(
            SheetFit.slicedEdges(content: 640, visible: 480, scrolled: 0),
            SheetFit.SlicedEdges(top: false, bottom: true)
        )
        XCTAssertEqual(
            SheetFit.slicedEdges(content: 640, visible: 480, scrolled: 80),
            SheetFit.SlicedEdges(top: true, bottom: true)
        )
        XCTAssertEqual(
            SheetFit.slicedEdges(content: 640, visible: 480, scrolled: 160),
            SheetFit.SlicedEdges(top: true, bottom: false)
        )
        XCTAssertEqual(
            SheetFit.slicedEdges(content: 640, visible: 480, scrolled: 190),
            SheetFit.SlicedEdges(top: true, bottom: false)
        )
    }

    func testAClampedCardAtRestMarksItsBarEvenWhenTheScrollViewNeverReportedWhereItSettled() {
        let unreported = SheetFit.ScrollMarks()
        let staleSizingPass = SheetFit.ScrollMarks(leftTop: false, reachedEnd: true)

        for marks in [unreported, staleSizingPass] {
            XCTAssertEqual(
                SheetFit.slicedEdges(content: 292, visible: 201.7, marks: marks),
                SheetFit.SlicedEdges(top: false, bottom: true)
            )
            XCTAssertEqual(SheetFit.slicedEdges(content: 201, visible: 201.7, marks: marks), SheetFit.SlicedEdges())
            XCTAssertEqual(SheetFit.slicedEdges(content: 292, visible: 0, marks: marks), SheetFit.SlicedEdges())
        }
        XCTAssertEqual(
            SheetFit.slicedEdges(content: 292, visible: 201.7, marks: SheetFit.ScrollMarks(leftTop: true, reachedEnd: false)),
            SheetFit.SlicedEdges(top: true, bottom: true)
        )
        XCTAssertEqual(
            SheetFit.slicedEdges(content: 292, visible: 201.7, marks: SheetFit.ScrollMarks(leftTop: true, reachedEnd: true)),
            SheetFit.SlicedEdges(top: true, bottom: false)
        )
        XCTAssertEqual(
            SheetFit.scrollMarks(content: 292, visible: 201.7, scrolled: 0),
            SheetFit.ScrollMarks(leftTop: false, reachedEnd: false)
        )
        XCTAssertEqual(
            SheetFit.scrollMarks(content: 292, visible: 201.7, scrolled: 90.3),
            SheetFit.ScrollMarks(leftTop: true, reachedEnd: true)
        )
    }

    func testAddingAShoppingItemKeepsAdicionarEContinuarAfterTheOwnerChipBesideOrAboveItsCommitAndNeverWrapsALabel() {
        func commitRow(_ size: DynamicTypeSize, width: CGFloat) -> CGSize {
            fittedSize(
                EditorCommitRow(title: "Adicionar", isEnabled: false, action: {}) {
                    EditorContinueButton(isEnabled: false) {}
                },
                width: width,
                dynamicTypeSize: size
            )
        }

        for size in [DynamicTypeSize.xSmall, .large, .xLarge, .xxLarge, .xxxLarge] {
            XCTAssertEqual(
                EditorSecondaryPlacement.continuePlacement(isAdding: true, isAccessibilitySize: size.isAccessibilitySize),
                .bar,
                "\(size)"
            )

            let quiet = fittedSize(EditorContinueButton(isEnabled: false) {}, width: 1_000, dynamicTypeSize: size).height
            let commit = fittedSize(
                NinaButtonFace(title: "Adicionar", systemName: "arrow.up"),
                width: 1_000,
                dynamicTypeSize: size
            ).height
            let oneRow = max(quiet, commit) + 12 + 8
            let stacked = quiet + 4 + commit + 12 + 8

            for width in [CGFloat(304), 359, 386, 424] {
                let row = commitRow(size, width: width)

                XCTAssertLessThanOrEqual(row.width, width + 0.5, "\(size) at \(width)")
                XCTAssertTrue(
                    abs(row.height - oneRow) < 0.5 || abs(row.height - stacked) < 0.5,
                    "a label wrapped at \(size), \(width): \(row.height), one row \(oneRow), stacked \(stacked)"
                )
            }

            if size == .large {
                XCTAssertEqual(commitRow(size, width: 304).height, stacked, accuracy: 0.5, "a 320-point phone")
            }
        }

        for (size, width) in [(DynamicTypeSize.large, CGFloat(359)), (.large, 386), (.xLarge, 386)] {
            XCTAssertEqual(commitRow(size, width: width).height, 50 + 12 + 8, accuracy: 0.5, "\(size) at \(width)")
        }

        for size in [DynamicTypeSize.accessibility1, .accessibility3, .accessibility5] {
            XCTAssertEqual(
                EditorSecondaryPlacement.continuePlacement(isAdding: true, isAccessibilitySize: size.isAccessibilitySize),
                .column,
                "\(size)"
            )
        }
        XCTAssertNil(EditorSecondaryPlacement.continuePlacement(isAdding: false, isAccessibilitySize: false))
        XCTAssertNil(EditorSecondaryPlacement.continuePlacement(isAdding: false, isAccessibilitySize: true))
    }

    func testAnEditorOffersApagarOnlyWhenEditingBesideTheCommitAndAtTheEndOfTheFieldsAtAccessibilitySizes() {
        let id = UUID()
        let add = TaskEditorMode.add(sectionID: AppStore.houseTasksSectionID)

        for size in [DynamicTypeSize.large, .accessibility1] {
            XCTAssertNil(TaskEditorSheet.deletePlacement(mode: add, dynamicTypeSize: size))
            XCTAssertNil(TaskEditorSheet.deletePlacement(mode: .plant(id), dynamicTypeSize: size))
        }
        XCTAssertEqual(TaskEditorSheet.deletePlacement(mode: .edit(id), dynamicTypeSize: .large), .bar)
        XCTAssertEqual(TaskEditorSheet.deletePlacement(mode: .edit(id), dynamicTypeSize: .xxxLarge), .bar)
        XCTAssertEqual(TaskEditorSheet.deletePlacement(mode: .edit(id), dynamicTypeSize: .accessibility1), .column)
        XCTAssertNil(EditorSecondaryPlacement.deletePlacement(isEditing: false, isAccessibilitySize: true))
        XCTAssertEqual(EditorSecondaryPlacement.deletePlacement(isEditing: true, isAccessibilitySize: false), .bar)
        XCTAssertEqual(EditorSecondaryPlacement.deletePlacement(isEditing: true, isAccessibilitySize: true), .column)
    }

    func testASwipeOrAStrayTapAboveTheCardNeverThrowsAwayWhatThePersonTypedInAnEditor() {
        let id = UUID()
        let add = TaskEditorMode.add(sectionID: AppStore.houseTasksSectionID)
        let due = date(year: 2026, month: 10, day: 20, hour: 9, minute: 0)
        let loaded = TaskEditorSheet.Draft(title: "Pagar a luz", subtitle: "", dueDate: due, category: .bills)

        XCTAssertFalse(TaskEditorSheet.hasUnsavedInput(mode: add, loaded: nil, current: TaskEditorSheet.Draft(dueDate: due)))
        XCTAssertFalse(TaskEditorSheet.hasUnsavedInput(mode: add, loaded: nil, current: TaskEditorSheet.Draft(title: "  \n", dueDate: due)))
        XCTAssertTrue(TaskEditorSheet.hasUnsavedInput(mode: add, loaded: nil, current: TaskEditorSheet.Draft(title: "Gás", dueDate: due)))
        XCTAssertTrue(TaskEditorSheet.hasUnsavedInput(mode: add, loaded: nil, current: TaskEditorSheet.Draft(subtitle: "Ligar antes", dueDate: due)))

        for mode in [TaskEditorMode.edit(id), .plant(id)] {
            XCTAssertFalse(TaskEditorSheet.hasUnsavedInput(mode: mode, loaded: nil, current: loaded), "\(mode)")
            XCTAssertFalse(TaskEditorSheet.hasUnsavedInput(mode: mode, loaded: loaded, current: loaded), "\(mode)")

            var retitled = loaded
            retitled.title = "Pagar a conta de luz"
            XCTAssertTrue(TaskEditorSheet.hasUnsavedInput(mode: mode, loaded: loaded, current: retitled), "\(mode)")

            var moved = loaded
            moved.dueDate = due.addingTimeInterval(3_600)
            XCTAssertTrue(TaskEditorSheet.hasUnsavedInput(mode: mode, loaded: loaded, current: moved), "\(mode)")

            var reassigned = loaded
            reassigned.ownerMemberID = UUID()
            XCTAssertTrue(TaskEditorSheet.hasUnsavedInput(mode: mode, loaded: loaded, current: reassigned), "\(mode)")
        }

        let item = ShoppingEditorSheet.Draft(title: "Gás", amount: "1 botijão")
        XCTAssertFalse(ShoppingEditorSheet.hasUnsavedInput(mode: .add, loaded: nil, current: ShoppingEditorSheet.Draft()))
        XCTAssertTrue(ShoppingEditorSheet.hasUnsavedInput(mode: .add, loaded: nil, current: ShoppingEditorSheet.Draft(amount: "2 kg")))
        XCTAssertFalse(ShoppingEditorSheet.hasUnsavedInput(mode: .edit(id), loaded: item, current: item))
        XCTAssertTrue(
            ShoppingEditorSheet.hasUnsavedInput(
                mode: .edit(id),
                loaded: item,
                current: ShoppingEditorSheet.Draft(title: "Gás", amount: "2 botijões")
            )
        )

        let person = MemberEditorSheet.Draft(name: "Thor", relationship: "Cachorro", householdRole: .pet, tone: .amber)
        XCTAssertFalse(MemberEditorSheet.hasUnsavedInput(mode: .addProfile, loaded: nil, current: MemberEditorSheet.Draft()))
        XCTAssertTrue(MemberEditorSheet.hasUnsavedInput(mode: .addProfile, loaded: nil, current: MemberEditorSheet.Draft(name: "Bia")))
        XCTAssertFalse(MemberEditorSheet.hasUnsavedInput(mode: .edit(id), loaded: person, current: person))
        var retoned = person
        retoned.tone = .lavender
        XCTAssertTrue(MemberEditorSheet.hasUnsavedInput(mode: .edit(id), loaded: person, current: retoned))
    }

    func testAStepMovesOnlyTheLeadingNumberAndKeepsTheWordsAfterIt() {
        let cases: [(amount: String, delta: Int, expected: String)] = [
            ("", 1, "1"),
            ("", 10, "10"),
            ("3", 1, "4"),
            ("3 kg", 1, "4 kg"),
            ("3kg", 10, "13kg"),
            ("  3 kg ", 1, "4 kg"),
            ("2 pacotes de café", 1, "3 pacotes de café"),
            ("1 garrafa de 2 litros", 1, "2 garrafas de 2 litros"),
            ("05", 1, "6"),
        ]

        for (amount, delta, expected) in cases {
            XCTAssertEqual(ShoppingAmount.stepped(amount, by: delta), expected, "\"\(amount)\" \(delta)")
        }
    }

    func testAStepNeverDropsAUnitAndNeverGuessesAtAFractionARangeOrAWord() {
        let cases: [(amount: String, delta: Int, expected: String?)] = [
            ("", -1, nil),
            ("1", -1, ""),
            ("0", -1, ""),
            ("0", 1, "1"),
            ("1 kg", -1, nil),
            ("1 botijão", -1, nil),
            ("meio quilo", 1, nil),
            ("uma dúzia", 1, nil),
            ("1,5 kg", 1, nil),
            ("1.000 g", 1, nil),
            ("1/2 kg", 1, nil),
            ("2-3", 1, nil),
            ("2 a 3", 1, nil),
            ("2 ou 3 latas", 1, nil),
            ("-3", 1, nil),
        ]

        for (amount, delta, expected) in cases {
            XCTAssertEqual(ShoppingAmount.stepped(amount, by: delta), expected, "\"\(amount)\" \(delta)")
        }
    }

    func testAPackTurnsIntoPacksAndBackAndAnAbbreviationStaysAsWritten() {
        let cases: [(amount: String, delta: Int, expected: String)] = [
            ("1 botijão", 1, "2 botijões"),
            ("2 botijões", -1, "1 botijão"),
            ("2 pacotes", -1, "1 pacote"),
            ("2 pacotes de 500 g", -1, "1 pacote de 500 g"),
            ("3 pacotes", 1, "4 pacotes"),
            ("0 pacotes", 1, "1 pacote"),
            ("1 pão", 1, "2 pães"),
            ("1 Caixa", 1, "2 Caixas"),
            ("1 bisnaga", 1, "2 bisnagas"),
            ("1 kg", 1, "2 kg"),
            ("3 un.", 1, "4 un."),
        ]

        for (amount, delta, expected) in cases {
            XCTAssertEqual(ShoppingAmount.stepped(amount, by: delta), expected, "\"\(amount)\" \(delta)")
        }
    }

    func testTheQuickStepsStopAt999() {
        XCTAssertEqual(ShoppingAmount.stepCeiling, 999)
        XCTAssertEqual(ShoppingAmount.stepped("995", by: 10), "999")
        XCTAssertNil(ShoppingAmount.stepped("999", by: 1))
        XCTAssertNil(ShoppingAmount.stepped("999", by: 10))
        XCTAssertNil(ShoppingAmount.stepped("1200 g", by: 1))
        XCTAssertEqual(ShoppingAmount.stepped("1200 g", by: -1), "1199 g")
    }

    func testABarsCommitSitsTwentyPointsAboveACardsFootOnAPhoneWithoutAHomeIndicator() {
        let commitRowBottom: CGFloat = 8

        XCTAssertEqual(commitRowBottom + SheetFit.barBottomPadding(bottomInset: 0, keyboardIsUp: false), 20)
        XCTAssertEqual(SheetFit.barBottomPadding(bottomInset: 34, keyboardIsUp: false), 0)
        XCTAssertEqual(SheetFit.barBottomPadding(bottomInset: 25, keyboardIsUp: false), 0)
        XCTAssertEqual(SheetFit.barBottomPadding(bottomInset: 5, keyboardIsUp: false), 7)
        XCTAssertEqual(SheetFit.barBottomPadding(bottomInset: 0, keyboardIsUp: true), 0)
    }

    func testASheetsEyebrowNeverRunsUnderItsCloseDiscAtAnyTypeSize() {
        let header = SheetHeader(eyebrow: "Plantar semente") {}
        let wide = fittedSize(header, width: 1_000, dynamicTypeSize: .accessibility3)
        let card = fittedSize(header, width: 359, dynamicTypeSize: .accessibility3)

        XCTAssertLessThanOrEqual(card.width, 359.5)
        XCTAssertGreaterThan(card.height, wide.height + 20, "the eyebrow kept one line under the close disc")
        XCTAssertEqual(fittedSize(header, width: 386, dynamicTypeSize: .large).height, 60, accuracy: 0.5)
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

    func testALabelTheReaderCouldNotPlaceSaysItHasNoReminder() {
        var vague = task(dueAt: nil)
        vague.dueLabel = "Sexta à tarde"
        XCTAssertTrue(vague.namesADayWithoutAReminder)

        var undated = vague
        undated.dueLabel = "Sem data"
        XCTAssertFalse(undated.namesADayWithoutAReminder)

        var seed = vague
        seed.kind = .seed
        XCTAssertFalse(seed.namesADayWithoutAReminder)

        var done = vague
        done.isDone = true
        XCTAssertFalse(done.namesADayWithoutAReminder)

        let dated = task(dueAt: date(year: 2026, month: 8, day: 14, hour: 15, minute: 0))
        XCTAssertFalse(dated.namesADayWithoutAReminder)
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

    func testClosingATaskLiftsTheMarkAndReopeningItLeavesTheMarkStill() {
        let store = AppStore(remoteHomeBackend: nil, ninaEngine: MockNinaEngine())
        guard let open = store.tasks.first(where: { !$0.isDone && $0.recurrence == .none }),
              let repeating = store.tasks.first(where: { !$0.isDone && $0.recurrence != .none }) else {
            return XCTFail("PreviewData should seed an open one-off task and an open repeating task.")
        }

        store.toggleTask(open)
        store.toggleTask(repeating)
        XCTAssertEqual(store.completionPulse, 2)

        guard let closed = store.tasks.first(where: { $0.id == open.id }) else { return XCTFail() }
        store.toggleTask(closed)
        XCTAssertEqual(store.completionPulse, 2)
    }

    func testAGroupListsWhatIsLateFirstThenTheSoonestAndUndatedLast() {
        var undated = task(dueAt: nil)
        undated.title = "Um dia, pintar a sala"
        var later = task(dueAt: now.addingTimeInterval(3 * 24 * 60 * 60))
        later.title = "Levar o carro na revisão"
        var late = task(dueAt: now.addingTimeInterval(-2 * 24 * 60 * 60))
        late.title = "Pagar a conta de luz"
        var soon = task(dueAt: now.addingTimeInterval(2 * 60 * 60))
        soon.title = "Buscar o Pedro"

        let ordered = TaskListOrder.sorted([undated, later, late, soon], now: now, calendar: calendar)

        XCTAssertEqual(ordered.map(\.title), [late.title, soon.title, later.title, undated.title])
    }

    func testUrgencyBreaksATieAndOtherwiseTheListKeepsItsOrder() {
        let moment = now.addingTimeInterval(60 * 60)
        var first = task(dueAt: moment)
        first.title = "Primeira"
        var urgent = task(dueAt: moment)
        urgent.title = "Urgente"
        urgent.priority = .urgent
        var second = task(dueAt: moment)
        second.title = "Segunda"

        let ordered = TaskListOrder.sorted([first, urgent, second], now: now, calendar: calendar)

        XCTAssertEqual(ordered.map(\.title), ["Urgente", "Primeira", "Segunda"])
    }

    func testAnUrgentTaskCarriesARedFlagAHighOneAYellowFlagWithAnEdgeAndANormalOneNone() {
        XCTAssertNil(PriorityFlag.fill(for: .normal))
        XCTAssertNil(PriorityFlag.edge(for: .normal))
        XCTAssertNil(TaskPriority.normal.rowFlagLabel)
        XCTAssertEqual(PriorityFlag.fill(for: .high), NinaTheme.priorityHigh)
        XCTAssertEqual(PriorityFlag.edge(for: .high), NinaTheme.priorityHighEdge)
        XCTAssertEqual(TaskPriority.high.rowFlagLabel, "Prioridade alta")
        XCTAssertEqual(PriorityFlag.fill(for: .urgent), NinaTheme.alert)
        XCTAssertNil(PriorityFlag.edge(for: .urgent))
        XCTAssertEqual(TaskPriority.urgent.rowFlagLabel, "Urgente")
    }

    func testAnOpenUrgentOrHighRowIsTintedWithNoHairlineAlongItAndADoneOrNormalRowIsNot() {
        var plain = task(dueAt: nil)
        plain.title = "Varrer"
        var high = task(dueAt: nil)
        high.title = "Comprar gás"
        high.priority = .high
        var urgent = task(dueAt: nil)
        urgent.title = "Pagar a luz"
        urgent.priority = .urgent
        var doneUrgent = urgent
        doneUrgent.id = UUID()
        doneUrgent.isDone = true
        var last = task(dueAt: nil)
        last.title = "Lavar a louça"

        XCTAssertNil(PriorityFlag.rowTint(for: plain))
        XCTAssertEqual(PriorityFlag.rowTint(for: high), NinaTheme.priorityHighWash)
        XCTAssertEqual(PriorityFlag.rowTint(for: urgent), NinaTheme.priorityUrgentWash)
        XCTAssertNil(PriorityFlag.rowTint(for: doneUrgent))

        XCTAssertEqual(PriorityFlag.rowAccessibilityTitle(for: urgent), "Urgente, Pagar a luz")
        XCTAssertEqual(PriorityFlag.rowAccessibilityTitle(for: high), "Prioridade alta, Comprar gás")
        XCTAssertEqual(PriorityFlag.rowAccessibilityTitle(for: doneUrgent), "Pagar a luz")

        let list = [plain, high, doneUrgent, last]
        XCTAssertFalse(PriorityFlag.showsDivider(after: plain, in: list))
        XCTAssertFalse(PriorityFlag.showsDivider(after: high, in: list))
        XCTAssertTrue(PriorityFlag.showsDivider(after: doneUrgent, in: list))
        XCTAssertFalse(PriorityFlag.showsDivider(after: last, in: list))
        XCTAssertTrue(PriorityFlag.showsDivider(after: last, in: list, dividesLast: true))
    }

    func testAProposalThatRepeatsSomethingStillOpenIsFlaggedAndADoneOneIsNot() {
        var gas = task(dueAt: nil)
        gas.title = "Comprar gás"
        var oldBill = task(dueAt: nil)
        oldBill.title = "Pagar a luz"
        oldBill.isDone = true
        let milk = ShoppingItem(title: "Leite", amount: "", owner: "Casa", isChecked: false)

        XCTAssertTrue(HouseSearch.openTwin(
            of: NinaProposalPayload(title: "comprar GAS", detail: ""),
            kind: .task, tasks: [gas, oldBill], shoppingItems: [milk]
        ))
        XCTAssertFalse(HouseSearch.openTwin(
            of: NinaProposalPayload(title: "Pagar a luz", detail: ""),
            kind: .reminder, tasks: [gas, oldBill], shoppingItems: [milk]
        ))
        XCTAssertTrue(HouseSearch.openTwin(
            of: NinaProposalPayload(title: "leite", detail: ""),
            kind: .shopping, tasks: [gas, oldBill], shoppingItems: [milk]
        ))
        XCTAssertFalse(HouseSearch.openTwin(
            of: NinaProposalPayload(title: "Comprar gás", detail: ""),
            kind: .memory, tasks: [gas, oldBill], shoppingItems: [milk]
        ))
    }

    func testSearchFindsATaskTypedWithoutAccentsOrCapitals() {
        var medicine = task(dueAt: nil)
        medicine.title = "Remédio do Pedro"
        var bill = task(dueAt: nil)
        bill.title = "Pagar a conta de luz"
        bill.subtitle = "Vence na sexta"

        XCTAssertEqual(HouseSearch.tasks([medicine, bill], query: "remedio").map(\.id), [medicine.id])
        XCTAssertEqual(HouseSearch.tasks([medicine, bill], query: "  SEXTA ").map(\.id), [bill.id])
        XCTAssertTrue(HouseSearch.tasks([medicine, bill], query: "   ").isEmpty)
    }

    func testSearchAlsoFindsWhatIsOnTheShoppingList() {
        let soap = ShoppingItem(title: "Sabão em pó", amount: "2 caixas", owner: "Casa", isChecked: false)
        let bread = ShoppingItem(title: "Pão", amount: "", owner: "Casa", isChecked: true)

        XCTAssertEqual(HouseSearch.shoppingItems([soap, bread], query: "sabao").map(\.id), [soap.id])
        XCTAssertEqual(HouseSearch.shoppingItems([soap, bread], query: "pao").map(\.id), [bread.id])
        XCTAssertEqual(HouseSearch.shoppingItems([soap, bread], query: "caixas").map(\.id), [soap.id])
    }

    func testSearchFindsAMemoryByItsTitleOrItsDetail() {
        func memory(_ title: String, _ body: String) -> NinaMemory {
            NinaMemory(
                id: UUID(),
                familyID: UUID(),
                ownerUserID: nil,
                title: title,
                body: body,
                visibility: .shared,
                confidence: 1,
                createdAt: .distantPast,
                updatedAt: .distantPast
            )
        }
        let allergy = memory("Alergia do Pedro", "Não pode amendoim")
        let wifi = memory("Senha do portão", "Código na gaveta da cozinha")

        XCTAssertEqual(HouseSearch.memories([allergy, wifi], query: "alergia").map(\.id), [allergy.id])
        XCTAssertEqual(HouseSearch.memories([allergy, wifi], query: "COZINHA").map(\.id), [wifi.id])
        XCTAssertEqual(HouseSearch.memories([allergy, wifi], query: "portao").map(\.id), [wifi.id])
        XCTAssertTrue(HouseSearch.memories([allergy, wifi], query: " ").isEmpty)
    }

    func testFinishingARepeatingTaskForTodayOffersAnUndoThatPutsTheOccurrenceBack() throws {
        try withIsolatedStore { store in
            var daily = task(dueAt: now.addingTimeInterval(2 * 60 * 60))
            daily.recurrence = .daily
            daily.dueLabel = "Hoje, 12:00"
            store.tasks = [daily]

            store.toggleTask(daily)
            let rolled = try XCTUnwrap(store.tasks.first { $0.id == daily.id })
            XCTAssertNotEqual(rolled.dueAt, daily.dueAt)
            XCTAssertEqual(store.undoableCompletionID, daily.id)

            store.undoLastCompletion()

            let restored = try XCTUnwrap(store.tasks.first { $0.id == daily.id })
            XCTAssertEqual(restored.dueAt, daily.dueAt)
            XCTAssertEqual(restored.dueLabel, daily.dueLabel)
            XCTAssertFalse(restored.isDone)
            XCTAssertNil(store.undoableCompletionID)
        }
    }

    func testFinishingFromAnEarlyReminderClosesTheAnnouncedOccurrenceEvenAfterAMissedOne() throws {
        try withIsolatedStore { store in
            let calendar = Calendar.current
            let announced = try XCTUnwrap(
                calendar.dateInterval(of: .minute, for: Date().addingTimeInterval(30 * 60))?.start
            )
            var daily = task(dueAt: try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: announced)))
            daily.recurrence = .daily
            store.tasks = [daily]

            store.toggleTask(daily, through: announced)

            let rolled = try XCTUnwrap(store.tasks.first { $0.id == daily.id })
            XCTAssertEqual(
                rolled.dueAt,
                calendar.date(byAdding: .day, value: 1, to: announced),
                "Yesterday's missed turn must not absorb the tap meant for today's."
            )
        }
    }

    func testFinishingSeveralTasksClosesEachAsOneTapWouldAndLeavesNoUndo() throws {
        try withIsolatedStore { store in
            let bill = task(dueAt: now.addingTimeInterval(60 * 60))
            let errand = task(dueAt: nil)
            var daily = task(dueAt: now.addingTimeInterval(2 * 60 * 60))
            daily.recurrence = .daily
            var seed = task(dueAt: nil)
            seed.kind = .seed
            let untouched = task(dueAt: nil)
            store.tasks = [bill, errand, daily, seed, untouched]

            store.completeTasks([bill.id, errand.id, daily.id, seed.id])

            let byID = Dictionary(uniqueKeysWithValues: store.tasks.map { ($0.id, $0) })
            XCTAssertEqual(byID[bill.id]?.isDone, true)
            XCTAssertEqual(byID[errand.id]?.isDone, true)
            XCTAssertEqual(byID[daily.id]?.isDone, false)
            XCTAssertNotEqual(byID[daily.id]?.dueAt, daily.dueAt, "A repeating task moves to its next turn.")
            XCTAssertEqual(byID[seed.id]?.isDone, false, "A semente is planted, never ticked.")
            XCTAssertEqual(byID[untouched.id]?.isDone, false)
            XCTAssertNil(store.undoableCompletionID)
        }
    }

    func testHandingSeveralTasksOverMovesOnlyThoseAndSemDonoClearsTheOwner() throws {
        try withIsolatedStore { store in
            let member = HouseholdMember(
                name: "Ana Souza",
                relationship: "Esposa",
                role: .adult,
                tone: .mint,
                taskCount: 0,
                memoryNote: ""
            )
            let first = task(dueAt: nil)
            let second = task(dueAt: nil)
            let other = task(dueAt: nil)
            store.tasks = [first, second, other]

            store.reassignTasks([first.id, second.id], to: member)

            XCTAssertEqual(store.tasks.filter { $0.ownerMemberID == member.id }.map(\.id).sorted(by: { $0.uuidString < $1.uuidString }),
                           [first.id, second.id].sorted(by: { $0.uuidString < $1.uuidString }))
            XCTAssertEqual(store.tasks.first { $0.id == first.id }?.owner, "Ana Souza")
            XCTAssertNil(store.tasks.first { $0.id == other.id }?.ownerMemberID)

            store.reassignTasks([first.id], to: nil)

            XCTAssertEqual(store.tasks.first { $0.id == first.id }?.owner, "Casa")
            XCTAssertNil(store.tasks.first { $0.id == first.id }?.ownerMemberID)
        }
    }

    func testDeletingSeveralTasksRemovesOnlyThose() throws {
        try withIsolatedStore { store in
            let first = task(dueAt: nil)
            let second = task(dueAt: nil)
            let kept = task(dueAt: nil)
            store.tasks = [first, second, kept]

            store.deleteTasks([first.id, second.id])

            XCTAssertEqual(store.tasks.map(\.id), [kept.id])
        }
    }

    func testAnUndoNeverMovesARepeatingTaskThatChangedSinceItWasFinished() throws {
        try withIsolatedStore { store in
            var daily = task(dueAt: now.addingTimeInterval(2 * 60 * 60))
            daily.recurrence = .daily
            store.tasks = [daily]

            store.toggleTask(daily)
            let elsewhere = now.addingTimeInterval(5 * 24 * 60 * 60)
            store.tasks[0].dueAt = elsewhere

            store.undoLastCompletion()

            XCTAssertEqual(store.tasks.first { $0.id == daily.id }?.dueAt, elsewhere)
            XCTAssertNil(store.undoableCompletionID)
        }
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

    private func selectionBar() -> some View {
        TaskSelectionControls(isEnabled: true, onDone: {}, onDelete: {}) {
            Button("Sem dono") {}
        }
    }

    private func fittedSize<Content: View>(
        _ view: Content,
        width: CGFloat,
        dynamicTypeSize: DynamicTypeSize
    ) -> CGSize {
        UIHostingController(rootView: view.environment(\.dynamicTypeSize, dynamicTypeSize))
            .sizeThatFits(in: CGSize(width: width, height: 2_000))
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
