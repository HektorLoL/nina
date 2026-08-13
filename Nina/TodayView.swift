import SwiftUI

private enum TodayFilter: String, CaseIterable, Identifiable {
    case all
    case mine
    case unowned
    case seeds

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "Tudo"
        case .mine: "Minhas"
        case .unowned: "Sem dono"
        case .seeds: "Sementes"
        }
    }
}

struct TodayView: View {
    @Environment(AppStore.self) private var store
    @Environment(RouterPath.self) private var router

    @State private var filter: TodayFilter = .all

    private var now: Date { .now }

    private var agenda: [TaskItem] {
        store.tasks
            .filter { $0.kind == .task && !$0.isDone && $0.belongsOnAgenda(for: now) }
    }

    private var overdue: [TaskItem] {
        agenda.filter { $0.isOverdue(relativeTo: now) }
    }

    private var dueToday: [TaskItem] {
        agenda.filter { !$0.isOverdue(relativeTo: now) }
    }

    private var mineCount: Int {
        guard let me = store.currentFamilyMember else { return 0 }
        return agenda.count { $0.ownerMemberID == me.id }
    }

    private var unownedCount: Int {
        agenda.count { HouseholdWorkload.isSharedOwner($0.owner) }
    }

    private var filtered: [TaskItem] {
        switch filter {
        case .all:
            return agenda
        case .mine:
            guard let me = store.currentFamilyMember else { return [] }
            return agenda.filter { $0.ownerMemberID == me.id }
        case .unowned:
            return agenda.filter { HouseholdWorkload.isSharedOwner($0.owner) }
        case .seeds:
            return store.openSeeds
        }
    }

    // A household that has never captured anything is a different screen from one
    // that has cleared its day: the first promises, the second congratulates.
    private var hasEverCaptured: Bool {
        !store.tasks.isEmpty || !store.shoppingItems.isEmpty
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header

                    if !hasEverCaptured {
                        firstDay
                    } else if agenda.isEmpty && filter == .all {
                        dayCleared
                    } else {
                        stats
                        filters
                        list
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 104)
            }

            if hasEverCaptured {
                fab
            }
        }
        .ninaScreenBackground()
        .onReceive(NotificationCenter.default.publisher(for: .ninaShowUnowned)) { _ in
            filter = .unowned
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Eyebrow(text: now.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "pt_BR"))))
                Text(greeting).ninaText(.screen)
            }

            Spacer()

            if let me = store.currentFamilyMember {
                Button {
                    Haptics.lightImpact()
                    router.presentedSheet = .settings
                } label: {
                    MemberAvatar(initials: me.name.ninaInitials, tone: me.tone, size: 36)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Abrir ajustes")
                .padding(.top, 6)
            }
        }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: now)
        let name = store.currentFamilyMember?.name.firstWord ?? ""
        let salute = hour < 12 ? "Bom dia" : (hour < 18 ? "Boa tarde" : "Boa noite")
        return name.isEmpty ? salute : "\(salute), \(name)"
    }

    private var stats: some View {
        HStack(spacing: 10) {
            statTile(value: mineCount, label: "na sua mão", style: .primary)
            statTile(value: overdue.count, label: "atrasadas", style: .late)
            statTile(value: unownedCount, label: "sem dono", style: .quiet)
        }
    }

    private enum StatStyle { case primary, late, quiet }

    private func statTile(value: Int, label: String, style: StatStyle) -> some View {
        let fill: Color = switch style {
        case .primary: NinaTheme.ink
        case .late: NinaTheme.terracottaWash
        case .quiet: NinaTheme.grout
        }
        let valueColor: Color = switch style {
        case .primary: NinaTheme.ground
        case .late: NinaTheme.terracotta
        case .quiet: NinaTheme.ink
        }
        // On the ink tile the palette has no legible muted value, so the label is
        // the ground colour held back rather than a second token.
        let labelColor: Color = switch style {
        case .primary: NinaTheme.ground.opacity(0.72)
        case .late: NinaTheme.terracotta
        case .quiet: NinaTheme.muted
        }

        return VStack(alignment: .leading, spacing: 2) {
            Text("\(value)").ninaText(.display, valueColor)
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(labelColor)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(fill, in: RoundedRectangle(cornerRadius: NinaTheme.Radius.card, style: .continuous))
    }

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(TodayFilter.allCases) { option in
                    Button {
                        Haptics.selection()
                        filter = option
                    } label: {
                        NinaChip(text: chipTitle(option), isSet: filter == option)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 1)
        }
        .scrollClipDisabled()
    }

    private func chipTitle(_ option: TodayFilter) -> String {
        let count = switch option {
        case .all: agenda.count
        case .mine: mineCount
        case .unowned: unownedCount
        case .seeds: store.openSeeds.count
        }
        return count > 0 ? "\(option.title) \(count)" : option.title
    }

    @ViewBuilder
    private var list: some View {
        if filter == .seeds {
            section(title: "Sementes", count: store.openSeeds.count, tasks: store.openSeeds)
        } else if filter == .all {
            if !overdue.isEmpty {
                section(title: "Atrasadas", count: overdue.count, tasks: overdue, isLate: true)
            }
            if !dueToday.isEmpty {
                section(title: "Hoje", count: dueToday.count, tasks: dueToday)
            }
        } else if filtered.isEmpty {
            // A filter that finds nothing educates; it never offers to create.
            ZeroState(
                headline: "Nada com esse filtro.",
                body_: "Isso é uma boa notícia, não um vazio para preencher.",
                showsMark: false
            )
            .padding(.top, 26)
        } else {
            section(title: filter.title, count: filtered.count, tasks: filtered)
        }
    }

    private func section(title: String, count: Int, tasks: [TaskItem], isLate: Bool = false) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(title.uppercased()) · \(count)")
                    .ninaText(.eyebrow, isLate ? NinaTheme.terracotta : NinaTheme.faint, weight: .bold)

                Spacer()

                if isLate, count > 1 {
                    Button {
                        Haptics.lightImpact()
                        rescheduleOverdue()
                    } label: {
                        Text("Remarcar as \(count)")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(NinaTheme.terracotta)
                            .padding(.horizontal, 12)
                            .frame(height: 30)
                            .overlay(Capsule().strokeBorder(NinaTheme.terracotta, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 8)

            ForEach(tasks) { task in
                TaskRowView(task: task)
                if task.id != tasks.last?.id {
                    NinaDivider(inset: 36)
                }
            }
        }
        .padding(.top, 6)
    }

    private func rescheduleOverdue() {
        let target = Calendar.current.date(
            bySettingHour: 9, minute: 0, second: 0,
            of: Calendar.current.date(byAdding: .day, value: 1, to: now) ?? now
        ) ?? now
        for task in overdue {
            store.snoozeTask(task.id, until: target)
        }
    }

    private var firstDay: some View {
        ZeroState(
            headline: "A casa começa vazia.",
            body_: "Você não precisa organizar nada agora. Conta pra Nina o que está pesando na cabeça, do jeito que vier. Ela monta e você confirma."
        ) {
            VStack(spacing: 6) {
                NinaButton(title: "Falar com a Nina", systemName: "bubble.left") {
                    Haptics.lightImpact()
                    router.presentedSheet = nil
                    NotificationCenter.default.post(name: .ninaSelectChatTab, object: nil)
                }
                NinaButton(title: "Escrever a primeira sem a Nina", kind: .quiet) {
                    Haptics.lightImpact()
                    router.presentedSheet = .addTask
                }
            }
        }
        .padding(.top, 40)
    }

    private var dayCleared: some View {
        // Credit goes to the house, never to a person: a two-name completion count
        // is a scoreboard on the one screen whose job is relief.
        ZeroState(
            headline: "Acabou o dia da casa.",
            body_: closedTodayCount > 0
                ? "A casa fechou \(closedTodayCount) \(closedTodayCount == 1 ? "coisa" : "coisas") hoje. Não tem mais nada te esperando até amanhã de manhã."
                : "Não tem nada te esperando até amanhã de manhã.",
            presence: .stored
        ) {
            Text("Pode largar o celular.").ninaText(.label, NinaTheme.ink, weight: .semibold)
        }
        .padding(.top, 40)
    }

    private var closedTodayCount: Int {
        store.tasks.count { task in
            guard let completedAt = task.completedAt else { return false }
            return Calendar.current.isDate(completedAt, inSameDayAs: now)
        }
    }

    private var fab: some View {
        Button {
            Haptics.lightImpact()
            router.presentedSheet = .addTask
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(NinaTheme.onCobalt)
                .frame(width: 56, height: 56)
                .background(NinaTheme.cobalt, in: Circle())
                .cardShadow()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Adicionar tarefa")
        .padding(.trailing, 20)
        .padding(.bottom, 96)
    }
}

extension Notification.Name {
    static let ninaSelectChatTab = Notification.Name("nina.selectChatTab")
}

// One row drawing, shared by Hoje and Tarefas, so the two lists cannot drift.
struct TaskRowView: View {
    @Environment(AppStore.self) private var store
    @Environment(RouterPath.self) private var router

    let task: TaskItem

    @State private var isShowingQuickActions = false
    @State private var didLongPress = false

    private var isOverdue: Bool { task.isOverdue() }

    private var owner: HouseholdMember? {
        store.familyGroup.members.first { $0.id == task.ownerMemberID }
    }

    var body: some View {
        HStack(spacing: 12) {
            Button {
                task.isDone ? Haptics.selection() : Haptics.success()
                store.toggleTask(task)
            } label: {
                NinaCheckbox(isOn: task.isDone, isOverdue: isOverdue)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.isDone ? "Marcar como não feita" : "Marcar como feita")

            Button {
                // The long press fires first and the tap follows on lift, so
                // without this the row opens the sheet and pushes the detail.
                guard !didLongPress else { didLongPress = false; return }
                Haptics.selection()
                router.navigate(to: .task(task.id))
            } label: {
                HStack(spacing: 10) {
                    Text(task.title)
                        .font(.system(size: 17, weight: .medium))
                        .tracking(-0.1)
                        .foregroundStyle(task.isDone ? NinaTheme.muted : NinaTheme.ink)
                        .strikethrough(task.isDone, color: NinaTheme.muted)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    if task.kind == .task {
                        Text(task.effectiveDueLabel())
                            .font(.system(size: 13, weight: isOverdue ? .semibold : .regular))
                            .foregroundStyle(isOverdue ? NinaTheme.terracotta : NinaTheme.muted)
                            .lineLimit(1)
                    }

                    // A semente's defining property is that it is a semente, so
                    // the kind glyph outranks the category one on its rows.
                    CategoryGlyph(
                        systemName: task.kind == .seed ? "leaf" : task.category.symbolName,
                        size: 15,
                        tint: NinaTheme.muted
                    )

                    if let owner {
                        MemberAvatar(initials: owner.name.ninaInitials, tone: owner.tone, size: 24)
                    } else {
                        Color.clear.frame(width: 24, height: 24)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(minHeight: 48)
        // Nina has no swipe actions by architectural necessity: the horizontal
        // drag belongs to the custom tab pager. Long-press is the substitute, and
        // it must be simultaneous or the row's own buttons swallow it.
        .contentShape(Rectangle())
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.4).onEnded { _ in
                didLongPress = true
                Haptics.lightImpact()
                isShowingQuickActions = true
            }
        )
        .sheet(isPresented: $isShowingQuickActions) {
            TaskQuickActionsSheet(task: task)
                .presentationDragIndicator(.visible)
        }
    }
}
