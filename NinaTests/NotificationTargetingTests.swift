import XCTest
@testable import Nina

final class NotificationTargetingTests: XCTestCase {
    func testAnotherAdultsTaskNeverSchedulesOnThisPhone() {
        let task = task(owner: "Bruno")

        XCTAssertFalse(LocalHomeNotificationScheduler.isForViewer(task, viewerName: "Ana"))
    }

    func testYourOwnTaskSchedulesOnYourPhone() {
        let task = task(owner: "Ana")

        XCTAssertTrue(LocalHomeNotificationScheduler.isForViewer(task, viewerName: "Ana"))
    }

    func testAHouseholdTaskWithNoOwnerReachesEveryone() {
        XCTAssertTrue(LocalHomeNotificationScheduler.isForViewer(task(owner: "Casa"), viewerName: "Ana"))
        XCTAssertTrue(LocalHomeNotificationScheduler.isForViewer(task(owner: "Casa"), viewerName: "Bruno"))
        XCTAssertTrue(LocalHomeNotificationScheduler.isForViewer(task(owner: ""), viewerName: "Ana"))
    }

    func testOwnerMatchingIgnoresCasingAndAccents() {
        XCTAssertTrue(LocalHomeNotificationScheduler.isForViewer(task(owner: "mônica"), viewerName: "Monica"))
        XCTAssertTrue(LocalHomeNotificationScheduler.isForViewer(task(owner: "MONICA"), viewerName: "Mônica"))
    }

    func testAChildsTaskDoesNotBuzzAnAdultsPhone() {
        let task = task(owner: "Pedro")

        XCTAssertFalse(LocalHomeNotificationScheduler.isForViewer(task, viewerName: "Ana"))
    }

    func testAnUnknownViewerFallsOpenSoRemindersAreNeverSilentlyLost() {
        XCTAssertTrue(LocalHomeNotificationScheduler.isForViewer(task(owner: "Bruno"), viewerName: nil))
        XCTAssertTrue(LocalHomeNotificationScheduler.isForViewer(task(owner: "Bruno"), viewerName: "   "))
    }

    private func task(owner: String) -> TaskItem {
        TaskItem(
            title: "Levar o Pedro ao dentista",
            subtitle: "Consultório na Vila",
            owner: owner,
            dueLabel: "hoje, 14:00",
            dueAt: Date().addingTimeInterval(3_600),
            category: .health,
            isDone: false,
            createdBy: "Manual"
        )
    }
}
