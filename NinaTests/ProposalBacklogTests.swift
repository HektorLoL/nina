import XCTest
@testable import Nina

@MainActor
final class ProposalBacklogTests: XCTestCase {
    func testOnlyCardsStillWaitingInOlderTurnsAreCountedAndTheOldestIsTheTarget() {
        let older = reply(states: [.pending, .accepted])
        let middle = reply(states: [.pending, .pending])
        let resolved = reply(states: [.rejected])
        let newest = reply(states: [.pending])

        let backlog = ProposalBacklog(messages: [older, middle, resolved, newest])

        XCTAssertEqual(backlog.count, 3)
        XCTAssertEqual(backlog.firstMessageID, older.id)
        XCTAssertEqual(backlog.line, "3 propostas esperando")
    }

    func testTheNewestTurnIsAlreadyOnScreenSoItsCardsNeverRaiseTheNotice() {
        let backlog = ProposalBacklog(messages: [reply(states: [.accepted]), reply(states: [.pending, .pending])])

        XCTAssertEqual(backlog.count, 0)
        XCTAssertNil(backlog.firstMessageID)
    }

    func testOneWaitingCardReadsInTheSingular() {
        let backlog = ProposalBacklog(messages: [reply(states: [.pending]), reply(states: [])])

        XCTAssertEqual(backlog.line, "1 proposta esperando")
        XCTAssertFalse(backlog.line.contains("!"))
    }

    private func reply(states: [NinaProposalState]) -> ChatMessage {
        ChatMessage(
            sender: .nina,
            text: "Anotei.",
            timestamp: .now,
            proposals: states.map { state in
                NinaProposal(
                    kind: .task,
                    state: state,
                    title: "Comprar gás",
                    detail: "",
                    actionTitle: "Criar tarefa",
                    payload: NinaProposalPayload(title: "Comprar gás", detail: "")
                )
            }
        )
    }
}
