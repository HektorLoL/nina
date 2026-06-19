import SwiftUI

struct HouseView: View {
    @Environment(AppStore.self) private var store
    @Environment(RouterPath.self) private var router
    @State private var isEditingHouse = false
    @State private var draftHouseName = ""
    @State private var isHouseDraftValid = true
    @State private var isRotatingInvite = false
    @State private var isShowingRotationAlert = false
    @State private var isShowingDeleteChatAlert = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                houseHeader
                if isEditingHouse {
                    houseEditSection
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                inviteSecuritySection
                membersSection
                memorySection
                insightsSection
            }
            .padding(18)
            .padding(.bottom, 104)
        }
        .scrollDismissesKeyboard(.interactively)
        .ninaScreenBackground()
        .navigationTitle("Casa")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: syncHouseDrafts)
        .onChange(of: draftHouseName) { _, _ in
            validateDrafts()
        }
        .alert("Gerar um novo convite?", isPresented: $isShowingRotationAlert) {
            Button("Cancelar", role: .cancel) {}
            Button("Gerar novo", role: .destructive) {
                rotateInvite()
            }
        } message: {
            Text("O link atual deixará de funcionar imediatamente.")
        }
        .alert("Apagar seu histórico com a Nina?", isPresented: $isShowingDeleteChatAlert) {
            Button("Cancelar", role: .cancel) {}
            Button("Apagar histórico", role: .destructive) {
                Task {
                    _ = await store.deleteNinaChatHistory()
                }
            }
        } message: {
            Text("Isso apaga somente a sua conversa privada. Tarefas e memórias já confirmadas continuam na casa.")
        }
    }

    private var houseHeader: some View {
        SoftCard(padding: 18) {
            HStack(alignment: .center, spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(NinaTheme.mint.opacity(0.16))
                        .frame(width: 82, height: 82)

                    Image(systemName: "house.and.flag.fill")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundStyle(NinaTheme.mint)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(store.familyGroup.name)
                        .font(.title2.weight(.black))
                        .foregroundStyle(NinaTheme.ink)

                    Text(store.familyLimitLabel)
                        .font(.subheadline)
                        .foregroundStyle(NinaTheme.muted)
                }
            }

            HStack(spacing: 10) {
                PrimaryCapsuleButton(title: "Convidar família", systemName: "link") {
                    Haptics.lightImpact()
                    router.presentedSheet = .inviteFamily
                }

                if store.canManageFamily {
                    CircleEditButton(isActive: isEditingHouse) {
                        toggleHouseEditor()
                    }
                }
            }
        }
    }

    private var houseEditSection: some View {
        SoftCard(padding: 18) {
            SectionTitle(title: "Editar casa", subtitle: "Ajuste o nome que aparece para sua família.")

            VStack(spacing: 10) {
                HouseEditField(
                    title: "Nome",
                    systemName: "house.fill",
                    placeholder: "Nome da casa",
                    text: $draftHouseName
                )
            }
            .padding(14)
            .background(NinaTheme.field, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            HStack {
                Label(store.familyLimitLabel, systemImage: "person.2.fill")
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(NinaTheme.muted)

                Spacer()

                Text(store.canInviteMorePeople ? "\(store.remainingFamilySlots) vagas" : "limite cheio")
                    .font(.caption.weight(.black))
                    .foregroundStyle(store.canInviteMorePeople ? NinaTheme.mint : NinaTheme.coral)
            }

            HStack(spacing: 10) {
                HouseEditorActionButton(title: "Cancelar", systemName: "xmark", style: .secondary) {
                    cancelHouseEditing()
                }

                HouseEditorActionButton(title: "Salvar", systemName: "checkmark", style: .primary) {
                    saveHouseChanges()
                }
                .disabled(!isHouseDraftValid)
                .opacity(isHouseDraftValid ? 1 : 0.5)
            }
        }
    }

    private var inviteSecuritySection: some View {
        SoftCard(padding: 18) {
            SectionTitle(
                title: "Convite seguro",
                subtitle: "Compartilhe o link com quem participa da casa."
            )

            HStack(spacing: 12) {
                IconBubble(systemName: "link", tone: .sky, size: 42)

                VStack(alignment: .leading, spacing: 4) {
                    Text(store.familyGroup.inviteCode)
                        .font(.subheadline.weight(.black))
                        .foregroundStyle(NinaTheme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .textSelection(.enabled)

                    Text("Só quem recebe este link consegue pedir entrada.")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(NinaTheme.muted)
                }
            }

            if store.canManageFamily {
                Button {
                    isShowingRotationAlert = true
                } label: {
                    Label(
                        isRotatingInvite ? "Gerando..." : "Gerar novo convite",
                        systemImage: "arrow.triangle.2.circlepath"
                    )
                    .font(.subheadline.weight(.black))
                    .foregroundStyle(NinaTheme.coral)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(NinaTheme.coral.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(isRotatingInvite || store.isSyncingHome)
            }
        }
    }

    private var membersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Participantes", subtitle: "Limite: 8 pessoas na casa. A Nina não ocupa vaga.")

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(store.familyGroup.members) { member in
                    Button {
                        Haptics.lightImpact()
                        router.presentedSheet = .member(member.id)
                    } label: {
                        SoftCard(padding: 14) {
                            HStack(spacing: 10) {
                                MemberAvatar(member: member, size: 46)

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(member.name)
                                        .font(.headline.weight(.black))
                                        .foregroundStyle(NinaTheme.ink)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)

                                    Text(member.relationship)
                                        .font(.caption.weight(.heavy))
                                        .foregroundStyle(member.tone.color)
                                        .lineLimit(1)
                                }
                            }

                            Text("\(member.taskCount) tarefas")
                                .font(.caption.weight(.heavy))
                                .foregroundStyle(NinaTheme.muted)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var memorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(
                title: "Memórias da Nina",
                subtitle: "Somente memórias confirmadas por uma pessoa da casa."
            )

            if store.ninaMemories.isEmpty {
                Text("Nenhuma memória confirmada ainda.")
                    .font(.subheadline)
                    .foregroundStyle(NinaTheme.muted)
                    .padding(.horizontal, 4)
            } else {
                ForEach(store.ninaMemories) { memory in
                    NinaMemoryCard(memory: memory)
                }
            }

            Button(role: .destructive) {
                isShowingDeleteChatAlert = true
            } label: {
                Label("Apagar meu histórico com a Nina", systemImage: "trash")
                    .font(.caption.weight(.black))
            }
            .buttonStyle(.plain)
            .foregroundStyle(NinaTheme.coral)
            .padding(.top, 2)
        }
    }
}

private struct NinaMemoryCard: View {
    @Environment(AppStore.self) private var store
    var memory: NinaMemory

    @State private var title: String
    @State private var draftBody: String
    @State private var visibility: NinaMemoryVisibility
    @State private var isEditing = false
    @State private var isSaving = false
    @State private var isShowingDeleteAlert = false

    init(memory: NinaMemory) {
        self.memory = memory
        _title = State(initialValue: memory.title)
        _draftBody = State(initialValue: memory.body)
        _visibility = State(initialValue: memory.visibility)
    }

    var body: some View {
        SoftCard(padding: 14) {
            HStack(alignment: .top, spacing: 12) {
                IconBubble(
                    systemName: visibility == .shared ? "house.fill" : "lock.fill",
                    tone: visibility == .shared ? .sky : .mint,
                    size: 40
                )

                VStack(alignment: .leading, spacing: 5) {
                    if isEditing {
                        TextField("Título", text: $title)
                            .font(.subheadline.weight(.black))
                        TextField("Memória", text: $draftBody, axis: .vertical)
                            .font(.caption)
                            .lineLimit(2...5)
                    } else {
                        Text(memory.title)
                            .font(.subheadline.weight(.black))
                            .foregroundStyle(NinaTheme.ink)

                        Text(memory.body)
                            .font(.caption)
                            .foregroundStyle(NinaTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Label(visibility.title, systemImage: visibility == .shared ? "person.2.fill" : "person.fill")
                        .font(.caption2.weight(.black))
                        .foregroundStyle(visibility == .shared ? NinaTheme.sky : NinaTheme.mint)
                }
            }

            if store.canEditMemory(memory) {
                HStack(spacing: 12) {
                    if isEditing {
                        Picker("Privacidade", selection: $visibility) {
                            ForEach(NinaMemoryVisibility.allCases, id: \.self) { option in
                                Text(option.title).tag(option)
                            }
                        }
                        .pickerStyle(.menu)

                        Button("Salvar") {
                            save()
                        }
                        .font(.caption.weight(.black))
                        .foregroundStyle(NinaTheme.mint)
                    } else {
                        Button("Editar") {
                            isEditing = true
                        }
                        .font(.caption.weight(.black))
                        .foregroundStyle(NinaTheme.sky)
                    }

                    Spacer()

                    Button(role: .destructive) {
                        isShowingDeleteAlert = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(NinaTheme.coral)
                    .accessibilityLabel("Apagar memória")
                }
            }
        }
        .disabled(isSaving)
        .alert("Apagar esta memória?", isPresented: $isShowingDeleteAlert) {
            Button("Cancelar", role: .cancel) {}
            Button("Apagar", role: .destructive) {
                Task {
                    _ = await store.deleteMemory(memory)
                }
            }
        } message: {
            Text("A Nina não usará mais esta memória em conversas futuras.")
        }
    }

    private func save() {
        isSaving = true
        var updated = memory
        updated.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.body = draftBody.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.visibility = visibility

        Task {
            if await store.updateMemory(updated) {
                isEditing = false
            }
            isSaving = false
        }
    }
}

private extension HouseView {
    var insightsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Insights familiares", subtitle: "Dados simples para conversas melhores.")

            ForEach(store.insights) { insight in
                InsightCard(insight: insight)
            }
        }
    }

    private func validateDrafts() {
        isHouseDraftValid = !draftHouseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func toggleHouseEditor() {
        if isEditingHouse {
            cancelHouseEditing()
        } else {
            Haptics.selection()
            syncHouseDrafts()
            withAnimation(.interactiveSpring(response: 0.34, dampingFraction: 0.88)) {
                isEditingHouse = true
            }
        }
    }

    private func syncHouseDrafts() {
        draftHouseName = store.familyGroup.name
        validateDrafts()
    }

    private func cancelHouseEditing() {
        Haptics.selection()
        syncHouseDrafts()
        withAnimation(.interactiveSpring(response: 0.34, dampingFraction: 0.88)) {
            isEditingHouse = false
        }
    }

    private func saveHouseChanges() {
        guard isHouseDraftValid else { return }

        Task {
            if await store.updateFamilyGroup(name: draftHouseName) {
                Haptics.success()
                syncHouseDrafts()
                withAnimation(.interactiveSpring(response: 0.34, dampingFraction: 0.88)) {
                    isEditingHouse = false
                }
            }
        }
    }

    private func rotateInvite() {
        guard !isRotatingInvite else { return }
        isRotatingInvite = true

        Task {
            let didRotate = await store.rotateFamilyInvite()
            isRotatingInvite = false

            if didRotate {
                Haptics.success()
            }
        }
    }
}

private struct CircleEditButton: View {
    var isActive: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isActive ? "xmark" : "pencil")
                .font(.system(size: 18, weight: .black))
                .foregroundStyle(isActive ? .white : NinaTheme.mint)
                .frame(width: 52, height: 52)
                .background(isActive ? NinaTheme.mint : NinaTheme.field, in: Circle())
                .overlay(
                    Circle()
                        .stroke(isActive ? NinaTheme.mint.opacity(0.4) : NinaTheme.line.opacity(0.8), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isActive ? "Fechar edição da casa" : "Editar casa")
    }
}

private struct HouseEditField: View {
    var title: String
    var systemName: String
    var placeholder: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 12) {
            Label(title, systemImage: systemName)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(NinaTheme.muted)

            TextField(placeholder, text: $text)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(NinaTheme.ink)
                .multilineTextAlignment(.trailing)
                .textFieldStyle(.plain)
                .lineLimit(1)
        }
        .padding(.vertical, 2)
    }
}

private enum HouseEditorActionStyle {
    case primary
    case secondary
}

private struct HouseEditorActionButton: View {
    var title: String
    var systemName: String
    var style: HouseEditorActionStyle
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemName)
                .font(.headline.weight(.heavy))
                .foregroundStyle(foregroundColor)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(backgroundColor, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var foregroundColor: Color {
        switch style {
        case .primary: .white
        case .secondary: NinaTheme.muted
        }
    }

    private var backgroundColor: Color {
        switch style {
        case .primary: NinaTheme.mint
        case .secondary: NinaTheme.line.opacity(0.35)
        }
    }
}

private struct MemoryLine: View {
    var symbolName: String
    var text: String
    var tone: MemberTone

    var body: some View {
        SoftCard(padding: 14) {
            HStack(spacing: 12) {
                IconBubble(systemName: symbolName, tone: tone, size: 40)

                Text(text)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(NinaTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct InsightCard: View {
    var insight: HouseholdInsight

    var body: some View {
        SoftCard {
            HStack(alignment: .top, spacing: 12) {
                IconBubble(systemName: insight.symbolName, tone: insight.tone)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(insight.title)
                            .font(.headline.weight(.black))
                            .foregroundStyle(NinaTheme.ink)

                        Spacer()

                        Text(insight.metric)
                            .font(.headline.weight(.black))
                            .foregroundStyle(insight.tone.color)
                    }

                    Text(insight.message)
                        .font(.subheadline)
                        .foregroundStyle(NinaTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if insight.title.contains("Carga") {
                WorkloadBars()
            }
        }
    }
}

#Preview {
    NavigationStack {
        HouseView()
            .environment(AppStore())
            .environment(RouterPath())
    }
}
