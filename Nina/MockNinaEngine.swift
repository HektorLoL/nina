import Foundation
#if canImport(Supabase)
import Supabase
#endif

struct NinaEngineResponse {
    var reply: String
    var suggestion: NinaSuggestion?
    var version: Int
    var runID: UUID?
    var threadID: UUID?
    var assistantMessageID: UUID?
    var proposals: [NinaProposal]
    var serverPersisted: Bool

    init(
        reply: String,
        suggestion: NinaSuggestion?,
        version: Int = 1,
        runID: UUID? = nil,
        threadID: UUID? = nil,
        assistantMessageID: UUID? = nil,
        proposals: [NinaProposal] = [],
        serverPersisted: Bool = false
    ) {
        self.reply = reply
        self.suggestion = suggestion
        self.version = version
        self.runID = runID
        self.threadID = threadID
        self.assistantMessageID = assistantMessageID
        self.proposals = proposals
        self.serverPersisted = serverPersisted
    }
}

enum NinaEngineError: Error, Equatable {
    case rateLimited
    case monthlyBudgetReached
    case inputTooLarge
    case adultAccessRequired
    case aiConsentRequired
    case attachmentsRequirePremium
    case inputNotSupported
    case requestInProgress
    case unavailable

    init(code: String) {
        switch code {
        case "rate_limited":
            self = .rateLimited
        case "monthly_budget_reached":
            self = .monthlyBudgetReached
        case "input_too_large":
            self = .inputTooLarge
        case "adult_access_required":
            self = .adultAccessRequired
        case "ai_consent_required":
            self = .aiConsentRequired
        case "attachments_require_premium":
            self = .attachmentsRequirePremium
        case "input_not_supported":
            self = .inputNotSupported
        case "request_in_progress":
            self = .requestInProgress
        default:
            self = .unavailable
        }
    }

    var userMessage: String {
        switch self {
        case .rateLimited:
            "Você chegou ao limite temporário de mensagens. Tente novamente mais tarde."
        case .monthlyBudgetReached:
            "A Nina atingiu o limite mensal de uso da casa. Novas respostas online voltam no próximo mês."
        case .inputTooLarge:
            "Essa mensagem ou anexo é grande demais para uma única conversa."
        case .adultAccessRequired:
            "A conversa com a Nina está disponível somente para adultos da casa."
        case .aiConsentRequired:
            "A Nina precisa do seu consentimento antes de conversar. Você pode aceitar em Ajustes."
        case .attachmentsRequirePremium:
            "A leitura de documentos e fotos faz parte do Premium da casa."
        case .inputNotSupported:
            "Não consigo ajudar com esse conteúdo."
        case .requestInProgress:
            "Essa mensagem ainda está sendo processada. Aguarde um instante."
        case .unavailable:
            "A Nina online está indisponível no momento."
        }
    }
}

struct NinaAttachmentInput: Encodable, Hashable {
    var metadata: ChatAttachment
    var data: Data

    private enum CodingKeys: String, CodingKey {
        case kind
        case filename
        case mimeType = "mime_type"
        case data = "data_base64"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(metadata.kind, forKey: .kind)
        try container.encode(metadata.filename, forKey: .filename)
        try container.encode(metadata.mimeType, forKey: .mimeType)
        try container.encode(data, forKey: .data)
    }
}

protocol NinaEngine {
    func respond(
        to text: String,
        attachments: [NinaAttachmentInput],
        familyID: UUID,
        messageID: UUID
    ) async throws -> NinaEngineResponse
}

struct MockNinaEngine: NinaEngine {
    func respond(
        to text: String,
        attachments: [NinaAttachmentInput],
        familyID _: UUID,
        messageID _: UUID
    ) async throws -> NinaEngineResponse {
        let normalized = text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()

        if let attachment = attachments.first {
            let isImage = attachment.metadata.kind == .image
            let title = isImage ? "Organizar foto enviada" : "Organizar documento enviado"
            let detail = "Revisar \(attachment.metadata.filename) e guardar as informações úteis para a casa."

            return NinaEngineResponse(
                reply: isImage
                    ? "Recebi a foto. Posso usar o que aparece nela para sugerir uma tarefa ou lembrete, e você confirma antes de eu criar qualquer coisa."
                    : "Recebi o documento. Posso resumir os pontos importantes e transformar datas ou pendências em uma sugestão para a casa.",
                suggestion: NinaSuggestion(
                    title: title,
                    detail: detail,
                    actionTitle: "Criar tarefa",
                    kind: .document,
                    payloadTitle: title,
                    payloadDetail: detail,
                    payloadOwner: "Casa",
                    payloadDueLabel: "Sem data",
                    category: .home,
                    symbolName: isImage ? "photo.fill" : "doc.text.fill"
                )
            )
        }

        if normalized.contains("veterin") || normalized.contains("thor") {
            return NinaEngineResponse(
                reply: "Claro. Posso deixar isso organizado para vocês. Quer que eu crie a tarefa do veterinário do Thor para esta semana?",
                suggestion: NinaSuggestion(
                    title: "Veterinário do Thor",
                    detail: "Marcar consulta e verificar carteira de vacinas.",
                    actionTitle: "Criar tarefa",
                    kind: .task,
                    payloadTitle: "Marcar veterinário para o Thor",
                    payloadDetail: "Conferir horários e carteira de vacinas.",
                    payloadOwner: "Heitor",
                    payloadDueLabel: "Esta semana",
                    category: .pet,
                    symbolName: "pawprint.fill"
                )
            )
        }

        if normalized.contains("gas") || normalized.contains("gás") {
            return NinaEngineResponse(
                reply: "Entendi. Pelo ritmo da casa, faz sentido lembrar antes de virar urgência. Posso criar um lembrete para daqui 8 dias.",
                suggestion: NinaSuggestion(
                    title: "Lembrete do gás",
                    detail: "Avisar antes do gás acabar para comprar sem correria.",
                    actionTitle: "Criar lembrete",
                    kind: .reminder,
                    payloadTitle: "Comprar gás",
                    payloadDetail: "O gás deve acabar em cerca de 10 dias.",
                    payloadOwner: "Casa",
                    payloadDueLabel: "Daqui 8 dias",
                    category: .home,
                    symbolName: "flame.fill"
                )
            )
        }

        if normalized.contains("aniversario") || normalized.contains("aniversário") || normalized.contains("mae") || normalized.contains("mãe") {
            return NinaEngineResponse(
                reply: "Boa lembrança. Posso guardar essa data e sugerir presentes dentro do orçamento que vocês costumam usar.",
                suggestion: NinaSuggestion(
                    title: "Aniversário da mãe",
                    detail: "Separar ideias de presente e criar lembrete para comprar antes do fim de semana.",
                    actionTitle: "Guardar data",
                    kind: .gift,
                    payloadTitle: "Comprar presente para aniversário da mãe",
                    payloadDetail: "Sugerir opções simples dentro do orçamento da família.",
                    payloadOwner: "Mirna",
                    payloadDueLabel: "Semana que vem",
                    category: .home,
                    symbolName: "gift.fill"
                )
            )
        }

        if normalized.contains("conta") || normalized.contains("boleto") || normalized.contains("vencimento") {
            return NinaEngineResponse(
                reply: "Se você me enviar uma foto da conta, eu consigo ler o vencimento e preparar uma sugestão para colocar o pagamento na rotina da casa.",
                suggestion: NinaSuggestion(
                    title: "Conta para pagar",
                    detail: "Registrar vencimento e colocar na lista de acompanhamento.",
                    actionTitle: "Criar tarefa",
                    kind: .document,
                    payloadTitle: "Revisar conta recebida",
                    payloadDetail: "Conferir vencimento e responsável pelo pagamento.",
                    payloadOwner: "Heitor",
                    payloadDueLabel: "Próximos dias",
                    category: .bills,
                    symbolName: "doc.text.viewfinder"
                )
            )
        }

        if normalized.contains("receita") || normalized.contains("remedio") || normalized.contains("remédio") || normalized.contains("medicamento") {
            return NinaEngineResponse(
                reply: "Envie uma foto ou o arquivo da receita. Eu posso ajudar a organizar horários, doses e quem precisa acompanhar, sem substituir a orientação médica.",
                suggestion: NinaSuggestion(
                    title: "Rotina de medicamento",
                    detail: "Criar lembrete diário para acompanhar a receita.",
                    actionTitle: "Criar rotina",
                    kind: .document,
                    payloadTitle: "Organizar medicamento da receita",
                    payloadDetail: "Registrar horários e responsável por acompanhar.",
                    payloadOwner: "Mirna",
                    payloadDueLabel: "Hoje",
                    category: .health,
                    symbolName: "pills.fill"
                )
            )
        }

        if normalized.contains("escola") || normalized.contains("comprovante") || normalized.contains("reuniao") || normalized.contains("reunião") {
            return NinaEngineResponse(
                reply: "Consigo usar o comprovante ou documento para preparar uma tarefa escolar com as datas e detalhes importantes.",
                suggestion: NinaSuggestion(
                    title: "Compromisso escolar",
                    detail: "Adicionar evento escolar à rotina da família.",
                    actionTitle: "Criar tarefa escolar",
                    kind: .document,
                    payloadTitle: "Organizar comprovante escolar",
                    payloadDetail: "Conferir data e material necessário.",
                    payloadOwner: "Mirna",
                    payloadDueLabel: "Esta semana",
                    category: .school,
                    symbolName: "backpack.fill"
                )
            )
        }

        if normalized.contains("cansad") || normalized.contains("sobrecarreg") || normalized.contains("estresse") {
            return NinaEngineResponse(
                reply: "Isso parece pesado. Se quiser, eu monto uma conversa sobre a divisão da casa — você decide se vale.",
                suggestion: NinaSuggestion(
                    title: "Revisar divisão da casa",
                    detail: "Uma conversa sobre quem está pegando o quê, sem números e sem placar.",
                    actionTitle: "Ver sugestão",
                    kind: .redistribution,
                    payloadTitle: "Revisar divisão doméstica",
                    payloadDetail: "Conversar sobre redistribuir tarefas recorrentes.",
                    payloadOwner: "Casa",
                    payloadDueLabel: "Hoje",
                    category: .home,
                    symbolName: "chart.bar.fill"
                )
            )
        }

        return NinaEngineResponse(
            reply: "Anotei. Como ainda não há uma data clara, posso guardar isso como semente e vocês decidem quando plantar.",
            suggestion: NinaSuggestion(
                title: "Guardar como semente",
                detail: "Manter essa intenção visível sem escolher uma data agora.",
                actionTitle: "Guardar semente",
                kind: .seed,
                payloadTitle: text,
                payloadDetail: "Intenção guardada a partir da conversa com a Nina.",
                payloadOwner: "Casa",
                payloadDueLabel: "Sem data",
                category: .home,
                symbolName: "leaf.fill"
            )
        )
    }
}

#if canImport(Supabase)
struct SupabaseNinaEngine: NinaEngine {
    var client: SupabaseClient
    var diagnostics: BackendDiagnosticsStore? = nil

    func respond(
        to text: String,
        attachments: [NinaAttachmentInput],
        familyID: UUID,
        messageID: UUID
    ) async throws -> NinaEngineResponse {
        do {
            let response: NinaFunctionResponse = try await BackendRequestLogger.perform(
                component: "nina",
                operation: "chat",
                diagnostics: diagnostics
            ) {
                try await client.functions.invoke(
                    "nina-chat",
                    options: FunctionInvokeOptions(
                        body: NinaFunctionRequest(
                            familyID: familyID,
                            messageID: messageID,
                            message: text,
                            attachments: attachments
                        )
                    )
                )
            }

            return response.domainResponse
        } catch FunctionsError.httpError(_, let data) {
            let payload = try? JSONDecoder().decode(NinaFunctionErrorResponse.self, from: data)
            throw NinaEngineError(code: payload?.error ?? "unavailable")
        } catch {
            throw NinaEngineError.unavailable
        }
    }
}

struct NinaFunctionErrorResponse: Decodable {
    var error: String
}

private struct NinaFunctionRequest: Encodable {
    var familyID: UUID
    var messageID: UUID
    var message: String
    var attachments: [NinaAttachmentInput]

    private enum CodingKeys: String, CodingKey {
        case familyID = "family_id"
        case messageID = "message_id"
        case message
        case attachments
    }
}

struct NinaFunctionResponse: Decodable {
    var version: Int?
    var runID: UUID?
    var threadID: UUID?
    var reply: String
    var assistantMessageID: UUID?
    var proposals: [NinaProposal]?
    var suggestion: NinaFunctionSuggestion?

    private enum CodingKeys: String, CodingKey {
        case version
        case runID = "run_id"
        case threadID = "thread_id"
        case reply
        case assistantMessageID = "assistant_message_id"
        case proposals
        case suggestion
    }

    var domainResponse: NinaEngineResponse {
        let responseVersion = version ?? 1
        return NinaEngineResponse(
            reply: reply,
            suggestion: suggestion?.domainSuggestion,
            version: responseVersion,
            runID: runID,
            threadID: threadID,
            assistantMessageID: assistantMessageID,
            proposals: proposals ?? [],
            serverPersisted: responseVersion >= 2
                && runID != nil
                && threadID != nil
                && assistantMessageID != nil
        )
    }
}

struct NinaFunctionSuggestion: Decodable {
    var title: String
    var detail: String
    var actionTitle: String
    var kind: NinaSuggestionKind
    var payloadTitle: String
    var payloadDetail: String
    var payloadOwner: String
    var payloadDueLabel: String
    var categoryID: String
    var symbolName: String

    private enum CodingKeys: String, CodingKey {
        case title
        case detail
        case actionTitle = "action_title"
        case kind
        case payloadTitle = "payload_title"
        case payloadDetail = "payload_detail"
        case payloadOwner = "payload_owner"
        case payloadDueLabel = "payload_due_label"
        case categoryID = "category"
        case symbolName = "symbol_name"
    }

    var domainSuggestion: NinaSuggestion {
        NinaSuggestion(
            title: title,
            detail: detail,
            actionTitle: actionTitle,
            kind: kind,
            payloadTitle: payloadTitle,
            payloadDetail: payloadDetail,
            payloadOwner: payloadOwner,
            payloadDueLabel: payloadDueLabel,
            category: TaskCategory.allCases.first { $0.id == categoryID } ?? .home,
            symbolName: symbolName
        )
    }
}
#endif
