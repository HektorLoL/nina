import XCTest
@testable import Nina

@MainActor
final class SupportContentTests: XCTestCase {
    private var everyQuestion: [SupportQuestion] {
        SupportContent.topics.flatMap(\.questions)
    }

    func testEveryAnswerSpeaksInNinasVoice() {
        let forbidden = ["!", "Toque para", " IA ", "assistente", "inteligência artificial"]

        for item in everyQuestion {
            for text in [item.question, item.answer] {
                for word in forbidden {
                    XCTAssertFalse(text.contains(word), "\"\(word)\" in: \(text)")
                }
                XCTAssertFalse(
                    text.unicodeScalars.contains { $0.properties.isEmojiPresentation },
                    "emoji in: \(text)"
                )
            }
            XCTAssertTrue(item.question.hasSuffix("?"), item.question)
            XCTAssertTrue(item.answer.hasSuffix("."), item.answer)
        }
    }

    func testNoAnswerClaimsNothingSentToTheModelIsKept() {
        let claims = [
            "fica guardado lá",
            "servidor nenhum",
            "usado só para responder",
            "não guarde o que recebe",
            "nada fica guardado",
        ]

        for item in everyQuestion {
            for claim in claims {
                XCTAssertFalse(item.answer.lowercased().contains(claim), item.answer)
            }
        }

        let modelAnswer = everyQuestion.first { $0.answer.contains("OpenAI") }
        XCTAssertEqual(modelAnswer?.answer.contains("30 dias"), true)
    }

    func testTheHouseLimitInTheAnswersIsTheOneTheAppEnforces() {
        let limitAnswer = everyQuestion.first { $0.answer.contains("A Nina não ocupa vaga.") }

        XCTAssertEqual(limitAnswer?.answer.hasPrefix("Até \(AppStore.maxFamilyPeople),"), true)
    }

    func testDeletingTheAccountIsNeverAnsweredAsCancellingTheSubscription() {
        let cancelAnswer = everyQuestion.first { $0.question == "Como cancelo o Premium?" }

        XCTAssertEqual(cancelAnswer?.answer.contains("Apagar a conta não cancela a cobrança."), true)
    }

    func testQuestionsAreUniqueSoOnlyOneOpensAtATime() {
        let ids = everyQuestion.map(\.id)

        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertFalse(ids.isEmpty)
    }

    func testTheSupportMailCarriesTheVersionsAndNothingFromTheHouse() throws {
        let url = SupportContent.mail(appVersion: "1.0 (11)", systemVersion: "26.4")
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let items = Dictionary(
            uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") }
        )

        XCTAssertEqual(components.scheme, "mailto")
        XCTAssertEqual(components.path, SupportContent.email)
        XCTAssertEqual(SupportContent.email, "oi@ninai.app")
        XCTAssertEqual(Set(items.keys), ["subject", "body"])
        XCTAssertEqual(items["subject"], "Ajuda com a Nina")
        XCTAssertEqual(items["body"], "\n\n—\nNina 1.0 (11) · iOS 26.4")
    }
}
