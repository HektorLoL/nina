import SwiftUI
import UIKit

struct SupportQuestion: Identifiable, Hashable {
    var question: String
    var answer: String

    var id: String { question }
}

struct SupportTopic: Identifiable, Hashable {
    var title: String
    var questions: [SupportQuestion]

    var id: String { title }
}

enum SupportContent {
    static var email: String {
        URLComponents(url: NinaLegalLinks.support, resolvingAgainstBaseURL: false)?.path ?? ""
    }

    // The website's /suporte/ page answers from web/src/support.ts, which a Deno test holds to this list.
    static let topics: [SupportTopic] = [
        SupportTopic(
            title: "Usar a Nina",
            questions: [
                SupportQuestion(
                    question: "Como a Nina cria uma tarefa?",
                    answer: "Você conta do seu jeito. A Nina propõe uma tarefa, um lembrete ou uma compra. Nada entra na casa antes de você confirmar."
                ),
                SupportQuestion(
                    question: "O que é uma semente?",
                    answer: "Uma vontade sem data, como pintar a sala um dia. Ela fica guardada e nunca vira atraso. Quando chegar a hora, você planta e ela ganha uma data."
                ),
                SupportQuestion(
                    question: "Por que um aviso não chegou?",
                    answer: "Confira Avisos nos Ajustes da Nina e nos Ajustes do iPhone. Uma tarefa sem horário não tem aviso. No silêncio da noite, o aviso chega na hora, sem som."
                ),
                SupportQuestion(
                    question: "Por que a conversa pede idade confirmada?",
                    answer: "Só adultos com idade confirmada pela Apple conversam com a Nina. O resto da Nina funciona sem isso."
                ),
            ]
        ),
        SupportTopic(
            title: "A casa",
            questions: [
                SupportQuestion(
                    question: "Como chamo alguém para a casa?",
                    answer: "Em Casa, use Convidar alguém e mande o link. Quem abrir pede para entrar, e alguém da casa aprova."
                ),
                SupportQuestion(
                    question: "Quantos cabem numa casa?",
                    answer: "Até \(AppStore.maxFamilyPeople), entre pessoas e pets. A Nina não ocupa vaga."
                ),
                SupportQuestion(
                    question: "Crianças podem usar a Nina?",
                    answer: "Uma criança ou um adolescente entra numa casa só com a aprovação de um responsável, e vê só as próprias tarefas."
                ),
                SupportQuestion(
                    question: "O que o Premium inclui?",
                    answer: "Vale para a casa toda: cada adulto manda até 30 mensagens por hora para a Nina, e a casa recebe o resumo semanal. Sem o Premium, são 10 mensagens por dia."
                ),
                SupportQuestion(
                    question: "Como cancelo o Premium?",
                    answer: "Nos Ajustes do iPhone, em Assinaturas. Apagar a conta não cancela a cobrança."
                ),
            ]
        ),
        SupportTopic(
            title: "Privacidade e conta",
            questions: [
                SupportQuestion(
                    question: "Quem lê minha conversa com a Nina?",
                    answer: "Na casa, só você. Cada adulto tem a própria conversa. Uma memória começa privada, e só vai para a casa se você compartilhar."
                ),
                SupportQuestion(
                    question: "Para onde vai o que eu escrevo?",
                    answer: "Os seus registros ficam em servidores no Brasil. O que você escreve para a Nina vai para a OpenAI, nos Estados Unidos, que pode guardar por até 30 dias para evitar abuso. Nome de criança ou adolescente vai trocado por um código."
                ),
                SupportQuestion(
                    question: "Como apago minha conta?",
                    answer: "Em Ajustes, no fim da lista, em Apagar conta. As tarefas que você criou ficam na casa, sem dono."
                ),
            ]
        ),
    ]

    // The mail carries the app and iOS versions and nothing from the house.
    static func mail(appVersion: String, systemVersion: String) -> URL {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = email
        components.queryItems = [
            URLQueryItem(name: "subject", value: "Ajuda com a Nina"),
            URLQueryItem(name: "body", value: "\n\n—\nNina \(appVersion) · iOS \(systemVersion)"),
        ]
        return components.url ?? NinaLegalLinks.support
    }
}

struct SupportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var openQuestionID: String?

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    var body: some View {
        VStack(spacing: 0) {
            BackHeader { dismiss() }

            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    Text("Dúvidas e suporte").ninaText(.screen)

                    ForEach(SupportContent.topics) { topic in
                        VStack(alignment: .leading, spacing: 4) {
                            Eyebrow(text: topic.title)

                            VStack(spacing: 0) {
                                ForEach(Array(topic.questions.enumerated()), id: \.element.id) { index, item in
                                    if index > 0 {
                                        NinaDivider(inset: 0)
                                    }
                                    SupportQuestionRow(
                                        item: item,
                                        isOpen: openQuestionID == item.id
                                    ) {
                                        toggle(item)
                                    }
                                }
                            }
                        }
                    }

                    contactCard
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 34)
            }
        }
        .ninaSheetBackground()
        .toolbar(.hidden, for: .navigationBar)
    }

    private var contactCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Ainda com dúvida?").ninaText(.title)
                Text(SupportContent.email)
                    .ninaText(.label, NinaTheme.muted)
                    .textSelection(.enabled)
            }

            NinaButton(title: "Escrever para o suporte", fillsWidth: true) {
                Haptics.lightImpact()
                openURL(
                    SupportContent.mail(
                        appVersion: appVersion,
                        systemVersion: UIDevice.current.systemVersion
                    )
                )
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ninaCard()
    }

    private func toggle(_ item: SupportQuestion) {
        Haptics.selection()
        let next = openQuestionID == item.id ? nil : item.id
        if reduceMotion {
            openQuestionID = next
        } else {
            withAnimation(.snappy(duration: 0.25)) {
                openQuestionID = next
            }
        }
    }
}

private struct SupportQuestionRow: View {
    var item: SupportQuestion
    var isOpen: Bool
    var onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: onToggle) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(item.question)
                        .ninaText(.body, NinaTheme.ink, weight: .medium)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(NinaTheme.faint)
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                        .accessibilityHidden(true)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(isOpen ? "Aberta" : "Fechada")

            if isOpen {
                Text(item.answer)
                    .ninaText(.label, NinaTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.trailing, 24)
                    .transition(.opacity)
            }
        }
        .padding(.vertical, 8)
    }
}
