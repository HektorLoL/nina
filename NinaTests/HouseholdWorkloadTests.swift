import XCTest
@testable import Nina

final class HouseholdWorkloadTests: XCTestCase {
    func testTooFewAssignedTasksRefuseToDrawASplit() {
        let snapshot = HouseholdWorkload.snapshot(
            tasks: [
                openTask(owner: "Mirna"),
                openTask(owner: "Heitor")
            ],
            members: [member(named: "Mirna", tone: .coral), member(named: "Heitor", tone: .sky)]
        )

        XCTAssertFalse(snapshot.isConclusive)
        XCTAssertNil(snapshot.leadName)
        XCTAssertEqual(snapshot.headline, "Ainda sem retrato da casa")
    }

    func testASingleCarrierNeverProducesAnOverloadSignal() {
        let snapshot = HouseholdWorkload.snapshot(
            tasks: (0..<9).map { _ in openTask(owner: "Mirna") },
            members: [member(named: "Mirna", tone: .coral), member(named: "Heitor", tone: .sky)]
        )

        XCTAssertFalse(snapshot.isConclusive)
        XCTAssertEqual(snapshot.assignedCount, 9)
    }

    func testAClearlyUnevenSplitNamesThePersonButNeverACount() {
        let tasks = (0..<8).map { _ in openTask(owner: "Mirna") } + [openTask(owner: "Heitor")]
        let snapshot = HouseholdWorkload.snapshot(
            tasks: tasks,
            members: [member(named: "Mirna", tone: .coral), member(named: "Heitor", tone: .sky)]
        )

        XCTAssertTrue(snapshot.isConclusive)
        XCTAssertFalse(snapshot.isBalanced)
        XCTAssertEqual(snapshot.leadName, "Mirna")
        XCTAssertEqual(snapshot.assignedCount, 9)
        XCTAssertEqual(snapshot.headline, "Sinal de sobrecarga")
        XCTAssertTrue(snapshot.message.contains("Mirna"))
        XCTAssertFalse(
            snapshot.message.contains(where: \.isNumber),
            "A quantified comparison between two people is a scoreboard whatever the caption says."
        )
    }

    func testTheBandsAreQualitativeAndTheHeavierCarrierIsNotFirstInTheList() {
        let tasks = (0..<8).map { _ in openTask(owner: "Heitor") } + [openTask(owner: "Mirna")]
        let snapshot = HouseholdWorkload.snapshot(
            tasks: tasks,
            members: [member(named: "Mirna", tone: .coral), member(named: "Heitor", tone: .sky)]
        )

        XCTAssertEqual(snapshot.entries.first { $0.name == "Heitor" }?.band, .heavier)
        XCTAssertEqual(snapshot.entries.first { $0.name == "Mirna" }?.band, .light)
        // Household order, never ranked: sorting by load is the ranking the
        // caption disclaims, so the heavier carrier must not float to the top.
        XCTAssertEqual(snapshot.entries.first?.name, "Mirna")
    }

    func testANarrowLeadStaysBalancedRatherThanAccusing() {
        let tasks = (0..<5).map { _ in openTask(owner: "Mirna") }
            + (0..<4).map { _ in openTask(owner: "Heitor") }
        let snapshot = HouseholdWorkload.snapshot(
            tasks: tasks,
            members: [member(named: "Mirna", tone: .coral), member(named: "Heitor", tone: .sky)]
        )

        XCTAssertTrue(snapshot.isConclusive)
        XCTAssertTrue(snapshot.isBalanced)
        XCTAssertEqual(snapshot.headline, "A casa está parecida")
    }

    func testHouseOwnedTasksAreCountedAsSharedAndNeverAttributedToAPerson() {
        let tasks = (0..<4).map { _ in openTask(owner: "Casa") }
            + (0..<4).map { _ in openTask(owner: "Mirna") }
            + (0..<4).map { _ in openTask(owner: "Heitor") }
        let snapshot = HouseholdWorkload.snapshot(
            tasks: tasks,
            members: [member(named: "Mirna", tone: .coral), member(named: "Heitor", tone: .sky)]
        )

        XCTAssertEqual(snapshot.sharedCount, 4)
        XCTAssertEqual(snapshot.assignedCount, 8)

        // The house gets its own band so the portrait can show unassigned work,
        // but it is never a person: no member id, and flagged shared so the view
        // draws it as a different weight rather than another face.
        let houseEntry = snapshot.entries.first { $0.isShared }
        XCTAssertEqual(houseEntry?.name, "Casa")
        XCTAssertNil(houseEntry?.memberID)
        XCTAssertFalse(snapshot.entries.contains { !$0.isShared && $0.name == "Casa" })
        XCTAssertEqual(snapshot.entries.filter { !$0.isShared }.count, 2)
    }

    func testSeedsAreExcludedSoUndatedIntentionsNeverCountAsLoad() {
        let tasks = (0..<7).map { _ in openTask(owner: "Mirna") }
            + (0..<7).map { _ in openTask(owner: "Heitor", kind: .seed) }
        let snapshot = HouseholdWorkload.snapshot(
            tasks: tasks,
            members: [member(named: "Mirna", tone: .coral), member(named: "Heitor", tone: .sky)]
        )

        XCTAssertEqual(snapshot.assignedCount, 7)
        XCTAssertFalse(snapshot.isConclusive)
    }

    func testCompletedTasksDoNotCountTowardOpenLoad() {
        var doneTask = openTask(owner: "Mirna")
        doneTask.isDone = true

        let snapshot = HouseholdWorkload.snapshot(
            tasks: [doneTask] + (0..<3).map { _ in openTask(owner: "Heitor") },
            members: [member(named: "Mirna", tone: .coral), member(named: "Heitor", tone: .sky)]
        )

        XCTAssertEqual(snapshot.assignedCount, 3)
        XCTAssertEqual(snapshot.entries.first { $0.name == "Mirna" }?.openCount, 0)
    }

    func testOwnerMatchingIgnoresAccentsAndCasingSoOneMemberIsNotSplitInTwo() {
        let tasks = (0..<4).map { _ in openTask(owner: "mirna") }
            + (0..<3).map { _ in openTask(owner: "MIRNA") }
            + (0..<3).map { _ in openTask(owner: "Heitor") }
        let snapshot = HouseholdWorkload.snapshot(
            tasks: tasks,
            members: [member(named: "Mirna", tone: .coral), member(named: "Heitor", tone: .sky)]
        )

        XCTAssertEqual(snapshot.entries.count, 2)
        XCTAssertEqual(snapshot.entries.first { $0.name == "Mirna" }?.openCount, 7)
    }

    func testAnOwnerWhoIsNoLongerAMemberStillShowsTheirRemainingLoad() {
        let tasks = (0..<6).map { _ in openTask(owner: "Tia Lu") }
            + (0..<3).map { _ in openTask(owner: "Heitor") }
        let snapshot = HouseholdWorkload.snapshot(
            tasks: tasks,
            members: [member(named: "Heitor", tone: .sky)]
        )

        XCTAssertEqual(snapshot.entries.first { $0.name == "Tia Lu" }?.openCount, 6)
        XCTAssertEqual(snapshot.assignedCount, 9)
    }

    func testTheAssistantIsNeverGivenAWorkloadRow() {
        let assistant = HouseholdMember(
            name: "Nina",
            relationship: "IA da casa",
            role: .assistant,
            tone: .mint,
            taskCount: 0,
            memoryNote: ""
        )

        let snapshot = HouseholdWorkload.snapshot(
            tasks: (0..<4).map { _ in openTask(owner: "Mirna") }
                + (0..<4).map { _ in openTask(owner: "Heitor") },
            members: [assistant, member(named: "Mirna", tone: .coral), member(named: "Heitor", tone: .sky)]
        )

        XCTAssertFalse(snapshot.entries.contains { $0.name == "Nina" })
        XCTAssertEqual(HouseholdWorkload.openTaskCount(for: assistant, in: [], members: [assistant]), 0)
    }

    func testMemberOpenTaskCountReflectsLiveTasksRatherThanAStoredColumn() {
        let mirna = member(named: "Mirna", tone: .coral)
        var completed = openTask(owner: "Mirna")
        completed.isDone = true

        let tasks = [openTask(owner: "Mirna"), openTask(owner: "Mirna"), completed, openTask(owner: "Casa")]

        XCTAssertEqual(mirna.taskCount, 0)
        XCTAssertEqual(HouseholdWorkload.openTaskCount(for: mirna, in: tasks, members: [mirna]), 2)
    }

    func testARenamedMemberKeepsEveryTaskInASingleBucket() {
        let mirna = member(named: "Mirna Castello", tone: .coral)
        let heitor = member(named: "Heitor", tone: .sky)
        let tasks = (0..<5).map { _ in openTask(owner: "Mirna", ownerMemberID: mirna.id) }
            + (0..<3).map { _ in openTask(owner: "Heitor", ownerMemberID: heitor.id) }

        let snapshot = HouseholdWorkload.snapshot(tasks: tasks, members: [mirna, heitor])

        XCTAssertEqual(snapshot.entries.count, 2)
        XCTAssertEqual(snapshot.entries.first { $0.memberID == mirna.id }?.openCount, 5)
        XCTAssertEqual(snapshot.entries.first { $0.memberID == mirna.id }?.name, "Mirna Castello")
        XCTAssertFalse(snapshot.entries.contains { $0.name == "Mirna" })
        XCTAssertEqual(HouseholdWorkload.openTaskCount(for: mirna, in: tasks, members: [mirna, heitor]), 5)
    }

    func testTwoMembersSharingANameKeepSeparateRowsToldApartByRelationship() {
        let mae = member(named: "Marina", relationship: "Mãe", tone: .coral)
        let prima = member(named: "Marina", relationship: "Prima", tone: .lavender)
        let tasks = (0..<6).map { _ in openTask(owner: "Marina", ownerMemberID: mae.id) }
            + (0..<2).map { _ in openTask(owner: "Marina", ownerMemberID: prima.id) }

        let snapshot = HouseholdWorkload.snapshot(tasks: tasks, members: [mae, prima])

        XCTAssertEqual(snapshot.entries.count, 2)
        XCTAssertEqual(Set(snapshot.entries.map(\.id)).count, 2)
        XCTAssertEqual(snapshot.entries.first { $0.memberID == mae.id }?.openCount, 6)
        XCTAssertEqual(snapshot.entries.first { $0.memberID == mae.id }?.name, "Marina · Mãe")
        XCTAssertEqual(snapshot.entries.first { $0.memberID == prima.id }?.openCount, 2)
        XCTAssertEqual(snapshot.entries.first { $0.memberID == prima.id }?.name, "Marina · Prima")
        XCTAssertEqual(HouseholdWorkload.openTaskCount(for: prima, in: tasks, members: [mae, prima]), 2)
    }

    func testWorkLabelledWithANameTwoMembersShareIsLeftUnattributed() {
        let mae = member(named: "Marina", relationship: "Mãe", tone: .coral)
        let prima = member(named: "Marina", relationship: "Prima", tone: .lavender)
        let tasks = (0..<4).map { _ in openTask(owner: "Marina") }

        let snapshot = HouseholdWorkload.snapshot(tasks: tasks, members: [mae, prima])

        XCTAssertEqual(snapshot.entries.first { $0.memberID == mae.id }?.openCount, 0)
        XCTAssertEqual(snapshot.entries.first { $0.memberID == prima.id }?.openCount, 0)
        XCTAssertEqual(snapshot.entries.first { $0.memberID == nil }?.openCount, 4)
        XCTAssertEqual(HouseholdWorkload.openTaskCount(for: mae, in: tasks, members: [mae, prima]), 0)
    }

    func testHouseWorkIsNeverAttributedToAPersonEvenWhenItCarriesAMemberID() {
        let mirna = member(named: "Mirna", tone: .coral)
        let heitor = member(named: "Heitor", tone: .sky)
        let tasks = (0..<4).map { _ in openTask(owner: "Casa", ownerMemberID: mirna.id) }
            + (0..<4).map { _ in openTask(owner: "Mirna", ownerMemberID: mirna.id) }
            + (0..<4).map { _ in openTask(owner: "Heitor", ownerMemberID: heitor.id) }

        let snapshot = HouseholdWorkload.snapshot(tasks: tasks, members: [mirna, heitor])

        XCTAssertEqual(snapshot.sharedCount, 4)
        XCTAssertEqual(snapshot.assignedCount, 8)
        XCTAssertEqual(snapshot.entries.first { $0.memberID == mirna.id }?.openCount, 4)
        XCTAssertEqual(HouseholdWorkload.openTaskCount(for: mirna, in: tasks, members: [mirna, heitor]), 4)
    }

    func testARemovedMembersTasksReturnToTheHouseRatherThanNamingSomeoneElse() {
        let heitor = member(named: "Heitor", tone: .sky)
        let departed = UUID()
        let tasks = (0..<5).map { _ in openTask(owner: "Casa", ownerMemberID: departed) }
            + (0..<3).map { _ in openTask(owner: "Heitor", ownerMemberID: heitor.id) }

        let snapshot = HouseholdWorkload.snapshot(tasks: tasks, members: [heitor])

        XCTAssertEqual(snapshot.sharedCount, 5)

        let people = snapshot.entries.filter { !$0.isShared }
        XCTAssertEqual(people.count, 1)
        XCTAssertEqual(people.first?.memberID, heitor.id)
        // The departed member's load lands on the house band, which carries no
        // member id — it is never re-attributed to whoever is still here.
        XCTAssertEqual(snapshot.entries.filter(\.isShared).count, 1)
        XCTAssertNil(snapshot.entries.first(where: \.isShared)?.memberID)
    }

    private func openTask(owner: String, ownerMemberID: UUID? = nil, kind: TaskKind = .task) -> TaskItem {
        TaskItem(
            kind: kind,
            title: "Tarefa",
            subtitle: "",
            owner: owner,
            ownerMemberID: ownerMemberID,
            dueLabel: "Sem data",
            category: .home,
            isDone: false,
            createdBy: "Manual"
        )
    }

    private func member(
        named name: String,
        relationship: String = "",
        tone: MemberTone
    ) -> HouseholdMember {
        HouseholdMember(
            name: name,
            relationship: relationship,
            role: .adult,
            tone: tone,
            taskCount: 0,
            memoryNote: ""
        )
    }
}
