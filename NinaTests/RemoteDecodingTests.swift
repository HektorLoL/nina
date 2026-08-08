import XCTest
@testable import Nina

final class RemoteDecodingTests: XCTestCase {
    // The exact rows begin_nina_chat_run writes into chat_messages.attachments, as returned
    // verbatim by get_current_nina_state.
    private static let serverAttachmentsJSON = """
    [
      {"kind":"image","filename":"boleto.jpg","mime_type":"image/jpeg","byte_count":412000},
      {"kind":"document","filename":"receita.pdf","mime_type":"application/pdf","byte_count":88000}
    ]
    """

    func testServerAttachmentMetadataDecodesWithoutAnIdentifierOrCamelCaseKeys() throws {
        let attachments = try JSONDecoder().decode(
            [ChatAttachment].self,
            from: Data(Self.serverAttachmentsJSON.utf8)
        )

        XCTAssertEqual(attachments.count, 2)
        XCTAssertEqual(attachments[0].kind, .image)
        XCTAssertEqual(attachments[0].filename, "boleto.jpg")
        XCTAssertEqual(attachments[0].mimeType, "image/jpeg")
        XCTAssertEqual(attachments[0].byteCount, 412_000)
        XCTAssertNil(attachments[0].thumbnailData)
        XCTAssertEqual(attachments[1].kind, .document)
        XCTAssertEqual(attachments[1].mimeType, "application/pdf")
    }

    func testAnAttachmentNeverFailsTheHouseholdSnapshotWhenFieldsAreMissing() throws {
        let attachment = try JSONDecoder().decode(
            ChatAttachment.self,
            from: Data(#"{"filename":"anexo-sem-tipo"}"#.utf8)
        )

        XCTAssertEqual(attachment.filename, "anexo-sem-tipo")
        XCTAssertEqual(attachment.kind, .document)
        XCTAssertEqual(attachment.mimeType, "")
        XCTAssertEqual(attachment.byteCount, 0)
    }

    func testAnUnknownAttachmentKindDoesNotThrow() throws {
        let attachment = try JSONDecoder().decode(
            ChatAttachment.self,
            from: Data(#"{"kind":"video","filename":"a.mov","mime_type":"video/quicktime","byte_count":10}"#.utf8)
        )

        XCTAssertEqual(attachment.kind, .document)
        XCTAssertEqual(attachment.byteCount, 10)
    }

    func testLocallyCachedCamelCaseAttachmentsWrittenByOlderBuildsStillDecode() throws {
        let legacy = """
        {"id":"1D2C1F5E-0000-4000-8000-00000000ABCD","kind":"image","filename":"antigo.jpg",
         "mimeType":"image/png","byteCount":2048}
        """

        let attachment = try JSONDecoder().decode(ChatAttachment.self, from: Data(legacy.utf8))

        XCTAssertEqual(attachment.id.uuidString, "1D2C1F5E-0000-4000-8000-00000000ABCD")
        XCTAssertEqual(attachment.mimeType, "image/png")
        XCTAssertEqual(attachment.byteCount, 2048)
    }

    func testAttachmentsSurviveAFullLocalCacheRoundTrip() throws {
        let original = ChatAttachment(
            kind: .image,
            filename: "conta-de-luz.jpg",
            mimeType: "image/jpeg",
            byteCount: 91_204,
            thumbnailData: Data([0x01, 0x02, 0x03])
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ChatAttachment.self, from: encoded)

        XCTAssertEqual(decoded, original)
    }

    func testProposalPayloadDecodesWhenTheModelOmitsOptionalFields() throws {
        let payload = try JSONDecoder().decode(
            NinaProposalPayload.self,
            from: Data(#"{"title":"Pagar o boleto da Enel","detail":"Vence dia 12"}"#.utf8)
        )

        XCTAssertEqual(payload.title, "Pagar o boleto da Enel")
        XCTAssertEqual(payload.owner, "Casa")
        XCTAssertEqual(payload.dueLabel, "Sem data")
        XCTAssertNil(payload.dueAt)
        XCTAssertEqual(payload.category.id, TaskCategory.home.id)
    }

    func testProposalPayloadReadsTheFullServerShape() throws {
        let json = """
        {"title":"Levar o Thor ao veterinário","detail":"Vacina anual","owner":"Heitor",
         "due_label":"sexta, 09:00","due_at":"2026-08-14T12:00:00Z","category":"pet",
         "symbol_name":"pawprint.fill","amount":"","visibility":null,"confidence":0.82,
         "deduplication_key":"vet-thor-2026-08"}
        """

        let payload = try JSONDecoder().decode(NinaProposalPayload.self, from: Data(json.utf8))

        XCTAssertEqual(payload.owner, "Heitor")
        XCTAssertEqual(payload.dueLabel, "sexta, 09:00")
        XCTAssertEqual(payload.dueAt, "2026-08-14T12:00:00Z")
        XCTAssertEqual(payload.category.id, TaskCategory.pet.id)
        XCTAssertEqual(payload.confidence, 0.82)
        XCTAssertEqual(payload.deduplicationKey, "vet-thor-2026-08")
    }
}
