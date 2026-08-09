import XCTest
@testable import Nina

final class NotificationTargetingTests: XCTestCase {
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
