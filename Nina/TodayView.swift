import SwiftUI

struct TodayView: View {
    @Environment(AppStore.self) private var store
    @Environment(PremiumSubscriptionStore.self) private var premiumStore
    @Environment(RouterPath.self) private var router
    @State private var taskPendingDeletion: TaskItem?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                greetingCard
                premiumInsightCard
                overloadCard
                priorityTasksSection
                seedsSection
            }
            .padding(18)
            .padding(.bottom, 104)
        }
        .ninaScreenBackground()
        .navigationTitle("Hoje")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Haptics.lightImpact()
                    router.presentedSheet = .addTask
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3.weight(.bold))
                }
                .accessibilityLabel("Adicionar tarefa")
            }
        }
        .alert(
            "Apagar esta tarefa?",
            isPresented: Binding(
                get: { taskPendingDeletion != nil },
                set: { isPresented in
                    if !isPresented {
                        taskPendingDeletion = nil
                    }
                }
            ),
            presenting: taskPendingDeletion
        ) { task in
            Button("Cancelar", role: .cancel) {
                taskPendingDeletion = nil
            }
            Button("Apagar", role: .destructive) {
                store.deleteTask(task.id)
                taskPendingDeletion = nil
            }
        } message: { _ in
            Text("A tarefa e o aviso agendado serão removidos.")
        }
    }

    private var greetingCard: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            SoftCard(padding: 18) {
                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(greeting(at: context.date)), \(store.familyGroup.name)")
                            .font(.title2.weight(.black))
                            .foregroundStyle(NinaTheme.ink)

                        Text("Hoje a Nina está de olho no que vence até o fim do dia.")
                            .font(.subheadline)
                            .foregroundStyle(NinaTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    NinaAvatarView(size: 70)
                }

                HStack(spacing: 10) {
                    TodayStat(
                        title: "Para hoje",
                        value: "\(todayTasks(relativeTo: context.date).count)",
                        tone: .mint
                    )
                    TodayStat(
                        title: "Atrasadas",
                        value: "\(overdueTodayCount(relativeTo: context.date))",
                        tone: .amber
                    )
                    TodayStat(
                        title: "Compras",
                        value: "\(store.pendingShoppingItems.count)",
                        tone: .sky
                    )
                }
            }
        }
    }

    private func greeting(at referenceDate: Date) -> String {
        switch Calendar.current.component(.hour, from: referenceDate) {
        case ..<12: "Bom dia"
        case ..<18: "Boa tarde"
        default: "Boa noite"
        }
    }

    private func todayTasks(relativeTo referenceDate: Date) -> [TaskItem] {
        let calendar = Calendar.current
        return store.openTasks.filter {
            $0.isDue(on: referenceDate, calendar: calendar)
        }
    }

    private func overdueTodayCount(relativeTo referenceDate: Date) -> Int {
        todayTasks(relativeTo: referenceDate).count {
            $0.isOverdue(relativeTo: referenceDate)
        }
    }

    private var premiumInsightCard: some View {
        PremiumTeaserCard(
            style: .featured,
            entitlement: premiumStore.entitlement,
            priceLabel: premiumStore.primaryPriceLabel
        ) {
            router.presentedSheet = .premium
        }
    }

    private var overloadCard: some View {
        SoftCard {
            HStack(alignment: .top, spacing: 12) {
                IconBubble(systemName: "heart.text.square.fill", tone: .coral)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Sinal de sobrecarga")
                        .font(.headline.weight(.black))
                        .foregroundStyle(NinaTheme.ink)

                    Text("A maior parte da gestão doméstica está caindo na Mirna. A Nina sugere revisar a divisão com calma.")
                        .font(.subheadline)
                        .foregroundStyle(NinaTheme.muted)
                }
            }

            WorkloadBars()
        }
    }

    private var priorityTasksSection: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .bottom) {
                    SectionTitle(
                        title: "Para resolver",
                        subtitle: "Tarefas, horários e lembretes em um só lugar."
                    )

                    Spacer(minLength: 12)

                    Button {
                        Haptics.lightImpact()
                        router.presentedSheet = .addTask
                    } label: {
                        Image(systemName: "plus")
                            .font(.caption.weight(.black))
                            .foregroundStyle(NinaTheme.mint)
                            .frame(width: 32, height: 32)
                            .background(NinaTheme.mint.opacity(0.13), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Adicionar tarefa")
                }

                if tasksForDisplay(relativeTo: context.date).isEmpty {
                    UnifiedTaskEmptyState {
                        router.presentedSheet = .addTask
                    }
                } else {
                    ForEach(tasksForDisplay(relativeTo: context.date)) { task in
                        let isCompleting = store.pendingPriorityTaskIDs.contains(task.id)

                        UnifiedTaskCard(
                            task: task,
                            referenceDate: context.date,
                            isMarkedComplete: isCompleting,
                            toggle: togglePriorityTask,
                            edit: {
                                Haptics.lightImpact()
                                router.presentedSheet = .editTask(task.id)
                            },
                            snooze: { date in
                                Haptics.selection()
                                store.snoozeTask(task.id, until: date)
                            },
                            delete: {
                                Haptics.warning()
                                taskPendingDeletion = task
                            }
                        )
                        .scaleEffect(isCompleting ? 0.985 : 1)
                        .opacity(isCompleting ? 0.72 : 1)
                        .animation(.spring(response: 0.32, dampingFraction: 0.76), value: isCompleting)
                        .transition(.asymmetric(insertion: .opacity, removal: .opacity.combined(with: .scale(scale: 0.98))))
                    }
                }
            }
        }
    }

    private func tasksForDisplay(relativeTo referenceDate: Date) -> [TaskItem] {
        let calendar = Calendar.current
        let visibleTasks = store.tasks.enumerated().filter { _, task in
            (!task.isDone || store.pendingPriorityTaskIDs.contains(task.id))
                && task.isDue(on: referenceDate, calendar: calendar)
        }

        return visibleTasks.sorted { left, right in
                let leftOverdue = left.element.isOverdue(relativeTo: referenceDate)
                let rightOverdue = right.element.isOverdue(relativeTo: referenceDate)
                if leftOverdue != rightOverdue {
                    return leftOverdue
                }

                if left.element.priority.sortRank != right.element.priority.sortRank {
                    return left.element.priority.sortRank > right.element.priority.sortRank
                }

                let leftDate = left.element.displayDate(
                    relativeTo: referenceDate,
                    calendar: calendar
                ) ?? .distantFuture
                let rightDate = right.element.displayDate(
                    relativeTo: referenceDate,
                    calendar: calendar
                ) ?? .distantFuture
                if leftDate != rightDate {
                    return leftDate < rightDate
                }

                return left.offset < right.offset
            }
            .map(\.element)
    }

    private func togglePriorityTask(_ task: TaskItem) {
        if store.pendingPriorityTaskIDs.contains(task.id) {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                store.clearPriorityTaskPending(task.id)
            }
            return
        }

        guard !task.isDone else { return }

        withAnimation(.spring(response: 0.32, dampingFraction: 0.76)) {
            store.markPriorityTaskPending(task.id)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            guard store.pendingPriorityTaskIDs.contains(task.id) else { return }

            withAnimation(.easeInOut(duration: 0.24)) {
                store.toggleTask(task)
                store.clearPriorityTaskPending(task.id)
            }
        }
    }

    @ViewBuilder
    private var seedsSection: some View {
        let seeds = store.openSeeds

        if !seeds.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(
                    title: "Sementes",
                    subtitle: "Ideias guardadas sem pressão de data. Plante quando chegar a hora."
                )

                ForEach(seeds) { seed in
                    SeedTodayCard(
                        seed: seed,
                        complete: {
                            Haptics.success()
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                store.toggleTask(seed)
                            }
                        },
                        plant: {
                            Haptics.lightImpact()
                            router.presentedSheet = .plantSeed(seed.id)
                        }
                    )
                }
            }
        }
    }
}

private struct SeedTodayCard: View {
    var seed: TaskItem
    var complete: () -> Void
    var plant: () -> Void

    var body: some View {
        SoftCard(padding: 14) {
            HStack(alignment: .top, spacing: 12) {
                Button(action: complete) {
                    Image(systemName: "circle")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(NinaTheme.muted.opacity(0.45))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Concluir semente \(seed.title)")

                IconBubble(systemName: "leaf.fill", tone: .mint, size: 40)

                VStack(alignment: .leading, spacing: 5) {
                    Text(seed.title)
                        .font(.headline.weight(.heavy))
                        .foregroundStyle(NinaTheme.ink)

                    if !seed.subtitle.isEmpty {
                        Text(seed.subtitle)
                            .font(.subheadline)
                            .foregroundStyle(NinaTheme.muted)
                            .lineLimit(2)
                    }

                    Label(seed.owner, systemImage: "person.fill")
                        .font(.caption2.weight(.black))
                        .foregroundStyle(seed.category.tone.color)
                }

                Spacer(minLength: 8)

                Button(action: plant) {
                    Label("Plantar", systemImage: "calendar.badge.plus")
                        .font(.caption.weight(.black))
                        .foregroundStyle(NinaTheme.mint)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(NinaTheme.mint.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Abre a semente para transformá-la em tarefa e escolher uma data.")
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(NinaTheme.mint.opacity(0.16), lineWidth: 1)
        )
    }
}

private struct UnifiedTaskEmptyState: View {
    var addTask: () -> Void

    var body: some View {
        SoftCard(padding: 16) {
            HStack(spacing: 12) {
                IconBubble(systemName: "checklist", tone: .mint, size: 42)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Nada para resolver")
                        .font(.headline.weight(.heavy))
                        .foregroundStyle(NinaTheme.ink)

                    Text("Crie uma tarefa simples ou com data, hora e repetição.")
                        .font(.subheadline)
                        .foregroundStyle(NinaTheme.muted)
                }

                Spacer()

                Button("Criar", action: addTask)
                    .font(.caption.weight(.black))
                    .foregroundStyle(NinaTheme.mint)
                    .buttonStyle(.plain)
            }
        }
    }
}

private struct UnifiedTaskCard: View {
    var task: TaskItem
    var referenceDate: Date
    var isMarkedComplete: Bool
    var toggle: (TaskItem) -> Void
    var edit: () -> Void
    var snooze: (Date) -> Void
    var delete: () -> Void

    private var isOverdue: Bool {
        task.isOverdue(relativeTo: referenceDate)
    }

    private var isSnoozed: Bool {
        guard let snoozedUntil = task.snoozedUntil else { return false }
        return snoozedUntil > referenceDate
    }

    private var displayDate: Date? {
        task.displayDate(relativeTo: referenceDate)
    }

    var body: some View {
        SoftCard(padding: 14) {
            HStack(alignment: .top, spacing: 12) {
                Button {
                    if isMarkedComplete {
                        Haptics.selection()
                    } else {
                        Haptics.success()
                    }
                    toggle(task)
                } label: {
                    Image(systemName: isMarkedComplete ? "checkmark.circle.fill" : "circle")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(isMarkedComplete ? NinaTheme.mint : NinaTheme.muted.opacity(0.45))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isMarkedComplete ? "Desfazer conclusão" : "Concluir tarefa")

                Button(action: edit) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top, spacing: 12) {
                            IconBubble(
                                systemName: task.category.symbolName,
                                tone: isOverdue ? .coral : task.category.tone,
                                size: 42
                            )

                            VStack(alignment: .leading, spacing: 5) {
                                Text(task.title)
                                    .font(.headline.weight(.heavy))
                                    .foregroundStyle(NinaTheme.ink)
                                    .lineLimit(2)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                if !task.subtitle.isEmpty {
                                    Text(task.subtitle)
                                        .font(.subheadline)
                                        .foregroundStyle(NinaTheme.muted)
                                        .lineLimit(2)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }

                        metadataBadges
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .layoutPriority(1)

                Menu {
                    Button(action: edit) {
                        Label("Editar", systemImage: "pencil")
                    }

                    Menu {
                        Button("10 minutos") {
                            snooze(referenceDate.addingTimeInterval(10 * 60))
                        }
                        Button("1 hora") {
                            snooze(referenceDate.addingTimeInterval(60 * 60))
                        }
                        Button("Amanhã às 9:00") {
                            snooze(tomorrowAtNine)
                        }
                    } label: {
                        Label("Adiar", systemImage: "clock.arrow.circlepath")
                    }

                    Divider()

                    Button(role: .destructive, action: delete) {
                        Label("Apagar", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.subheadline.weight(.black))
                        .foregroundStyle(NinaTheme.muted)
                        .frame(width: 30, height: 30)
                        .background(NinaTheme.field, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Opções da tarefa")
            }
        }
    }

    private var statusLabel: String {
        if isOverdue {
            return "Atrasado · \(baseDateLabel)"
        }
        if isSnoozed {
            return "Adiado · \(baseDateLabel)"
        }
        return baseDateLabel
    }

    private var baseDateLabel: String {
        guard let displayDate else { return task.dueLabel }
        return TaskEditorSheet.dateLabel(for: displayDate, relativeTo: referenceDate)
    }

    private var statusTone: MemberTone {
        if isOverdue {
            return .coral
        }
        if isSnoozed {
            return .lavender
        }
        return task.category.tone
    }

    private var statusSymbolName: String {
        if isOverdue {
            return "exclamationmark.circle.fill"
        }
        if isSnoozed {
            return "clock.arrow.circlepath"
        }
        return "clock.fill"
    }

    private var metadataBadges: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 7) {
                statusBadge
                secondaryBadges
            }

            VStack(alignment: .leading, spacing: 7) {
                statusBadge
                secondaryBadges
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statusBadge: some View {
        UnifiedTaskMetadataBadge(
            title: statusLabel,
            systemName: statusSymbolName,
            tone: statusTone
        )
    }

    @ViewBuilder
    private var secondaryBadges: some View {
        HStack(spacing: 7) {
            if task.recurrence != .none {
                UnifiedTaskMetadataBadge(
                    title: task.recurrence.explicitTitle,
                    systemName: "repeat",
                    tone: .lavender
                )
            }

            if task.priority != .normal {
                UnifiedTaskMetadataBadge(
                    title: task.priority.title,
                    systemName: task.priority.symbolName,
                    tone: task.priority.tone
                )
            }
        }
    }

    private var tomorrowAtNine: Date {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: referenceDate) ?? referenceDate
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
    }
}

private struct UnifiedTaskMetadataBadge: View {
    var title: String
    var systemName: String
    var tone: MemberTone

    var body: some View {
        Label(title, systemImage: systemName)
            .font(.caption2.weight(.black))
            .foregroundStyle(tone.color)
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(tone.softColor, in: Capsule())
            .fixedSize(horizontal: true, vertical: false)
    }
}

private struct TodayStat: View {
    var title: String
    var value: String
    var tone: MemberTone

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3.weight(.black))
                .foregroundStyle(tone.color)

            Text(title)
                .font(.caption.weight(.heavy))
                .foregroundStyle(NinaTheme.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(tone.softColor, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct WorkloadBars: View {
    var body: some View {
        VStack(spacing: 10) {
            WorkloadBar(name: "Mirna", count: 82, progress: 0.92, tone: .coral)
            WorkloadBar(name: "Heitor", count: 8, progress: 0.18, tone: .sky)
        }
    }
}

private struct WorkloadBar: View {
    var name: String
    var count: Int
    var progress: CGFloat
    var tone: MemberTone

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(name)
                    .font(.caption.weight(.black))
                    .foregroundStyle(NinaTheme.ink)

                Spacer()

                Text("\(count) tarefas")
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(NinaTheme.muted)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(NinaTheme.line.opacity(0.8))

                    Capsule()
                        .fill(tone.color)
                        .frame(width: proxy.size.width * min(progress, 1))
                }
            }
            .frame(height: 10)
        }
    }
}

#Preview {
    NavigationStack {
        TodayView()
            .environment(AppStore())
            .environment(RouterPath())
            .environment(TabSwipeLock())
    }
}
