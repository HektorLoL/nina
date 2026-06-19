import SwiftUI

struct TodayView: View {
    @Environment(AppStore.self) private var store
    @Environment(PremiumSubscriptionStore.self) private var premiumStore
    @Environment(RouterPath.self) private var router

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                greetingCard
                premiumInsightCard
                overloadCard
                remindersSection
                priorityTasksSection
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
    }

    private var greetingCard: some View {
        SoftCard(padding: 18) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Bom dia, \(store.familyGroup.name)")
                        .font(.title2.weight(.black))
                        .foregroundStyle(NinaTheme.ink)

                    Text("Hoje a Nina está de olho em escola, contas e energia da casa.")
                        .font(.subheadline)
                        .foregroundStyle(NinaTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                NinaAvatarView(size: 70)
            }

            HStack(spacing: 10) {
                TodayStat(title: "Abertas", value: "\(store.openTasks.count)", tone: .mint)
                TodayStat(title: "Lembretes", value: "\(store.reminders.count)", tone: .amber)
                TodayStat(title: "Compras", value: "\(store.pendingShoppingItems.count)", tone: .sky)
            }
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

    private var remindersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Lembretes próximos", subtitle: "Coisas que não precisam ficar na cabeça.")

            ForEach(store.reminders.prefix(3)) { reminder in
                SoftCard(padding: 14) {
                    HStack(spacing: 12) {
                        IconBubble(systemName: reminder.symbolName, tone: reminder.tone, size: 42)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(reminder.title)
                                .font(.headline.weight(.heavy))
                                .foregroundStyle(NinaTheme.ink)

                            Text(reminder.detail)
                                .font(.subheadline)
                                .foregroundStyle(NinaTheme.muted)
                        }

                        Spacer()

                        Text(reminder.dateLabel)
                            .font(.caption.weight(.black))
                            .foregroundStyle(reminder.tone.color)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(reminder.tone.softColor, in: Capsule())
                    }
                }
            }
        }
    }

    private var priorityTasksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Para resolver", subtitle: "Poucas tarefas, bem claras.")

            ForEach(priorityTasksForDisplay) { task in
                let isCompleting = store.pendingPriorityTaskIDs.contains(task.id)

                TaskCard(
                    task: task,
                    isMarkedComplete: isCompleting,
                    onToggle: togglePriorityTask
                )
                .scaleEffect(isCompleting ? 0.985 : 1)
                .opacity(isCompleting ? 0.72 : 1)
                .animation(.spring(response: 0.32, dampingFraction: 0.76), value: isCompleting)
                .transition(.asymmetric(insertion: .opacity, removal: .opacity.combined(with: .scale(scale: 0.98))))
            }
        }
    }

    private var priorityTasksForDisplay: [TaskItem] {
        let visibleTasks = store.tasks.enumerated().filter { _, task in
            !task.isDone || store.pendingPriorityTaskIDs.contains(task.id)
        }

        return Array(
            visibleTasks.sorted { left, right in
                if left.element.priority.sortRank != right.element.priority.sortRank {
                    return left.element.priority.sortRank > right.element.priority.sortRank
                }

                return left.offset < right.offset
            }
            .prefix(3)
            .map(\.element)
        )
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
