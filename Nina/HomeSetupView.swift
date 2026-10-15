import SwiftUI

enum HomeSetupMode {
    case choose
    case create
    case join
}

enum HomeSetupArrival {
    static func focus(mode: HomeSetupMode, voiceOverOn: Bool) -> HomeSetupView.FocusedField? {
        guard !voiceOverOn else { return nil }
        switch mode {
        case .choose:
            return nil
        case .create:
            return .homeName
        case .join:
            return .invite
        }
    }
}

struct HomeSetupView: View {
    @Environment(AppStore.self) private var store
    @Environment(AuthSessionStore.self) private var authSession
    @Environment(OnboardingStore.self) private var onboardingStore
    @Environment(ProfileStore.self) private var profileStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled

    @State private var mode: HomeSetupMode
    @State private var homeName = ""
    @State private var inviteText = ""
    @State private var firstName = ""
    @State private var errorMessage: String?
    @State private var isSavingName = false
    @FocusState private var focusedField: FocusedField?

    @State private var canCreateHome = false
    @State private var canJoinHome = false
    @State private var isShowingDeletion = false

    enum FocusedField {
        case homeName
        case invite
        case firstName
    }

    // Creating and joining weigh the same on arrival, so a partner who lost the link does not open a second house.
    init(initialMode: HomeSetupMode = .choose) {
        _mode = State(initialValue: initialMode)
    }

    private var knownName: String? {
        authSession.currentUser.flatMap { profileStore.profiles[$0.id]?.displayName }
    }

    // The house copies this name into the member row it creates, so a placeholder must never reach it.
    private var needsName: Bool {
        ProfileNaming.asksForName(
            user: authSession.currentUser,
            knownName: knownName,
            sharedGivenName: authSession.sharedGivenName
        )
    }

    private var hasChosenName: Bool {
        !needsName || !ProfileNaming.isPlaceholder(firstName)
    }

    private var displayedError: String? {
        errorMessage ?? store.syncErrorMessage ?? authSession.errorMessage
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            if mode == .choose {
                choosePath
            } else {
                ScrollView {
                    modeContent
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                        .padding(.bottom, 16)
                }
                .scrollDismissesKeyboard(.interactively)
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .ninaScreenBackground()
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: mode)
        .onChange(of: mode) { _, _ in
            errorMessage = nil
        }
        .task(id: mode) {
            await Task.yield()
            focusedField = HomeSetupArrival.focus(mode: mode, voiceOverOn: voiceOverEnabled)
        }
        .onChange(of: homeName) { _, newValue in
            canCreateHome = !AppStore.normalizedHomeName(newValue).isEmpty
        }
        .onChange(of: inviteText) { _, newValue in
            canJoinHome = AppStore.normalizedInviteCode(from: newValue) != nil
        }
        .accountDeletionSheet(isPresented: $isShowingDeletion)
    }

    // "Sair da conta" never wraps beside the wordmark; where it would, it moves into the menu.
    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                NinaWordmark(size: 20)

                Spacer()

                optionsMenu(includesSignOut: false)

                Button(action: signOut) {
                    Text("Sair da conta")
                        .ninaText(.label, NinaTheme.muted, weight: .semibold)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .disabled(isSigningOutBlocked)
                .opacity(isSigningOutBlocked ? 0.4 : 1)
            }

            HStack {
                NinaWordmark(size: 20)

                Spacer()

                optionsMenu(includesSignOut: true)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
    }

    private var isSigningOutBlocked: Bool {
        authSession.isSigningIn || isSavingName
    }

    private func optionsMenu(includesSignOut: Bool) -> some View {
        Menu {
            if includesSignOut {
                Button("Sair da conta", action: signOut)
                    .disabled(isSigningOutBlocked)
            }

            Button("Apagar conta") {
                Haptics.lightImpact()
                isShowingDeletion = true
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(NinaTheme.muted)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Mais opções")
    }

    private func signOut() {
        Haptics.selection()
        Task {
            onboardingStore.cancelReplay()
            await authSession.signOut()
        }
    }

    @ViewBuilder
    private var modeContent: some View {
        switch mode {
        case .choose, .create:
            createPath
        case .join:
            joinPath
        }
    }

    private var choosePath: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 32)

                    VStack(spacing: 14) {
                        Text("Primeiro, a casa.")
                            .ninaText(.display)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("Se alguém da casa já usa a Nina, peça o convite.")
                            .ninaText(.label, NinaTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .multilineTextAlignment(.center)

                    Spacer(minLength: 32)

                    VStack(spacing: 12) {
                        NinaButton(title: "Criar uma casa", kind: .outline, fillsWidth: true) {
                            Haptics.selection()
                            mode = .create
                        }

                        NinaButton(title: "Tenho um convite", kind: .outline, fillsWidth: true) {
                            Haptics.selection()
                            mode = .join
                        }

                        if let displayedError {
                            errorLine(displayedError)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
                .frame(minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private var createPath: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 22) {
                Text("Toda casa começa com um nome.")
                    .ninaText(.display)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 10) {
                    HomeSetupField(title: "Nome da casa") {
                        TextField("Nossa casa", text: $homeName)
                            .textInputAutocapitalization(.words)
                            .submitLabel(needsName ? .next : .done)
                            .focused($focusedField, equals: .homeName)
                            .onSubmit {
                                if needsName {
                                    focusedField = .firstName
                                } else {
                                    createHome()
                                }
                            }
                    }

                    if needsName {
                        ChosenNameField(name: $firstName, focus: $focusedField, focusValue: .firstName)
                            .submitLabel(.done)
                            .onSubmit(createHome)
                    }
                }
            }

            actionGroup(
                title: store.isSyncingHome || isSavingName ? "Criando" : "Criar",
                isEnabled: canCreateHome && hasChosenName && !store.isSyncingHome && !isSavingName,
                action: createHome,
                alternateTitle: "Tenho um convite",
                alternateTarget: .join
            )
            .padding(.top, 28)
        }
    }

    private var joinPath: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 22) {
                Text("Entrar numa casa.")
                    .ninaText(.display)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 10) {
                    HomeSetupField(title: "Link ou código") {
                        TextField("casa-47a9f2d0b3c1e8a4d6f2", text: $inviteText)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(needsName ? .next : .join)
                            .focused($focusedField, equals: .invite)
                            .onSubmit {
                                if needsName {
                                    focusedField = .firstName
                                } else {
                                    joinHome()
                                }
                            }
                    }

                    if needsName {
                        ChosenNameField(name: $firstName, focus: $focusedField, focusValue: .firstName)
                            .submitLabel(.join)
                            .onSubmit(joinHome)
                    }

                    // Possessing an invite grants nothing: it opens a request an owner approves.
                    Text("Ter o convite não dá acesso. Alguém da casa aprova.")
                        .ninaText(.label, NinaTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            actionGroup(
                title: store.isSyncingHome || isSavingName ? "Enviando" : "Pedir para entrar",
                isEnabled: canJoinHome && hasChosenName && !store.isSyncingHome && !isSavingName,
                action: joinHome,
                alternateTitle: "Criar uma casa",
                alternateTarget: .create
            )
            .padding(.top, 28)
        }
    }

    private func actionGroup(
        title: String,
        isEnabled: Bool,
        action: @escaping () -> Void,
        alternateTitle: String,
        alternateTarget: HomeSetupMode
    ) -> some View {
        VStack(spacing: 12) {
            NinaButton(title: title, fillsWidth: true, isEnabled: isEnabled, action: action)

            if let displayedError {
                errorLine(displayedError)
            }

            NinaButton(title: alternateTitle, kind: .quiet) {
                Haptics.selection()
                mode = alternateTarget
            }
        }
    }

    private func errorLine(_ message: String) -> some View {
        NinaErrorNote(text: message, alignment: .center)
            .frame(maxWidth: .infinity)
    }

    private func createHome() {
        guard canCreateHome, hasChosenName, !isSavingName else { return }
        focusedField = nil
        errorMessage = nil
        Task {
            guard await saveChosenNameIfNeeded() else { return }
            if await store.createHome(named: homeName, owner: authSession.currentUser) {
                Haptics.success()
            }
        }
    }

    private func joinHome() {
        guard canJoinHome else {
            errorMessage = "Cole um código ou link de convite válido."
            Haptics.error()
            return
        }
        guard hasChosenName, !isSavingName else { return }

        focusedField = nil
        errorMessage = nil

        Task {
            guard await saveChosenNameIfNeeded() else { return }
            if await store.joinHome(with: inviteText, member: authSession.currentUser) {
                Haptics.success()
            } else {
                errorMessage = store.syncErrorMessage ?? "Não deu para abrir esse convite agora. Tente de novo."
            }
        }
    }

    private func saveChosenNameIfNeeded() async -> Bool {
        guard let user = authSession.currentUser else { return false }
        guard let name = ProfileNaming.nameToSave(
            user: user,
            knownName: knownName,
            sharedGivenName: authSession.sharedGivenName,
            typed: firstName
        ) else { return true }
        isSavingName = true
        defer { isSavingName = false }
        let saved = await profileStore.chooseDisplayName(name, for: user)
        guard authSession.currentUser?.id == user.id else { return false }
        guard saved else {
            errorMessage = ChosenNameCopy.saveFailed
            return false
        }
        authSession.noteChosenDisplayName(name)
        return true
    }
}

// An adult names themself where the house first needs the name, in the same words the minor path uses.
enum ChosenNameCopy {
    static let title = "Seu primeiro nome"
    static let placeholder = "Como a casa chama você"
    static let saveFailed = "Não deu para salvar seu nome. Tente de novo."
}

struct ChosenNameField<Focus: Hashable>: View {
    @Binding var name: String
    var focus: FocusState<Focus>.Binding
    var focusValue: Focus

    var body: some View {
        HomeSetupField(title: ChosenNameCopy.title) {
            TextField(ChosenNameCopy.placeholder, text: $name)
                .textContentType(.givenName)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .focused(focus, equals: focusValue)
                .accessibilityLabel(ChosenNameCopy.title)
        }
    }
}

struct HomeSetupField<Field: View>: View {
    var title: String
    @ViewBuilder var field: Field

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .ninaText(.meta, NinaTheme.muted)
                .accessibilityHidden(true)

            field
                .ninaText(.body, NinaTheme.ink)
                .textFieldStyle(.plain)
                .lineLimit(1)
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
