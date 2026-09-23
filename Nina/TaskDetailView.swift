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
        .alert(task.kind == .seed ? "Apagar esta semente?" : "Apagar esta tarefa?", isPresented: $isConfirmingDelete) {
            Button("Apagar", role: .destructive) {
                store.deleteTask(task.id)
                dismiss()
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Some para toda a casa. Não dá para desfazer.")
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
                    .frame(width: 44, height: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Voltar")

            Spacer()

            Button {
                Haptics.lightImpact()
                router.presentedSheet = .editTask(task.id)
            } label: {
                Text("Editar")
                    .ninaText(.label, NinaTheme.ink, weight: .semibold)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
    }

    private var titleBlock: some View {
        HStack(alignment: .top, spacing: 14) {
            Button {
                task.isDone ? Haptics.selection() : Haptics.success()
                store.toggleTask(task)
            } label: {
                NinaCheckbox(isOn: task.isDone, isOverdue: isOverdue, size: 26)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.completionActionTitle)

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
            metaRow(
                "Quando",
                value: task.kind == .seed ? "Plante depois" : task.effectiveDueLabel(),
                isLate: isOverdue
            ) {
                metaGlyph("calendar")
            }
            NinaDivider(inset: 36)

            if task.kind == .task, task.recurrence != .none {
                metaRow("Repete", value: task.recurrence.title) {
                    metaGlyph("repeat")
                }
                NinaDivider(inset: 36)
            }

            metaRow("Dono", value: HouseholdWorkload.isSharedOwner(task.owner) ? "Sem dono" : task.owner) {
                // Unassigned work is credited to the house and never given a face.
                if let owner {
                    MemberAvatar(initials: owner.name.ninaInitials, tone: owner.tone, size: 24)
                } else {
                    metaGlyph("person")
                }
            }
            NinaDivider(inset: 36)

            metaRow("Categoria", value: task.category.title) {
                metaGlyph(task.category.symbolName)
            }

            // What the editor asks for must be readable somewhere afterwards.
            if task.priority != .normal {
                NinaDivider(inset: 36)
                metaRow("Prioridade", value: task.priority.title) {
                    metaGlyph("flag")
                }
            }

            if task.kind == .task, task.dueAt != nil {
                NinaDivider(inset: 36)
                metaRow("Aviso", value: task.reminderLead.title) {
                    metaGlyph("bell")
                }
            }
        }
    }

    private func metaRow<Leading: View>(
        _ label: String,
        value: String,
        isLate: Bool = false,
        @ViewBuilder leading: () -> Leading
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            leading()
                .frame(width: 24)
            Text(value)
                .ninaText(.label, isLate ? NinaTheme.terracotta : NinaTheme.ink, weight: isLate ? .semibold : .regular)
            Spacer(minLength: 0)
        }
        .frame(minHeight: 46)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(isLate ? "Atrasada, \(value)" : value)
    }

    private func metaGlyph(_ systemName: String) -> some View {
        CategoryGlyph(systemName: systemName, size: 17, tint: NinaTheme.muted)
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
        if task.createdBy.caseInsensitiveCompare(assistant) == .orderedSame {
            return "Veio de uma conversa com a Nina."
        }
        // "Manual" is the sentinel addTask stamps when nobody is named. It is not
        // a person, and rendering it as one invents a housemate.
        let isPerson = store.familyGroup.members.contains {
            $0.name.caseInsensitiveCompare(task.createdBy) == .orderedSame
        }
        guard isPerson else { return "Escrita à mão." }
        if let me = store.currentFamilyMember, me.name.caseInsensitiveCompare(task.createdBy) == .orderedSame {
            return "Você colocou isto aqui."
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
                    actionChip("Passar para \(otherAdult.name.firstWord)") {
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
                    title: task.completionActionTitle,
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
