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
        let tasks = store.tasks(in: sectionID)

        return TimelineView(.periodic(from: .now, by: 60)) { context in
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(title: section.title, subtitle: section.subtitle)

                if tasks.isEmpty {
                    TaskSectionEmptyState(section: section) {
                        Haptics.lightImpact()
                        router.presentedSheet = section.addDestination
                    }
                } else {
                    ForEach(tasks) { task in
                        TaskCard(
                            task: task,
                            isMarkedComplete: task.isDone,
                            onToggle: toggleTask,
                            referenceDate: context.date
                        )
                    }
                }
            }
        }
    }

    private var shoppingList: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Lista de compras", subtitle: "\(store.pendingShoppingItems.count) itens pendentes")

            ForEach(store.shoppingItems) { item in
                ShoppingRow(item: item)
                    .onTapGesture {
                        Haptics.lightImpact()
                        router.presentedSheet = .editShoppingItem(item.id)
                    }
            }
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

private struct ShoppingRow: View {
    @Environment(AppStore.self) private var store
    var item: ShoppingItem

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

                IconBubble(systemName: "cart.fill", tone: .amber, size: 40)

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
                    .foregroundStyle(NinaTheme.amber)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(MemberTone.amber.softColor, in: Capsule())
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
