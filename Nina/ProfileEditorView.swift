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

    private var coreMemories: [ProfileCoreMemory] {
        appStore.ninaMemories.map { memory in
            ProfileCoreMemory(
                id: memory.id.uuidString,
                title: memory.title,
                detail: memory.body,
                systemName: memory.visibility == .shared ? "house.fill" : "person.fill",
                tone: memory.visibility == .shared ? .mint : .sky
            )
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                identitySection
                avatarSection
                contactSection
                routineSection
                ninaSection

                PrimaryCapsuleButton(title: "Salvar perfil", systemName: "checkmark") {
                    saveProfile()
                }
                .disabled(!canSave)
                .opacity(canSave ? 1 : 0.5)
            }
            .padding(18)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .ninaScreenBackground()
        .navigationTitle("Meu perfil")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancelar") {
                    Haptics.selection()
                    dismiss()
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button("Salvar") {
                    saveProfile()
                }
                .disabled(!canSave)
            }
        }
        .onAppear(perform: loadProfileIfNeeded)
        .onChange(of: selectedPhotoItem) { _, newItem in
            loadPhoto(from: newItem)
        }
        .sheet(isPresented: $isShowingCoreMemories) {
            NavigationStack {
                ProfileCoreMemoriesSheet(memories: coreMemories)
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    private var header: some View {
        SoftCard(padding: 18) {
            HStack(spacing: 16) {
                ProfileAvatarView(profile: draft, photoData: activePhotoData, size: 76)

                VStack(alignment: .leading, spacing: 6) {
                    Text(draft.displayName.isEmpty ? "Seu perfil" : draft.displayName)
                        .font(.title2.weight(.black))
                        .foregroundStyle(NinaTheme.ink)
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)

                    Text("A Nina usa isso para falar com você do jeito certo.")
                        .font(.subheadline)
                        .foregroundStyle(NinaTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var identitySection: some View {
        ProfileEditorGroup(title: "Identidade") {
            ProfileTextFieldRow(
                title: "Nome",
                systemName: "person.fill",
                tone: .mint,
                placeholder: "Seu nome",
                text: $draft.displayName
            )

            ProfileDivider()

            ProfileMenuChoiceRow(
                title: "Sexo",
                selectedTitle: draft.sex.title,
                systemName: "person.crop.circle.fill",
                tone: .lavender
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

            ProfileDivider()

            ProfileMenuChoiceRow(
                title: "Papel na casa",
                selectedTitle: draft.householdRole.title,
                systemName: draft.householdRole.symbolName,
                tone: .sky
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

    private var avatarSection: some View {
        ProfileEditorGroup(title: "Foto e avatar") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    ProfileAvatarView(profile: draft, photoData: activePhotoData, size: 82)

                    VStack(alignment: .leading, spacing: 10) {
                        PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                            Label("Escolher foto", systemImage: "photo.on.rectangle.angled")
                                .font(.headline.weight(.heavy))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(NinaTheme.sky, in: Capsule())
                        }
                        .buttonStyle(.plain)

                        if draft.avatar.kind == .photo || pendingPhotoData != nil {
                            Button {
                                removePhoto()
                            } label: {
                                Label("Remover foto", systemImage: "trash.fill")
                                    .font(.subheadline.weight(.heavy))
                                    .foregroundStyle(NinaTheme.coral)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if let photoError {
                    Label(photoError, systemImage: "exclamationmark.circle.fill")
                        .font(.caption.weight(.heavy))
                        .foregroundStyle(NinaTheme.coral)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text("A foto é convertida para JPEG e reduzida para \(ProfilePhotoPolicy.limitDescription) antes do envio.")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(NinaTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Ou escolha uma base visual para o perfil.")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(NinaTheme.muted)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 74), spacing: 10)], spacing: 10) {
                    ForEach(ProfileAvatarPreset.all) { preset in
                        Button {
                            selectPreset(preset)
                        } label: {
                            VStack(spacing: 8) {
                                ProfileAvatarGlyph(variantID: preset.symbolName, tone: preset.tone, size: 46)

                                Text(preset.title)
                                    .font(.caption2.weight(.black))
                                    .foregroundStyle(NinaTheme.ink)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.72)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 76)
                            .background(
                                preset.id == draft.avatar.presetID && draft.avatar.kind == .preset ? preset.tone.softColor : NinaTheme.field,
                                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(preset.id == draft.avatar.presetID && draft.avatar.kind == .preset ? preset.tone.color : NinaTheme.line, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(14)
        }
    }

    private var contactSection: some View {
        ProfileEditorGroup(title: "Contato") {
            ProfileReadOnlyRow(
                title: "Email",
                value: user.email ?? "Email não vinculado",
                systemName: user.provider.systemImage,
                tone: user.provider == .apple ? .lavender : .mint
            )

            ProfileDivider()

            ProfileTextFieldRow(
                title: "Telefone",
                systemName: "phone.fill",
                tone: .sky,
                placeholder: "(00) 00000-0000",
                text: $draft.phone,
                keyboardType: .phonePad
            )
        }
    }

    private var routineSection: some View {
        ProfileEditorGroup(title: "Rotina da casa") {
            ProfileTextFieldRow(
                title: "Aniversário",
                systemName: "birthday.cake.fill",
                tone: .amber,
                placeholder: "Ex.: 12 de maio",
                text: $draft.birthdayLabel
            )

            ProfileDivider()

            ProfileTextFieldRow(
                title: "Disponibilidade",
                systemName: "clock.fill",
                tone: .mint,
                placeholder: "Quando costuma resolver coisas da casa?",
                text: $draft.availabilityNote,
                axis: .vertical
            )
        }
    }

    private var ninaSection: some View {
        ProfileEditorGroup(title: "Como a Nina ajuda") {
            ProfileMenuChoiceRow(
                title: "Tom das sugestões",
                selectedTitle: draft.communicationPreference.title,
                detail: draft.communicationPreference.detail,
                systemName: "quote.bubble.fill",
                tone: .lavender
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

            ProfileDivider()

            ProfileMemorySummaryRow(
                count: coreMemories.count,
                preview: coreMemories.first?.detail ?? "A Nina ainda não registrou memórias principais.",
                action: showCoreMemories
            )
        }
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
        Haptics.selection()
        isShowingCoreMemories = true
    }

    private func selectPreset(_ preset: ProfileAvatarPreset) {
        Haptics.selection()
        pendingPhotoData = nil
        photoError = nil
        draft.avatar = preset.avatar
    }

    private func removePhoto() {
        Haptics.warning()
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

struct ProfileAvatarView: View {
    var profile: UserProfile
    var photoData: Data?
    var size: CGFloat = 48

    var body: some View {
        ZStack {
            if let photoData,
               profile.avatar.kind == .photo,
               let image = platformImage(from: photoData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                ProfileAvatarGlyph(variantID: profile.avatar.symbolName, tone: profile.avatar.tone, size: size)
            }
        }
        .frame(width: size, height: size)
        .overlay(
            Circle()
                .stroke(NinaTheme.cardStroke, lineWidth: 1)
        )
        .shadow(color: profile.avatar.tone.color.opacity(0.18), radius: 12, x: 0, y: 7)
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

private enum ProfileAvatarFeature: Equatable {
    case base
    case shortHair
    case longHair
    case bangs
    case glasses
    case smile
    case collar
    case soft

    static func from(_ variantID: String) -> ProfileAvatarFeature {
        switch variantID {
        case "avatar.shortHair": .shortHair
        case "avatar.longHair": .longHair
        case "avatar.bangs": .bangs
        case "avatar.glasses": .glasses
        case "avatar.smile": .smile
        case "avatar.collar": .collar
        case "avatar.soft": .soft
        default: .base
        }
    }
}

private struct ProfileAvatarGlyph: View {
    var variantID: String
    var tone: MemberTone
    var size: CGFloat

    private var feature: ProfileAvatarFeature {
        ProfileAvatarFeature.from(variantID)
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(tone.softColor)

            if feature == .longHair {
                RoundedRectangle(cornerRadius: size * 0.16, style: .continuous)
                    .fill(tone.color.opacity(0.24))
                    .frame(width: size * 0.34, height: size * 0.42)
                    .offset(y: size * 0.02)
            }

            Circle()
                .fill(tone.color.opacity(feature == .soft ? 0.72 : 0.9))
                .frame(width: size * 0.25, height: size * 0.25)
                .offset(y: -size * 0.12)

            Capsule()
                .fill(tone.color.opacity(feature == .soft ? 0.72 : 0.9))
                .frame(width: size * 0.52, height: size * 0.28)
                .offset(y: size * 0.19)

            avatarAccessory
        }
        .frame(width: size, height: size)
    }

    @ViewBuilder
    private var avatarAccessory: some View {
        switch feature {
        case .base:
            EmptyView()
        case .shortHair:
            Capsule()
                .fill(tone.color)
                .frame(width: size * 0.23, height: size * 0.08)
                .offset(y: -size * 0.24)
        case .longHair:
            Circle()
                .trim(from: 0.0, to: 0.5)
                .stroke(tone.color.opacity(0.8), style: StrokeStyle(lineWidth: size * 0.04, lineCap: .round))
                .frame(width: size * 0.34, height: size * 0.30)
                .rotationEffect(.degrees(180))
                .offset(y: -size * 0.13)
        case .bangs:
            HStack(spacing: size * 0.015) {
                ForEach(0..<3, id: \.self) { _ in
                    Capsule()
                        .fill(tone.color)
                        .frame(width: size * 0.055, height: size * 0.12)
                }
            }
            .rotationEffect(.degrees(-8))
            .offset(y: -size * 0.22)
        case .glasses:
            HStack(spacing: size * 0.03) {
                Circle()
                    .stroke(NinaTheme.field, lineWidth: max(1.4, size * 0.035))
                    .frame(width: size * 0.11, height: size * 0.11)

                Circle()
                    .stroke(NinaTheme.field, lineWidth: max(1.4, size * 0.035))
                    .frame(width: size * 0.11, height: size * 0.11)
            }
            .overlay(
                Capsule()
                    .fill(NinaTheme.field)
                    .frame(width: size * 0.06, height: max(1.2, size * 0.025))
            )
            .offset(y: -size * 0.12)
        case .smile:
            Capsule()
                .fill(NinaTheme.field)
                .frame(width: size * 0.13, height: max(1.6, size * 0.035))
                .offset(y: -size * 0.05)
        case .collar:
            HStack(spacing: size * 0.04) {
                Capsule()
                    .fill(NinaTheme.field.opacity(0.9))
                    .frame(width: size * 0.08, height: size * 0.18)
                    .rotationEffect(.degrees(-28))

                Capsule()
                    .fill(NinaTheme.field.opacity(0.9))
                    .frame(width: size * 0.08, height: size * 0.18)
                    .rotationEffect(.degrees(28))
            }
            .offset(y: size * 0.11)
        case .soft:
            HStack(spacing: size * 0.20) {
                Circle()
                    .fill(NinaTheme.card.opacity(0.75))
                    .frame(width: size * 0.05, height: size * 0.05)

                Circle()
                    .fill(NinaTheme.card.opacity(0.75))
                    .frame(width: size * 0.05, height: size * 0.05)
            }
            .offset(y: -size * 0.08)
        }
    }
}

private struct ProfileEditorGroup<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.black))
                .foregroundStyle(NinaTheme.muted)
                .padding(.horizontal, 2)

            SoftCard(padding: 0) {
                VStack(spacing: 0) {
                    content
                }
            }
        }
    }
}

private struct ProfileTextFieldRow: View {
    var title: String
    var systemName: String
    var tone: MemberTone
    var placeholder: String
    @Binding var text: String
    var axis: Axis = .horizontal
    var keyboardType: UIKeyboardType = .default

    var body: some View {
        HStack(alignment: axis == .vertical ? .top : .center, spacing: 12) {
            IconBubble(systemName: systemName, tone: tone, size: 40)

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.caption.weight(.black))
                    .foregroundStyle(NinaTheme.muted)

                TextField(placeholder, text: $text, axis: axis)
                    .lineLimit(axis == .vertical ? 2...4 : 1...1)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(NinaTheme.ink)
                    .keyboardType(keyboardType)
                    .textFieldStyle(.plain)
            }
        }
        .padding(14)
    }
}

private struct ProfileReadOnlyRow: View {
    var title: String
    var value: String
    var systemName: String
    var tone: MemberTone

    var body: some View {
        HStack(spacing: 12) {
            IconBubble(systemName: systemName, tone: tone, size: 40)

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.caption.weight(.black))
                    .foregroundStyle(NinaTheme.muted)

                Text(value)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(NinaTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }

            Spacer(minLength: 12)

            Text("login")
                .font(.caption.weight(.black))
                .foregroundStyle(NinaTheme.muted)
        }
        .padding(14)
    }
}

private struct ProfileMenuChoiceRow<MenuContent: View>: View {
    var title: String
    var selectedTitle: String
    var detail: String?
    var systemName: String
    var tone: MemberTone
    @ViewBuilder var menuContent: MenuContent

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            IconBubble(systemName: systemName, tone: tone, size: 40)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(title)
                        .font(.headline.weight(.heavy))
                        .foregroundStyle(NinaTheme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.76)
                        .layoutPriority(1)

                    Spacer(minLength: 6)

                    Menu {
                        menuContent
                    } label: {
                        HStack(spacing: 6) {
                            Text(selectedTitle)
                                .font(.subheadline.weight(.heavy))
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)

                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 12, weight: .black))
                        }
                        .foregroundStyle(tone.color)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(tone.softColor, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .layoutPriority(2)
                    .accessibilityLabel(title)
                    .accessibilityValue(selectedTitle)
                }

                if let detail {
                    Text(detail)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(NinaTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(14)
    }
}

private struct ProfileMemorySummaryRow: View {
    var count: Int
    var preview: String
    var action: () -> Void

    private var countLabel: String {
        count == 1 ? "1 memória principal" : "\(count) memórias principais"
    }

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                IconBubble(systemName: "brain.head.profile", tone: .sky, size: 40)

                VStack(alignment: .leading, spacing: 5) {
                    Text("Memória pessoal")
                        .font(.caption.weight(.black))
                        .foregroundStyle(NinaTheme.muted)

                    Text(countLabel)
                        .font(.headline.weight(.heavy))
                        .foregroundStyle(NinaTheme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)

                    Text(preview)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(NinaTheme.muted)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(NinaTheme.sky)
                    .padding(.top, 22)
            }
            .contentShape(Rectangle())
            .padding(14)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Abre a lista completa de memórias da Nina")
    }
}

private struct ProfileDivider: View {
    var body: some View {
        Divider()
            .padding(.leading, 66)
    }
}

private struct ProfileCoreMemory: Identifiable, Hashable {
    var id: String
    var title: String
    var detail: String
    var systemName: String
    var tone: MemberTone
}

private struct ProfileCoreMemoriesSheet: View {
    @Environment(\.dismiss) private var dismiss

    var memories: [ProfileCoreMemory]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SectionTitle(
                    title: "Memórias da Nina",
                    subtitle: "Somente memórias confirmadas. Você pode editar, apagar e mudar a privacidade na tela Casa."
                )
                .padding(.bottom, 2)

                ForEach(memories) { memory in
                    ProfileCoreMemoryRow(memory: memory)
                }
            }
            .padding(18)
            .padding(.bottom, 20)
        }
        .ninaSheetBackground()
        .navigationTitle("Memórias")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Fechar") {
                    Haptics.selection()
                    dismiss()
                }
            }
        }
    }
}

private struct ProfileCoreMemoryRow: View {
    var memory: ProfileCoreMemory

    var body: some View {
        SoftCard(padding: 14) {
            HStack(alignment: .top, spacing: 12) {
                IconBubble(systemName: memory.systemName, tone: memory.tone, size: 40)

                VStack(alignment: .leading, spacing: 5) {
                    Text(memory.title)
                        .font(.caption.weight(.black))
                        .foregroundStyle(NinaTheme.muted)

                    Text(memory.detail)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(NinaTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

#Preview("Profile editor") {
    let authUser = AuthUser(id: "preview", displayName: "Mirna", email: "mirna@ninai.app", provider: .email)

    return NavigationStack {
        ProfileEditorView(user: authUser)
            .environment(AppStore())
            .environment(ProfileStore())
    }
}
