import SwiftUI

enum TaskListFilter: String, CaseIterable, Identifiable, Hashable {
    case all
    case mine
    case unowned
    case seeds
    case shopping

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "Tudo"
        case .mine: "Minhas"
        case .unowned: "Sem dono"
        case .seeds: "Sementes"
        case .shopping: "Compras"
        }
    }
}

struct TasksView: View {
    @Environment(AppStore.self) private var store
    @Environment(RouterPath.self) private var router

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var filter: TaskListFilter = .all
    @State private var searchQuery = ""
    @State private var isSearching = false
    @State private var collapsed: Set<String> = []
    @State private var isShowingCompleted = false
    @State private var isConfirmingShoppingClear = false
    @State private var isSelecting = false
    @State private var selection: Set<TaskItem.ID> = []
    @State private var isConfirmingBulkDelete = false
    @FocusState private var isSearchFocused: Bool

    private var openTasks: [TaskItem] {
        store.tasks.filter { $0.kind == .task && !$0.isDone }
    }

    private var mine: [TaskItem] {
        guard let me = store.currentFamilyMember else { return [] }
        return openTasks.filter { $0.ownerMemberID == me.id }
    }

    private var unowned: [TaskItem] {
        openTasks.filter { HouseholdWorkload.isUnowned($0, members: store.familyGroup.members) }
    }

    private var completedToday: [TaskItem] {
        let closed = store.tasks.filter { task in
            guard let completedAt = task.completedAt else { return false }
            return Calendar.current.isDateInToday(completedAt)
        }
        // The completed list sits under the filter chips and has to obey them,
        // or "Minhas" quietly shows the whole household's closings.
        guard filter == .mine, let me = store.currentFamilyMember else { return closed }
        return closed.filter { $0.ownerMemberID == me.id }
    }

    var body: some View {
        if isSearching {
            searchScreen
        } else {
            main
        }
    }


    private var main: some View {
        ZStack(alignment: .bottomTrailing) {
            GeometryReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        header
                        if !isSelecting {
                            filters
                        }
                        content
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                    .padding(.bottom, isSelecting ? 176 : 104)
                    .frame(minHeight: showsZeroState ? proxy.size.height : nil, alignment: .top)
                }
            }

            if isSelecting {
                selectionBar
            } else if filter != .shopping {
                fab
            }
        }
        .ninaScreenBackground()
        .ninaStatusBarMask()
        .onReceive(NotificationCenter.default.publisher(for: .ninaShowUnowned)) { _ in
            endSelection()
            filter = .unowned
        }
        .onChange(of: store.tasks.map(\.id)) { _, ids in
            selection.formIntersection(ids)
        }
        .alert(bulkDeleteTitle, isPresented: $isConfirmingBulkDelete) {
            Button("Cancelar", role: .cancel) {}
            Button("Apagar", role: .destructive) {
                store.deleteTasks(selection)
                endSelection()
            }
        } message: {
            Text("Some para toda a casa. Não dá para desfazer.")
        }
    }

    @ViewBuilder
    private var header: some View {
        if isSelecting {
            selectionHeader
        } else {
            browsingHeader
        }
    }

    private var browsingHeader: some View {
        HStack(alignment: .center) {
            Text(screenTitle).ninaText(.screen)

            Spacer()

            if canSelect {
                Button {
                    Haptics.selection()
                    isSelecting = true
                } label: {
                    Image(systemName: "checklist")
                        .font(.system(size: 19, weight: .regular))
                        .foregroundStyle(NinaTheme.ink)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Selecionar tarefas")
            }

            Button {
                Haptics.lightImpact()
                isSearching = true
                isSearchFocused = true
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 19, weight: .regular))
                    .foregroundStyle(NinaTheme.ink)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Buscar")
        }
    }

    private var selectionHeader: some View {
        HStack(alignment: .center) {
            Text(selectionTitle).ninaText(.screen)

            Spacer()

            Button {
                Haptics.selection()
                endSelection()
            } label: {
                Text("Cancelar")
                    .ninaText(.label, NinaTheme.muted, weight: .medium)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
        }
    }

    private var selectionTitle: String {
        switch selection.count {
        case 0: "Selecionar"
        case 1: "1 tarefa"
        default: "\(selection.count) tarefas"
        }
    }

    private var bulkDeleteTitle: String {
        selection.count == 1 ? "Apagar 1 tarefa?" : "Apagar \(selection.count) tarefas?"
    }

    private var selectableTasks: [TaskItem] {
        switch filter {
        case .all: openTasks
        case .mine: mine
        case .unowned: unowned
        case .seeds, .shopping: []
        }
    }

    private var canSelect: Bool {
        !selectableTasks.isEmpty
    }

    private func endSelection() {
        isSelecting = false
        selection = []
    }

    private func toggleSelection(_ id: TaskItem.ID) {
        Haptics.selection()
        if selection.contains(id) {
            selection.remove(id)
        } else {
            selection.insert(id)
        }
    }

    private var handOverChoices: [HouseholdMember] {
        store.familyGroup.members.filter { $0.role == .adult }
    }

    private var selectionBar: some View {
        HStack(spacing: 10) {
            NinaButton(
                title: "Feitas",
                systemName: "checkmark",
                fillsWidth: true,
                isEnabled: !selection.isEmpty
            ) {
                Haptics.success()
                store.completeTasks(selection)
                endSelection()
            }

            Menu {
                ForEach(handOverChoices) { member in
                    Button(member.id == store.currentFamilyMember?.id ? "Comigo" : member.name.firstWord) {
                        Haptics.success()
                        store.reassignTasks(selection, to: member)
                        endSelection()
                    }
                }
                Button("Sem dono") {
                    Haptics.success()
                    store.reassignTasks(selection, to: nil)
                    endSelection()
                }
            } label: {
                NinaButtonFace(title: "Passar", kind: .outline, systemName: "person.2", fillsWidth: true)
            }
            .buttonStyle(.plain)
            .disabled(selection.isEmpty)
            .opacity(selection.isEmpty ? 0.4 : 1)

            Button {
                Haptics.warning()
                isConfirmingBulkDelete = true
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(NinaTheme.ink)
                    .frame(width: 48, height: 48)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Apagar")
            .disabled(selection.isEmpty)
            .opacity(selection.isEmpty ? 0.4 : 1)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .background(alignment: .top) {
            NinaTheme.ground
                .overlay(alignment: .top) {
                    Rectangle().fill(NinaTheme.line).frame(height: 1)
                }
        }
        .padding(.bottom, 84)
    }

    private var screenTitle: String {
        switch filter {
        case .shopping: "Compras"
        case .seeds: "Sementes"
        default: "Tarefas"
        }
    }

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(TaskListFilter.allCases) { option in
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
        .fixedSize(horizontal: false, vertical: true)
    }

    private func chipTitle(_ option: TaskListFilter) -> String {
        let count: Int = switch option {
        case .all: openTasks.count
        case .mine: mine.count
        case .unowned: unowned.count
        case .seeds: store.openSeeds.count
        case .shopping: store.pendingShoppingItems.count
        }
        return count > 0 ? "\(option.title) \(count)" : option.title
    }

    private var showsZeroState: Bool {
        switch filter {
        case .all: store.tasks.isEmpty
        case .seeds: store.openSeeds.isEmpty
        case .shopping: store.shoppingItems.isEmpty
        case .mine, .unowned: false
        }
    }

    @ViewBuilder
    private var content: some View {
        switch filter {
        case .shopping: shopping
        case .seeds: seeds
        case .mine: grouped(mine, emptyLine: "Nada com você.")
        case .unowned: grouped(unowned, emptyLine: "Tudo tem dono.")
        case .all:
            if store.tasks.isEmpty {
                firstTasks
            } else {
                grouped(openTasks, emptyLine: "Nada em aberto.")
            }
        }
    }


    @ViewBuilder
    private func grouped(_ tasks: [TaskItem], emptyLine: String) -> some View {
        if tasks.isEmpty, completedToday.isEmpty {
            Text(emptyLine)
                .ninaText(.label, NinaTheme.muted)
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        } else {
            VStack(spacing: 18) {
                ForEach(categoryGroups(of: tasks), id: \.0.id) { category, items in
                    categorySection(category, items)
                }

                if !completedToday.isEmpty, !isSelecting {
                    completedSection
                }
            }
            .padding(.top, 4)
        }
    }

    private func categoryGroups(of tasks: [TaskItem]) -> [(TaskCategory, [TaskItem])] {
        var order: [String] = []
        var buckets: [String: (TaskCategory, [TaskItem])] = [:]
        for task in tasks {
            let key = task.category.id
            if buckets[key] == nil {
                buckets[key] = (task.category, [])
                order.append(key)
            }
            buckets[key]?.1.append(task)
        }
        return order.compactMap { bucket in
            buckets[bucket].map { ($0.0, TaskListOrder.sorted($0.1)) }
        }
    }

    private func categorySection(_ category: TaskCategory, _ items: [TaskItem]) -> some View {
        let isCollapsed = collapsed.contains(category.id)
        return VStack(spacing: 0) {
            Button {
                Haptics.selection()
                if isCollapsed { collapsed.remove(category.id) } else { collapsed.insert(category.id) }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(NinaTheme.faint)
                    Text("\(category.title.uppercased()) · \(items.count)")
                        .ninaText(.eyebrow, NinaTheme.faint, weight: .bold)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(isCollapsed ? "recolhida" : "aberta")
            .padding(.bottom, isCollapsed ? 0 : 8)

            if !isCollapsed {
                ForEach(items) { task in
                    VStack(spacing: 0) {
                        if isSelecting {
                            SelectableTaskRow(task: task, isSelected: selection.contains(task.id)) {
                                toggleSelection(task.id)
                            }
                        } else {
                            TaskRowView(task: task)
                        }
                        if task.id != items.last?.id {
                            NinaDivider(inset: 36)
                        }
                    }
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .leading)))
                }
            }
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.3), value: items.map(\.id))
    }

    private var completedSection: some View {
        VStack(spacing: 0) {
            Button {
                Haptics.selection()
                isShowingCompleted.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isShowingCompleted ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(NinaTheme.faint)
                    Text("CONCLUÍDAS HOJE · \(completedToday.count)")
                        .ninaText(.eyebrow, NinaTheme.faint, weight: .bold)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(isShowingCompleted ? "aberta" : "recolhida")
            .padding(.bottom, isShowingCompleted ? 8 : 0)

            if isShowingCompleted {
                ForEach(completedToday) { task in
                    TaskRowView(task: task)
                    if task.id != completedToday.last?.id {
                        NinaDivider(inset: 36)
                    }
                }
            }
        }
    }

    private var firstTasks: some View {
        ZeroState(
            headline: "Nada combinado ainda.",
            body_: "Conta pra Nina. Ela propõe, você confirma."
        ) {
            NinaButton(title: "Conversar com a Nina", kind: .quiet, systemName: "bubble.left") {
                Haptics.lightImpact()
                NotificationCenter.default.post(name: .ninaSelectChatTab, object: nil)
            }
        }
        .centeredBelowHeader(minimumGap: 44)
    }


    @ViewBuilder
    private var seeds: some View {
        if store.openSeeds.isEmpty {
            ZeroState(headline: "Semente é vontade sem data.", body_: "", showsMark: false) {
                VStack(spacing: 20) {
                    // Teaching by showing the real object: a semente rendered as it
                    // will look, with the date slot deliberately empty.
                    HStack(spacing: 12) {
                        CategoryGlyph(systemName: "leaf", size: 18, tint: NinaTheme.ink)
                        Text("Pintar a sala")
                            .ninaText(.body, NinaTheme.ink, weight: .medium)
                        Spacer()
                        Text("Plante depois").ninaText(.meta, NinaTheme.muted)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .ninaCard(fill: NinaTheme.grout, stroke: .clear)

                    NinaButton(title: "Nova semente", kind: .outline) {
                        Haptics.lightImpact()
                        router.presentedSheet = .addSeed
                    }
                }
            }
            .centeredBelowHeader(minimumGap: 34)
        } else {
            VStack(spacing: 0) {
                ForEach(store.openSeeds) { seed in
                    TaskRowView(task: seed)
                    if seed.id != store.openSeeds.last?.id {
                        NinaDivider(inset: 36)
                    }
                }
            }
            .padding(.top, 4)
        }
    }


    @ViewBuilder
    private var shopping: some View {
        if store.shoppingItems.isEmpty {
            VStack(spacing: 22) {
                ZeroState(
                    headline: "Nada faltando.",
                    body_: "O que acabar em casa aparece aqui."
                )

                ShoppingQuickAdd()
            }
            .centeredBelowHeader(minimumGap: 34)
        } else {
            VStack(spacing: 0) {
                ShoppingQuickAdd()
                    .padding(.bottom, 8)

                // Checked items stay exactly where they are: in an aisle you need
                // positional stability, so nothing reflows under your thumb.
                ForEach(store.shoppingItems) { item in
                    shoppingRow(item)
                    if item.id != store.shoppingItems.last?.id {
                        NinaDivider(inset: 36)
                    }
                }

                if store.shoppingItems.contains(where: \.isChecked) {
                    NinaButton(title: "Limpar comprados", kind: .quiet) {
                        Haptics.warning()
                        isConfirmingShoppingClear = true
                    }
                    .padding(.top, 10)
                }
            }
            .padding(.top, 4)
            .alert("Limpar comprados?", isPresented: $isConfirmingShoppingClear) {
                Button("Limpar", role: .destructive) {
                    _ = store.clearCheckedShoppingItems()
                }
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text("Some da lista para todo mundo da casa.")
            }
        }
    }

    // At accessibility sizes the amount moves under the name instead of squeezing it.
    @ViewBuilder
    private func shoppingRowLabel(_ item: ShoppingItem) -> some View {
        let title = Text(item.title)
            .ninaText(.body, item.isChecked ? NinaTheme.muted : NinaTheme.ink, weight: .medium)
            .strikethrough(item.isChecked, color: NinaTheme.muted)
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 4) {
                title.lineLimit(3)
                if !item.amount.isEmpty {
                    Text(item.amount).ninaText(.meta, NinaTheme.muted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(spacing: 10) {
                title.lineLimit(2)
                Spacer(minLength: 8)
                if !item.amount.isEmpty {
                    Text(item.amount).ninaText(.meta, NinaTheme.muted)
                }
            }
        }
    }

    private func shoppingRow(_ item: ShoppingItem) -> some View {
        HStack(spacing: 12) {
            Button {
                item.isChecked ? Haptics.selection() : Haptics.success()
                store.toggleShoppingItem(item)
            } label: {
                // Squares carry stock; circles carry things with an owner and a moment.
                NinaCheckbox(isOn: item.isChecked, isSquare: true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.isChecked ? "Desmarcar \(item.title)" : "Marcar \(item.title) como comprado")

            Button {
                Haptics.lightImpact()
                router.presentedSheet = .editShoppingItem(item.id)
            } label: {
                shoppingRowLabel(item)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(minHeight: 48)
    }

    private var searchScreen: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(NinaTheme.muted)
                    // Autocorrect turns a household's own words into other words:
                    // "boleto" became "Bolero" the first time this ran.
                    TextField("Procurar na casa", text: $searchQuery)
                        .ninaText(.label, NinaTheme.ink, weight: .medium)
                        .focused($isSearchFocused)
                        .submitLabel(.search)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                .padding(.horizontal, 12)
                .frame(height: 40)
                .background(NinaTheme.grout, in: RoundedRectangle(cornerRadius: NinaTheme.Radius.field, style: .continuous))

                Button {
                    Haptics.selection()
                    searchQuery = ""
                    isSearching = false
                } label: {
                    Text("Cancelar")
                        .ninaText(.label, NinaTheme.muted, weight: .medium)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .padding(.bottom, 14)

            if searchQuery.trimmingCharacters(in: .whitespaces).isEmpty {
                Spacer()
            } else if searchResults.isEmpty && shoppingResults.isEmpty {
                // No create button: someone who searched does not want to invent
                // the thing, they want to find it.
                VStack(alignment: .leading, spacing: 10) {
                    Text("Nada com esse nome.").ninaText(.screen)
                    Text("Tenta outra palavra.").ninaText(.label, NinaTheme.muted)

                    Button {
                        Haptics.lightImpact()
                        searchQuery = ""
                        isSearching = false
                        NotificationCenter.default.post(name: .ninaSelectChatTab, object: nil)
                    } label: {
                        NinaChip(text: "Conversar com a Nina", isSet: true)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 12)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)

                Spacer()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(searchResults) { task in
                            TaskRowView(task: task)
                            NinaDivider(inset: 36)
                        }

                        if !shoppingResults.isEmpty {
                            Eyebrow(text: "Compras · \(shoppingResults.count)")
                                .padding(.top, searchResults.isEmpty ? 0 : 22)
                                .padding(.bottom, 4)
                            ForEach(shoppingResults) { item in
                                shoppingRow(item)
                                NinaDivider(inset: 36)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 104)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .ninaScreenBackground()
    }

    private var searchResults: [TaskItem] {
        HouseSearch.tasks(store.tasks, query: searchQuery)
    }

    private var shoppingResults: [ShoppingItem] {
        HouseSearch.shoppingItems(store.shoppingItems, query: searchQuery)
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
        .accessibilityLabel("Adicionar")
        .padding(.trailing, 20)
        .padding(.bottom, 96)
    }
}

// A list is built one word at a time: return adds the item and keeps the keyboard up for the next.
private struct ShoppingQuickAdd: View {
    @Environment(AppStore.self) private var store
    @Environment(RouterPath.self) private var router

    @State private var draft = ""
    @FocusState private var isFocused: Bool

    private var trimmed: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(NinaTheme.cobalt)
                .accessibilityHidden(true)

            TextField("Adicionar item", text: $draft)
                .ninaText(.label, NinaTheme.ink, weight: .medium)
                .tint(NinaTheme.cobalt)
                .focused($isFocused)
                .submitLabel(.next)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.sentences)
                .onSubmit(add)

            if !trimmed.isEmpty {
                Button(action: add) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(NinaTheme.cobalt)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Adicionar")
            } else {
                Button {
                    Haptics.lightImpact()
                    router.presentedSheet = .addShoppingItem
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(NinaTheme.muted)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Adicionar com quantidade e dono")
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 4)
        .frame(minHeight: 50)
        .frame(maxWidth: .infinity)
        .background(NinaTheme.grout, in: RoundedRectangle(cornerRadius: NinaTheme.Radius.field, style: .continuous))
    }

    private func add() {
        guard !trimmed.isEmpty else {
            isFocused = false
            return
        }
        Haptics.success()
        store.addShoppingItem(title: trimmed, amount: "", owner: "")
        draft = ""
        isFocused = true
    }
}

// Inside a group the next thing to do comes first: late, then soonest, then undated, and urgency breaks a tie.
enum TaskListOrder {
    static func sorted(_ tasks: [TaskItem], now: Date = .now, calendar: Calendar = .current) -> [TaskItem] {
        tasks.enumerated()
            .sorted { lhs, rhs in
                let left = lhs.element.displayDate(relativeTo: now, calendar: calendar)
                let right = rhs.element.displayDate(relativeTo: now, calendar: calendar)
                switch (left, right) {
                case let (left?, right?) where left != right:
                    return left < right
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                default:
                    let leftRank = rank(lhs.element.priority)
                    let rightRank = rank(rhs.element.priority)
                    return leftRank != rightRank ? leftRank > rightRank : lhs.offset < rhs.offset
                }
            }
            .map(\.element)
    }

    private static func rank(_ priority: TaskPriority) -> Int {
        switch priority {
        case .urgent: 2
        case .high: 1
        case .normal: 0
        }
    }
}

private struct SelectableTaskRow: View {
    let task: TaskItem
    let isSelected: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 24, weight: .regular))
                    .foregroundStyle(isSelected ? NinaTheme.ink : NinaTheme.faint)
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title)
                        .ninaText(.body, NinaTheme.ink, weight: .medium)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                    Text(task.effectiveDueLabel())
                        .ninaText(.meta, task.isOverdue() ? NinaTheme.terracotta : NinaTheme.muted)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
