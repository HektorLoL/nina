import SwiftUI

struct OnboardingTutorialView: View {
    @Environment(AuthSessionStore.self) private var authSession
    @Environment(OnboardingStore.self) private var onboardingStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var step: TutorialStep = .capture
    @State private var draft = ""
    @State private var sentPhrase = ""
    @State private var reading = TutorialReading()
    @State private var isCorrecting = false
    @FocusState private var isComposerFocused: Bool

    private var hasCompletedTutorial: Bool {
        onboardingStore.hasCompletedTutorial(for: authSession.currentUser)
    }

    private var meLabel: String {
        let name = (authSession.currentUser?.displayName ?? "").firstWord
        return name.isEmpty ? "Você" : name
    }

    var body: some View {
        VStack(spacing: 0) {
            if step.showsChrome {
                header
            }

            switch step {
            case .capture:
                captureStep.transition(.opacity)
            case .confirm:
                confirmStep.transition(.opacity)
            case .close:
                closeStep.transition(.opacity)
            }
        }
        .ninaScreenBackground()
    }

    private var header: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                NinaWordmark(size: 15)

                Spacer(minLength: 0)

                NinaButton(title: hasCompletedTutorial ? "Fechar" : "Pular", kind: .quiet) {
                    closeTutorial()
                }
                .accessibilityLabel(hasCompletedTutorial ? "Fechar tutorial" : "Pular tutorial")
            }

            HStack(spacing: 8) {
                ForEach(TutorialStep.allCases, id: \.self) { each in
                    Capsule()
                        .fill(each.rawValue <= step.rawValue ? NinaTheme.cobalt : NinaTheme.grout)
                        .frame(height: 3)
                }
            }
            .accessibilityElement()
            .accessibilityLabel("Etapa \(step.rawValue + 1) de \(TutorialStep.allCases.count)")
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .padding(.bottom, 4)
    }

    private var captureStep: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("O que está na sua cabeça agora?")
                        .ninaText(.display)
                        .fixedSize(horizontal: false, vertical: true)

                    Eyebrow(text: "Ou toque em uma")
                        .padding(.top, 12)

                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(TutorialPhrase.all) { phrase in
                            Button {
                                Haptics.lightImpact()
                                draft = phrase.phrase
                                isComposerFocused = true
                            } label: {
                                NinaChip(text: phrase.phrase)
                                    .frame(minHeight: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)

            composer
        }
        .task {
            await Task.yield()
            isComposerFocused = true
        }
    }

    private var composer: some View {
        VStack(spacing: 0) {
            NinaDivider(inset: 0)

            HStack(alignment: .bottom, spacing: 12) {
                TextField("Escreva do seu jeito", text: $draft, axis: .vertical)
                    .lineLimit(1...4)
                    .ninaText(.body, NinaTheme.ink)
                    .tint(NinaTheme.cobalt)
                    .focused($isComposerFocused)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 13)
                    .background(
                        NinaTheme.grout,
                        in: RoundedRectangle(cornerRadius: NinaTheme.Radius.sheet, style: .continuous)
                    )

                Button {
                    showToNina()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(NinaTheme.onCobalt)
                        .frame(width: 48, height: 48)
                        .background(NinaTheme.cobalt, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(!canShowToNina)
                .opacity(canShowToNina ? 1 : 0.4)
                .accessibilityLabel("Mostrar para a Nina")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
    }

    private var canShowToNina: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var confirmStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                saidBubble
                readBubble

                VStack(alignment: .leading, spacing: 10) {
                    proposalCard

                    Text("A Nina pode ler errado. Nada entra sem você confirmar.")
                        .ninaText(.meta, NinaTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
    }

    private var saidBubble: some View {
        HStack {
            Spacer(minLength: 48)

            Text(sentPhrase)
                .ninaText(.body, NinaTheme.ground)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    NinaTheme.ink,
                    in: RoundedRectangle(cornerRadius: NinaTheme.Radius.card, style: .continuous)
                )
        }
    }

    private var readBubble: some View {
        HStack(alignment: .top, spacing: 12) {
            NinaMark(size: 24, presence: .rest)

            Text("Li assim. Confere?")
                .ninaText(.body, NinaTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    NinaTheme.cobaltWash,
                    in: RoundedRectangle(cornerRadius: NinaTheme.Radius.card, style: .continuous)
                )

            Spacer(minLength: 24)
        }
    }

    // The rehearsal writes nothing. Every claim on this step is about what the
    // proposal would become, never about something that already exists.
    private var proposalCard: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(NinaTheme.faint)
                            .accessibilityHidden(true)

                        Eyebrow(text: "Ainda não existe")
                    }

                    HStack(alignment: .top, spacing: 10) {
                        CategoryGlyph(
                            systemName: reading.category.symbolName,
                            size: 18,
                            tint: NinaTheme.ink
                        )
                        .accessibilityLabel(reading.category.title)

                        Text(reading.title)
                            .ninaText(.body, NinaTheme.ink, weight: .semibold)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                if isCorrecting {
                    correctionChips
                } else {
                    metaLine
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)

            VStack(spacing: 8) {
                NinaButton(title: confirmTitle, fillsWidth: true) {
                    confirmProposal()
                }

                HStack(spacing: 8) {
                    NinaButton(
                        title: isCorrecting ? "Pronto" : "Corrigir",
                        kind: .outline,
                        fillsWidth: true
                    ) {
                        toggleCorrecting()
                    }

                    // The live card's third exit is "Não"; the rehearsal teaches the same word.
                    NinaButton(title: "Não", kind: .quiet, fillsWidth: true) {
                        ignoreProposal()
                    }
                    .frame(height: 50)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(NinaTheme.grout)
            .overlay(alignment: .top) {
                Rectangle().fill(NinaTheme.line).frame(height: 1)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: NinaTheme.Radius.card, style: .continuous))
        .ninaCard()
    }

    // Correcting the date rebinds what the button creates: an undated correction
    // becomes a semente, so the confirmation can never promise a date the reading
    // no longer carries.
    private var confirmTitle: String {
        reading.isSeed ? "Criar semente" : "Criar tarefa"
    }

    private var dateGlyph: String {
        reading.isSeed ? "leaf" : "calendar"
    }

    private var dateValue: String {
        reading.when ?? "Plante depois"
    }

    private var metaLine: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) { metaPairs }
            VStack(alignment: .leading, spacing: 8) { metaPairs }
        }
    }

    @ViewBuilder
    private var metaPairs: some View {
        metaPair(
            reading.isSeed ? TaskKind.seed.title : "Quando",
            glyph: dateGlyph,
            value: dateValue,
            isMuted: reading.isSeed
        )

        metaPair("Dono", glyph: "person", value: reading.owner)
    }

    private func metaPair(
        _ label: String,
        glyph: String,
        value: String,
        isMuted: Bool = false
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: glyph)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(NinaTheme.muted)

            Text(value)
                .ninaText(.label, isMuted ? NinaTheme.muted : NinaTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value)
    }

    private var correctionChips: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { correctionChipSet }
            VStack(alignment: .leading, spacing: 4) { correctionChipSet }
        }
    }

    @ViewBuilder
    private var correctionChipSet: some View {
        correctionChip(
            "Quando",
            glyph: dateGlyph,
            text: dateValue,
            value: reading.when,
            options: reading.whenOptions
        ) {
            reading.when = $0
        }

        correctionChip(
            "Dono",
            glyph: "person",
            text: reading.owner,
            value: reading.owner,
            options: reading.ownerOptions
        ) {
            reading.owner = $0
        }
    }

    private func correctionChip<Value: Equatable>(
        _ label: String,
        glyph: String,
        text: String,
        value: Value,
        options: [Value],
        set: @escaping (Value) -> Void
    ) -> some View {
        Button {
            Haptics.selection()
            set(cycled(value, in: options))
        } label: {
            Group {
                if text.isEmpty {
                    Image(systemName: glyph)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(NinaTheme.muted)
                        .frame(width: 44, height: 36)
                        .overlay(Capsule().strokeBorder(NinaTheme.control, lineWidth: 1))
                } else {
                    NinaChip(text: text, isSet: true, systemName: glyph)
                }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(text)
        .accessibilityHint("Troca pela próxima opção.")
    }

    private var closeStep: some View {
        VStack(spacing: 0) {
            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: 12) {
                        Text("Agora é com você.")
                            .ninaText(.display)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("Foi só um ensaio. Nada foi criado.")
                            .ninaText(.label, NinaTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 32)
                    .frame(minHeight: proxy.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
            }

            NinaButton(title: "Começar", fillsWidth: true) {
                finishTutorial()
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 10)
        }
    }

    private func showToNina() {
        let phrase = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !phrase.isEmpty else { return }

        sentPhrase = phrase
        reading = makeReading(for: phrase)
        isCorrecting = false
        isComposerFocused = false
        Haptics.selection()
        advance(to: .confirm)
    }

    private func toggleCorrecting() {
        Haptics.selection()
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
            isCorrecting.toggle()
        }
    }

    private func confirmProposal() {
        Haptics.success()
        advance(to: .close)
    }

    private func ignoreProposal() {
        Haptics.selection()
        advance(to: .close)
    }

    private func advance(to next: TutorialStep) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.24)) {
            step = next
        }
    }

    private func closeTutorial() {
        if hasCompletedTutorial {
            Haptics.selection()
            withAnimation(.easeInOut(duration: 0.22)) {
                onboardingStore.cancelReplay()
            }
        } else {
            finishTutorial()
        }
    }

    private func finishTutorial() {
        Haptics.success()
        withAnimation(.easeInOut(duration: 0.26)) {
            onboardingStore.completeTutorial(for: authSession.currentUser)
        }
    }

    private func makeReading(for phrase: String) -> TutorialReading {
        let ownerOptions = ["Sem dono", meLabel]
        let normalized = phrase.lowercased()

        if let prepared = TutorialPhrase.all.first(where: { $0.phrase.lowercased() == normalized }) {
            return TutorialReading(
                title: prepared.title,
                category: prepared.category,
                when: prepared.when,
                whenOptions: prepared.whenOptions,
                owner: ownerOptions.first ?? "",
                ownerOptions: ownerOptions
            )
        }

        // Nothing was read, so nothing is inferred: an unrecognised phrase lands
        // undated rather than borrowing a date from the prepared material.
        return TutorialReading(
            title: asTitle(phrase),
            category: .home,
            when: nil,
            whenOptions: [nil, "Hoje", "Esta semana"],
            owner: ownerOptions.first ?? "",
            ownerOptions: ownerOptions
        )
    }

    private func cycled<Value: Equatable>(_ current: Value, in options: [Value]) -> Value {
        guard let index = options.firstIndex(of: current) else { return options.first ?? current }
        return options[(index + 1) % options.count]
    }

    private func asTitle(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return trimmed }
        return first.uppercased() + trimmed.dropFirst()
    }
}

private enum TutorialStep: Int, CaseIterable {
    case capture
    case confirm
    case close

    var showsChrome: Bool { self != .close }
}

private struct TutorialReading {
    var title = ""
    var category = TaskCategory.home
    var when: String?
    var whenOptions: [String?] = [nil]
    var owner = ""
    var ownerOptions: [String] = []

    var isSeed: Bool { when == nil }
}

private struct TutorialPhrase: Identifiable {
    var phrase: String
    var title: String
    var category: TaskCategory
    var when: String?
    var whenOptions: [String?]

    var id: String { phrase }

    // A literal date in a rehearsal goes stale; the reading is always next Monday.
    private static var nextMondayLabel: String {
        let calendar = Calendar.current
        let next = calendar.nextDate(
            after: .now,
            matching: DateComponents(weekday: 2),
            matchingPolicy: .nextTime
        ) ?? .now
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.dateFormat = "EEE, d MMM"
        let label = formatter.string(from: next)
        return label.prefix(1).uppercased() + label.dropFirst()
    }

    static let all: [TutorialPhrase] = [
        TutorialPhrase(
            phrase: "o boleto do condomínio vence segunda",
            title: "Pagar o condomínio",
            category: .bills,
            when: nextMondayLabel,
            whenOptions: [nextMondayLabel, nil]
        ),
        TutorialPhrase(
            phrase: "tenho que marcar o pediatra",
            title: "Marcar o pediatra",
            category: .health,
            when: nil,
            whenOptions: [nil, "Esta semana"]
        ),
        TutorialPhrase(
            phrase: "acabou a ração do cachorro",
            title: "Comprar ração do cachorro",
            category: .pet,
            when: nil,
            whenOptions: [nil, "Hoje"]
        ),
        TutorialPhrase(
            phrase: "um dia eu queria arrumar o quintal",
            title: "Arrumar o quintal",
            category: .home,
            when: nil,
            whenOptions: [nil, "Neste mês"]
        )
    ]
}

#Preview("Tutorial") {
    let auth = AuthSessionStore()
    auth.currentUser = AuthUser(id: "preview", displayName: "Preview", email: "preview@ninai.app", provider: .email)

    return OnboardingTutorialView()
        .environment(auth)
        .environment(OnboardingStore())
}
