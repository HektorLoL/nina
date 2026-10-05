import XCTest
@testable import Nina

@MainActor
final class AnnouncementTests: XCTestCase {
    private let board = NinaAnnouncementBoard.current

    func testTheBoardOpensOnceAndThenStaysQuiet() {
        XCTAssertEqual(
            AnnouncementGate.decision(seenBoardID: "", board: board, finishedTutorialThisLaunch: false),
            .present
        )
        XCTAssertEqual(
            AnnouncementGate.decision(seenBoardID: "2026-09", board: board, finishedTutorialThisLaunch: false),
            .present
        )
        XCTAssertEqual(
            AnnouncementGate.decision(seenBoardID: board.id, board: board, finishedTutorialThisLaunch: false),
            .stayQuiet
        )
    }

    func testSomeoneWhoJustFinishedTheTutorialIsShownNoNewsAndTheBoardIsFiled() {
        XCTAssertEqual(
            AnnouncementGate.decision(seenBoardID: "", board: board, finishedTutorialThisLaunch: true),
            .markSeen
        )
    }

    func testAnEmptyBoardNeverOpens() {
        let empty = NinaAnnouncementBoard(id: "empty", items: [])

        XCTAssertEqual(
            AnnouncementGate.decision(seenBoardID: "", board: empty, finishedTutorialThisLaunch: false),
            .stayQuiet
        )
    }

    func testEveryAnnouncementIsShortAndInNinasVoice() {
        XCTAssertFalse(board.items.isEmpty)
        XCTAssertEqual(Set(board.items.map(\.id)).count, board.items.count)

        for item in board.items {
            XCTAssertLessThanOrEqual(item.title.split(separator: " ").count, 5, item.title)
            XCTAssertLessThanOrEqual(item.detail.split(separator: " ").count, 10, item.detail)
            XCTAssertTrue(item.detail.hasSuffix("."), item.detail)
            for text in [item.title, item.detail] {
                XCTAssertFalse(text.contains("!"), text)
                XCTAssertFalse(text.unicodeScalars.contains { $0.properties.isEmojiPresentation }, text)
            }
            XCTAssertNotNil(UIImage(systemName: item.systemName), item.systemName)
        }
    }
}
