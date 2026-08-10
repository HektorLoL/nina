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

    func testThePhotographedDocumentNeverRidesUpWithTheLegacyChatInsert() throws {
        let message = ChatMessage(
            sender: .user,
            text: "Segue o boleto",
            timestamp: Date(timeIntervalSince1970: 1_785_000_000),
            attachments: [
                ChatAttachment(
                    kind: .image,
                    filename: "foto-1.jpg",
                    mimeType: "image/jpeg",
                    byteCount: 412_000,
                    thumbnailData: Data("thumbnail-do-boleto".utf8)
                )
            ]
        )

        let row = ChatMessageInsertRow(message: message, familyID: UUID(), currentUserID: UUID())
        let encoded = try XCTUnwrap(String(data: JSONEncoder().encode(row), encoding: .utf8))

        XCTAssertFalse(encoded.contains("thumbnail_data"))
        XCTAssertFalse(encoded.contains(Data("thumbnail-do-boleto".utf8).base64EncodedString()))
        XCTAssertTrue(encoded.contains("foto-1.jpg"))
        XCTAssertTrue(encoded.contains("412000"))
    }

    func testATaskCachedByAnOlderBuildWithoutAnOwnerMemberIDStillDecodes() throws {
        let legacy = """
        {"id":"3F1A0000-0000-4000-8000-00000000AAAA","title":"Pagar a conta de luz",
         "owner":"Mirna","dueLabel":"amanhã, 09:00","isDone":false,"version":3}
        """

        let task = try JSONDecoder().decode(TaskItem.self, from: Data(legacy.utf8))

        XCTAssertEqual(task.owner, "Mirna")
        XCTAssertNil(task.ownerMemberID)
        XCTAssertEqual(task.version, 3)
    }

    func testACompletedTaskCachedByAnOlderBuildWithoutACompletionTimestampStillDecodes() throws {
        let legacy = """
        {"id":"3F1A0000-0000-4000-8000-00000000CCCC","title":"Trocar o filtro","owner":"Casa",
         "dueLabel":"Sem data","isDone":true,"createdBy":"Manual","version":2}
        """

        let task = try JSONDecoder().decode(TaskItem.self, from: Data(legacy.utf8))

        XCTAssertTrue(task.isDone)
        XCTAssertNil(task.completedAt)
        XCTAssertEqual(task.title, "Trocar o filtro")
        XCTAssertEqual(task.version, 2)
    }

    func testACompletionTimestampSurvivesALocalCacheRoundTrip() throws {
        let completedAt = Date(timeIntervalSince1970: 1_785_000_000)
        let task = TaskItem(
            title: "Pagar a escola",
            subtitle: "",
            owner: "Casa",
            dueLabel: "Sem data",
            category: .home,
            isDone: true,
            completedAt: completedAt,
            createdBy: "Manual"
        )

        let decoded = try JSONDecoder().decode(TaskItem.self, from: JSONEncoder().encode(task))

        XCTAssertEqual(decoded.completedAt, completedAt)
    }

    func testATaskCachedByAnOlderBuildWithoutAReminderLeadTimeStillDecodes() throws {
        let legacy = """
        {"id":"3F1A0000-0000-4000-8000-00000000DDDD","title":"Levar o Pedro ao dentista",
         "owner":"Mirna","dueLabel":"amanhã, 09:00","isDone":false,"version":4}
        """

        let task = try JSONDecoder().decode(TaskItem.self, from: Data(legacy.utf8))

        XCTAssertEqual(task.remindOffsetMinutes, 0)
        XCTAssertEqual(task.reminderLead, .atTime)
        XCTAssertEqual(task.version, 4)
    }

    func testAReminderLeadTimeSurvivesALocalCacheRoundTrip() throws {
        let task = TaskItem(
            title: "Pagar o boleto da Enel",
            subtitle: "",
            owner: "Casa",
            dueLabel: "sexta, 09:00",
            category: .bills,
            reminderLead: .thirtyMinutes,
            isDone: false,
            createdBy: "Manual"
        )

        let decoded = try JSONDecoder().decode(TaskItem.self, from: JSONEncoder().encode(task))

        XCTAssertEqual(decoded.reminderLead, .thirtyMinutes)
        XCTAssertEqual(decoded.remindOffsetMinutes, 30)
    }

    func testACachedLeadTimeTheDatabaseWouldRejectFallsBackToTheDueMoment() throws {
        let legacy = """
        {"id":"3F1A0000-0000-4000-8000-00000000EEEE","title":"Renovar o seguro","owner":"Casa",
         "dueLabel":"Sem data","isDone":false,"remindOffsetMinutes":37,"version":1}
        """

        let task = try JSONDecoder().decode(TaskItem.self, from: Data(legacy.utf8))

        XCTAssertEqual(task.remindOffsetMinutes, 0)
    }

    func testEveryOfferedLeadTimeIsOneTheDatabaseAccepts() {
        let accepted = [0, 5, 10, 15, 30, 60, 120, 1440]

        XCTAssertEqual(TaskReminderLead.allCases.map(\.minutes), accepted)
        for option in TaskReminderLead.editorOptions {
            XCTAssertTrue(accepted.contains(option.minutes))
            XCTAssertFalse(option.title.contains("!"))
        }
    }

    func testAShoppingItemCachedByAnOlderBuildWithoutAnOwnerMemberIDStillDecodes() throws {
        let legacy = #"{"id":"3F1A0000-0000-4000-8000-00000000BBBB","title":"Gás","amount":"1 botijão","owner":"Casa","isChecked":false}"#

        let item = try JSONDecoder().decode(ShoppingItem.self, from: Data(legacy.utf8))

        XCTAssertEqual(item.title, "Gás")
        XCTAssertEqual(item.owner, "Casa")
        XCTAssertNil(item.ownerMemberID)
    }

    func testTheAssignedMemberSurvivesALocalCacheRoundTrip() throws {
        let memberID = UUID()
        let task = TaskItem(
            title: "Levar o Thor ao veterinário",
            subtitle: "",
            owner: "Heitor",
            ownerMemberID: memberID,
            dueLabel: "sexta, 09:00",
            category: .pet,
            isDone: false,
            createdBy: "Manual"
        )
        let item = ShoppingItem(title: "Ração", amount: "3 kg", owner: "Heitor", ownerMemberID: memberID, isChecked: false)

        let decodedTask = try JSONDecoder().decode(TaskItem.self, from: JSONEncoder().encode(task))
        let decodedItem = try JSONDecoder().decode(ShoppingItem.self, from: JSONEncoder().encode(item))

        XCTAssertEqual(decodedTask.ownerMemberID, memberID)
        XCTAssertEqual(decodedItem.ownerMemberID, memberID)
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

    func testWhatNinaReadOffTheDocumentArrivesWithTheProposalSheDerivedFromIt() throws {
        let json = """
        {"title":"Pagar o boleto da Enel","detail":"Vence dia 12","owner":"Casa",
         "due_label":"12/08, 09:00","due_at":"2026-08-12T12:00:00Z","category":"bills",
         "symbol_name":"bolt.fill","amount":"",
         "extracted":[{"label":"Vencimento","value":"12/08/2026"},
                      {"label":"Valor","value":"R$ 187,43"}],
         "visibility":null,"confidence":0.74,"deduplication_key":"enel-2026-08"}
        """

        let payload = try JSONDecoder().decode(NinaProposalPayload.self, from: Data(json.utf8))

        XCTAssertEqual(payload.extracted.count, 2)
        XCTAssertEqual(payload.extracted.first?.label, "Vencimento")
        XCTAssertEqual(payload.extracted.first?.value, "12/08/2026")
        XCTAssertEqual(payload.extracted.last?.value, "R$ 187,43")
    }

    func testAProposalWithoutExtractedReadingsDecodesWithNothingForTheCardToDraw() throws {
        let older = try JSONDecoder().decode(
            NinaProposalPayload.self,
            from: Data(#"{"title":"Pagar o boleto","detail":"","amount":""}"#.utf8)
        )
        let explicitlyNull = try JSONDecoder().decode(
            NinaProposalPayload.self,
            from: Data(#"{"title":"Pagar o boleto","detail":"","extracted":null}"#.utf8)
        )
        let empty = try JSONDecoder().decode(
            NinaProposalPayload.self,
            from: Data(#"{"title":"Pagar o boleto","detail":"","extracted":[]}"#.utf8)
        )

        XCTAssertTrue(older.extracted.isEmpty)
        XCTAssertTrue(explicitlyNull.extracted.isEmpty)
        XCTAssertTrue(empty.extracted.isEmpty)
    }

    func testAHalfReadLineIsNeverShownAsSomethingNinaReadOffTheDocument() throws {
        let json = """
        {"title":"Pagar o boleto","detail":"",
         "extracted":[{"label":"Vencimento","value":"12/08/2026"},
                      {"label":"Valor","value":"   "},
                      {"label":"","value":"R$ 90,00"},
                      {"label":"Código"}]}
        """

        let payload = try JSONDecoder().decode(NinaProposalPayload.self, from: Data(json.utf8))

        XCTAssertEqual(payload.extracted, [NinaExtractedReading(label: "Vencimento", value: "12/08/2026")])
    }

    func testCorrectingAProposalKeepsWhatNinaReadOffTheDocumentBesideTheCorrection() {
        let payload = NinaProposalPayload(
            title: "Pagar o boleto da Enel",
            detail: "",
            dueLabel: "12/08",
            dueAt: "2026-08-12T12:00:00Z",
            extracted: [NinaExtractedReading(label: "Vencimento", value: "12/08/2026")]
        )

        let edited = payload.edited(
            title: payload.title,
            detail: payload.detail,
            owner: payload.owner,
            dueLabel: "18/08",
            amount: ""
        )

        XCTAssertEqual(edited.extracted, payload.extracted)
        XCTAssertEqual(edited.dueLabel, "18/08")
    }

    func testExtractedReadingsSurviveALocalCacheRoundTrip() throws {
        let payload = NinaProposalPayload(
            title: "Levar a receita na farmácia",
            detail: "",
            extracted: [
                NinaExtractedReading(label: "Medicamento", value: "Amoxicilina 500 mg"),
                NinaExtractedReading(label: "Posologia", value: "1 comprimido a cada 8 h")
            ]
        )

        let decoded = try JSONDecoder().decode(
            NinaProposalPayload.self,
            from: JSONEncoder().encode(payload)
        )

        XCTAssertEqual(decoded.extracted, payload.extracted)
    }

    func testTheBasisNinaBuiltAProposalFromArrivesWithTheProposal() throws {
        let json = """
        {"title":"Pagar o boleto da Enel","detail":"Vence dia 12","owner":"Casa",
         "due_label":"12/08, 09:00","due_at":"2026-08-12T12:00:00Z","category":"bills",
         "symbol_name":"bolt.fill","amount":"",
         "rationale":"Vencimento que li na foto","source":"anexo",
         "visibility":null,"confidence":0.74,"deduplication_key":"enel-2026-08"}
        """

        let payload = try JSONDecoder().decode(NinaProposalPayload.self, from: Data(json.utf8))

        XCTAssertEqual(payload.rationale, "Vencimento que li na foto")
        XCTAssertEqual(payload.source, .attachment)
        XCTAssertEqual(payload.source?.title, "Do anexo")
        XCTAssertEqual(payload.source?.tone, .sky)
    }

    func testAProposalWithoutABasisDecodesWithNothingForTheCardToDraw() throws {
        let older = try JSONDecoder().decode(
            NinaProposalPayload.self,
            from: Data(#"{"title":"Pagar o boleto","detail":""}"#.utf8)
        )
        let explicitlyNull = try JSONDecoder().decode(
            NinaProposalPayload.self,
            from: Data(#"{"title":"Pagar o boleto","detail":"","rationale":null,"source":null}"#.utf8)
        )
        let blank = try JSONDecoder().decode(
            NinaProposalPayload.self,
            from: Data(#"{"title":"Pagar o boleto","detail":"","rationale":"   ","source":""}"#.utf8)
        )

        for payload in [older, explicitlyNull, blank] {
            XCTAssertTrue(payload.rationale.isEmpty)
            XCTAssertNil(payload.source)
        }
    }

    func testASourceFromANewerServerLeavesTheChipOffInsteadOfDrawingABlankOne() throws {
        let payload = try JSONDecoder().decode(
            NinaProposalPayload.self,
            from: Data(#"{"title":"Combinar o rodízio","detail":"","source":"intuicao"}"#.utf8)
        )

        XCTAssertNil(payload.source)
        XCTAssertEqual(payload.title, "Combinar o rodízio")
    }

    func testEverySourceTheServerCanSendNamesItselfInNinasVoice() {
        let sources: [(String, NinaProposalSource)] = [
            ("mensagem", .message),
            ("anexo", .attachment),
            ("tarefa_existente", .existingTask),
            ("memoria", .memory),
            ("rotina", .routine)
        ]

        for (wireValue, source) in sources {
            XCTAssertEqual(NinaProposalSource(rawValue: wireValue), source)
            XCTAssertFalse(source.title.isEmpty)
            XCTAssertFalse(source.title.contains("!"))
            XCTAssertNotEqual(source.tone, .coral)
        }
    }

    func testTheBasisSurvivesALocalCacheRoundTrip() throws {
        let payload = NinaProposalPayload(
            title: "Levar o Thor ao veterinário",
            detail: "",
            rationale: "Você comentou na conversa",
            source: .message
        )

        let decoded = try JSONDecoder().decode(
            NinaProposalPayload.self,
            from: JSONEncoder().encode(payload)
        )

        XCTAssertEqual(decoded.rationale, "Você comentou na conversa")
        XCTAssertEqual(decoded.source, .message)
    }

    func testCorrectingAProposalKeepsTheBasisItWasBuiltFrom() {
        let payload = NinaProposalPayload(
            title: "Pagar o boleto da Enel",
            detail: "",
            dueLabel: "12/08",
            dueAt: "2026-08-12T12:00:00Z",
            rationale: "Vencimento que li na foto",
            source: .attachment
        )

        let edited = payload.edited(
            title: payload.title,
            detail: payload.detail,
            owner: payload.owner,
            dueLabel: "18/08",
            amount: ""
        )

        XCTAssertEqual(edited.rationale, payload.rationale)
        XCTAssertEqual(edited.source, .attachment)
    }

    func testHowSureNinaIsChangesNothingTheProposalCardCanDraw() throws {
        func payload(confidence: Double) throws -> NinaProposalPayload {
            try JSONDecoder().decode(
                NinaProposalPayload.self,
                from: Data("""
                {"title":"Pagar o boleto da Enel","detail":"Vence dia 12",
                 "rationale":"Vencimento que li na foto","source":"anexo",
                 "confidence":\(confidence)}
                """.utf8)
            )
        }

        let unsure = try payload(confidence: 0.11)
        let sure = try payload(confidence: 0.99)

        XCTAssertEqual(unsure.confidence, 0.11)
        XCTAssertEqual(sure.confidence, 0.99)
        XCTAssertEqual(unsure.rationale, sure.rationale)
        XCTAssertEqual(unsure.source?.title, sure.source?.title)
        XCTAssertEqual(unsure.source?.tone, sure.source?.tone)
        XCTAssertEqual(unsure.source?.symbolName, sure.source?.symbolName)
        XCTAssertFalse(unsure.rationale.contains("11"))
        XCTAssertFalse(sure.rationale.contains("99"))
    }

    func testASeedProposalFromTheServerDecodesAsASeedAndNotAsAPlainTask() throws {
        let json = """
        {"id":"5A1B0000-0000-4000-8000-000000000001","kind":"seed","state":"pending",
         "title":"Guardar como semente","detail":"Ainda não há uma data clara",
         "action_title":"Guardar semente",
         "payload":{"title":"Organizar as fotos da família","detail":"","category":"home"}}
        """

        let proposal = try JSONDecoder().decode(NinaProposal.self, from: Data(json.utf8))

        XCTAssertEqual(proposal.kind, .seed)
        XCTAssertEqual(proposal.actionTitle, "Guardar semente")
    }

    func testAProposalKindFromANewerServerDoesNotCostTheUserTheConversation() throws {
        let json = """
        {"id":"5A1B0000-0000-4000-8000-000000000002","kind":"ritual","state":"pending",
         "title":"Combinar o rodízio da louça","detail":"","action_title":"Combinar",
         "payload":{"title":"Rodízio da louça","detail":""}}
        """

        let proposal = try JSONDecoder().decode(NinaProposal.self, from: Data(json.utf8))

        XCTAssertEqual(proposal.kind, .task)
        XCTAssertEqual(proposal.title, "Combinar o rodízio da louça")
    }

    func testASeedProposalConfirmsUndatedEvenWhenNinaAttachedADate() {
        let proposal = NinaProposal(
            kind: .seed,
            title: "Guardar como semente",
            detail: "",
            actionTitle: "Guardar semente",
            payload: NinaProposalPayload(
                title: "Planejar a viagem de fim de ano",
                detail: "",
                dueLabel: "dezembro",
                dueAt: "2026-12-01T12:00:00Z"
            )
        )

        let shown = proposal.confirmationPayload

        XCTAssertEqual(shown.dueLabel, "Sem data")
        XCTAssertNil(shown.dueAt)
    }

    func testACorrectionCannotGiveASeedADateTheCardNeverOffered() {
        let proposal = NinaProposal(
            kind: .seed,
            title: "Guardar como semente",
            detail: "",
            actionTitle: "Guardar semente",
            payload: NinaProposalPayload(
                title: "Trocar a lâmpada da varanda",
                detail: "",
                dueLabel: "Sem data"
            )
        )

        let shown = proposal.confirmationPayload(
            title: proposal.payload.title,
            detail: proposal.payload.detail,
            owner: proposal.payload.owner,
            dueLabel: "amanhã",
            amount: ""
        )

        XCTAssertEqual(shown.dueLabel, "Sem data")
        XCTAssertNil(shown.dueAt)
    }

    func testCorrectingWhenAProposalHappensMovesTheScheduledDateAndNotJustTheLabel() {
        let now = Date(timeIntervalSince1970: 1_786_000_000)
        let payload = NinaProposalPayload(
            title: "Levar o Thor ao veterinário",
            detail: "Vacina anual",
            dueLabel: "amanhã",
            dueAt: "2026-08-11T12:00:00Z"
        )

        let edited = payload.edited(
            title: payload.title,
            detail: payload.detail,
            owner: payload.owner,
            dueLabel: "hoje",
            amount: "",
            now: now
        )

        XCTAssertEqual(edited.dueLabel, "hoje")
        XCTAssertNotEqual(edited.dueAt, payload.dueAt)
        let expected = try? XCTUnwrap(AppStore.inferredDueAt(from: "hoje", now: now))
        XCTAssertEqual(edited.dueAt, expected.map(ISO8601DateFormatter().string(from:)))
    }

    func testAnUnparseableCorrectionLandsUndatedRatherThanKeepingTheModelsDate() {
        let payload = NinaProposalPayload(
            title: "Renovar o seguro",
            detail: "",
            dueLabel: "sexta, 09:00",
            dueAt: "2026-08-14T12:00:00Z"
        )

        let edited = payload.edited(
            title: payload.title,
            detail: payload.detail,
            owner: payload.owner,
            dueLabel: "quando der",
            amount: ""
        )

        XCTAssertEqual(edited.dueLabel, "quando der")
        XCTAssertNil(edited.dueAt)
    }

    func testAnUntouchedLabelKeepsTheDateNinaProposed() {
        let payload = NinaProposalPayload(
            title: "Pagar o boleto",
            detail: "",
            dueLabel: "sexta, 09:00",
            dueAt: "2026-08-14T12:00:00Z"
        )

        let edited = payload.edited(
            title: "Pagar o boleto da Enel",
            detail: payload.detail,
            owner: "Heitor",
            dueLabel: "  sexta, 09:00  ",
            amount: ""
        )

        XCTAssertEqual(edited.title, "Pagar o boleto da Enel")
        XCTAssertEqual(edited.owner, "Heitor")
        XCTAssertEqual(edited.dueAt, "2026-08-14T12:00:00Z")
    }

    func testAnEditedShoppingQuantityReachesThePayloadTrimmed() {
        let payload = NinaProposalPayload(title: "Arroz", detail: "", amount: "1 pacote")

        let edited = payload.edited(
            title: payload.title,
            detail: payload.detail,
            owner: payload.owner,
            dueLabel: payload.dueLabel,
            amount: "  2 pacotes  "
        )

        XCTAssertEqual(edited.amount, "2 pacotes")
    }
}
