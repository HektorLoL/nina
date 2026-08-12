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
    @FocusState private var isNameFocused: Bool

    private var member: HouseholdMember? {
        guard case .edit(let id) = mode else { return nil }
        return store.familyGroup.members.first { $0.id == id }
    }

    private var isAdding: Bool {
        if case .addProfile = mode { true } else { false }
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
        VStack(spacing: 0) {
            header

            if case .edit = mode, member == nil {
                ZeroState(
                    headline: "Essa pessoa não está mais na casa.",
                    body_: "Alguém com permissão pode ter removido o perfil.",
                    showsMark: false
                )
                .padding(.horizontal, 20)
                .padding(.top, 40)
                .frame(maxHeight: .infinity, alignment: .top)
            } else {
                editorContent
            }
        }
        .ninaSheetBackground()
        .toolbar(.hidden, for: .navigationBar)
        .onAppear(perform: loadIfNeeded)
        .task {
            await Task.yield()
            if isAdding {
                isNameFocused = true
            }
        }
        .alert("Remover esta pessoa?", isPresented: $isShowingRemoveConfirmation) {
            Button("Cancelar", role: .cancel) {}
            Button("Remover", role: .destructive) {
                removeMember()
            }
        } message: {
            Text("A pessoa perde o acesso à casa. As tarefas já feitas continuam no histórico.")
        }
    }

    private var header: some View {
        HStack {
            Button {
                Haptics.selection()
                dismiss()
            } label: {
                Text("Fechar")
                    .ninaText(.label, NinaTheme.muted, weight: .semibold)
                    .frame(height: 40, alignment: .leading)
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
    }

    private var editorContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                titleBlock
                identityFields
                classification
                careFields
                permissionBlock
                actions
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .padding(.bottom, 32)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                MemberAvatar(
                    initials: displayName.ninaInitials,
                    tone: tone,
                    size: 56,
                    isAssistant: member?.role == .assistant
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text(displayName).ninaText(.title)
                    Text(statusLine).ninaText(.caption, NinaTheme.muted)
                }
            }

            if isAdding {
                Text(slotLine).ninaText(.caption, NinaTheme.muted)
            }

            if !canEdit {
                Text(lockedReason)
                    .ninaText(.caption, NinaTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var identityFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            MemberField_(title: "Nome") {
                TextField("Como a casa chama", text: $name)
                    .focused($isNameFocused)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
            }
            .disabled(isNameLocked)
            .opacity(isNameLocked ? 0.5 : 1)

            if isNameLocked {
                Text("O nome vem da conta desta pessoa.")
                    .ninaText(.meta, NinaTheme.muted)
                    .padding(.leading, 4)
            }

            MemberField_(title: "Na casa") {
                TextField("Filha, filho, cachorro", text: $relationship)
                    .submitLabel(.done)
            }
        }
        .disabled(!canEdit)
        .opacity(canEdit ? 1 : 0.5)
    }

    @ViewBuilder
    private var classification: some View {
        VStack(alignment: .leading, spacing: 18) {
            if member?.identityState != .claimed {
                VStack(alignment: .leading, spacing: 8) {
                    Eyebrow(text: "Tipo de perfil")

                    HStack(spacing: 8) {
                        ForEach(availableHouseholdRoles) { role in
                            Button {
                                Haptics.lightImpact()
                                householdRole = role
                            } label: {
                                NinaChip(text: role.title, isSet: householdRole == role)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Eyebrow(text: "Tom do círculo")

                HStack(spacing: 12) {
                    ForEach(MemberTone.allCases) { option in
                        Button {
                            Haptics.lightImpact()
                            tone = option
                        } label: {
                            MemberAvatar(initials: displayName.ninaInitials, tone: option, size: 36)
                                .overlay(
                                    Circle()
                                        .strokeBorder(
                                            tone == option ? NinaTheme.ink : Color.clear,
                                            lineWidth: 1.6
                                        )
                                        .padding(-4)
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(toneTitle(option))
                        .accessibilityAddTraits(tone == option ? [.isSelected] : [])
                    }
                }
                .padding(.top, 2)
            }
        }
        .onChange(of: householdRole) { oldValue, newValue in
            updateDefaultRelationship(from: oldValue, to: newValue)
            if newValue == .pet, tone == .amber {
                tone = .lavender
            }
        }
        .disabled(!canEdit)
        .opacity(canEdit ? 1 : 0.5)
    }

    @ViewBuilder
    private var careFields: some View {
        if householdRole == .child || householdRole == .pet {
            VStack(alignment: .leading, spacing: 12) {
                Eyebrow(text: householdRole == .pet ? "Cuidados do pet" : "Dados da criança")

                Toggle(isOn: $hasBirthDate) {
                    Text("Salvar data de nascimento").ninaText(.label)
                }
                .tint(NinaTheme.ink)

                if hasBirthDate {
                    HStack(spacing: 12) {
                        Text("Nascimento").ninaText(.label, NinaTheme.muted)
                        Spacer(minLength: 0)
                        DatePicker(
                            "",
                            selection: $birthDate,
                            in: ...Date(),
                            displayedComponents: .date
                        )
                        .labelsHidden()
                        .tint(NinaTheme.ink)
                        .accessibilityLabel("Data de nascimento")
                    }
                    .frame(minHeight: 44)
                }

                if householdRole == .pet {
                    MemberField_(title: "Espécie") {
                        TextField("Cachorro, gato", text: $petSpecies)
                            .submitLabel(.done)
                    }

                    MemberField_(title: "Raça") {
                        TextField("Opcional", text: $petBreed)
                            .submitLabel(.done)
                    }
                }

                MemberField_(title: "O que a Nina lembra") {
                    TextField(noteHint, text: $memoryNote, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .disabled(!canEdit)
            .opacity(canEdit ? 1 : 0.5)
        } else if member != nil {
            VStack(alignment: .leading, spacing: 12) {
                Eyebrow(text: "Contexto")

                MemberField_(title: "O que a Nina lembra") {
                    TextField(noteHint, text: $memoryNote, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .disabled(!canEdit)
            .opacity(canEdit ? 1 : 0.5)
        }
    }

    @ViewBuilder
    private var permissionBlock: some View {
        if let member, member.role != .assistant {
            VStack(alignment: .leading, spacing: 10) {
                Eyebrow(text: "Permissão")

                if member.identityState == .claimed {
                    // Owner is never offered here: no RPC can grant or revoke it.
                    if store.canChangePermissionRole(for: member) {
                        HStack(spacing: 8) {
                            permissionChip(.admin)
                            permissionChip(.member)
                        }
                    } else {
                        Text(permissionRole.title).ninaText(.label)
                    }

                    Text(permissionRole.summary)
                        .ninaText(.caption, NinaTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Perfil da casa. Não entra no app e não usa a Nina.")
                        .ninaText(.caption, NinaTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func permissionChip(_ role: FamilyPermissionRole) -> some View {
        Button {
            Haptics.lightImpact()
            permissionRole = role
        } label: {
            NinaChip(text: role.title, isSet: permissionRole == role)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var actions: some View {
        VStack(spacing: 8) {
            if canEdit {
                NinaButton(
                    title: isSaving ? "Salvando..." : saveButtonTitle,
                    systemName: "checkmark",
                    fillsWidth: true,
                    isEnabled: canSave && !isSaving
                ) {
                    save()
                }
            }

            if let member, store.canRemoveFamilyMember(member) {
                NinaButton(title: "Remover da casa", kind: .quiet, isEnabled: !isSaving) {
                    Haptics.warning()
                    isShowingRemoveConfirmation = true
                }
                .padding(.top, 4)
            }

            if let error = store.syncErrorMessage {
                Text(error)
                    .ninaText(.caption, NinaTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .ninaCard(fill: NinaTheme.grout, stroke: .clear)
            }
        }
        .padding(.top, 4)
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

    private var saveButtonTitle: String {
        switch mode {
        case .addProfile: "Adicionar perfil"
        case .edit: "Salvar"
        }
    }

    private var defaultName: String {
        householdRole == .pet ? "Novo pet" : "Nova criança"
    }

    private var displayName: String {
        name.isEmpty ? defaultName : name
    }

    private var isNameLocked: Bool {
        member?.identityState == .claimed
    }

    private var noteHint: String {
        switch householdRole {
        case .pet: "Rotina, comida, remédios"
        case .child: "Escola, rotina, o que ajuda"
        case .adult, .assistant: "O que a casa precisa lembrar"
        }
    }

    private var statusLine: String {
        if member?.role == .assistant {
            return "IA da casa · não ocupa vaga"
        }
        if member?.identityState == .claimed {
            return "\(permissionRole.title) · usa o app"
        }
        return "\(householdRole.title) · perfil da casa"
    }

    // A house of one still reads correctly: the counter branches on the number.
    private var slotLine: String {
        let people = store.familyPeopleCount
        let peopleText = people == 1 ? "1 pessoa na casa" : "\(people) pessoas na casa"

        let remaining = store.remainingFamilySlots
        let remainingText: String
        switch remaining {
        case 0: remainingText = "Sem vaga livre"
        case 1: remainingText = "Cabe mais 1"
        default: remainingText = "Cabem mais \(remaining)"
        }

        return "\(peopleText). \(remainingText). A Nina não ocupa vaga."
    }

    private var lockedReason: String {
        if isAdding {
            return store.canInviteMorePeople
                ? "Só quem cuida da casa adiciona perfis."
                : "As 8 vagas estão ocupadas. Remova um perfil para abrir espaço."
        }
        return "Você pode ver este perfil, mas não editar."
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
        case .mint: "Tinta"
        case .coral: "Grafite"
        case .sky: "Chumbo"
        case .amber: "Pedra"
        case .lavender: "Névoa"
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

    private var isBusy: Bool {
        isWorking || store.isSyncingHome
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            NinaRow(
                title: request.requesterName,
                subtitle: "Pediu entrada \(request.createdAt.formatted(.relative(presentation: .named)))"
            ) {
                MemberAvatar(initials: request.requesterName.ninaInitials, tone: .mint)
            } trailing: {
                EmptyView()
            }

            if store.canChangeFamilyPermissions {
                VStack(alignment: .leading, spacing: 8) {
                    Eyebrow(text: "Entra como")

                    HStack(spacing: 8) {
                        permissionChip(.member)
                        permissionChip(.admin)
                    }
                }
            }

            Text(permissionRole.summary)
                .ninaText(.caption, NinaTheme.muted)
                .fixedSize(horizontal: false, vertical: true)

            if !store.canInviteMorePeople {
                Text("As 8 vagas da casa estão ocupadas. A Nina não ocupa vaga.")
                    .ninaText(.caption, NinaTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .ninaCard(fill: NinaTheme.grout, stroke: .clear)
            }

            HStack(spacing: 10) {
                NinaButton(
                    title: store.canInviteMorePeople ? "Aprovar" : "Casa cheia",
                    fillsWidth: true,
                    isEnabled: store.canInviteMorePeople && !isBusy
                ) {
                    approve()
                }

                NinaButton(title: "Recusar", kind: .outline, isEnabled: !isBusy) {
                    Haptics.warning()
                    isShowingDeclineConfirmation = true
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ninaCard()
        .alert("Recusar pedido?", isPresented: $isShowingDeclineConfirmation) {
            Button("Cancelar", role: .cancel) {}
            Button("Recusar", role: .destructive) {
                decline()
            }
        } message: {
            Text("\(request.requesterName) não recebe acesso à casa.")
        }
    }

    private func permissionChip(_ role: FamilyPermissionRole) -> some View {
        Button {
            Haptics.lightImpact()
            permissionRole = role
        } label: {
            NinaChip(text: role.title, isSet: permissionRole == role)
        }
        .buttonStyle(.plain)
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
        VStack(spacing: 0) {
            Spacer(minLength: 24)

            ZeroState(headline: "Pedido enviado", body_: waitingBody, presence: .waiting) {
                VStack(spacing: 10) {
                    if let request = store.pendingJoinRequest {
                        Text(request.status.title).ninaText(.meta, NinaTheme.muted)
                    }

                    NinaButton(
                        title: "Atualizar status",
                        systemName: "arrow.clockwise",
                        fillsWidth: true,
                        isEnabled: !store.isSyncingHome
                    ) {
                        Task {
                            await store.activateHomeContext(for: authSession.currentUser)
                        }
                    }

                    NinaButton(
                        title: "Cancelar pedido",
                        kind: .quiet,
                        isEnabled: !isCancelling && !store.isSyncingHome
                    ) {
                        cancelRequest()
                    }
                }
                .frame(maxWidth: 320)
            }

            Spacer(minLength: 24)

            NinaButton(title: "Sair", kind: .quiet) {
                Task {
                    onboardingStore.cancelReplay()
                    await authSession.signOut()
                }
            }
            .padding(.bottom, 12)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ninaScreenBackground()
    }

    // Possessing the link grants nothing: the request waits for a person.
    private var waitingBody: String {
        let house = store.pendingJoinRequest?.familyName ?? "esta casa"
        return "Uma pessoa responsável por \(house) precisa aprovar sua entrada. "
            + "Ter o link não dá acesso."
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

struct FamilyAccessDecisionView: View {
    @Environment(AppStore.self) private var store
    @Environment(AuthSessionStore.self) private var authSession
    @Environment(OnboardingStore.self) private var onboardingStore

    @State private var isAcknowledging = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)

            ZeroState(headline: title, body_: message, presence: .unavailable) {
                VStack(spacing: 12) {
                    if let decision = store.familyAccessDecision {
                        Text(decisionLine(for: decision)).ninaText(.meta, NinaTheme.muted)
                    }

                    Text(nextStep)
                        .ninaText(.caption, NinaTheme.muted)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 306)

                    if let syncErrorMessage = store.syncErrorMessage {
                        Text(syncErrorMessage)
                            .ninaText(.caption, NinaTheme.ink)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity)
                            .padding(14)
                            .ninaCard(fill: NinaTheme.grout, stroke: .clear)
                    }

                    NinaButton(
                        title: "Entendi",
                        fillsWidth: true,
                        isEnabled: !isAcknowledging && !store.isSyncingHome
                    ) {
                        acknowledge()
                    }
                    .padding(.top, 2)
                }
                .frame(maxWidth: 320)
            }

            Spacer(minLength: 24)

            NinaButton(title: "Sair", kind: .quiet) {
                Task {
                    onboardingStore.cancelReplay()
                    await authSession.signOut()
                }
            }
            .padding(.bottom, 12)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ninaScreenBackground()
    }

    private var outcome: FamilyAccessOutcome {
        store.familyAccessDecision?.outcome ?? .declined
    }

    private var title: String {
        switch outcome {
        case .declined: "Seu pedido não foi aprovado"
        case .removed: "Você não está mais nessa casa"
        }
    }

    private var message: String {
        switch outcome {
        case .declined:
            "Essa casa não liberou sua entrada desta vez. A Nina não recebe o motivo, então não sabe te dizer."
        case .removed:
            "Seu acesso foi encerrado. As tarefas e as listas continuam com a casa."
        }
    }

    private var nextStep: String {
        switch outcome {
        case .declined:
            "Dá para pedir um convite novo para alguém de lá, ou começar a sua própria casa agora."
        case .removed:
            "Dá para voltar com um convite novo, ou começar a sua própria casa agora."
        }
    }

    private func decisionLine(for decision: FamilyAccessDecision) -> String {
        let day = decision.decidedAt.formatted(date: .abbreviated, time: .omitted)
        switch decision.outcome {
        case .declined: return "\(decision.familyName) · resposta em \(day)"
        case .removed: return "\(decision.familyName) · acesso encerrado em \(day)"
        }
    }

    private func acknowledge() {
        guard !isAcknowledging else { return }
        isAcknowledging = true
        Task {
            let acknowledged = await store.acknowledgeFamilyAccessDecision()
            isAcknowledging = false
            if acknowledged {
                Haptics.selection()
            }
        }
    }
}

// Only the person who owns the house is marked. A second badge for an admin would
// rank the household; the crown answers one question — who can decide.
struct MemberPermissionBadge: View {
    @Environment(AppStore.self) private var store
    let member: HouseholdMember

    var body: some View {
        if member.role != .assistant, effectivePermissionRole == .owner {
            CategoryGlyph(systemName: "crown.fill", size: 14, tint: NinaTheme.ink)
                .accessibilityLabel("Responsável pela casa")
        }
    }

    private var effectivePermissionRole: FamilyPermissionRole {
        if member.userID == store.currentFamilyMember?.userID {
            return store.currentPermissionRole
        }
        return member.permissionRole
    }
}

private struct MemberField_<Field: View>: View {
    var title: String
    @ViewBuilder var field: Field

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).ninaText(.meta, NinaTheme.muted)
            field
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(NinaTheme.ink)
                .tint(NinaTheme.cobalt)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            NinaTheme.grout,
            in: RoundedRectangle(cornerRadius: NinaTheme.Radius.field, style: .continuous)
        )
    }
}
