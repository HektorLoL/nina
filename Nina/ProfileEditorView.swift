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
    @State private var saveError: String?
    @State private var isSaving = false
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

    private var memoryCountValue: String {
        coreMemories.isEmpty ? "Nenhuma" : "\(coreMemories.count)"
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    Text("Meu perfil").ninaText(.screen)
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
                    .frame(width: 44, height: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Voltar")

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
    }

    private var nameField: some View {
        ProfileField(label: "Nome") {
            TextField("", text: $draft.displayName)
                .textContentType(.name)
                .submitLabel(.done)
                .focused($isNameFocused)
                .accessibilityLabel("Nome")
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
            Eyebrow(text: "Foto")

            HStack(alignment: .top, spacing: 14) {
                ProfileAvatarView(profile: draft, photoData: activePhotoData, size: 64)

                VStack(alignment: .leading, spacing: 8) {
                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        Text(hasPhoto ? "Trocar foto" : "Escolher foto")
                            .ninaText(.body, NinaTheme.ink, weight: .semibold)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 50)
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

            tonePicker
        }
    }

    private var tonePicker: some View {
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

    private var contactSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Eyebrow(text: "Contato")

            ProfileReadOnlyField(
                label: "Email",
                value: user.email ?? "Email não vinculado",
                note: user.provider == .email ? nil : user.provider.title
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
            Eyebrow(text: "Rotina")

            ProfileField(label: "Aniversário") {
                TextField("12 de maio", text: $draft.birthdayLabel)
            }

            ProfileField(label: "Disponibilidade") {
                TextField("Noites e sábados", text: $draft.availabilityNote, axis: .vertical)
                    .lineLimit(2...4)
            }
        }
    }

    private var ninaSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Eyebrow(text: "Nina")

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

            NinaDivider(inset: 0)

            Button(action: showCoreMemories) {
                NinaRow(title: "Memórias") {
                    CategoryGlyph(systemName: "bookmark")
                } trailing: {
                    HStack(spacing: 8) {
                        Text(memoryCountValue).ninaText(.label, NinaTheme.muted)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(NinaTheme.muted)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let saveError {
                Text(saveError)
                    .ninaText(.caption, NinaTheme.ink, weight: .medium)
                    .fixedSize(horizontal: false, vertical: true)
            }

            NinaButton(
                title: isSaving ? "Salvando" : "Salvar",
                fillsWidth: true,
                isEnabled: canSave,
                isPending: isSaving,
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

        guard !isSaving else { return }
        let hadServerPhoto = profileStore.profile(for: user).avatar.kind == .photo
        var preparedPhoto: Data?
        var removesPhoto = false

        // The photo is written first: a profile that points at a photo the disk
        // does not hold would render a face that cannot be loaded.
        if let pendingPhotoData {
            do {
                preparedPhoto = try profileStore.savePhotoData(pendingPhotoData, for: profile.userID)
                profile.avatar = profile.avatar.asPhoto(for: profile.userID)
            } catch {
                photoError = error.localizedDescription
                Haptics.error()
                return
            }
        } else if profile.avatar.kind == .preset {
            profileStore.deleteLocalPhoto(for: profile.userID)
            removesPhoto = hadServerPhoto
        }

        profileStore.saveProfile(profile, user: user)
        isSaving = true
        saveError = nil

        Task {
            let reachedServer = await profileStore.pushProfileToServer(
                profile,
                photoData: preparedPhoto,
                removesPhoto: removesPhoto,
                user: user
            )
            isSaving = false
            if reachedServer {
                Haptics.success()
                dismiss()
            } else {
                saveError = "Salvo só neste aparelho. Tente de novo."
                Haptics.error()
            }
        }
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
                    Haptics.selection()
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
                .ninaText(.body, NinaTheme.ink)
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
    var note: String?

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(label).ninaText(.meta, NinaTheme.muted)
                Text(value)
                    .ninaText(.body, NinaTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 8)

            if let note {
                Text(note).ninaText(.meta, NinaTheme.muted)
            }
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
            SheetHeader(eyebrow: "Memórias") {
                dismiss()
            }
            .padding(.top, 8)

            GeometryReader { proxy in
                ScrollView {
                    list
                        .padding(.horizontal, 20)
                        .padding(.top, 6)
                        .padding(.bottom, 28)
                        .frame(
                            minHeight: proxy.size.height,
                            alignment: memories.isEmpty ? .center : .top
                        )
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .ninaSheetBackground()
    }

    @ViewBuilder
    private var list: some View {
        if memories.isEmpty {
            ZeroState(
                headline: "Nada guardado ainda.",
                body_: "A Nina propõe guardar. Memórias começam privadas."
            )
        } else {
            VStack(alignment: .leading, spacing: 0) {
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

                Text("Para editar ou apagar, vá em Casa.")
                    .ninaText(.meta, NinaTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
            }
        }
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
