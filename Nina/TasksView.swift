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

    private static let shoppingSectionID = "shopping-list"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                TaskSectionChooser(
                    sections: sections,
                    selectedSection: selectedSection,
                    selectSection: selectSection,
                    createSection: presentSectionCreator
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

        return VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: section.title, subtitle: section.subtitle)

            if tasks.isEmpty {
                TaskSectionEmptyState(section: section)
            } else {
                ForEach(tasks) { task in
                    TaskCard(
                        task: task,
                        isMarkedComplete: task.isDone,
                        onToggle: toggleTask
                    )
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

    private func createTaskSection(_ title: String) {
        let section = store.addTaskSection(title: title)

        Haptics.success()
        withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
            selectedSectionID = section.id
        }
    }

    private func taskSectionSubtitle(_ sectionID: String) -> String {
        let counts = store.taskCounts(in: sectionID)
        return "\(counts.open) abertas · \(counts.completed) concluídas"
    }
}

private struct TaskSectionChooser: View {
    var sections: [TaskSectionDescriptor]
    var selectedSection: TaskSectionDescriptor
    var selectSection: (TaskSectionDescriptor) -> Void
    var createSection: () -> Void

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

    var body: some View {
        SoftCard(padding: 16) {
            HStack(spacing: 12) {
                IconBubble(systemName: section.systemImage, tone: section.tone, size: 42)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Nenhuma tarefa ainda")
                        .font(.headline.weight(.heavy))
                        .foregroundStyle(NinaTheme.ink)

                    Text("Tudo limpo por enquanto.")
                        .font(.subheadline)
                        .foregroundStyle(NinaTheme.muted)
                }
            }
        }
    }
}

private struct TaskSectionCreatorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @FocusState private var isTitleFocused: Bool
    var createSection: (String) -> Void

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

                PrimaryCapsuleButton(title: "Criar seção", systemName: "plus.circle.fill") {
                    createSection(trimmedTitle)
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
