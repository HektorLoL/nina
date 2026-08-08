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

    func testAClearlyUnevenSplitIsReportedWithRealCounts() {
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
        XCTAssertTrue(snapshot.message.contains("8 das 9 tarefas abertas"))
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
        XCTAssertEqual(snapshot.headline, "Divisão equilibrada")
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
        XCTAssertFalse(snapshot.entries.contains { $0.name == "Casa" })
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
        XCTAssertEqual(HouseholdWorkload.openTaskCount(for: assistant, in: []), 0)
    }

    func testMemberOpenTaskCountReflectsLiveTasksRatherThanAStoredColumn() {
        let mirna = member(named: "Mirna", tone: .coral)
        var completed = openTask(owner: "Mirna")
        completed.isDone = true

        let tasks = [openTask(owner: "Mirna"), openTask(owner: "Mirna"), completed, openTask(owner: "Casa")]

        XCTAssertEqual(mirna.taskCount, 0)
        XCTAssertEqual(HouseholdWorkload.openTaskCount(for: mirna, in: tasks), 2)
    }

    private func openTask(owner: String, kind: TaskKind = .task) -> TaskItem {
        TaskItem(
            kind: kind,
            title: "Tarefa",
            subtitle: "",
            owner: owner,
            dueLabel: "Sem data",
            category: .home,
            isDone: false,
            createdBy: "Manual"
        )
    }

    private func member(named name: String, tone: MemberTone) -> HouseholdMember {
        HouseholdMember(
            name: name,
            relationship: "",
            role: .adult,
            tone: tone,
            taskCount: 0,
            memoryNote: ""
        )
    }
}
