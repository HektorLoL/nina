import SwiftUI

private enum TaskSectionContent: Hashable {
    case taskSection(String)
    case shopping
}

private struct TaskSectionDescriptor: Identifiable, Hashable {
    var id: String
    var title: String
    var subtitle: String
    var systemImage: String
    var tone: MemberTone
    var content: TaskSectionContent
    var addDestination: SheetDestination
    var addAccessibilityLabel: String
}

struct TasksView: View {
    @Environment(AppStore.self) private var store
    @Environment(RouterPath.self) private var router
    @State private var selectedSectionID = AppStore.houseTasksSectionID
    @State private var isPresentingSectionCreator = false
    @State private var sectionPendingDeletion: TaskSectionDescriptor?
    @State private var searchQuery = ""
    @State private var selectedFilter: TaskListFilter = .all
    @State private var isShowingCompleted = false
    @State private var isConfirmingShoppingClear = false

    private static let shoppingSectionID = "shopping-list"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                TaskSectionChooser(
                    sections: sections,
                    selectedSection: selectedSection,
                    selectSection: selectSection,
                    createSection: presentSectionCreator,
                    canDeleteSelectedSection: canDeleteSelectedSection,
                    deleteSelectedSection: requestDeleteSelectedSection
                )

                selectedSectionContent
            }
            .padding(18)
            .padding(.bottom, 104)
        }
        .ninaScreenBackground()
        .searchable(
            text: $searchQuery,
            placement: .navigationBarDrawer(displayMode: .automatic),
            prompt: "Buscar por título, responsável ou categoria"
        )
        .navigationTitle("Tarefas")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Haptics.lightImpact()
                    router.presentedSheet = selectedSection.addDestination
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3.weight(.bold))
                }
                .accessibilityLabel(selectedSection.addAccessibilityLabel)
            }
        }
        .sheet(isPresented: $isPresentingSectionCreator) {
            NavigationStack {
                TaskSectionCreatorSheet(createSection: createTaskSection)
            }
            .presentationDragIndicator(.visible)
        }
        .alert(
            "Excluir esta seção?",
            isPresented: Binding(
                get: { sectionPendingDeletion != nil },
                set: { isPresented in
                    if !isPresented {
                        sectionPendingDeletion = nil
                    }
                }
            ),
            presenting: sectionPendingDeletion
        ) { section in
            Button("Cancelar", role: .cancel) {
                sectionPendingDeletion = nil
            }
            Button("Excluir seção", role: .destructive) {
                deleteTaskSection(section)
            }
        } message: { section in
            let taskCount = store.tasks(in: section.id).count
            if taskCount == 0 {
                Text("A seção “\(section.title)” será apagada.")
            } else {
                Text(
                    "\(taskCount) \(taskCount == 1 ? "tarefa será movida" : "tarefas serão movidas") para “Tarefas da casa”."
                )
            }
        }
        .alert("Limpar os itens comprados?", isPresented: $isConfirmingShoppingClear) {
            Button("Cancelar", role: .cancel) {}
            Button("Limpar", role: .destructive) {
                clearBoughtShoppingItems()
            }
        } message: {
            let count = store.shoppingItems.count(where: \.isChecked)
            Text(
                count == 1
                    ? "1 item comprado sai da lista da casa."
                    : "\(count) itens comprados saem da lista da casa."
            )
        }
    }

    private func clearBoughtShoppingItems() {
        Haptics.success()
        withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
            store.clearCheckedShoppingItems()
        }
    }

    private var sections: [TaskSectionDescriptor] {
        taskSectionDescriptors + [
            TaskSectionDescriptor(
                id: Self.shoppingSectionID,
                title: "Lista de compras",
                subtitle: "\(store.pendingShoppingItems.count) itens pendentes",
                systemImage: "cart.fill",
                tone: .amber,
                content: .shopping,
                addDestination: .addShoppingItem,
                addAccessibilityLabel: "Adicionar compra"
            )
        ]
    }

    private var taskSectionDescriptors: [TaskSectionDescriptor] {
        store.taskSections.map { section in
            TaskSectionDescriptor(
                id: section.id,
                title: section.title,
                subtitle: taskSectionSubtitle(section.id),
                systemImage: section.symbolName,
                tone: section.tone,
                content: .taskSection(section.id),
                addDestination: .addTaskInSection(section.id),
                addAccessibilityLabel: "Adicionar tarefa em \(section.title)"
            )
        }
    }

    private var selectedSection: TaskSectionDescriptor {
        sections.first { $0.id == selectedSectionID } ?? sections[0]
    }

    private var canDeleteSelectedSection: Bool {
        guard case .taskSection(let sectionID) = selectedSection.content else {
            return false
        }
        return sectionID != AppStore.houseTasksSectionID
    }

    @ViewBuilder
    private var selectedSectionContent: some View {
        switch selectedSection.content {
        case .taskSection(let sectionID):
            taskList(for: selectedSection, sectionID: sectionID)
        case .shopping:
            shoppingList
        }
    }

    private var header: some View {
        SoftCard(padding: 18) {
            HStack(spacing: 14) {
                IconBubble(systemName: "checklist", tone: .mint, size: 54)

                VStack(alignment: .leading, spacing: 5) {
                    Text("Organização manual")
                        .font(.title2.weight(.black))
                        .foregroundStyle(NinaTheme.ink)

                    Text("Para quando você quer resolver direto, sem conversar.")
                        .font(.subheadline)
                        .foregroundStyle(NinaTheme.muted)
                }
            }
        }
    }

    private func taskList(for section: TaskSectionDescriptor, sectionID: String) -> some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let allTasks = store.tasks(in: sectionID)
            let open = visibleOpenTasks(in: sectionID, relativeTo: context.date)
            let completed = allTasks.filter(\.isDone)

            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(title: section.title, subtitle: section.subtitle)

                if !allTasks.isEmpty {
                    TaskFilterBar(
                        selectedFilter: $selectedFilter,
                        counts: filterCounts(in: sectionID, relativeTo: context.date)
                    )
                }

                if allTasks.isEmpty {
                    TaskSectionEmptyState(section: section) {
                        Haptics.lightImpact()
                        router.presentedSheet = section.addDestination
                    }
                } else if open.isEmpty {
                    TaskFilterEmptyState(filter: selectedFilter, hasSearch: !trimmedQuery.isEmpty)
                } else {
                    ForEach(open) { task in
                        TaskCard(
                            task: task,
                            isMarkedComplete: task.isDone,
                            onToggle: toggleTask,
                            togglesOnTap: false,
                            referenceDate: context.date
                        )
                    }
                }

                if !completed.isEmpty, trimmedQuery.isEmpty, selectedFilter == .all {
                    completedDisclosure(completed, referenceDate: context.date)
                }
            }
        }
    }

    @ViewBuilder
    private func completedDisclosure(_ completed: [TaskItem], referenceDate: Date) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                Haptics.selection()
                withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                    isShowingCompleted.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isShowingCompleted ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.black))
                    Text(
                        completed.count == 1
                            ? "1 tarefa concluída"
                            : "\(completed.count) tarefas concluídas"
                    )
                    .font(.subheadline.weight(.black))
                    Spacer()
                }
                .foregroundStyle(NinaTheme.muted)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isShowingCompleted {
                ForEach(completed) { task in
                    TaskCard(
                        task: task,
                        isMarkedComplete: true,
                        onToggle: toggleTask,
                        togglesOnTap: false,
                        referenceDate: referenceDate
                    )
                }
            }
        }
        .padding(.top, 6)
    }

    private var trimmedQuery: String {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func visibleOpenTasks(in sectionID: String, relativeTo referenceDate: Date) -> [TaskItem] {
        let calendar = Calendar.current
        let viewer = store.currentFamilyMember
        return store.openTasks(in: sectionID)
            .filter {
                selectedFilter.matches(
                    $0,
                    referenceDate: referenceDate,
                    calendar: calendar,
                    currentMemberID: viewer?.id,
                    currentUserName: viewer?.name
                )
            }
            .filter { matchesSearch($0) }
            .sorted { left, right in
                let leftOverdue = left.isOverdue(relativeTo: referenceDate, calendar: calendar)
                let rightOverdue = right.isOverdue(relativeTo: referenceDate, calendar: calendar)
                if leftOverdue != rightOverdue { return leftOverdue }

                if left.priority.sortRank != right.priority.sortRank {
                    return left.priority.sortRank > right.priority.sortRank
                }

                let leftDate = left.displayDate(relativeTo: referenceDate, calendar: calendar) ?? .distantFuture
                let rightDate = right.displayDate(relativeTo: referenceDate, calendar: calendar) ?? .distantFuture
                if leftDate != rightDate { return leftDate < rightDate }

                return left.title.localizedCaseInsensitiveCompare(right.title) == .orderedAscending
            }
    }

    private func matchesSearch(_ task: TaskItem) -> Bool {
        let query = trimmedQuery
        guard !query.isEmpty else { return true }
        return [task.title, task.subtitle, task.owner, task.category.title]
            .contains { $0.localizedCaseInsensitiveContains(query) }
    }

    private func filterCounts(in sectionID: String, relativeTo referenceDate: Date) -> [TaskListFilter: Int] {
        let calendar = Calendar.current
        let open = store.openTasks(in: sectionID).filter(matchesSearch)
        let viewer = store.currentFamilyMember

        return TaskListFilter.allCases.reduce(into: [:]) { counts, filter in
            counts[filter] = open.count {
                filter.matches(
                    $0,
                    referenceDate: referenceDate,
                    calendar: calendar,
                    currentMemberID: viewer?.id,
                    currentUserName: viewer?.name
                )
            }
        }
    }

    private var shoppingList: some View {
        let pending = store.shoppingItems.filter { !$0.isChecked && matchesShoppingSearch($0) }
        let bought = store.shoppingItems.filter { $0.isChecked && matchesShoppingSearch($0) }

        return VStack(alignment: .leading, spacing: 12) {
            SectionTitle(
                title: "Lista de compras",
                subtitle: store.pendingShoppingItems.count == 1
                    ? "1 item pendente"
                    : "\(store.pendingShoppingItems.count) itens pendentes"
            )

            if store.shoppingItems.isEmpty {
                ShoppingEmptyState {
                    Haptics.lightImpact()
                    router.presentedSheet = .addShoppingItem
                }
            } else if pending.isEmpty, bought.isEmpty {
                TaskFilterEmptyState(filter: .all, hasSearch: true)
            } else {
                ForEach(pending) { item in
                    shoppingRow(item)
                }

                if pending.isEmpty {
                    Text("Tudo comprado. Nada pendente na lista.")
                        .font(.subheadline)
                        .foregroundStyle(NinaTheme.muted)
                        .padding(.vertical, 4)
                }

                if !bought.isEmpty {
                    HStack {
                        Text(bought.count == 1 ? "1 comprado" : "\(bought.count) comprados")
                            .font(.subheadline.weight(.black))
                            .foregroundStyle(NinaTheme.muted)

                        Spacer()

                        Button("Limpar comprados") {
                            Haptics.warning()
                            isConfirmingShoppingClear = true
                        }
                        .font(.caption.weight(.black))
                        .foregroundStyle(NinaTheme.coral)
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 6)

                    ForEach(bought) { item in
                        shoppingRow(item)
                    }
                }
            }
        }
    }

    private func shoppingRow(_ item: ShoppingItem) -> some View {
        ShoppingRow(item: item, tone: shoppingTone(for: item))
            .onTapGesture {
                Haptics.lightImpact()
                router.presentedSheet = .editShoppingItem(item.id)
            }
            .contextMenu {
                Button(role: .destructive) {
                    deleteShoppingItem(item)
                } label: {
                    Label("Apagar item", systemImage: "trash")
                }
            }
    }

    private func shoppingTone(for item: ShoppingItem) -> MemberTone {
        let people = store.familyGroup.members.filter { $0.role != .assistant }
        if let memberID = item.ownerMemberID {
            return people.first { $0.id == memberID }?.tone ?? .amber
        }
        return people
            .first { $0.name.localizedCaseInsensitiveCompare(item.owner) == .orderedSame }?
            .tone ?? .amber
    }

    private func matchesShoppingSearch(_ item: ShoppingItem) -> Bool {
        let query = trimmedQuery
        guard !query.isEmpty else { return true }
        return [item.title, item.amount, item.owner]
            .contains { $0.localizedCaseInsensitiveContains(query) }
    }

    private func deleteShoppingItem(_ item: ShoppingItem) {
        Haptics.success()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.84)) {
            store.deleteShoppingItem(item.id)
        }
    }

    private func toggleTask(_ task: TaskItem) {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
            store.toggleTask(task)
        }
    }

    private func selectSection(_ section: TaskSectionDescriptor) {
        guard selectedSectionID != section.id else { return }

        Haptics.selection()
        withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
            selectedSectionID = section.id
        }
    }

    private func presentSectionCreator() {
        Haptics.lightImpact()
        isPresentingSectionCreator = true
    }

    private func requestDeleteSelectedSection() {
        guard canDeleteSelectedSection else { return }
        Haptics.warning()
        sectionPendingDeletion = selectedSection
    }

    private func deleteTaskSection(_ section: TaskSectionDescriptor) {
        guard case .taskSection(let sectionID) = section.content,
              store.deleteTaskSection(sectionID) else {
            sectionPendingDeletion = nil
            return
        }

        Haptics.success()
        withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
            selectedSectionID = AppStore.houseTasksSectionID
        }
        sectionPendingDeletion = nil
    }

    private func createTaskSection(_ title: String, symbolName: String) {
        let section = store.addTaskSection(title: title, symbolName: symbolName)

        Haptics.success()
        withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
            selectedSectionID = section.id
        }
    }

    private func taskSectionSubtitle(_ sectionID: String) -> String {
        let counts = store.taskCounts(in: sectionID)
        let seedCount = store.openTasks(in: sectionID).count { $0.kind == .seed }
        let seedSummary = seedCount == 0 ? "" : " · \(seedCount) \(seedCount == 1 ? "semente" : "sementes")"
        return "\(counts.open) abertas · \(counts.completed) concluídas\(seedSummary)"
    }
}

enum TaskListFilter: String, CaseIterable, Identifiable, Hashable {
    case all
    case mine
    case overdue
    case seeds

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "Todas"
        case .mine: "Minhas"
        case .overdue: "Atrasadas"
        case .seeds: "Sementes"
        }
    }

    var symbolName: String {
        switch self {
        case .all: "tray.full.fill"
        case .mine: "person.fill"
        case .overdue: "exclamationmark.circle.fill"
        case .seeds: "leaf.fill"
        }
    }

    var tone: MemberTone {
        switch self {
        case .all: .mint
        case .mine: .sky
        case .overdue: .coral
        case .seeds: .lavender
        }
    }

    var emptyMessage: String {
        switch self {
        case .all: "Nada por aqui ainda."
        case .mine: "Nenhuma tarefa está com você agora."
        case .overdue: "Nada atrasado. A casa está em dia."
        case .seeds: "Nenhuma semente guardada nesta seção."
        }
    }

    func matches(
        _ task: TaskItem,
        referenceDate: Date,
        calendar: Calendar,
        currentMemberID: UUID?,
        currentUserName: String?
    ) -> Bool {
        switch self {
        case .all:
            true
        case .mine:
            if let currentMemberID, let ownerMemberID = task.ownerMemberID {
                ownerMemberID == currentMemberID
            } else {
                currentUserName.map { task.owner.localizedCaseInsensitiveCompare($0) == .orderedSame } ?? false
            }
        case .overdue:
            task.isOverdue(relativeTo: referenceDate, calendar: calendar)
        case .seeds:
            task.kind == .seed
        }
    }
}

private struct TaskFilterBar: View {
    @Binding var selectedFilter: TaskListFilter
    var counts: [TaskListFilter: Int]

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(TaskListFilter.allCases) { filter in
                    let count = counts[filter] ?? 0
                    let isSelected = selectedFilter == filter

                    Button {
                        Haptics.lightImpact()
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                            selectedFilter = filter
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: filter.symbolName)
                                .font(.caption2.weight(.black))
                            Text(filter.title)
                                .font(.caption.weight(.black))
                            Text("\(count)")
                                .font(.caption2.weight(.heavy))
                                .opacity(0.75)
                        }
                        .foregroundStyle(isSelected ? .white : filter.tone.color)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            isSelected ? filter.tone.color : filter.tone.softColor,
                            in: Capsule()
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(count == 0 && filter != .all && !isSelected)
                    .opacity(count == 0 && filter != .all && !isSelected ? 0.45 : 1)
                    .accessibilityLabel("\(filter.title), \(count) tarefas")
                    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                }
            }
            .padding(.horizontal, 2)
        }
        .scrollIndicators(.hidden)
    }
}

private struct TaskFilterEmptyState: View {
    var filter: TaskListFilter
    var hasSearch: Bool

    var body: some View {
        SoftCard(padding: 18) {
            HStack(spacing: 12) {
                IconBubble(
                    systemName: hasSearch ? "magnifyingglass" : filter.symbolName,
                    tone: filter.tone,
                    size: 40
                )

                Text(hasSearch ? "Nenhuma tarefa encontrada para essa busca." : filter.emptyMessage)
                    .font(.subheadline)
                    .foregroundStyle(NinaTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
        }
    }
}

private struct TaskSectionChooser: View {
    var sections: [TaskSectionDescriptor]
    var selectedSection: TaskSectionDescriptor
    var selectSection: (TaskSectionDescriptor) -> Void
    var createSection: () -> Void
    var canDeleteSelectedSection: Bool
    var deleteSelectedSection: () -> Void

    var body: some View {
        Menu {
            ForEach(sections) { section in
                Button {
                    selectSection(section)
                } label: {
                    Label {
                        Text(section.title)
                    } icon: {
                        Image(systemName: selectedSection.id == section.id ? "checkmark" : section.systemImage)
                    }
                }
            }

            Divider()

            Button(action: createSection) {
                Label("Nova seção", systemImage: "plus.circle.fill")
            }

            if canDeleteSelectedSection {
                Divider()

                Button(role: .destructive, action: deleteSelectedSection) {
                    Label("Excluir seção", systemImage: "trash.fill")
                }
            }
        } label: {
            HStack(spacing: 12) {
                IconBubble(systemName: selectedSection.systemImage, tone: selectedSection.tone, size: 44)

                VStack(alignment: .leading, spacing: 4) {
                    Text(selectedSection.title)
                        .font(.headline.weight(.heavy))
                        .foregroundStyle(NinaTheme.ink)

                    Text(selectedSection.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(NinaTheme.muted)
                }

                Spacer()

                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.black))
                    .foregroundStyle(NinaTheme.muted)
                    .frame(width: 28, height: 28)
                    .background(NinaTheme.field, in: Circle())
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(NinaTheme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(NinaTheme.cardStroke, lineWidth: 1)
            )
            .cardShadow()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Selecionar seção de tarefas")
        .accessibilityValue(selectedSection.title)
        .accessibilityHint("Abre a lista de seções")
    }
}

private struct TaskSectionEmptyState: View {
    var section: TaskSectionDescriptor
    var addTask: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SoftCard(padding: 16) {
                HStack(spacing: 12) {
                    IconBubble(systemName: section.systemImage, tone: section.tone, size: 42)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Nenhuma tarefa ou semente ainda")
                            .font(.headline.weight(.heavy))
                            .foregroundStyle(NinaTheme.ink)

                        Text("Tudo limpo por enquanto.")
                            .font(.subheadline)
                            .foregroundStyle(NinaTheme.muted)
                    }
                }
            }

            PrimaryCapsuleButton(
                title: "Adicionar",
                systemName: "plus.circle.fill",
                action: addTask
            )
            .accessibilityLabel(section.addAccessibilityLabel)
        }
    }
}

private struct TaskSectionIconOption: Identifiable {
    var id: String { systemName }
    var systemName: String
    var accessibilityTitle: String
}

private struct TaskSectionCreatorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var selectedSymbolName = "list.bullet.rectangle.fill"
    @FocusState private var isTitleFocused: Bool
    var createSection: (String, String) -> Void

    private static let iconOptions = [
        TaskSectionIconOption(systemName: "list.bullet.rectangle.fill", accessibilityTitle: "Lista"),
        TaskSectionIconOption(systemName: "house.fill", accessibilityTitle: "Casa"),
        TaskSectionIconOption(systemName: "briefcase.fill", accessibilityTitle: "Trabalho"),
        TaskSectionIconOption(systemName: "backpack.fill", accessibilityTitle: "Escola"),
        TaskSectionIconOption(systemName: "pawprint.fill", accessibilityTitle: "Pet"),
        TaskSectionIconOption(systemName: "creditcard.fill", accessibilityTitle: "Contas"),
        TaskSectionIconOption(systemName: "cross.case.fill", accessibilityTitle: "Saúde"),
        TaskSectionIconOption(systemName: "fork.knife", accessibilityTitle: "Comida"),
        TaskSectionIconOption(systemName: "cart.fill", accessibilityTitle: "Compras"),
        TaskSectionIconOption(systemName: "calendar", accessibilityTitle: "Calendário"),
        TaskSectionIconOption(systemName: "figure.2.and.child.holdinghands", accessibilityTitle: "Família"),
        TaskSectionIconOption(systemName: "sparkles", accessibilityTitle: "Outros")
    ]

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SectionTitle(
                    title: "Nova seção",
                    subtitle: "Escola, pet, contas ou qualquer rotina."
                )

                SoftCard {
                    TextField("Nome da seção", text: $title)
                        .font(.headline)
                        .textFieldStyle(.plain)
                        .submitLabel(.done)
                        .focused($isTitleFocused)
                }

                SoftCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Ícone da seção")
                            .font(.subheadline.weight(.heavy))
                            .foregroundStyle(NinaTheme.muted)

                        LazyVGrid(
                            columns: Array(
                                repeating: GridItem(.flexible(), spacing: 10),
                                count: 4
                            ),
                            spacing: 10
                        ) {
                            ForEach(Self.iconOptions) { option in
                                let isSelected = selectedSymbolName == option.systemName

                                Button {
                                    Haptics.selection()
                                    selectedSymbolName = option.systemName
                                } label: {
                                    Image(systemName: option.systemName)
                                        .font(.title3.weight(.bold))
                                        .foregroundStyle(isSelected ? .white : NinaTheme.ink)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 46)
                                        .background(
                                            isSelected ? NinaTheme.mint : NinaTheme.field,
                                            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        )
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(option.accessibilityTitle)
                                .accessibilityValue(isSelected ? "Selecionado" : "Não selecionado")
                            }
                        }
                    }
                }

                PrimaryCapsuleButton(title: "Criar seção", systemName: "plus.circle.fill") {
                    createSection(trimmedTitle, selectedSymbolName)
                    dismiss()
                }
                .disabled(trimmedTitle.isEmpty)
                .opacity(trimmedTitle.isEmpty ? 0.5 : 1)
            }
            .padding(18)
        }
        .scrollDismissesKeyboard(.interactively)
        .ninaSheetBackground()
        .navigationTitle("Nova seção")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Fechar") {
                    Haptics.selection()
                    dismiss()
                }
            }
        }
        .task {
            await Task.yield()
            isTitleFocused = true
        }
    }
}

private struct ShoppingEmptyState: View {
    var addItem: () -> Void

    var body: some View {
        SoftCard(padding: 18) {
            HStack(spacing: 12) {
                IconBubble(systemName: "cart.fill", tone: .amber, size: 40)

                VStack(alignment: .leading, spacing: 4) {
                    Text("A lista está vazia")
                        .font(.headline.weight(.black))
                        .foregroundStyle(NinaTheme.ink)

                    Text("Some o que faltar em casa. A Nina também pode montar a lista com você.")
                        .font(.subheadline)
                        .foregroundStyle(NinaTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            PrimaryCapsuleButton(title: "Adicionar item", systemName: "plus", action: addItem)
        }
    }
}

private struct ShoppingRow: View {
    @Environment(AppStore.self) private var store
    var item: ShoppingItem
    var tone: MemberTone = .amber

    var body: some View {
        SoftCard(padding: 14) {
            HStack(spacing: 12) {
                Button {
                    if item.isChecked {
                        Haptics.selection()
                    } else {
                        Haptics.success()
                    }
                    store.toggleShoppingItem(item)
                } label: {
                    Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(item.isChecked ? NinaTheme.mint : NinaTheme.muted.opacity(0.45))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.isChecked ? "Marcar como pendente" : "Marcar como comprado")

                IconBubble(systemName: "cart.fill", tone: tone, size: 40)

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.headline.weight(.heavy))
                        .foregroundStyle(NinaTheme.ink)
                        .strikethrough(item.isChecked)

                    Text(item.amount.isEmpty ? "Sem quantidade" : item.amount)
                        .font(.subheadline)
                        .foregroundStyle(NinaTheme.muted)
                }

                Spacer()

                Text(item.owner)
                    .font(.caption.weight(.black))
                    .foregroundStyle(tone.color)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(tone.softColor, in: Capsule())
            }
        }
    }
}

#Preview {
    NavigationStack {
        TasksView()
            .environment(AppStore())
            .environment(RouterPath())
    }
}
