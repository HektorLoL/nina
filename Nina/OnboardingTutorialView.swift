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
    @State private var proposalOutcome: ProposalOutcome?
    @State private var removedSuggestions: Set<String> = []
    @State private var questionIndex = 0
    @State private var answers: [Int: String] = [:]
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
            case .subtract:
                subtractStep.transition(.opacity)
            case .questions:
                questionsStep.transition(.opacity)
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

                    Text("Do jeito que você pensou. Sem data, sem categoria, sem forma certa.")
                        .ninaText(.label, NinaTheme.muted)
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
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(NinaTheme.ink)
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
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    saidBubble
                    readBubble
                    proposalCard
                    waitingLine
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 24)
            }

            accuracyNote
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

            Text("Li assim. Se eu entendi errado alguma coisa, corrija antes de confirmar.")
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
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(NinaTheme.faint)

                Eyebrow(text: "Isto ainda não existe")

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                NinaTheme.grout,
                in: UnevenRoundedRectangle(
                    topLeadingRadius: NinaTheme.Radius.card,
                    topTrailingRadius: NinaTheme.Radius.card,
                    style: .continuous
                )
            )

            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 12) {
                    NinaCheckbox(isOn: false, size: 24)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(reading.title)
                            .ninaText(.body, NinaTheme.ink, weight: .semibold)
                            .fixedSize(horizontal: false, vertical: true)

                        if !reading.detail.isEmpty {
                            Text(reading.detail).ninaText(.caption, NinaTheme.muted)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 6) {
                        CategoryGlyph(
                            systemName: reading.category.symbolName,
                            size: 16,
                            tint: NinaTheme.muted
                        )
                        Text(reading.category.title).ninaText(.caption, NinaTheme.muted)
                    }
                }
                .padding(.bottom, 14)

                NinaDivider(inset: 0)

                decisiveRow("Quando", value: reading.when, options: reading.whenOptions) {
                    reading.when = $0
                }

                // A semente has no date, so it cannot repeat. Correcting Quando to
                // "sem data" and leaving "todo mês" on the card teaches a
                // contradiction on the screen that teaches the whole grammar.
                if reading.when != TutorialReading.noDate {
                    NinaDivider(inset: 0)

                    decisiveRow("Repete", value: reading.repeats, options: reading.repeatOptions) {
                        reading.repeats = $0
                    }
                }

                NinaDivider(inset: 0)

                decisiveRow("Dono", value: reading.owner, options: reading.ownerOptions) {
                    reading.owner = $0
                }

                if isCorrecting {
                    Text("Toque em um valor para trocar.")
                        .ninaText(.caption, NinaTheme.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 12)
                }
            }
            .padding(16)

            VStack(spacing: 10) {
                NinaButton(title: confirmTitle, fillsWidth: true) {
                    confirmProposal()
                }

                HStack(spacing: 10) {
                    NinaButton(
                        title: isCorrecting ? "Pronto" : "Corrigir",
                        kind: .outline,
                        fillsWidth: true
                    ) {
                        toggleCorrecting()
                    }

                    NinaButton(title: "Ignorar", kind: .outline, fillsWidth: true) {
                        ignoreProposal()
                    }
                }
            }
            .padding(16)
            .background(
                NinaTheme.grout,
                in: UnevenRoundedRectangle(
                    bottomLeadingRadius: NinaTheme.Radius.card,
                    bottomTrailingRadius: NinaTheme.Radius.card,
                    style: .continuous
                )
            )
        }
        .ninaCard()
    }

    // Correcting the date rebinds what the button creates: an undated correction
    // becomes a semente, so the confirmation can never promise a date the reading
    // no longer carries.
    private var confirmTitle: String {
        reading.isSeed ? "Confirmar e criar 1 semente" : "Confirmar e criar 1 tarefa"
    }

    private func decisiveRow(
        _ label: String,
        value: String,
        options: [String],
        set: @escaping (String) -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .ninaText(.label, NinaTheme.muted)
                .frame(width: 84, alignment: .leading)

            if isCorrecting {
                Button {
                    Haptics.selection()
                    set(cycled(value, in: options))
                } label: {
                    NinaChip(text: value, isSet: true)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(label): \(value). Toque para trocar.")
            } else {
                Text(value).ninaText(.label, NinaTheme.ink)
            }

            Spacer(minLength: 0)
        }
        .frame(minHeight: 46)
    }

    private var waitingLine: some View {
        HStack(spacing: 10) {
            NinaMark(size: 12, presence: .waiting)

            Text("A Nina está esperando você.")
                .ninaText(.caption, NinaTheme.cobalt, weight: .semibold)
        }
    }

    private var accuracyNote: some View {
        VStack(spacing: 0) {
            NinaDivider(inset: 0)

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "info.circle")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(NinaTheme.faint)

                Text("A Nina pode ler errado. Ela nunca cria, altera ou apaga nada sozinha — nada acontece até você tocar em confirmar.")
                    .ninaText(.caption, NinaTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
    }

    private var subtractStep: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Tire o que não é a sua casa.")
                        .ninaText(.display)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Isto é o que costuma pesar numa casa brasileira. Você não escreveu nada disso — e não precisa aceitar nada disso.")
                        .ninaText(.label, NinaTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(spacing: 0) {
                        ForEach(TutorialSuggestion.all) { suggestion in
                            suggestionRow(suggestion)

                            if suggestion.id != TutorialSuggestion.all.last?.id {
                                NinaDivider(inset: 0)
                            }
                        }
                    }
                    .padding(.top, 8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 20)
            }

            subtractFooter
        }
    }

    private func suggestionRow(_ suggestion: TutorialSuggestion) -> some View {
        let isRemoved = removedSuggestions.contains(suggestion.id)

        return HStack(spacing: 12) {
            CategoryGlyph(
                systemName: suggestion.category.symbolName,
                size: 20,
                tint: isRemoved ? NinaTheme.line : NinaTheme.ink
            )
            .frame(width: 40, alignment: .center)

            Text(suggestion.title)
                .font(.system(size: 17, weight: .medium))
                .tracking(-0.1)
                .foregroundStyle(isRemoved ? NinaTheme.faint : NinaTheme.ink)
                .strikethrough(isRemoved, color: NinaTheme.faint)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                toggleSuggestion(suggestion)
            } label: {
                Image(systemName: isRemoved ? "plus" : "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isRemoved ? NinaTheme.faint : NinaTheme.muted)
                    .frame(width: 32, height: 32)
                    .background(isRemoved ? Color.clear : NinaTheme.grout, in: Circle())
                    .overlay(
                        Circle()
                            .strokeBorder(isRemoved ? NinaTheme.line : Color.clear, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                isRemoved ? "Trazer \(suggestion.title) de volta" : "Tirar \(suggestion.title)"
            )
        }
        .frame(minHeight: 56)
    }

    private var subtractFooter: some View {
        VStack(spacing: 0) {
            NinaDivider(inset: 0)

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(removedHeadline).ninaText(.title)

                    Text(removedInsight)
                        .ninaText(.label, NinaTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                NinaButton(title: keptTitle, fillsWidth: true) {
                    keepSuggestions()
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 8)
        }
    }

    private var keptSuggestions: Int {
        TutorialSuggestion.all.count - removedSuggestions.count
    }

    private var removedHeadline: String {
        removedSuggestions.isEmpty ? "Nada fora." : "\(removedSuggestions.count) fora."
    }

    private var removedInsight: String {
        if removedSuggestions.isEmpty {
            return "Tudo isto pesa na sua casa. Também é uma resposta."
        }

        let petIDs = Set(TutorialSuggestion.all.filter { $0.category.id == "pet" }.map(\.id))
        if petIDs.isSubset(of: removedSuggestions) {
            return "Você não tem pet. Sobrou a sua casa."
        }

        return "Sobrou o que é a sua casa."
    }

    private var keptTitle: String {
        switch keptSuggestions {
        case 0: "Seguir sem nenhuma"
        case 1: "Ficar com esta"
        default: "Ficar com estas \(keptSuggestions)"
        }
    }

    private var questionsStep: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Eyebrow(text: "Pergunta \(questionIndex + 1) de \(TutorialQuestion.all.count)")

                    Text(currentQuestion.title)
                        .ninaText(.display)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(currentQuestion.detail)
                        .ninaText(.label, NinaTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(spacing: 10) {
                        ForEach(currentQuestion.options, id: \.self) { option in
                            answerCard(option, isOpen: false)
                        }

                        answerCard(currentQuestion.openOption, isOpen: true)
                    }
                    .padding(.top, 6)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 20)
            }

            VStack(spacing: 6) {
                NinaButton(
                    title: "Continuar",
                    fillsWidth: true,
                    isEnabled: answers[questionIndex] != nil
                ) {
                    advanceQuestion()
                }

                NinaButton(title: "Prefiro não responder", kind: .quiet, fillsWidth: true) {
                    skipQuestion()
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 10)
        }
    }

    private var currentQuestion: TutorialQuestion {
        TutorialQuestion.all[min(max(questionIndex, 0), TutorialQuestion.all.count - 1)]
    }

    private func answerCard(_ option: String, isOpen: Bool) -> some View {
        let isSelected = answers[questionIndex] == option

        return Button {
            Haptics.selection()
            answers[questionIndex] = option
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    if isSelected {
                        Circle().fill(NinaTheme.cobalt)
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(NinaTheme.onCobalt)
                    } else {
                        Circle()
                            .strokeBorder(
                                NinaTheme.line,
                                style: StrokeStyle(lineWidth: 1.6, dash: isOpen ? [3, 3] : [])
                            )
                    }
                }
                .frame(width: 24, height: 24)

                Text(option)
                    .font(.system(size: 17, weight: .medium))
                    .tracking(-0.1)
                    .foregroundStyle(isOpen && !isSelected ? NinaTheme.muted : NinaTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .background(
                isSelected ? NinaTheme.cobaltWash : NinaTheme.ground,
                in: RoundedRectangle(cornerRadius: NinaTheme.Radius.field, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: NinaTheme.Radius.field, style: .continuous)
                    .strokeBorder(
                        isSelected ? NinaTheme.cobalt : NinaTheme.line,
                        style: StrokeStyle(lineWidth: 1, dash: isOpen && !isSelected ? [5, 4] : [])
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var closeStep: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Agora sim, é com você.")
                        .ninaText(.display)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Você acabou de ver como funciona. A Nina lê, mostra o que entendeu e espera. Quem cria, muda ou apaga é você.")
                        .ninaText(.label, NinaTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(rehearsalLines, id: \.self) { line in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(NinaTheme.moss)

                                Text(line)
                                    .ninaText(.label, NinaTheme.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        NinaTheme.grout,
                        in: RoundedRectangle(cornerRadius: NinaTheme.Radius.card, style: .continuous)
                    )
                    .padding(.top, 6)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 48)
                .padding(.bottom, 20)
            }

            VStack(spacing: 12) {
                NinaButton(title: "Começar", fillsWidth: true) {
                    finishTutorial()
                }

                Text("Isto foi um ensaio: nada aqui virou tarefa. Na conversa, o que você confirmar passa a existir para a casa inteira.")
                    .ninaText(.caption, NinaTheme.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 10)
        }
    }

    private var rehearsalLines: [String] {
        var lines: [String] = []

        switch proposalOutcome {
        case .confirmed(let isSeed):
            lines.append(
                isSeed
                    ? "Você confirmou uma semente, sem data nenhuma."
                    : "Você leu a proposta inteira antes de confirmar."
            )
        case .ignored:
            lines.append("Você ignorou a proposta, e nada foi criado.")
        case nil:
            lines.append("Você viu a Nina propor, e a decisão ficou com você.")
        }

        switch keptSuggestions {
        case 0: lines.append("Você não ficou com nenhuma das sugestões.")
        case 1: lines.append("Você ficou com 1 de \(TutorialSuggestion.all.count) sugestões.")
        default:
            lines.append("Você ficou com \(keptSuggestions) de \(TutorialSuggestion.all.count) sugestões.")
        }

        lines.append(
            answers.isEmpty
                ? "Você pulou as perguntas. Isso também vale."
                : "Nenhuma resposta sua vira cobrança."
        )

        return lines
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
        Haptics.lightImpact()
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
            isCorrecting.toggle()
        }
    }

    private func confirmProposal() {
        Haptics.success()
        proposalOutcome = .confirmed(isSeed: reading.isSeed)
        advance(to: .subtract)
    }

    private func ignoreProposal() {
        Haptics.selection()
        proposalOutcome = .ignored
        advance(to: .subtract)
    }

    private func toggleSuggestion(_ suggestion: TutorialSuggestion) {
        Haptics.selection()
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
            if removedSuggestions.contains(suggestion.id) {
                removedSuggestions.remove(suggestion.id)
            } else {
                removedSuggestions.insert(suggestion.id)
            }
        }
    }

    private func keepSuggestions() {
        Haptics.selection()
        advance(to: .questions)
    }

    private func advanceQuestion() {
        Haptics.selection()

        if questionIndex + 1 < TutorialQuestion.all.count {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                questionIndex += 1
            }
            return
        }

        advance(to: .close)
    }

    private func skipQuestion() {
        answers[questionIndex] = nil
        advanceQuestion()
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
        let ownerOptions = ["A casa, por enquanto", meLabel]
        let normalized = phrase.lowercased()

        if let prepared = TutorialPhrase.all.first(where: { $0.phrase.lowercased() == normalized }) {
            return TutorialReading(
                title: prepared.title,
                detail: prepared.detail,
                category: prepared.category,
                when: prepared.when,
                whenOptions: prepared.whenOptions,
                repeats: prepared.repeats,
                repeatOptions: prepared.repeatOptions,
                owner: ownerOptions.first ?? "",
                ownerOptions: ownerOptions
            )
        }

        // Nothing was read, so nothing is inferred: an unrecognised phrase lands
        // undated rather than borrowing a date from the prepared material.
        return TutorialReading(
            title: asTitle(phrase),
            detail: "",
            category: .home,
            when: TutorialReading.noDate,
            whenOptions: [TutorialReading.noDate, "hoje", "esta semana"],
            repeats: "não repete",
            repeatOptions: ["não repete", "toda semana", "todo mês"],
            owner: ownerOptions.first ?? "",
            ownerOptions: ownerOptions
        )
    }

    private func cycled(_ current: String, in options: [String]) -> String {
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
    case subtract
    case questions
    case close

    var showsChrome: Bool { self != .close }
}

private enum ProposalOutcome {
    case confirmed(isSeed: Bool)
    case ignored
}

private struct TutorialReading {
    static let noDate = "sem data"

    var title = ""
    var detail = ""
    var category = TaskCategory.home
    var when = TutorialReading.noDate
    var whenOptions: [String] = [TutorialReading.noDate]
    var repeats = "não repete"
    var repeatOptions: [String] = ["não repete"]
    var owner = ""
    var ownerOptions: [String] = []

    var isSeed: Bool { when == TutorialReading.noDate }
}

private struct TutorialPhrase: Identifiable {
    var phrase: String
    var title: String
    var detail: String
    var category: TaskCategory
    var when: String
    var whenOptions: [String]
    var repeats: String
    var repeatOptions: [String]

    var id: String { phrase }

    static let all: [TutorialPhrase] = [
        TutorialPhrase(
            phrase: "o boleto do condomínio vence dia 10",
            title: "Pagar o condomínio",
            detail: "",
            category: .bills,
            when: "segunda, 10 de agosto",
            whenOptions: ["segunda, 10 de agosto", TutorialReading.noDate],
            repeats: "todo mês",
            repeatOptions: ["todo mês", "não repete"]
        ),
        TutorialPhrase(
            phrase: "tenho que marcar o pediatra do Téo",
            title: "Marcar o pediatra do Téo",
            detail: "",
            category: .health,
            when: TutorialReading.noDate,
            whenOptions: [TutorialReading.noDate, "esta semana"],
            repeats: "não repete",
            repeatOptions: ["não repete", "todo ano"]
        ),
        TutorialPhrase(
            phrase: "acabou a ração do Bidu",
            title: "Comprar ração do Bidu",
            detail: "",
            category: .pet,
            when: TutorialReading.noDate,
            whenOptions: [TutorialReading.noDate, "hoje"],
            repeats: "não repete",
            repeatOptions: ["não repete", "todo mês"]
        ),
        TutorialPhrase(
            phrase: "um dia eu queria arrumar o quintal",
            title: "Arrumar o quintal",
            detail: "",
            category: .home,
            when: TutorialReading.noDate,
            whenOptions: [TutorialReading.noDate, "neste mês"],
            repeats: "não repete",
            repeatOptions: ["não repete"]
        )
    ]
}

private struct TutorialSuggestion: Identifiable {
    var title: String
    var category: TaskCategory

    var id: String { title }

    static let all: [TutorialSuggestion] = [
        TutorialSuggestion(title: "Boleto do condomínio", category: .bills),
        TutorialSuggestion(title: "Reunião de pais", category: .school),
        TutorialSuggestion(title: "Vacina do pet", category: .pet),
        TutorialSuggestion(title: "Conta de luz", category: .bills),
        TutorialSuggestion(title: "Banho e tosa", category: .pet),
        TutorialSuggestion(title: "IPVA e licenciamento", category: .bills),
        TutorialSuggestion(title: "Comprar ração", category: .pet)
    ]
}

private struct TutorialQuestion {
    var title: String
    var detail: String
    var options: [String]
    var openOption: String

    static let all: [TutorialQuestion] = [
        TutorialQuestion(
            title: "Quem lembra das coisas nesta casa?",
            detail: "Não é para julgar ninguém. Nenhuma resposta vira cobrança.",
            options: [
                "A gente divide, mas quem lembra sou eu",
                "Sou eu em praticamente tudo",
                "A gente divide bem de verdade",
                "Não divido a casa com ninguém"
            ],
            openOption: "É outra coisa"
        ),
        TutorialQuestion(
            title: "O que mais some da sua cabeça?",
            detail: "Escolha o que mais pesa hoje. Amanhã pode ser outro.",
            options: [
                "Contas e vencimentos",
                "Escola e crianças",
                "Mercado e casa",
                "Consultas e remédios"
            ],
            openOption: "É outra coisa"
        ),
        TutorialQuestion(
            title: "Quando dá para parar e resolver?",
            detail: "Lembrete bom é o que chega na hora em que dá para resolver.",
            options: [
                "De manhã, antes da casa acordar",
                "No meio do dia",
                "Depois que a casa dorme",
                "Não tem hora certa"
            ],
            openOption: "É outra coisa"
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
