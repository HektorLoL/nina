import SwiftUI

enum MemberEditorMode: Hashable {
    case addProfile
    case edit(UUID)
}

struct MemberEditorSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(RouterPath.self) private var router
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
    @State private var guardianSheet: GuardianSheetMode?
    @State private var isHandingOver = false
    @State private var handOverConfirmation = ""
    @FocusState private var isNameFocused: Bool
    @FocusState private var isHandOverFocused: Bool

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
            (store.canManageFamily || store.canActForMinors) && store.canInviteMorePeople
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
                    headline: "Essa pessoa não está mais aqui.",
                    body_: "Alguém pode ter removido este perfil.",
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
        .sheet(item: $guardianSheet) { mode in
            NavigationStack {
                GuardianApprovalSheet(mode: mode) {
                    dismiss()
                }
            }
            .presentationDragIndicator(.visible)
        }
        .alert("Tirar esta pessoa da casa?", isPresented: $isShowingRemoveConfirmation) {
            Button("Cancelar", role: .cancel) {}
            Button("Tirar", role: .destructive) {
                removeMember()
            }
        } message: {
            Text("Perde o acesso à casa. As tarefas feitas ficam.")
        }
    }

    private var header: some View {
        SheetHeader(eyebrow: "Pessoa") {
            dismiss()
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

                Text(displayName).ninaText(.title)
            }

            if isAdding, householdRole != .adult {
                Text("Os adultos cuidam deste perfil. Não usa o app.")
                    .ninaText(.caption, NinaTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
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
                TextField("", text: $name)
                    .focused($isNameFocused)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .accessibilityLabel("Nome")
            }
            .disabled(isNameLocked)
            .opacity(isNameLocked ? 0.4 : 1)

            if householdRole == .adult, !isAdding {
                MemberField_(title: "Na casa") {
                    TextField("Esposa, marido, avó", text: $relationship)
                        .submitLabel(.done)
                }
            }
        }
        .disabled(!canEdit)
        .opacity(canEdit ? 1 : 0.4)
    }

    @ViewBuilder
    private var classification: some View {
        VStack(alignment: .leading, spacing: 18) {
            if member?.identityState != .claimed {
                VStack(alignment: .leading, spacing: 8) {
                    Eyebrow(text: "Tipo")

                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) { roleChips }
                        VStack(alignment: .leading, spacing: 8) { roleChips }
                    }

                    if isAdding, !store.canActForMinors {
                        Text("Só um responsável com idade confirmada pela Apple cadastra.")
                            .ninaText(.caption, NinaTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
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
        .opacity(canEdit ? 1 : 0.4)
    }

    @ViewBuilder
    private var roleChips: some View {
        ForEach(availableHouseholdRoles) { role in
            let isEnabled = isRoleAvailable(role)
            Button {
                Haptics.lightImpact()
                householdRole = role
            } label: {
                NinaChip(text: role.title, isSet: householdRole == role, isDisabled: !isEnabled)
            }
            .buttonStyle(.plain)
            .disabled(!isEnabled)
        }
    }

    // Children and teens are registered only by a guardian Apple confirmed; a pet only by who runs the house.
    private func isRoleAvailable(_ role: HouseholdRole) -> Bool {
        guard isAdding else { return true }
        switch role {
        case .teen, .child: return store.canActForMinors
        case .pet: return store.canManageFamily
        case .adult: return true
        case .assistant, .unrecognized: return false
        }
    }

    @ViewBuilder
    private var careFields: some View {
        if householdRole == .pet {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: $hasBirthDate) {
                    Text("Data de nascimento").ninaText(.label)
                }
                .tint(NinaTheme.ink)

                if hasBirthDate {
                    HStack(spacing: 12) {
                        DatePicker(
                            "",
                            selection: $birthDate,
                            in: ...Date(),
                            displayedComponents: .date
                        )
                        .labelsHidden()
                        .tint(NinaTheme.ink)
                        .accessibilityLabel("Data de nascimento")
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: 44)
                }

                if householdRole == .pet {
                    MemberField_(title: "Espécie") {
                        TextField("Cachorro, gato", text: $petSpecies)
                            .submitLabel(.done)
                    }

                    MemberField_(title: "Raça") {
                        TextField("Vira-lata", text: $petBreed)
                            .submitLabel(.done)
                    }
                }
            }
            .disabled(!canEdit)
            .opacity(canEdit ? 1 : 0.4)
        } else if member != nil, !householdRole.isMinorRole {
            MemberField_(title: "O que a Nina lembra") {
                TextField("Horários, preferências", text: $memoryNote, axis: .vertical)
                    .lineLimit(3...6)
            }
            .disabled(!canEdit)
            .opacity(canEdit ? 1 : 0.4)
        }
    }

    @ViewBuilder
    private var permissionBlock: some View {
        if let member, member.role != .assistant, member.identityState == .claimed {
            VStack(alignment: .leading, spacing: 10) {
                Eyebrow(text: "Permissão")

                // Owner is never a chip: the house changes hands only through Passar a casa.
                if store.canChangePermissionRole(for: member) {
                    HStack(spacing: 8) {
                        permissionChip(.admin)
                        permissionChip(.member)
                    }

                    if permissionRole == .admin {
                        Text(permissionRole.summary)
                            .ninaText(.caption, NinaTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Text(permissionRole.title).ninaText(.label)
                }

                if store.canOfferHouse(to: member) {
                    handOverBlock(for: member)
                }
            }
        }
    }

    // Handing the house over is weighed like a deletion: the person's name typed, then an ink button.
    @ViewBuilder
    private func handOverBlock(for member: HouseholdMember) -> some View {
        if store.houseOffer(to: member) != nil {
            VStack(alignment: .leading, spacing: 4) {
                Text("Esperando \(member.name) aceitar a casa.")
                    .ninaText(.caption, NinaTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)

                NinaButton(title: "Desfazer pedido", kind: .quiet, isEnabled: !isSaving) {
                    withdrawOffer()
                }
            }
            .padding(.top, 6)
        } else if isHandingOver {
            VStack(alignment: .leading, spacing: 14) {
                Text("\(member.name) recebe um pedido para virar titular. Quando aceitar, você passa a administrar a casa e pode sair depois.")
                    .ninaText(.caption, NinaTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)

                SheetField(label: "Escreva \(member.name) para confirmar") {
                    TextField(member.name, text: $handOverConfirmation)
                        .accessibilityLabel("Escreva \(member.name) para confirmar")
                        .focused($isHandOverFocused)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                }

                InkButton(
                    title: isSaving ? "Enviando" : "Passar para \(member.name)",
                    isEnabled: confirmsHandOver(to: member) && !isSaving
                ) {
                    handOver(to: member)
                }

                NinaButton(title: "Cancelar", kind: .quiet, isEnabled: !isSaving) {
                    Haptics.selection()
                    closeHandOver()
                }
            }
            .padding(.top, 6)
        } else {
            if let waiting = store.houseOfferRecipientName {
                Text("A casa já foi oferecida a \(waiting). Um novo pedido substitui esse.")
                    .ninaText(.caption, NinaTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            NinaButton(title: "Passar a casa", kind: .quiet, isEnabled: !isSaving) {
                Haptics.warning()
                isHandingOver = true
                Task {
                    await Task.yield()
                    isHandOverFocused = true
                }
            }
        }
    }

    private func closeHandOver() {
        isHandOverFocused = false
        handOverConfirmation = ""
        isHandingOver = false
    }

    private func confirmsHandOver(to member: HouseholdMember) -> Bool {
        let typed = handOverConfirmation.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = member.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !name.isEmpty
            && typed.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
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
            if isAdding, householdRole == .adult {
                Text("Adultos entram por convite.")
                    .ninaText(.label, NinaTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                NinaButton(title: "Convidar", fillsWidth: true, isEnabled: store.canInviteMorePeople) {
                    Haptics.lightImpact()
                    router.presentedSheet = .inviteFamily
                }
            } else if canEdit {
                NinaButton(
                    title: isSaving ? "Salvando" : saveButtonTitle,
                    systemName: "checkmark",
                    fillsWidth: true,
                    isEnabled: canSave && !isSaving
                ) {
                    save()
                }
            }

            if let member, store.canRemoveFamilyMember(member) {
                NinaButton(title: "Tirar da casa", kind: .quiet, isEnabled: !isSaving) {
                    Haptics.warning()
                    isShowingRemoveConfirmation = true
                }
                .padding(.top, 4)
            }

            if let error = store.syncErrorMessage {
                NinaErrorNote(text: error, style: .card, announces: false)
            }
        }
        .padding(.top, 4)
    }

    private var draftMember: HouseholdMember {
        HouseholdMember(
            id: member?.id ?? UUID(),
            userID: member?.userID,
            name: name.isEmpty ? defaultName : name,
            relationship: savedRelationship,
            role: householdRole,
            permissionRole: permissionRole,
            identityState: member?.identityState ?? .unclaimed,
            tone: tone,
            taskCount: member?.taskCount ?? 0,
            memoryNote: MemberRecollection.storedNote(
                memoryNote,
                for: householdRole.isMinorRole ? .child : householdRole
            ),
            birthDate: hasBirthDate && householdRole == .pet ? birthDate : nil,
            petSpecies: householdRole == .pet ? petSpecies : "",
            petBreed: householdRole == .pet ? petBreed : ""
        )
    }

    // Nina reads a member's relationship, not the species field, so a pet's species travels in it.
    private var savedRelationship: String {
        let species = petSpecies.trimmingCharacters(in: .whitespacesAndNewlines)
        guard householdRole == .pet, let first = species.first else { return relationship }
        return first.uppercased() + species.dropFirst()
    }

    // A child or teen row keeps its role; an adult or pet row can never become one.
    private var availableHouseholdRoles: [HouseholdRole] {
        switch mode {
        case .addProfile:
            HouseholdRole.editorRoles
        case .edit:
            member?.role.isMinorRole == true ? [] : [.adult, .pet]
        }
    }

    private var saveButtonTitle: String {
        switch mode {
        case .addProfile: householdRole.isMinorRole ? "Continuar" : "Adicionar perfil"
        case .edit: "Salvar"
        }
    }

    private var defaultName: String {
        switch householdRole {
        case .pet: "Novo pet"
        case .teen: "Novo adolescente"
        case .child: "Nova criança"
        case .adult, .assistant, .unrecognized: "Nova pessoa"
        }
    }

    private var displayName: String {
        name.isEmpty ? defaultName : name
    }

    private var isNameLocked: Bool {
        member?.identityState == .claimed
    }

    private var lockedReason: String {
        if isAdding {
            return store.canInviteMorePeople
                ? "Só quem cuida da casa adiciona perfis."
                : "As 8 vagas estão ocupadas."
        }
        return "Você não pode editar este perfil."
    }

    private func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true

        switch mode {
        case .addProfile:
            householdRole = store.canActForMinors ? .child : (store.canManageFamily ? .pet : .adult)
            relationship = householdRole == .pet ? "Pet" : "Criança"
            tone = householdRole == .pet ? .lavender : .amber
        case .edit:
            guard let member else { return }
            name = member.name
            relationship = member.relationship
            householdRole = member.role
            permissionRole = member.userID == store.currentFamilyMember?.userID
                ? store.currentPermissionRole
                : member.permissionRole
            tone = member.tone
            memoryNote = MemberRecollection.replacesNote(for: member.role) ? "" : member.memoryNote
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
        if isAdding, householdRole.isMinorRole {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guardianSheet = .newProfile(name: trimmed, band: householdRole == .child ? .under12 : nil)
            return
        }
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

    private func handOver(to member: HouseholdMember) {
        guard confirmsHandOver(to: member), !isSaving else { return }
        isSaving = true
        isHandOverFocused = false

        Task {
            let success = await store.offerHouse(to: member)
            isSaving = false
            if success {
                Haptics.success()
                closeHandOver()
            }
        }
    }

    private func withdrawOffer() {
        guard !isSaving else { return }
        isSaving = true

        Task {
            let success = await store.withdrawHouseOffer()
            isSaving = false
            if success {
                Haptics.selection()
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
        let oldDefault = oldRole == .pet ? "Pet" : oldRole.title
        guard trimmedRelationship.isEmpty || trimmedRelationship == oldDefault else { return }

        switch newRole {
        case .pet:
            relationship = "Pet"
        case .child:
            relationship = "Criança"
        case .teen:
            relationship = "Adolescente"
        case .adult, .assistant, .unrecognized:
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
    @State private var guardianSheet: GuardianSheetMode?

    private var isBusy: Bool {
        isWorking || store.isSyncingHome
    }

    private var isAdultRequester: Bool {
        request.requesterAge.isAdult
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            NinaRow(
                title: request.requesterName,
                subtitle: request.createdAt.formatted(.relative(presentation: .named))
            ) {
                MemberAvatar(initials: request.requesterName.ninaInitials, tone: .mint)
                    .accessibilityHidden(true)
            } trailing: {
                EmptyView()
            }

            // The tag is the live reading, never the snapshot taken when the request was sent.
            Text(request.requesterAge.tag)
                .ninaText(.caption, NinaTheme.ink, weight: .semibold)
                .padding(.horizontal, 12)
                .frame(minHeight: 28)
                .background(NinaTheme.grout, in: Capsule())

            if isAdultRequester {
                adultApproval
            } else {
                guardianApproval
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
        .sheet(item: $guardianSheet) { mode in
            NavigationStack {
                GuardianApprovalSheet(mode: mode)
            }
            .presentationDragIndicator(.visible)
        }
    }

    @ViewBuilder
    private var adultApproval: some View {
        if store.canChangeFamilyPermissions {
            VStack(alignment: .leading, spacing: 8) {
                Eyebrow(text: "Entra como")

                HStack(spacing: 8) {
                    permissionChip(.member)
                    permissionChip(.admin)
                }

                if permissionRole == .admin {
                    Text(permissionRole.summary)
                        .ninaText(.caption, NinaTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }

        HStack(spacing: 10) {
            NinaButton(
                title: store.canInviteMorePeople ? "Aprovar" : "Casa cheia",
                fillsWidth: true,
                isEnabled: store.canInviteMorePeople && !isBusy
            ) {
                approve()
            }

            declineButton
        }
    }

    // A minor or a person of unknown age enters only as a member, approved by a guardian Apple confirmed.
    @ViewBuilder
    private var guardianApproval: some View {
        if !store.canActForMinors {
            Text("Isso pede idade confirmada pela Apple.")
                .ninaText(.caption, NinaTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }

        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                guardianButton
                declineButton
            }
            VStack(spacing: 10) {
                guardianButton
                declineButton
            }
        }
    }

    private var guardianButton: some View {
        NinaButton(
            title: store.canInviteMorePeople ? "Aprovar como responsável" : "Casa cheia",
            fillsWidth: true,
            isEnabled: store.canInviteMorePeople && store.canActForMinors && !isBusy
        ) {
            guardianSheet = .approval(request)
        }
    }

    private var declineButton: some View {
        NinaButton(title: "Recusar", kind: .outline, isEnabled: !isBusy) {
            Haptics.warning()
            isShowingDeclineConfirmation = true
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
        guard !isWorking, store.canInviteMorePeople, isAdultRequester else { return }
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

// The person an owner offered the house to decides here; nothing changes until they accept.
struct HouseOwnershipOfferCard: View {
    @Environment(AppStore.self) private var store
    @State private var isWorking = false
    @State private var isShowingDeclineConfirmation = false

    private var isBusy: Bool {
        isWorking || store.isSyncingHome
    }

    private var ownerName: String {
        store.houseOfferOwnerName ?? "O titular"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("\(ownerName) quer passar a casa para você.")
                .ninaText(.title)
                .fixedSize(horizontal: false, vertical: true)

            Text("Como titular, você cuida de convites, permissões e ajustes. Para sair depois, passe a casa para outra pessoa.")
                .ninaText(.caption, NinaTheme.muted)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                NinaButton(title: isWorking ? "Aceitando" : "Aceitar", fillsWidth: true, isEnabled: !isBusy) {
                    accept()
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
        .alert("Recusar a casa?", isPresented: $isShowingDeclineConfirmation) {
            Button("Cancelar", role: .cancel) {}
            Button("Recusar", role: .destructive) {
                decline()
            }
        } message: {
            Text("\(ownerName) continua como titular.")
        }
    }

    private func accept() {
        guard !isWorking else { return }
        isWorking = true
        Task {
            let success = await store.acceptHouseOffer()
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
            let success = await store.withdrawHouseOffer()
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
    @State private var isShowingDeletion = false

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 24)

                    ZeroState(headline: "Pedido enviado.", body_: waitingBody, presence: .waiting) {
                        VStack(spacing: 10) {
                            if let message = store.syncErrorMessage ?? authSession.errorMessage {
                                NinaErrorNote(text: message, alignment: .center)
                            }

                            NinaButton(
                                title: "Atualizar",
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

                    NinaButton(title: "Sair da conta", kind: .quiet) {
                        Haptics.warning()
                        Task {
                            onboardingStore.cancelReplay()
                            await authSession.signOut()
                        }
                    }

                    NinaButton(title: "Apagar conta", kind: .quiet) {
                        Haptics.lightImpact()
                        isShowingDeletion = true
                    }
                    .padding(.bottom, 12)
                }
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .ninaScreenBackground()
        .accountDeletionSheet(isPresented: $isShowingDeletion)
        // Nobody should have to tap "Atualizar" to learn they were let in.
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                guard !Task.isCancelled else { return }
                await store.activateHomeContext(for: authSession.currentUser)
            }
        }
    }

    // Possessing the link grants nothing: the request waits for a person.
    private var waitingBody: String {
        let house = store.pendingJoinRequest?.familyName ?? "A casa"
        return "\(house) precisa aprovar sua entrada."
    }

    private func cancelRequest() {
        guard !isCancelling else { return }
        isCancelling = true
        Task {
            if await store.cancelPendingJoinRequest() {
                Haptics.selection()
            }
            isCancelling = false
        }
    }
}

struct FamilyAccessDecisionView: View {
    @Environment(AppStore.self) private var store
    @Environment(AuthSessionStore.self) private var authSession
    @Environment(OnboardingStore.self) private var onboardingStore

    @State private var isAcknowledging = false
    @State private var isShowingDeletion = false

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 24)

                    ZeroState(headline: title, body_: message, presence: .unavailable) {
                        VStack(spacing: 12) {
                            if let decision = store.familyAccessDecision {
                                Text(decisionLine(for: decision)).ninaText(.meta, NinaTheme.muted)
                            }

                            if let syncErrorMessage = store.syncErrorMessage ?? authSession.errorMessage {
                                NinaErrorNote(text: syncErrorMessage, style: .card, alignment: .center)
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

                    NinaButton(title: "Sair da conta", kind: .quiet) {
                        Haptics.warning()
                        Task {
                            onboardingStore.cancelReplay()
                            await authSession.signOut()
                        }
                    }

                    NinaButton(title: "Apagar conta", kind: .quiet) {
                        Haptics.lightImpact()
                        isShowingDeletion = true
                    }
                    .padding(.bottom, 12)
                }
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .ninaScreenBackground()
        .accountDeletionSheet(isPresented: $isShowingDeletion)
    }

    private var outcome: FamilyAccessOutcome {
        store.familyAccessDecision?.outcome ?? .declined
    }

    private var title: String {
        switch outcome {
        case .declined: "Seu pedido não foi aprovado."
        case .removed: "Você não está mais nessa casa."
        }
    }

    private var message: String {
        switch outcome {
        case .declined: "A Nina não recebe o motivo."
        case .removed: "As tarefas e as listas ficam com a casa."
        }
    }

    private func decisionLine(for decision: FamilyAccessDecision) -> String {
        let day = decision.decidedAt.formatted(date: .abbreviated, time: .omitted)
        return "\(decision.familyName) · \(day)"
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
            CategoryGlyph(systemName: "crown.fill", size: 14, tint: NinaTheme.ink, label: "Titular da casa")
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
            Text(title)
                .ninaText(.meta, NinaTheme.muted)
                .accessibilityHidden(true)
            field
                .ninaText(.body, NinaTheme.ink)
                .tint(NinaTheme.cobalt)
                .accessibilityLabel(title)
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
