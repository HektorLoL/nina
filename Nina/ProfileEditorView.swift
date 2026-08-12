import PhotosUI
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct ProfileEditorView: View {
    @Environment(AppStore.self) private var appStore
    @Environment(ProfileStore.self) private var profileStore
    @Environment(\.dismiss) private var dismiss

    let user: AuthUser

    @State private var draft: UserProfile
    @State private var didLoad = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var pendingPhotoData: Data?
    @State private var photoError: String?
    @State private var isShowingCoreMemories = false
    @FocusState private var isNameFocused: Bool

    init(user: AuthUser) {
        self.user = user
        _draft = State(initialValue: UserProfile.default(for: user))
    }

    private var activePhotoData: Data? {
        pendingPhotoData ?? profileStore.photoData(for: draft)
    }

    private var canSave: Bool {
        !draft.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var hasPhoto: Bool {
        draft.avatar.kind == .photo || pendingPhotoData != nil
    }

    private var initialsPreview: String {
        let initials = draft.displayName.ninaInitials
        return initials.isEmpty ? user.displayName.ninaInitials : initials
    }

    private var tonePresets: [ProfileAvatarPreset] {
        var seen: Set<MemberTone> = []
        return ProfileAvatarPreset.all.filter { seen.insert($0.tone).inserted }
    }

    private var coreMemories: [ProfileCoreMemory] {
        appStore.ninaMemories.map { memory in
            ProfileCoreMemory(
                id: memory.id.uuidString,
                title: memory.title,
                detail: memory.body,
                systemName: memory.visibility == .shared ? "house" : "lock",
                scopeLabel: memory.visibility == .shared ? "Casa" : "Só sua"
            )
        }
    }

    private var memoryPreview: String {
        coreMemories.first?.detail ?? "A Nina só guarda o que você confirma."
    }

    private var photoLimitNote: String {
        "A foto vira JPEG e cabe em \(ProfilePhotoPolicy.limitDescription) antes de sair daqui."
    }

    private var memoryCountLabel: String {
        switch coreMemories.count {
        case 0: "Nada guardado ainda"
        case 1: "1 memória guardada"
        default: "\(coreMemories.count) memórias guardadas"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    intro
                    nameField
                    classification
                    faceSection
                    contactSection
                    routineSection
                    ninaSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 28)
            }
            .scrollDismissesKeyboard(.interactively)

            footer
        }
        .ninaScreenBackground()
        .onAppear(perform: loadProfileIfNeeded)
        .task {
            await Task.yield()
            isNameFocused = draft.displayName.isEmpty
        }
        .onChange(of: selectedPhotoItem) { _, newItem in
            loadPhoto(from: newItem)
        }
        .sheet(isPresented: $isShowingCoreMemories) {
            ProfileCoreMemoriesSheet(memories: coreMemories)
                .presentationDetents([.large])
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
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Meu perfil").ninaText(.screen)
            Text("A Nina usa isto para falar com você do jeito certo.")
                .ninaText(.label, NinaTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var nameField: some View {
        ProfileField(label: "Nome") {
            TextField("Como a Nina chama você", text: $draft.displayName)
                .textContentType(.name)
                .submitLabel(.done)
                .focused($isNameFocused)
        }
    }

    private var classification: some View {
        VStack(alignment: .leading, spacing: 16) {
            ProfileChoiceField(
                label: "Sexo",
                value: draft.sex.title,
                systemName: "person"
            ) {
                ForEach(ProfileSex.allCases) { sex in
                    Button {
                        Haptics.selection()
                        draft.sex = sex
                    } label: {
                        Label(sex.title, systemImage: sex.symbolName)
                    }
                }
            }

            ProfileChoiceField(
                label: "Papel na casa",
                value: draft.householdRole.title,
                systemName: "house"
            ) {
                ForEach(ProfileHouseholdRole.allCases) { role in
                    Button {
                        Haptics.selection()
                        draft.householdRole = role
                    } label: {
                        Label(role.title, systemImage: role.symbolName)
                    }
                }
            }
        }
    }

    private var faceSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Eyebrow(text: "Como você aparece")

            HStack(alignment: .top, spacing: 14) {
                ProfileAvatarView(profile: draft, photoData: activePhotoData, size: 64)

                VStack(alignment: .leading, spacing: 8) {
                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        Text(hasPhoto ? "Trocar foto" : "Escolher foto")
                            .font(.system(size: 16, weight: .semibold))
                            .tracking(-0.1)
                            .foregroundStyle(NinaTheme.ink)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .contentShape(Rectangle())
                            .overlay(
                                RoundedRectangle(
                                    cornerRadius: NinaTheme.Radius.field,
                                    style: .continuous
                                )
                                .strokeBorder(NinaTheme.line, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)

                    if hasPhoto {
                        NinaButton(title: "Remover foto", kind: .quiet) {
                            removePhoto()
                        }
                    }
                }
            }

            if let photoError {
                HStack(alignment: .top, spacing: 8) {
                    CategoryGlyph(systemName: "exclamationmark.circle", size: 15)
                    Text(photoError)
                        .ninaText(.caption, NinaTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Text(photoLimitNote)
                .ninaText(.meta, NinaTheme.muted)
                .fixedSize(horizontal: false, vertical: true)

            tonePicker
        }
    }

    private var tonePicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sem foto, você aparece pelas iniciais. O tom só diferencia na lista.")
                .ninaText(.meta, NinaTheme.muted)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 14) {
                ForEach(Array(tonePresets.enumerated()), id: \.element.id) { index, preset in
                    Button {
                        selectPreset(preset)
                    } label: {
                        MemberAvatar(initials: initialsPreview, tone: preset.tone, size: 44)
                            .padding(3)
                            .overlay(
                                Circle().strokeBorder(
                                    isToneSelected(preset) ? NinaTheme.cobalt : Color.clear,
                                    lineWidth: 2
                                )
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Tom \(index + 1) de \(tonePresets.count)")
                    .accessibilityAddTraits(isToneSelected(preset) ? [.isSelected] : [])
                }

                Spacer(minLength: 0)
            }
        }
    }

    private var contactSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Eyebrow(text: "Contato")

            ProfileReadOnlyField(
                label: "E-mail",
                value: user.email ?? "Email não vinculado",
                note: user.provider.title
            )

            ProfileField(label: "Telefone") {
                TextField("(00) 00000-0000", text: $draft.phone)
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
            }
        }
    }

    private var routineSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Eyebrow(text: "Rotina da casa")

            ProfileField(label: "Aniversário") {
                TextField("Ex.: 12 de maio", text: $draft.birthdayLabel)
            }

            ProfileField(label: "Disponibilidade") {
                TextField(
                    "Quando você costuma resolver coisas da casa",
                    text: $draft.availabilityNote,
                    axis: .vertical
                )
                .lineLimit(2...4)
            }
        }
    }

    private var ninaSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Eyebrow(text: "Como a Nina fala com você")

            ProfileChoiceField(
                label: "Tom das sugestões",
                value: draft.communicationPreference.title,
                systemName: "text.bubble"
            ) {
                ForEach(ProfileCommunicationPreference.allCases) { preference in
                    Button {
                        Haptics.selection()
                        draft.communicationPreference = preference
                    } label: {
                        Text(preference.title)
                    }
                }
            }

            Text(draft.communicationPreference.detail)
                .ninaText(.meta, NinaTheme.muted)
                .fixedSize(horizontal: false, vertical: true)

            NinaDivider(inset: 0)

            Button(action: showCoreMemories) {
                NinaRow(
                    title: memoryCountLabel,
                    subtitle: memoryPreview
                ) {
                    CategoryGlyph(systemName: "bookmark")
                } trailing: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(NinaTheme.muted)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Abre a lista de memórias que a Nina guardou")
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Só o nome é obrigatório.")
                .ninaText(.meta, NinaTheme.muted)

            NinaButton(
                title: "Salvar perfil",
                fillsWidth: true,
                isEnabled: canSave,
                action: saveProfile
            )
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    private func isToneSelected(_ preset: ProfileAvatarPreset) -> Bool {
        draft.avatar.kind == .preset && draft.avatar.tone == preset.tone
    }

    private func loadProfileIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        draft = profileStore.profile(for: user)
    }

    private func saveProfile() {
        guard canSave else {
            Haptics.error()
            return
        }

        var profile = draft
        profile.displayName = profile.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.phone = profile.phone.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.birthdayLabel = profile.birthdayLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.availabilityNote = profile.availabilityNote.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.memoryNote = profile.memoryNote.trimmingCharacters(in: .whitespacesAndNewlines)

        // The photo is written first: a profile that points at a photo the disk
        // does not hold would render a face that cannot be loaded.
        if let pendingPhotoData {
            do {
                try profileStore.savePhotoData(pendingPhotoData, for: profile.userID)
                profile.avatar = profile.avatar.asPhoto(for: profile.userID)
            } catch {
                photoError = error.localizedDescription
                Haptics.error()
                return
            }
        } else if profile.avatar.kind == .preset {
            profileStore.deleteLocalPhoto(for: profile.userID)
        }

        profileStore.saveProfile(profile, user: user)
        Haptics.success()
        dismiss()
    }

    private func showCoreMemories() {
        Haptics.lightImpact()
        isShowingCoreMemories = true
    }

    private func selectPreset(_ preset: ProfileAvatarPreset) {
        Haptics.selection()
        pendingPhotoData = nil
        photoError = nil
        draft.avatar = preset.avatar
    }

    private func removePhoto() {
        Haptics.selection()
        pendingPhotoData = nil
        photoError = nil
        draft.avatar = ProfileAvatar.defaultPreset
    }

    private func loadPhoto(from item: PhotosPickerItem?) {
        guard let item else { return }

        Task {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else { return }
                let normalizedData = try await Task.detached(priority: .userInitiated) {
                    try ProfilePhotoPolicy.prepareForStorage(data)
                }.value

                await MainActor.run {
                    pendingPhotoData = normalizedData
                    draft.avatar = draft.avatar.asPhoto(for: draft.userID)
                    photoError = nil
                    Haptics.success()
                }
            } catch {
                await MainActor.run {
                    photoError = error.localizedDescription
                    Haptics.error()
                }
            }
        }
    }
}

// A face is a photo or initials, never a drawn character: the household tells
// people apart by the letters of their names, and colour is spent on lateness.
struct ProfileAvatarView: View {
    var profile: UserProfile
    var photoData: Data?
    var size: CGFloat = 48

    var body: some View {
        Group {
            if let photoData,
               profile.avatar.kind == .photo,
               let image = platformImage(from: photoData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(NinaTheme.line, lineWidth: 1))
            } else {
                MemberAvatar(
                    initials: profile.displayName.ninaInitials,
                    tone: profile.avatar.tone,
                    size: size
                )
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Foto de perfil de \(profile.displayName)")
    }

    private func platformImage(from data: Data) -> UIImage? {
        #if canImport(UIKit)
        UIImage(data: data)
        #else
        nil
        #endif
    }
}

private struct ProfileField<Field: View>: View {
    var label: String
    @ViewBuilder var field: Field

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).ninaText(.meta, NinaTheme.muted)
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

private struct ProfileReadOnlyField: View {
    var label: String
    var value: String
    var note: String

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(label).ninaText(.meta, NinaTheme.muted)
                Text(value)
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(NinaTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 8)

            Text(note).ninaText(.meta, NinaTheme.muted)
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

private struct ProfileChoiceField<MenuContent: View>: View {
    var label: String
    var value: String
    var systemName: String
    @ViewBuilder var menuContent: MenuContent

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).ninaText(.meta, NinaTheme.muted)

            Menu {
                menuContent
            } label: {
                NinaChip(text: value, isSet: true, systemName: systemName)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
            .accessibilityValue(value)
        }
    }
}

private struct ProfileCoreMemory: Identifiable, Hashable {
    var id: String
    var title: String
    var detail: String
    var systemName: String
    var scopeLabel: String
}

private struct ProfileCoreMemoriesSheet: View {
    @Environment(\.dismiss) private var dismiss

    var memories: [ProfileCoreMemory]

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    intro
                    list
                }
                .padding(.horizontal, 20)
                .padding(.top, 6)
                .padding(.bottom, 28)
            }
        }
        .ninaSheetBackground()
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("O que a Nina guardou").ninaText(.title)
            Text("Só entra aqui o que você confirmou. Dá para editar e apagar na tela Casa.")
                .ninaText(.label, NinaTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var list: some View {
        if memories.isEmpty {
            ZeroState(
                headline: "Nada guardado ainda",
                body_: "Quando você confirmar uma memória na conversa, ela aparece aqui."
            )
            .padding(.top, 28)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(memories.enumerated()), id: \.element.id) { index, memory in
                    if index > 0 {
                        NinaDivider()
                    }

                    NinaRow(title: memory.title, subtitle: memory.detail) {
                        CategoryGlyph(systemName: memory.systemName)
                    } trailing: {
                        Text(memory.scopeLabel).ninaText(.meta, NinaTheme.muted)
                    }
                }
            }
        }
    }

    private var header: some View {
        HStack {
            Button {
                Haptics.selection()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(NinaTheme.ink)
                    .frame(width: 34, height: 34)
                    .background(NinaTheme.grout, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Fechar")

            Spacer()

            Eyebrow(text: "Memórias")

            Spacer()

            Color.clear.frame(width: 34, height: 34)
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
    }
}

#Preview("Profile editor") {
    ProfileEditorView(
        user: AuthUser(
            id: "preview",
            displayName: "Mirna",
            email: "mirna@ninai.app",
            provider: .email
        )
    )
    .environment(AppStore())
    .environment(ProfileStore())
}
