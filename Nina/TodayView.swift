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

    var emptyLine: String {
        switch self {
        case .all: "Nada mais para hoje."
        case .mine: "Nada com você."
        case .unowned: "Tudo tem dono."
        case .seeds: "Nenhuma semente."
        }
    }
}

struct TodayView: View {
    @Environment(AppStore.self) private var store
    @Environment(RouterPath.self) private var router

    @State private var filter: TodayFilter = .all
    @State private var isOverdueCollapsed = false
    @State private var isConfirmingReschedule = false

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
            return agenda.filter { HouseholdWorkload.isUnowned($0, members: store.familyGroup.members) }
        case .seeds:
            return store.openSeeds
        }
    }

    // A household that has never captured anything is a different screen from one
    // that has cleared its day: the first promises, the second congratulates.
    private var hasEverCaptured: Bool {
        !store.tasks.isEmpty || !store.shoppingItems.isEmpty
    }

    private var showsZeroState: Bool {
        !hasEverCaptured || (agenda.isEmpty && filter == .all)
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            GeometryReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header

                        if !hasEverCaptured {
                            firstDay
                        } else if agenda.isEmpty && filter == .all {
                            dayCleared
                        } else {
                            filters
                            list
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                    .padding(.bottom, 104)
                    .frame(minHeight: showsZeroState ? proxy.size.height : nil, alignment: .top)
                }
            }

            fab
        }
        .ninaScreenBackground()
        .ninaStatusBarMask()
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .center, spacing: 10) {
                    Eyebrow(text: now.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "pt_BR"))))
                    if store.householdPremium.isActive {
                        PremiumBadge()
                    }
                }
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
            .padding(.trailing, 20)
        }
        .scrollClipDisabled()
        .chipRowTrailingFade()
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
        if filter == .all {
            if !overdue.isEmpty {
                overdueSection
            }
            if !overdue.isEmpty && !dueToday.isEmpty {
                NinaDivider(inset: 0)
            }
            if !dueToday.isEmpty {
                rows(dueToday)
            }
        } else if filtered.isEmpty {
            // A filter that finds nothing never offers to create.
            Text(filter.emptyLine)
                .ninaText(.label, NinaTheme.muted)
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        } else {
            rows(filtered)
        }
    }

    private var overdueSection: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    Haptics.selection()
                    isOverdueCollapsed.toggle()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isOverdueCollapsed ? "chevron.right" : "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(NinaTheme.terracotta)
                        Text("ATRASADAS · \(overdue.count)")
                            .ninaText(.eyebrow, NinaTheme.terracotta, weight: .bold)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityValue(isOverdueCollapsed ? "recolhida" : "aberta")

                Spacer()

                if overdue.count > 1 {
                    // Lateness is the count, not the control: the capsule stays ink.
                    Button {
                        Haptics.lightImpact()
                        isConfirmingReschedule = true
                    } label: {
                        Text("Remarcar")
                            .ninaText(.meta, NinaTheme.ink, weight: .semibold)
                            .padding(.horizontal, 12)
                            .frame(minHeight: 30)
                            .overlay(Capsule().strokeBorder(NinaTheme.control, lineWidth: 1))
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .confirmationDialog(
                        "Remarcar para amanhã, 09:00?",
                        isPresented: $isConfirmingReschedule,
                        titleVisibility: .visible
                    ) {
                        Button("Remarcar") {
                            rescheduleOverdue()
                        }
                        Button("Cancelar", role: .cancel) {}
                    } message: {
                        Text("Nada é apagado.")
                    }
                }
            }
            .padding(.bottom, isOverdueCollapsed ? 0 : 8)

            if !isOverdueCollapsed {
                rows(overdue)
            }
        }
        .padding(.top, 6)
    }

    private func rows(_ tasks: [TaskItem]) -> some View {
        VStack(spacing: 0) {
            ForEach(tasks) { task in
                TaskRowView(task: task)
                if task.id != tasks.last?.id {
                    NinaDivider(inset: 36)
                }
            }
        }
    }

    private func rescheduleOverdue() {
        let target = Calendar.current.date(
            bySettingHour: 9, minute: 0, second: 0,
            of: Calendar.current.date(byAdding: .day, value: 1, to: now) ?? now
        ) ?? now
        for task in overdue {
            store.snoozeTask(task.id, until: target)
        }
        Haptics.success()
    }

    private var firstDay: some View {
        ZeroState(
            headline: "A casa começa vazia.",
            body_: "Conta pra Nina o que está pesando."
        ) {
            NinaButton(title: "Conversar com a Nina", kind: .quiet, systemName: "bubble.left") {
                Haptics.lightImpact()
                router.presentedSheet = nil
                NotificationCenter.default.post(name: .ninaSelectChatTab, object: nil)
            }
        }
        .centeredBelowHeader(minimumGap: 40)
    }

    private var dayCleared: some View {
        // No completion tally here: on the one screen whose job is relief, a count is a scoreboard.
        ZeroState(
            headline: "Nada mais para hoje.",
            body_: "Pode largar o celular.",
            presence: .stored
        ) {
            if let next = nextUp {
                VStack(alignment: .leading, spacing: 8) {
                    Eyebrow(text: "Próxima")
                    HStack(spacing: 12) {
                        NinaCheckbox(isOn: false, size: 22)
                        Text(next.title)
                            .ninaText(.label, NinaTheme.ink, weight: .medium)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(next.effectiveDueLabel()).ninaText(.meta, NinaTheme.muted)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .ninaCard()
            }
        }
        .centeredBelowHeader(minimumGap: 40)
    }

    // What the day being clear does not mean: that nothing is coming.
    private var nextUp: TaskItem? {
        store.tasks
            .filter { $0.kind == .task && !$0.isDone }
            .compactMap { task -> (TaskItem, Date)? in
                guard let date = task.displayDate(relativeTo: now), date > now else { return nil }
                return (task, date)
            }
            .min { $0.1 < $1.1 }?
            .0
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

extension View {
    func centeredBelowHeader(minimumGap: CGFloat) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: minimumGap)
            self
            Spacer(minLength: 0)
        }
    }
}

// One row drawing, shared by Hoje and Tarefas, so the two lists cannot drift.
struct TaskRowView: View {
    @Environment(AppStore.self) private var store
    @Environment(RouterPath.self) private var router

    let task: TaskItem

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var isShowingQuickActions = false
    @State private var didLongPress = false

    private var isOverdue: Bool { task.isOverdue() }

    private var owner: HouseholdMember? {
        store.familyGroup.members.first { $0.id == task.ownerMemberID }
    }

    // At accessibility sizes the date moves under the title instead of squeezing it to a stub.
    @ViewBuilder
    private var rowLabel: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 6) {
                rowTitle.lineLimit(3)
                HStack(spacing: 10) {
                    rowTrailing
                    Spacer(minLength: 0)
                }
            }
        } else {
            HStack(spacing: 10) {
                rowTitle.lineLimit(2)
                Spacer(minLength: 8)
                rowTrailing
            }
        }
    }

    private var rowTitle: some View {
        Text(task.title)
            .ninaText(.body, task.isDone ? NinaTheme.muted : NinaTheme.ink, weight: .medium)
            .strikethrough(task.isDone, color: NinaTheme.muted)
            .multilineTextAlignment(.leading)
    }

    @ViewBuilder
    private var rowTrailing: some View {
        if task.kind == .task {
            Text(task.effectiveDueLabel())
                .ninaText(.meta, isOverdue ? NinaTheme.terracotta : NinaTheme.muted, weight: isOverdue ? .semibold : .regular)
                .lineLimit(1)
                .accessibilityLabel(
                    isOverdue ? "Atrasada, \(task.effectiveDueLabel())" : task.effectiveDueLabel()
                )
        } else {
            Text("Plante depois").ninaText(.meta, NinaTheme.muted)
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
                .accessibilityLabel("Dono: \(owner.name)")
        } else {
            Color.clear.frame(width: 24, height: 24)
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Button {
                // A semente is planted, never ticked: the checkbox opens the date.
                if task.kind == .seed, !task.isDone {
                    Haptics.lightImpact()
                    router.presentedSheet = .plantSeed(task.id)
                    return
                }
                task.isDone ? Haptics.selection() : Haptics.success()
                store.toggleTask(task)
            } label: {
                NinaCheckbox(isOn: task.isDone, isOverdue: isOverdue)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.kind == .seed && !task.isDone ? "Plantar" : task.completionActionTitle)

            Button {
                // The long press fires first and the tap follows on lift, so
                // without this the row opens the sheet and pushes the detail.
                guard !didLongPress else { didLongPress = false; return }
                Haptics.selection()
                router.navigate(to: .task(task.id))
            } label: {
                rowLabel
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(minHeight: 48)
        // Rows live in a ScrollView, not a List, so there are no swipe actions:
        // long-press is the substitute, and it must be simultaneous or the row's
        // own buttons swallow it.
        .contentShape(Rectangle())
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.4).onEnded { _ in
                didLongPress = true
                Haptics.lightImpact()
                isShowingQuickActions = true
            }
        )
        // VoiceOver cannot long-press; the same sheet is one rotor action away.
        .accessibilityAction(named: "Ações rápidas") {
            isShowingQuickActions = true
        }
        .sheet(isPresented: $isShowingQuickActions) {
            TaskQuickActionsSheet(task: task)
                .presentationDragIndicator(.visible)
        }
    }
}
