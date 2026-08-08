import SwiftUI

enum MemberEditorMode: Hashable {
    case addProfile
    case edit(UUID)
}

struct MemberEditorSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let mode: MemberEditorMode

    @State private var name = ""
    @State private var relationship = ""
    @State private var householdRole: HouseholdRole = .child
    @State private var permissionRole: FamilyPermissionRole = .member
    @State private var tone: MemberTone = .amber
    @State private var memoryNote = ""
    @State private var hasBirthDate = false
    @State private var birthDate = Date()
    @State private var petSpecies = ""
    @State private var petBreed = ""
    @State private var didLoad = false
    @State private var isSaving = false
    @State private var isShowingRemoveConfirmation = false

    private var member: HouseholdMember? {
        guard case .edit(let id) = mode else { return nil }
        return store.familyGroup.members.first { $0.id == id }
    }

    private var canEdit: Bool {
        switch mode {
        case .addProfile:
            store.canManageFamily && store.canInviteMorePeople
        case .edit:
            member.map(store.canEditFamilyMember) == true
        }
    }

    private var canSave: Bool {
        canEdit && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Group {
            if case .edit = mode, member == nil {
                ContentUnavailableView(
                    "Participante indisponível",
                    systemImage: "person.crop.circle.badge.questionmark",
                    description: Text("Este perfil não faz mais parte da casa.")
                )
            } else {
                editorContent
            }
        }
        .ninaSheetBackground()
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Fechar") {
                    dismiss()
                }
            }
        }
        .onAppear(perform: loadIfNeeded)
        .alert("Remover esta pessoa?", isPresented: $isShowingRemoveConfirmation) {
            Button("Cancelar", role: .cancel) {}
            Button("Remover", role: .destructive) {
                removeMember()
            }
        } message: {
            Text("A pessoa perderá acesso à casa. Tarefas existentes continuam no histórico.")
        }
    }

    private var editorContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                identitySection
                profileSection
                permissionsSection

                if canEdit {
                    PrimaryCapsuleButton(
                        title: isSaving ? "Salvando..." : saveButtonTitle,
                        systemName: "checkmark"
                    ) {
                        save()
                    }
                    .disabled(!canSave || isSaving)
                    .opacity(canSave && !isSaving ? 1 : 0.5)
                }

                if let member, store.canRemoveFamilyMember(member) {
                    Button(role: .destructive) {
                        Haptics.warning()
                        isShowingRemoveConfirmation = true
                    } label: {
                        Label("Remover da casa", systemImage: "person.fill.xmark")
                            .font(.headline.weight(.black))
                            .foregroundStyle(NinaTheme.coral)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(NinaTheme.coral.opacity(0.1), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(isSaving)
                }

                if let error = store.syncErrorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.heavy))
                        .foregroundStyle(NinaTheme.coral)
                }
            }
            .padding(18)
            .padding(.bottom, 24)
        }
    }

    private var header: some View {
        SoftCard(padding: 18) {
            HStack(spacing: 16) {
                MemberAvatar(member: draftMember, size: 64)

                VStack(alignment: .leading, spacing: 5) {
                    Text(name.isEmpty ? defaultName : name)
                        .font(.title2.weight(.black))
                        .foregroundStyle(NinaTheme.ink)

                    Label(statusTitle, systemImage: statusSymbol)
                        .font(.caption.weight(.black))
                        .foregroundStyle(tone.color)
                }
            }
        }
    }

    private var identitySection: some View {
        SoftCard(padding: 16) {
            SectionTitle(
                title: "Perfil",
                subtitle: mode == .addProfile
                    ? "Crie um perfil para uma criança ou pet da casa."
                    : "Mantenha os dados usados nas tarefas e cuidados."
            )

            VStack(spacing: 12) {
                MemberEditorField(title: "Nome", systemName: "person.fill", text: $name)
                    .disabled(member?.identityState == .claimed)

                Divider()

                MemberEditorField(
                    title: "Relação",
                    systemName: "heart.fill",
                    placeholder: "Filha, filho, cachorro...",
                    text: $relationship
                )

                if member?.identityState != .claimed {
                    Divider()

                    Picker("Tipo de perfil", selection: $householdRole) {
                        ForEach(availableHouseholdRoles) { role in
                            Label(role.title, systemImage: role.symbolName).tag(role)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(NinaTheme.ink)
                    .onChange(of: householdRole) { oldValue, newValue in
                        updateDefaultRelationship(from: oldValue, to: newValue)
                        if newValue == .pet, tone == .amber {
                            tone = .lavender
                        }
                    }
                }

                Divider()

                Picker("Cor", selection: $tone) {
                    ForEach(MemberTone.allCases) { option in
                        Text(toneTitle(option)).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .tint(tone.color)
            }
            .disabled(!canEdit)
        }
    }

    @ViewBuilder
    private var profileSection: some View {
        if householdRole == .child || householdRole == .pet {
            SoftCard(padding: 16) {
                SectionTitle(
                    title: householdRole == .pet ? "Cuidados do pet" : "Dados da criança",
                    subtitle: "Informações simples para organizar rotinas com contexto."
                )

                Toggle("Salvar data de nascimento", isOn: $hasBirthDate)
                    .font(.subheadline.weight(.bold))
                    .tint(NinaTheme.mint)

                if hasBirthDate {
                    DatePicker(
                        "Nascimento",
                        selection: $birthDate,
                        in: ...Date(),
                        displayedComponents: .date
                    )
                }

                if householdRole == .pet {
                    Divider()
                    MemberEditorField(
                        title: "Espécie",
                        systemName: "pawprint.fill",
                        placeholder: "Cachorro, gato...",
                        text: $petSpecies
                    )
                    Divider()
                    MemberEditorField(
                        title: "Raça",
                        systemName: "tag.fill",
                        placeholder: "Opcional",
                        text: $petBreed
                    )
                }

                Divider()

                TextField(
                    householdRole == .pet ? "Rotina, alimentação e cuidados" : "Escola, rotina e observações",
                    text: $memoryNote,
                    axis: .vertical
                )
                .font(.subheadline.weight(.semibold))
                .lineLimit(3...6)
            }
            .disabled(!canEdit)
        } else if member != nil {
            SoftCard(padding: 16) {
                SectionTitle(title: "Contexto", subtitle: "Observação compartilhada com a casa.")

                TextField("Observação", text: $memoryNote, axis: .vertical)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(3...6)
            }
            .disabled(!canEdit)
        }
    }

    @ViewBuilder
    private var permissionsSection: some View {
        if let member, member.role != .assistant {
            SoftCard(padding: 16) {
                SectionTitle(title: "Permissões", subtitle: permissionRole.summary)

                HStack(spacing: 12) {
                    IconBubble(systemName: permissionRole.symbolName, tone: permissionTone, size: 42)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(permissionRole.title)
                            .font(.headline.weight(.black))
                            .foregroundStyle(NinaTheme.ink)

                        Text(member.identityState == .claimed ? "Conta conectada" : "Perfil sem acesso ao app")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(NinaTheme.muted)
                    }

                    Spacer()

                    if store.canChangePermissionRole(for: member) {
                        Picker("Permissão", selection: $permissionRole) {
                            Text(FamilyPermissionRole.admin.title).tag(FamilyPermissionRole.admin)
                            Text(FamilyPermissionRole.member.title).tag(FamilyPermissionRole.member)
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                }
            }
        }
    }

    private var draftMember: HouseholdMember {
        HouseholdMember(
            id: member?.id ?? UUID(),
            userID: member?.userID,
            name: name.isEmpty ? defaultName : name,
            relationship: relationship,
            role: householdRole,
            permissionRole: permissionRole,
            identityState: member?.identityState ?? .unclaimed,
            tone: tone,
            taskCount: member?.taskCount ?? 0,
            memoryNote: memoryNote,
            birthDate: hasBirthDate ? birthDate : nil,
            petSpecies: householdRole == .pet ? petSpecies : "",
            petBreed: householdRole == .pet ? petBreed : ""
        )
    }

    private var availableHouseholdRoles: [HouseholdRole] {
        switch mode {
        case .addProfile:
            [.child, .pet]
        case .edit:
            [.adult, .child, .pet]
        }
    }

    private var navigationTitle: String {
        switch mode {
        case .addProfile: "Novo perfil"
        case .edit: "Participante"
        }
    }

    private var saveButtonTitle: String {
        switch mode {
        case .addProfile: "Adicionar perfil"
        case .edit: "Salvar alterações"
        }
    }

    private var defaultName: String {
        householdRole == .pet ? "Novo pet" : "Nova criança"
    }

    private var statusTitle: String {
        if member?.role == .assistant {
            return "Assistente da casa"
        }
        if member?.identityState == .claimed {
            return permissionRole.title
        }
        return "\(householdRole.title) · perfil da casa"
    }

    private var statusSymbol: String {
        member?.identityState == .claimed ? permissionRole.symbolName : householdRole.symbolName
    }

    private var permissionTone: MemberTone {
        switch permissionRole {
        case .owner: .amber
        case .admin: .sky
        case .member: .mint
        }
    }

    private func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true

        switch mode {
        case .addProfile:
            householdRole = .child
            relationship = "Criança"
            tone = .amber
        case .edit:
            guard let member else { return }
            name = member.name
            relationship = member.relationship
            householdRole = member.role
            permissionRole = member.userID == store.currentFamilyMember?.userID
                ? store.currentPermissionRole
                : member.permissionRole
            tone = member.tone
            memoryNote = member.memoryNote
            if let value = member.birthDate {
                birthDate = value
                hasBirthDate = true
            }
            petSpecies = member.petSpecies
            petBreed = member.petBreed
        }
    }

    private func save() {
        guard canSave, !isSaving else { return }
        isSaving = true

        Task {
            let success: Bool
            switch mode {
            case .addProfile:
                success = await store.addFamilyMember(draftMember)
            case .edit:
                success = await store.updateFamilyMember(draftMember)
            }

            isSaving = false
            if success {
                Haptics.success()
                dismiss()
            }
        }
    }

    private func removeMember() {
        guard let member, !isSaving else { return }
        isSaving = true

        Task {
            let success = await store.removeFamilyMember(member)
            isSaving = false
            if success {
                Haptics.success()
                dismiss()
            }
        }
    }

    private func toneTitle(_ tone: MemberTone) -> String {
        switch tone {
        case .mint: "Verde"
        case .coral: "Coral"
        case .sky: "Azul"
        case .amber: "Âmbar"
        case .lavender: "Lavanda"
        }
    }

    private func updateDefaultRelationship(
        from oldRole: HouseholdRole,
        to newRole: HouseholdRole
    ) {
        let trimmedRelationship = relationship.trimmingCharacters(in: .whitespacesAndNewlines)
        let oldDefault = oldRole == .pet ? "Pet" : "Criança"
        guard trimmedRelationship.isEmpty || trimmedRelationship == oldDefault else { return }

        switch newRole {
        case .pet:
            relationship = "Pet"
        case .child:
            relationship = "Criança"
        case .adult, .assistant:
            break
        }
    }
}

struct PendingJoinRequestCard: View {
    @Environment(AppStore.self) private var store
    let request: FamilyJoinRequest

    @State private var permissionRole: FamilyPermissionRole = .member
    @State private var isWorking = false
    @State private var isShowingDeclineConfirmation = false

    var body: some View {
        SoftCard(padding: 14) {
            HStack(alignment: .top, spacing: 12) {
                IconBubble(systemName: "person.crop.circle.badge.clock", tone: .amber, size: 44)

                VStack(alignment: .leading, spacing: 4) {
                    Text(request.requesterName)
                        .font(.headline.weight(.black))
                        .foregroundStyle(NinaTheme.ink)

                    Text("Pediu entrada \(request.createdAt.formatted(.relative(presentation: .named)))")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(NinaTheme.muted)
                }

                Spacer()

                if store.canChangeFamilyPermissions {
                    Picker("Permissão inicial", selection: $permissionRole) {
                        Text("Participante").tag(FamilyPermissionRole.member)
                        Text("Administrador").tag(FamilyPermissionRole.admin)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
            }

            Text(permissionRole.summary)
                .font(.caption)
                .foregroundStyle(NinaTheme.muted)

            if !store.canInviteMorePeople {
                Label("A casa já atingiu o limite de 8 pessoas.", systemImage: "person.2.slash.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(NinaTheme.coral)
            }

            HStack(spacing: 10) {
                Button {
                    approve()
                } label: {
                    Label(
                        store.canInviteMorePeople ? "Aprovar" : "Casa cheia",
                        systemImage: store.canInviteMorePeople ? "checkmark" : "person.2.slash.fill"
                    )
                        .font(.subheadline.weight(.black))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(
                            store.canInviteMorePeople ? NinaTheme.mint : NinaTheme.muted,
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
                .disabled(!store.canInviteMorePeople)

                Button(role: .destructive) {
                    isShowingDeclineConfirmation = true
                } label: {
                    Label("Recusar", systemImage: "xmark")
                        .font(.subheadline.weight(.black))
                        .foregroundStyle(NinaTheme.coral)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(NinaTheme.coral.opacity(0.1), in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .disabled(isWorking || store.isSyncingHome)
        }
        .alert("Recusar pedido?", isPresented: $isShowingDeclineConfirmation) {
            Button("Cancelar", role: .cancel) {}
            Button("Recusar", role: .destructive) {
                decline()
            }
        } message: {
            Text("\(request.requesterName) não receberá acesso à casa.")
        }
    }

    private func approve() {
        guard !isWorking, store.canInviteMorePeople else { return }
        isWorking = true
        Task {
            let success = await store.approveJoinRequest(request, permissionRole: permissionRole)
            isWorking = false
            if success {
                Haptics.success()
            }
        }
    }

    private func decline() {
        guard !isWorking else { return }
        isWorking = true
        Task {
            let success = await store.declineJoinRequest(request)
            isWorking = false
            if success {
                Haptics.selection()
            }
        }
    }
}

struct PendingHomeApprovalView: View {
    @Environment(AppStore.self) private var store
    @Environment(AuthSessionStore.self) private var authSession
    @Environment(OnboardingStore.self) private var onboardingStore

    @State private var isCancelling = false

    var body: some View {
        VStack(spacing: 18) {
            IconBubble(systemName: "person.crop.circle.badge.clock", tone: .amber, size: 68)

            VStack(spacing: 8) {
                Text("Pedido enviado")
                    .font(.title2.weight(.black))
                    .foregroundStyle(NinaTheme.ink)

                Text("Uma pessoa responsável por \(store.pendingJoinRequest?.familyName ?? "esta casa") precisa aprovar sua entrada.")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(NinaTheme.muted)
                    .multilineTextAlignment(.center)
            }

            if let request = store.pendingJoinRequest {
                SoftCard(padding: 16) {
                    HStack(spacing: 12) {
                        IconBubble(systemName: "house.fill", tone: .mint, size: 42)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(request.familyName)
                                .font(.headline.weight(.black))
                                .foregroundStyle(NinaTheme.ink)

                            Text(request.status.title)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(NinaTheme.amber)
                        }
                    }
                }
            }

            PrimaryCapsuleButton(title: "Atualizar status", systemName: "arrow.clockwise") {
                Task {
                    await store.activateHomeContext(for: authSession.currentUser)
                }
            }
            .disabled(store.isSyncingHome)

            Button("Cancelar pedido") {
                cancelRequest()
            }
            .font(.headline.weight(.bold))
            .foregroundStyle(NinaTheme.coral)
            .disabled(isCancelling || store.isSyncingHome)

            Button("Sair") {
                Task {
                    onboardingStore.cancelReplay()
                    await authSession.signOut()
                }
            }
            .font(.subheadline.weight(.bold))
            .foregroundStyle(NinaTheme.muted)
        }
        .padding(28)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ninaScreenBackground()
    }

    private func cancelRequest() {
        guard !isCancelling else { return }
        isCancelling = true
        Task {
            _ = await store.cancelPendingJoinRequest()
            isCancelling = false
        }
    }
}

struct MemberPermissionBadge: View {
    @Environment(AppStore.self) private var store
    let member: HouseholdMember

    var body: some View {
        Label(badgeTitle, systemImage: badgeSymbol)
            .font(.caption2.weight(.black))
            .foregroundStyle(badgeTone.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(badgeTone.color.opacity(0.11), in: Capsule())
    }

    private var badgeTitle: String {
        if member.role == .assistant {
            return "Nina"
        }
        if member.identityState == .unclaimed {
            return member.role.title
        }
        return effectivePermissionRole.title
    }

    private var badgeSymbol: String {
        member.identityState == .unclaimed ? member.role.symbolName : effectivePermissionRole.symbolName
    }

    private var badgeTone: MemberTone {
        switch effectivePermissionRole {
        case .owner: .amber
        case .admin: .sky
        case .member: member.tone
        }
    }

    private var effectivePermissionRole: FamilyPermissionRole {
        if member.userID == store.currentFamilyMember?.userID {
            return store.currentPermissionRole
        }
        return member.permissionRole
    }
}

private struct MemberEditorField: View {
    let title: String
    let systemName: String
    var placeholder: String = ""
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
        }
    }
}
