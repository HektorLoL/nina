import SwiftUI

struct SoftCard<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .padding(padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NinaTheme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(NinaTheme.cardStroke, lineWidth: 1)
        )
        .cardShadow()
    }
}

struct IconBubble: View {
    var systemName: String
    var tone: MemberTone
    var size: CGFloat = 44

    var body: some View {
        ZStack {
            Circle()
                .fill(tone.softColor)

            Image(systemName: systemName)
                .font(.system(size: size * 0.38, weight: .bold))
                .foregroundStyle(tone.color)
        }
        .frame(width: size, height: size)
    }
}

struct NinaAvatarView: View {
    var size: CGFloat = 76

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [NinaTheme.mint, NinaTheme.sky],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            // Hair Silhouette (Dark Teal Bob)
            Path { path in
                path.move(to: CGPoint(x: size * 0.50, y: size * 0.24))
                path.addCurve(
                    to: CGPoint(x: size * 0.80, y: size * 0.56),
                    control1: CGPoint(x: size * 0.68, y: size * 0.24),
                    control2: CGPoint(x: size * 0.80, y: size * 0.38)
                )
                path.addCurve(
                    to: CGPoint(x: size * 0.74, y: size * 0.73),
                    control1: CGPoint(x: size * 0.80, y: size * 0.66),
                    control2: CGPoint(x: size * 0.78, y: size * 0.73)
                )
                path.addQuadCurve(
                    to: CGPoint(x: size * 0.50, y: size * 0.75),
                    control: CGPoint(x: size * 0.62, y: size * 0.75)
                )
                path.addQuadCurve(
                    to: CGPoint(x: size * 0.26, y: size * 0.73),
                    control: CGPoint(x: size * 0.38, y: size * 0.75)
                )
                path.addCurve(
                    to: CGPoint(x: size * 0.20, y: size * 0.56),
                    control1: CGPoint(x: size * 0.22, y: size * 0.73),
                    control2: CGPoint(x: size * 0.20, y: size * 0.34)
                )
                path.addCurve(
                    to: CGPoint(x: size * 0.50, y: size * 0.24),
                    control1: CGPoint(x: size * 0.20, y: size * 0.38),
                    control2: CGPoint(x: size * 0.32, y: size * 0.24)
                )
            }
            .fill(Color(red: 0.10, green: 0.29, blue: 0.34))

            // Subtle House-shaped Highlight at the Crown
            Path { path in
                path.move(to: CGPoint(x: size * 0.50, y: size * 0.25))
                path.addLine(to: CGPoint(x: size * 0.60, y: size * 0.34))
                path.addLine(to: CGPoint(x: size * 0.57, y: size * 0.42))
                path.addLine(to: CGPoint(x: size * 0.43, y: size * 0.42))
                path.addLine(to: CGPoint(x: size * 0.40, y: size * 0.34))
                path.closeSubpath()
            }
            .fill(Color.white.opacity(0.15))

            // Face Skin (with curved hairline)
            Path { path in
                path.move(to: CGPoint(x: size * 0.32, y: size * 0.50))
                path.addQuadCurve(
                    to: CGPoint(x: size * 0.68, y: size * 0.50),
                    control: CGPoint(x: size * 0.50, y: size * 0.38)
                )
                path.addCurve(
                    to: CGPoint(x: size * 0.50, y: size * 0.77),
                    control1: CGPoint(x: size * 0.68, y: size * 0.64),
                    control2: CGPoint(x: size * 0.62, y: size * 0.77)
                )
                path.addCurve(
                    to: CGPoint(x: size * 0.32, y: size * 0.50),
                    control1: CGPoint(x: size * 0.38, y: size * 0.77),
                    control2: CGPoint(x: size * 0.32, y: size * 0.64)
                )
            }
            .fill(NinaTheme.avatarFace)

            // Cheeks
            Capsule()
                .fill(NinaTheme.coral.opacity(0.20))
                .frame(width: size * 0.10, height: size * 0.065)
                .offset(x: -size * 0.14, y: size * 0.08)

            Capsule()
                .fill(NinaTheme.coral.opacity(0.20))
                .frame(width: size * 0.10, height: size * 0.065)
                .offset(x: size * 0.14, y: size * 0.08)

            // Eyes
            Circle()
                .fill(NinaTheme.avatarInk)
                .frame(width: size * 0.065, height: size * 0.065)
                .offset(x: -size * 0.08, y: size * 0.02)

            Circle()
                .fill(NinaTheme.avatarInk)
                .frame(width: size * 0.065, height: size * 0.065)
                .offset(x: size * 0.08, y: size * 0.02)

            // Smiling Mouth
            Path { path in
                path.move(to: CGPoint(x: size * 0.44, y: size * 0.60))
                path.addQuadCurve(
                    to: CGPoint(x: size * 0.56, y: size * 0.60),
                    control: CGPoint(x: size * 0.50, y: size * 0.67)
                )
            }
            .stroke(
                NinaTheme.coral,
                style: StrokeStyle(
                    lineWidth: max(CGFloat(2.5), size * 0.035),
                    lineCap: .round
                )
            )

            // Sparkle (singular "sparkle" SF Symbol)
            Image(systemName: "sparkle")
                .font(.system(size: size * 0.20, weight: .bold))
                .foregroundStyle(.white)
                .offset(x: size * 0.18, y: -size * 0.16)
        }
        .frame(width: size, height: size)
        .drawingGroup()
        .shadow(color: NinaTheme.mint.opacity(0.25), radius: 14, x: 0, y: 8)
        .accessibilityLabel("Avatar da Nina")
    }
}

struct MemberAvatar: View {
    var member: HouseholdMember
    var size: CGFloat = 48

    var body: some View {
        if member.role == .assistant {
            NinaAvatarView(size: size)
                .accessibilityLabel(member.name)
        } else {
            ZStack {
                Circle()
                    .fill(member.tone.softColor)

                Text(String(member.name.prefix(1)))
                    .font(.system(size: size * 0.42, weight: .heavy, design: .rounded))
                    .foregroundStyle(member.tone.color)
            }
            .frame(width: size, height: size)
            .accessibilityLabel(member.name)
        }
    }
}

struct SectionTitle: View {
    var title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title3.weight(.heavy))
                .foregroundStyle(NinaTheme.ink)

            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(NinaTheme.muted)
            }
        }
    }
}

struct QuickChip: View {
    var title: String
    var systemName: String
    var tone: MemberTone
    var action: () -> Void

    var body: some View {
        Button {
            Haptics.lightImpact()
            action()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: systemName)
                    .font(.system(size: 14, weight: .bold))
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)
            }
            .foregroundStyle(tone.color)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(tone.softColor, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct PrimaryCapsuleButton: View {
    var title: String
    var systemName: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemName)
                .font(.headline.weight(.heavy))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(NinaTheme.mint, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

enum PremiumTeaserStyle {
    case compact
    case featured
    case settings

    var eyebrow: String {
        switch self {
        case .compact:
            "Novo"
        case .featured:
            "Premium"
        case .settings:
            "Plano"
        }
    }

    var title: String {
        switch self {
        case .compact:
            "Nina Premium"
        case .featured:
            "Mais presença da Nina na rotina"
        case .settings:
            "Nina Premium"
        }
    }

    var subtitle: String {
        switch self {
        case .compact:
            "Rotinas, documentos e resumos com uma camada mais esperta."
        case .featured:
            "Resumo semanal, leitura de documentos e sugestões com prioridade para aliviar a casa."
        case .settings:
            "Gerencie assinatura, benefícios e restauração pelo App Store."
        }
    }

    var badgeText: String {
        switch self {
        case .compact, .featured:
            "Ver benefícios"
        case .settings:
            "Ver planos"
        }
    }

    var chips: [PremiumTeaserChip] {
        switch self {
        case .compact:
            []
        case .featured:
            [
                PremiumTeaserChip(title: "Digest", systemName: "calendar.badge.clock"),
                PremiumTeaserChip(title: "Docs", systemName: "doc.text.viewfinder"),
                PremiumTeaserChip(title: "Prioridade", systemName: "sparkles")
            ]
        case .settings:
            [
                PremiumTeaserChip(title: "StoreKit", systemName: "creditcard.fill"),
                PremiumTeaserChip(title: "Servidor", systemName: "checkmark.seal.fill")
            ]
        }
    }

    var padding: CGFloat {
        switch self {
        case .compact:
            14
        case .featured, .settings:
            18
        }
    }

    var iconSize: CGFloat {
        switch self {
        case .compact:
            46
        case .featured, .settings:
            58
        }
    }

    var accessibilityLabel: String {
        "\(title). \(subtitle). \(badgeText)"
    }
}

struct PremiumTeaserCard: View {
    var style: PremiumTeaserStyle
    var entitlement: PremiumEntitlement? = nil
    var priceLabel: String? = nil
    var action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let cornerRadius: CGFloat = 26

    var body: some View {
        Button {
            Haptics.lightImpact()
            action()
        } label: {
            cardContent
                .padding(style.padding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(NinaTheme.premiumGradient, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(premiumDecoration)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(.white.opacity(0.58), lineWidth: 1)
                )
                .shadow(color: NinaTheme.gold.opacity(0.28), radius: 22, x: 0, y: 12)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var title: String {
        entitlement?.isActive == true && style == .settings ? "Nina Premium ativo" : style.title
    }

    private var subtitle: String {
        if style == .settings, let entitlement {
            return entitlement.renewalSummary
        }
        return style.subtitle
    }

    private var badgeText: String {
        if entitlement?.isActive == true {
            return "Ativo"
        }
        return priceLabel ?? style.badgeText
    }

    private var chips: [PremiumTeaserChip] {
        if entitlement?.isActive == true {
            return [
                PremiumTeaserChip(title: "Verificado", systemName: "checkmark.seal.fill"),
                PremiumTeaserChip(title: "App Store", systemName: "creditcard.fill")
            ]
        }
        return style.chips
    }

    private var accessibilityLabel: String {
        "\(title). \(subtitle). \(badgeText)"
    }

    @ViewBuilder
    private var cardContent: some View {
        switch style {
        case .compact:
            HStack(spacing: 12) {
                PremiumMark(size: style.iconSize)

                VStack(alignment: .leading, spacing: 5) {
                    premiumEyebrow

                    Text(title)
                        .font(.headline.weight(.black))
                        .foregroundStyle(NinaTheme.premiumInk)

                    Text(subtitle)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(NinaTheme.premiumInk.opacity(0.74))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 10)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.black))
                    .foregroundStyle(NinaTheme.premiumInk.opacity(0.78))
                    .frame(width: 30, height: 30)
                    .background(.white.opacity(0.36), in: Circle())
            }
        case .featured, .settings:
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 14) {
                    PremiumMark(size: style.iconSize)

                    VStack(alignment: .leading, spacing: 7) {
                        premiumEyebrow

                        Text(title)
                            .font(.title3.weight(.black))
                            .foregroundStyle(NinaTheme.premiumInk)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(subtitle)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(NinaTheme.premiumInk.opacity(0.76))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if !chips.isEmpty {
                    FlexiblePremiumChips(chips: chips)
                }

                HStack(spacing: 8) {
                    Text(badgeText)
                        .font(.subheadline.weight(.black))

                    Image(systemName: "arrow.right")
                        .font(.caption.weight(.black))
                }
                .foregroundStyle(NinaTheme.premiumInk)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.white.opacity(0.38), in: Capsule())
            }
        }
    }

    private var premiumEyebrow: some View {
        Label(style.eyebrow, systemImage: "sparkles")
            .font(.caption.weight(.black))
            .foregroundStyle(NinaTheme.premiumInk)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.white.opacity(0.36), in: Capsule())
    }

    private var premiumDecoration: some View {
        GeometryReader { proxy in
            ZStack {
                Image(systemName: "sparkles")
                    .font(.system(size: 92, weight: .black))
                    .foregroundStyle(.white.opacity(0.16))
                    .rotationEffect(.degrees(-12))
                    .offset(x: proxy.size.width * 0.34, y: -proxy.size.height * 0.2)

                Image(systemName: "crown.fill")
                    .font(.system(size: 74, weight: .black))
                    .foregroundStyle(NinaTheme.premiumInk.opacity(0.08))
                    .rotationEffect(.degrees(14))
                    .offset(x: proxy.size.width * 0.2, y: proxy.size.height * 0.34)

                if !reduceMotion {
                    LinearGradient(
                        colors: [.clear, .white.opacity(0.46), .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .opacity(0.18)
                    .blendMode(.screen)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct PremiumTeaserChip: Hashable {
    var title: String
    var systemName: String
}

private struct PremiumMark: View {
    var size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(.white.opacity(0.36))

            Circle()
                .stroke(.white.opacity(0.62), lineWidth: 1)

            Image(systemName: "crown.fill")
                .font(.system(size: size * 0.43, weight: .black))
                .foregroundStyle(NinaTheme.premiumInk)

            Image(systemName: "sparkle")
                .font(.system(size: size * 0.18, weight: .black))
                .foregroundStyle(.white)
                .offset(x: size * 0.26, y: -size * 0.24)
        }
        .frame(width: size, height: size)
        .shadow(color: NinaTheme.premiumInk.opacity(0.14), radius: 10, x: 0, y: 6)
    }
}

private struct FlexiblePremiumChips: View {
    var chips: [PremiumTeaserChip]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                chipViews
            }

            VStack(alignment: .leading, spacing: 8) {
                chipViews
            }
        }
    }

    @ViewBuilder
    private var chipViews: some View {
        ForEach(chips, id: \.title) { chip in
            Label(chip.title, systemImage: chip.systemName)
                .font(.caption.weight(.black))
                .foregroundStyle(NinaTheme.premiumInk)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(.white.opacity(0.30), in: Capsule())
        }
    }
}

struct TaskDetailCard: View {
    var task: TaskItem

    private var dynamicDueLabel: String {
        guard let date = task.effectiveDueDate else { return task.dueLabel }
        return TaskEditorSheet.dateLabel(for: date)
    }

    var body: some View {
        SoftCard {
            HStack(spacing: 12) {
                IconBubble(
                    systemName: task.kind == .seed ? TaskKind.seed.symbolName : task.category.symbolName,
                    tone: task.kind == .seed ? .mint : task.category.tone
                )

                VStack(alignment: .leading, spacing: 5) {
                    Text(task.title)
                        .font(.headline.weight(.heavy))
                        .foregroundStyle(NinaTheme.ink)

                    Text(task.subtitle.isEmpty ? "Sem detalhe adicional." : task.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(NinaTheme.muted)
                }
            }

            HStack(spacing: 8) {
                if task.kind == .seed {
                    Label("Semente", systemImage: "leaf.fill")
                }
                Label(task.owner, systemImage: "person.fill")
                if task.kind == .task {
                    Label(dynamicDueLabel, systemImage: "clock.fill")
                }
                Label(task.priority.title, systemImage: task.priority.symbolName)
                Label(task.createdBy, systemImage: "sparkles")
            }
            .font(.caption.weight(.bold))
            .foregroundStyle(NinaTheme.muted)
        }
    }
}

struct TaskCard: View {
    @Environment(RouterPath.self) private var router
    var task: TaskItem
    var isMarkedComplete: Bool
    var onToggle: (TaskItem) -> Void
    var togglesOnTap = true
    var referenceDate: Date = .now

    var body: some View {
        if togglesOnTap {
            baseCard
                .onTapGesture(perform: toggleTask)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel(isMarkedComplete ? "Cancelar conclusão de \(task.title)" : "Concluir \(task.title)")
                .accessibilityAction(named: Text(isMarkedComplete ? "Cancelar conclusão" : "Concluir"), toggleTask)
                .accessibilityAction(named: Text("Editar tarefa"), openEditor)
        } else {
            baseCard
        }
    }

    private var baseCard: some View {
        cardContent
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .contextMenu {
                Button(action: openEditor) {
                    Label("Editar tarefa", systemImage: "pencil")
                }
            }
            .accessibilityHint("Mantenha pressionado para editar.")
            .accessibilityAction(named: Text("Editar tarefa"), openEditor)
    }

    private var cardContent: some View {
        HStack(spacing: 12) {
            completionControl

            IconBubble(
                systemName: task.kind == .seed ? TaskKind.seed.symbolName : task.category.symbolName,
                tone: task.kind == .seed ? .mint : task.category.tone,
                size: 40
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(.headline.weight(.heavy))
                    .foregroundStyle(NinaTheme.ink)
                    .strikethrough(isMarkedComplete)

                Text(task.subtitle.isEmpty ? "\(task.owner) · \(dynamicDueLabel)" : task.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(NinaTheme.muted)
                    .lineLimit(2)

                if task.kind == .seed {
                    Label("Semente · sem data definida", systemImage: "leaf.fill")
                        .font(.caption2.weight(.black))
                        .foregroundStyle(NinaTheme.mint)
                } else if task.recurrence != .none {
                    Label(task.recurrence.explicitTitle, systemImage: "repeat")
                        .font(.caption2.weight(.black))
                        .foregroundStyle(NinaTheme.mint)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                Text(task.owner)
                    .font(.caption.weight(.black))
                    .foregroundStyle(task.category.tone.color)

                Text(task.kind == .seed ? "Plante depois" : dynamicDueLabel)
                    .font(.caption2.weight(.heavy))
                    .foregroundStyle(NinaTheme.muted)

                if task.priority != .normal {
                    Label(task.priority.title, systemImage: task.priority.symbolName)
                        .font(.caption2.weight(.black))
                        .foregroundStyle(task.priority.tone.color)
                        .labelStyle(.iconOnly)
                        .accessibilityLabel("Prioridade \(task.priority.title)")
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(taskCardBackground, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.black.opacity(isMarkedComplete ? 0.045 : 0))
                .allowsHitTesting(false)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(taskCardStroke, lineWidth: 1)
        )
        .cardShadow()
    }

    private var taskCardBackground: Color {
        if isMarkedComplete {
            return NinaTheme.taskCard.opacity(0.62)
        }
        return task.kind == .seed
            ? NinaTheme.mint.opacity(0.055)
            : NinaTheme.taskCard
    }

    private var taskCardStroke: Color {
        if isMarkedComplete {
            return NinaTheme.taskCardStroke.opacity(0.72)
        }
        return task.kind == .seed
            ? NinaTheme.mint.opacity(0.22)
            : NinaTheme.taskCardStroke
    }

    private var dynamicDueLabel: String {
        guard let date = task.effectiveDueDate else { return task.dueLabel }
        return TaskEditorSheet.dateLabel(for: date, relativeTo: referenceDate)
    }

    @ViewBuilder
    private var completionControl: some View {
        if togglesOnTap {
            completionIcon
        } else {
            Button(action: toggleTask) {
                completionIcon
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isMarkedComplete ? "Marcar como pendente" : "Concluir tarefa")
        }
    }

    private var completionIcon: some View {
        Image(systemName: isMarkedComplete ? "checkmark.circle.fill" : "circle")
            .font(.title2.weight(.bold))
            .foregroundStyle(isMarkedComplete ? NinaTheme.mint : NinaTheme.muted.opacity(0.45))
    }

    private func toggleTask() {
        if isMarkedComplete {
            Haptics.selection()
        } else {
            Haptics.success()
        }
        onToggle(task)
    }

    private func openEditor() {
        Haptics.lightImpact()
        router.presentedSheet = .editTask(task.id)
    }
}

struct MemberDetailContent: View {
    var member: HouseholdMember

    var body: some View {
        SoftCard {
            HStack(spacing: 14) {
                MemberAvatar(member: member, size: 64)

                VStack(alignment: .leading, spacing: 5) {
                    Text(member.name)
                        .font(.title2.weight(.black))
                        .foregroundStyle(NinaTheme.ink)

                    Label(member.relationship, systemImage: member.role.symbolName)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(member.tone.color)
                }
            }

            Text(member.memoryNote)
                .font(.body)
                .foregroundStyle(NinaTheme.ink)

            HStack {
                Text("Tarefas nos últimos 30 dias")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(NinaTheme.muted)

                Spacer()

                Text("\(member.taskCount)")
                    .font(.title3.weight(.black))
                    .foregroundStyle(member.tone.color)
            }
            .padding(.top, 6)
        }
    }
}
