import SwiftUI

struct OnboardingTutorialView: View {
    @Environment(AuthSessionStore.self) private var authSession
    @Environment(OnboardingStore.self) private var onboardingStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var selectedIndex = 0
    @State private var didAppear = false

    private let steps = TutorialStep.all

    private var selectedStep: TutorialStep {
        steps[selectedIndex]
    }

    private var isLastStep: Bool {
        selectedIndex == steps.count - 1
    }

    private var hasCompletedTutorial: Bool {
        onboardingStore.hasCompletedTutorial(for: authSession.currentUser)
    }

    var body: some View {
        ZStack {
            NinaTheme.screenGradient
                .ignoresSafeArea()

            VStack(spacing: 18) {
                header

                TabView(selection: $selectedIndex) {
                    ForEach(steps.indices, id: \.self) { index in
                        TutorialPage(step: steps[index], isActive: selectedIndex == index)
                            .tag(index)
                            .padding(.horizontal, 22)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.interactiveSpring(response: 0.42, dampingFraction: 0.88), value: selectedIndex)

                controls
            }
            .padding(.top, 20)
            .padding(.bottom, 22)
        }
        .onAppear {
            guard !didAppear else { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.32)) {
                didAppear = true
            }
        }
        .onChange(of: selectedIndex) { oldValue, newValue in
            guard oldValue != newValue else { return }
            Haptics.selection()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(hasCompletedTutorial ? "Tutorial da Nina" : "Primeiro acesso")
                    .font(.title2.weight(.black))
                    .foregroundStyle(NinaTheme.ink)

                Text("\(selectedIndex + 1) de \(steps.count)")
                    .font(.caption.weight(.black))
                    .foregroundStyle(selectedStep.tone.color)
            }

            Spacer()

            Button {
                closeTutorial()
            } label: {
                Image(systemName: "xmark")
                    .font(.headline.weight(.black))
                    .foregroundStyle(NinaTheme.ink)
                    .frame(width: 42, height: 42)
                    .background(NinaTheme.card, in: Circle())
                    .overlay(
                        Circle()
                            .stroke(NinaTheme.line, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(hasCompletedTutorial ? "Fechar tutorial" : "Pular tutorial")
        }
        .padding(.horizontal, 22)
        .opacity(didAppear ? 1 : 0)
        .offset(y: didAppear || reduceMotion ? 0 : -10)
    }

    private var controls: some View {
        VStack(spacing: 16) {
            HStack(spacing: 8) {
                ForEach(steps.indices, id: \.self) { index in
                    Capsule()
                        .fill(index == selectedIndex ? steps[index].tone.color : NinaTheme.line.opacity(0.88))
                        .frame(width: index == selectedIndex ? 34 : 10, height: 10)
                        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: selectedIndex)
                }
            }
            .accessibilityLabel("Progresso do tutorial, etapa \(selectedIndex + 1) de \(steps.count)")

            HStack(spacing: 12) {
                if selectedIndex > 0 {
                    Button {
                        moveBack()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.headline.weight(.black))
                            .foregroundStyle(NinaTheme.ink)
                            .frame(width: 52, height: 52)
                            .background(NinaTheme.card, in: Circle())
                            .overlay(
                                Circle()
                                    .stroke(NinaTheme.line, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Voltar")
                }

                Button {
                    moveForwardOrFinish()
                } label: {
                    HStack(spacing: 10) {
                        Text(isLastStep ? "Começar" : "Próximo")
                            .font(.headline.weight(.heavy))

                        Image(systemName: isLastStep ? "checkmark" : "chevron.right")
                            .font(.headline.weight(.black))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(selectedStep.tone.color, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isLastStep ? "Começar a usar a Nina" : "Próxima etapa")
            }
        }
        .padding(.horizontal, 22)
        .opacity(didAppear ? 1 : 0)
        .offset(y: didAppear || reduceMotion ? 0 : 16)
    }

    private func moveBack() {
        withAnimation(.interactiveSpring(response: 0.38, dampingFraction: 0.86)) {
            selectedIndex = max(selectedIndex - 1, 0)
        }
    }

    private func moveForwardOrFinish() {
        if isLastStep {
            finishTutorial()
            return
        }

        withAnimation(.interactiveSpring(response: 0.38, dampingFraction: 0.86)) {
            selectedIndex = min(selectedIndex + 1, steps.count - 1)
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
}

private struct TutorialStep: Identifiable, Hashable {
    var id: TutorialKind
    var eyebrow: String
    var title: String
    var message: String
    var systemImage: String
    var tone: MemberTone

    static let all: [TutorialStep] = [
        TutorialStep(
            id: .chat,
            eyebrow: "Nina",
            title: "Converse do seu jeito",
            message: "Jogue uma lembrança solta. A Nina entende, responde e sugere o próximo passo.",
            systemImage: "sparkles",
            tone: .mint
        ),
        TutorialStep(
            id: .today,
            eyebrow: "Hoje",
            title: "Veja o que importa agora",
            message: "A tela Hoje destaca lembretes, sobrecarga e poucas tarefas para resolver sem ruído.",
            systemImage: "sun.max.fill",
            tone: .amber
        ),
        TutorialStep(
            id: .tasks,
            eyebrow: "Tarefas",
            title: "Resolva tarefas e compras",
            message: "Use listas manuais quando quiser agir direto. Marque, segure para editar e adicione itens.",
            systemImage: "checklist",
            tone: .sky
        ),
        TutorialStep(
            id: .house,
            eyebrow: "Casa",
            title: "Cuide da família e da privacidade",
            message: "A Casa reúne participantes, convite, memória local e sinais para conversas melhores.",
            systemImage: "house.fill",
            tone: .lavender
        )
    ]
}

private enum TutorialKind: Hashable {
    case chat
    case today
    case tasks
    case house
}

private struct TutorialPage: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var step: TutorialStep
    var isActive: Bool

    var body: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 0)

            OnboardingIllustration(step: step)
                .frame(maxWidth: .infinity)
                .frame(height: 300)
                .clipped()
                .scaleEffect(isActive || reduceMotion ? 1 : 0.96)
                .opacity(isActive ? 1 : 0.7)

            VStack(spacing: 10) {
                Label(step.eyebrow, systemImage: step.systemImage)
                    .font(.subheadline.weight(.black))
                    .foregroundStyle(step.tone.color)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(step.tone.softColor, in: Capsule())

                Text(step.title)
                    .font(.system(size: 31, weight: .black, design: .rounded))
                    .foregroundStyle(NinaTheme.ink)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text(step.message)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(NinaTheme.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 4)

            Spacer(minLength: 0)
        }
        .animation(reduceMotion ? nil : .spring(response: 0.46, dampingFraction: 0.88), value: isActive)
        .accessibilityElement(children: .combine)
    }
}

private struct OnboardingIllustration: View {
    var step: TutorialStep

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(NinaTheme.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .stroke(step.tone.color.opacity(0.28), lineWidth: 1)
                )
                .cardShadow()

            switch step.id {
            case .chat:
                chatIllustration
            case .today:
                todayIllustration
            case .tasks:
                tasksIllustration
            case .house:
                houseIllustration
            }
        }
    }

    private var chatIllustration: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                NinaAvatarView(size: 58)

                VStack(alignment: .leading, spacing: 5) {
                    Text("Oi, eu sou a Nina")
                        .font(.headline.weight(.black))
                        .foregroundStyle(NinaTheme.ink)

                    Text("Pode falar como falaria em casa.")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(NinaTheme.muted)
                }

                Spacer()
            }

            MiniBubble(text: "Lembrar do veterinário do Thor", tone: .sky, alignment: .trailing)
            MiniBubble(text: "Criei uma tarefa para esta semana.", tone: .mint, alignment: .leading)

            HStack(spacing: 8) {
                MiniChip(title: "tarefa", systemName: "checkmark.circle.fill", tone: .mint)
                MiniChip(title: "lembrete", systemName: "bell.fill", tone: .amber)
            }
        }
        .padding(20)
    }

    private var todayIllustration: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                MiniStat(title: "Abertas", value: "6", tone: .mint)
                MiniStat(title: "Lembretes", value: "3", tone: .amber)
                MiniStat(title: "Compras", value: "8", tone: .sky)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Sinal de sobrecarga")
                    .font(.headline.weight(.black))
                    .foregroundStyle(NinaTheme.ink)

                WorkloadPreview(name: "Mirna", value: 0.78, tone: .coral)
                WorkloadPreview(name: "Heitor", value: 0.42, tone: .sky)
                WorkloadPreview(name: "Casa", value: 0.56, tone: .mint)
            }
            .padding(15)
            .background(NinaTheme.field, in: RoundedRectangle(cornerRadius: 20, style: .continuous))

            MiniBubble(text: "Poucas tarefas, bem claras.", tone: .amber, alignment: .leading)
        }
        .padding(20)
    }

    private var tasksIllustration: some View {
        VStack(spacing: 12) {
            MiniTaskRow(title: "Pagar escola", detail: "Hoje", tone: .sky, isDone: false)
            MiniTaskRow(title: "Comprar gás", detail: "Esta semana", tone: .coral, isDone: false)
            MiniTaskRow(title: "Ração do Thor", detail: "Compras", tone: .lavender, isDone: true)

            HStack(spacing: 10) {
                MiniChip(title: "Tarefas", systemName: "checklist", tone: .sky)
                MiniChip(title: "Compras", systemName: "cart.fill", tone: .amber)
            }
        }
        .padding(20)
    }

    private var houseIllustration: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                MemberAvatar(member: PreviewData.familyGroup.members[0], size: 42)
                MemberAvatar(member: PreviewData.familyGroup.members[1], size: 42)
                MemberAvatar(member: PreviewData.familyGroup.members[3], size: 42)

                Spacer()

                IconBubble(systemName: "link", tone: .mint, size: 40)
            }

            VStack(spacing: 8) {
                MiniPrivacyRow(title: "Memória local", systemName: "lock.fill", tone: .lavender)
                MiniPrivacyRow(title: "Convite familiar", systemName: "person.2.fill", tone: .mint)
                MiniPrivacyRow(title: "Insights simples", systemName: "chart.bar.fill", tone: .sky)
            }

            MiniBubble(text: "A Nina não ocupa vaga na casa.", tone: .lavender, alignment: .leading)
        }
        .padding(16)
    }
}

private enum MiniBubbleAlignment {
    case leading
    case trailing
}

private struct MiniBubble: View {
    var text: String
    var tone: MemberTone
    var alignment: MiniBubbleAlignment

    var body: some View {
        HStack {
            if alignment == .trailing {
                Spacer(minLength: 42)
            }

            Text(text)
                .font(.caption.weight(.heavy))
                .foregroundStyle(alignment == .trailing ? .white : NinaTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(alignment == .trailing ? tone.color : tone.softColor, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            if alignment == .leading {
                Spacer(minLength: 42)
            }
        }
    }
}

private struct MiniChip: View {
    var title: String
    var systemName: String
    var tone: MemberTone

    var body: some View {
        Label(title, systemImage: systemName)
            .font(.caption.weight(.black))
            .foregroundStyle(tone.color)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(tone.softColor, in: Capsule())
    }
}

private struct MiniStat: View {
    var title: String
    var value: String
    var tone: MemberTone

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3.weight(.black))
                .foregroundStyle(tone.color)

            Text(title)
                .font(.caption2.weight(.black))
                .foregroundStyle(NinaTheme.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.74)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(tone.softColor, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct WorkloadPreview: View {
    var name: String
    var value: CGFloat
    var tone: MemberTone

    var body: some View {
        HStack(spacing: 10) {
            Text(name)
                .font(.caption.weight(.black))
                .foregroundStyle(NinaTheme.ink)
                .frame(width: 48, alignment: .leading)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(NinaTheme.line.opacity(0.7))

                    Capsule()
                        .fill(tone.color)
                        .frame(width: proxy.size.width * value)
                }
            }
            .frame(height: 9)
        }
    }
}

private struct MiniTaskRow: View {
    var title: String
    var detail: String
    var tone: MemberTone
    var isDone: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                .font(.title3.weight(.black))
                .foregroundStyle(isDone ? NinaTheme.mint : tone.color)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline.weight(.black))
                    .foregroundStyle(NinaTheme.ink)
                    .strikethrough(isDone)
                    .lineLimit(1)

                Text(detail)
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(NinaTheme.muted)
            }

            Spacer()

            IconBubble(systemName: "chevron.left", tone: tone, size: 36)
        }
        .padding(13)
        .background(NinaTheme.field, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct MiniPrivacyRow: View {
    var title: String
    var systemName: String
    var tone: MemberTone

    var body: some View {
        HStack(spacing: 10) {
            IconBubble(systemName: systemName, tone: tone, size: 32)

            Text(title)
                .font(.subheadline.weight(.black))
                .foregroundStyle(NinaTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            Spacer()

            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(tone.color)
        }
        .padding(9)
        .background(NinaTheme.field, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

#Preview("Tutorial") {
    let auth = AuthSessionStore()
    auth.currentUser = AuthUser(id: "preview", displayName: "Preview", email: "preview@ninai.app", provider: .email)

    return OnboardingTutorialView()
        .environment(auth)
        .environment(OnboardingStore())
}
