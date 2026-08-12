import SwiftUI

// The screen that did not exist: tapping a task opened an edit form, even for a
// viewer who cannot edit. `createdBy` was captured on every task and rendered
// nowhere reachable, so "why is this here?" had to become a conversation.
struct TaskDetailView: View {
    @Environment(AppStore.self) private var store
    @Environment(RouterPath.self) private var router
    @Environment(\.dismiss) private var dismiss

    let task: TaskItem

    @State private var isConfirmingDelete = false

    private var isOverdue: Bool { task.isOverdue() }

    private var owner: HouseholdMember? {
        store.familyGroup.members.first { $0.id == task.ownerMemberID }
    }

    private var otherAdult: HouseholdMember? {
        store.familyGroup.members.first {
            $0.role == .adult && $0.id != task.ownerMemberID && $0.id != store.currentFamilyMember?.id
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    titleBlock
                    metadata
                    provenance
                    quickActions
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 28)
            }

            footer
        }
        .ninaScreenBackground()
        .alert("Apagar esta tarefa?", isPresented: $isConfirmingDelete) {
            Button("Apagar", role: .destructive) {
                store.deleteTask(task.id)
                dismiss()
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Ela sai para todo mundo da casa. Não dá para desfazer.")
        }
    }

    private var header: some View {
        HStack {
            Button {
                Haptics.selection()
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(NinaTheme.ink)
                    .frame(width: 40, height: 40, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Voltar")

            Spacer()

            Button {
                Haptics.lightImpact()
                router.presentedSheet = .editTask(task.id)
            } label: {
                Text("Editar")
                    .ninaText(.label, NinaTheme.cobalt, weight: .semibold)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
    }

    private var titleBlock: some View {
        HStack(alignment: .top, spacing: 14) {
            Button {
                Haptics.selection()
                store.toggleTask(task)
            } label: {
                NinaCheckbox(isOn: task.isDone, isOverdue: isOverdue, size: 26)
            }
            .buttonStyle(.plain)
            .padding(.top, 6)

            VStack(alignment: .leading, spacing: 6) {
                Text(task.title).ninaText(.title)
                if !task.subtitle.isEmpty {
                    Text(task.subtitle).ninaText(.label, NinaTheme.muted)
                }
            }
        }
    }

    private var metadata: some View {
        VStack(spacing: 0) {
            metaRow("Quando") {
                Text(task.kind == .seed ? "Sem data — plante quando quiser" : task.dueLabel)
                    .ninaText(.label, isOverdue ? NinaTheme.terracotta : NinaTheme.ink, weight: isOverdue ? .semibold : .regular)
            }
            NinaDivider(inset: 0)

            if task.kind == .task {
                metaRow("Repete") {
                    Text(task.recurrence.title).ninaText(.label)
                }
                NinaDivider(inset: 0)
            }

            metaRow("Dono") {
                HStack(spacing: 8) {
                    if let owner {
                        MemberAvatar(initials: owner.name.ninaInitials, tone: owner.tone, size: 24)
                    }
                    // Unassigned work is credited to the house and never given a face.
                    Text(task.owner).ninaText(.label)
                }
            }
            NinaDivider(inset: 0)

            metaRow("Categoria") {
                HStack(spacing: 8) {
                    CategoryGlyph(systemName: task.category.symbolName, size: 17)
                    Text(task.category.title).ninaText(.label)
                }
            }
        }
    }

    private func metaRow<V: View>(_ label: String, @ViewBuilder value: () -> V) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(label)
                .ninaText(.caption, NinaTheme.muted)
                .frame(width: 92, alignment: .leading)
            value()
            Spacer(minLength: 0)
        }
        .frame(minHeight: 46)
    }

    @ViewBuilder
    private var provenance: some View {
        if !task.createdBy.isEmpty {
            HStack(spacing: 10) {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(NinaTheme.faint)
                Text(provenanceLine).ninaText(.caption, NinaTheme.muted)
            }
        }
    }

    // Nina never appears as the author of anything: a confirmed proposal is a
    // human's act, and crediting her would be a past-tense claim she cannot make.
    private var provenanceLine: String {
        let assistant = store.familyGroup.members.first { $0.role == .assistant }?.name ?? "Nina"
        guard task.createdBy.caseInsensitiveCompare(assistant) != .orderedSame else {
            return "Veio de uma conversa com a Nina."
        }
        return "\(task.createdBy) colocou isto aqui."
    }

    private var quickActions: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if task.kind == .task {
                    actionChip("Remarcar") {
                        router.presentedSheet = .editTask(task.id)
                    }
                }

                if let otherAdult {
                    actionChip("Passar pro \(otherAdult.name.firstWord)") {
                        store.updateTask(
                            id: task.id,
                            title: task.title,
                            subtitle: task.subtitle,
                            owner: otherAdult.name,
                            ownerMemberID: otherAdult.id,
                            dueLabel: task.dueLabel,
                            dueAt: task.dueAt,
                            category: task.category,
                            priority: task.priority
                        )
                    }
                }

                if task.kind == .task {
                    actionChip("Virar semente") {
                        store.updateTask(
                            id: task.id,
                            title: task.title,
                            subtitle: task.subtitle,
                            owner: task.owner,
                            ownerMemberID: task.ownerMemberID,
                            dueLabel: "Sem data",
                            dueAt: nil,
                            category: task.category,
                            priority: task.priority,
                            kind: .seed
                        )
                    }
                } else {
                    actionChip("Plantar") {
                        router.presentedSheet = .plantSeed(task.id)
                    }
                }
            }
        }
        .scrollClipDisabled()
    }

    private func actionChip(_ title: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.lightImpact()
            action()
        } label: {
            NinaChip(text: title)
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        VStack(spacing: 6) {
            if task.kind == .task {
                NinaButton(
                    title: task.isDone ? "Marcar como não feita" : "Marcar como feita",
                    systemName: task.isDone ? "arrow.uturn.backward" : "checkmark",
                    fillsWidth: true
                ) {
                    // Completing fires success; un-completing is only a selection.
                    // The asymmetry is deliberate: closing something is the event.
                    task.isDone ? Haptics.selection() : Haptics.success()
                    store.toggleTask(task)
                }
            }

            NinaButton(title: "Apagar", kind: .quiet) {
                Haptics.warning()
                isConfirmingDelete = true
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }
}

extension String {
    var ninaInitials: String {
        let parts = split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first }.map(String.init)
        return letters.joined().uppercased()
    }

    var firstWord: String {
        String(split(separator: " ").first ?? "")
    }
}
