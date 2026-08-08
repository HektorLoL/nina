import SwiftUI

private enum HomeSetupMode: String, CaseIterable, Identifiable {
    case create
    case join

    var id: String { rawValue }

    var title: String {
        switch self {
        case .create: "Criar"
        case .join: "Entrar"
        }
    }
}

struct HomeSetupView: View {
    @Environment(AppStore.self) private var store
    @Environment(AuthSessionStore.self) private var authSession
    @Environment(OnboardingStore.self) private var onboardingStore

    @State private var mode: HomeSetupMode = .create
    @State private var homeName = ""
    @State private var inviteText = ""
    @State private var errorMessage: String?
    @FocusState private var focusedField: FocusedField?

    @State private var normalizedHomeName = ""
    @State private var canCreateHome = false
    @State private var normalizedInviteCode: String? = nil
    @State private var canJoinHome = false

    private enum FocusedField {
        case homeName
        case invite
    }

    private var displayedError: String? {
        errorMessage ?? store.syncErrorMessage
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    modePicker
                    modeContent
                }
                .padding(18)
                .padding(.bottom, 28)
            }
            .scrollDismissesKeyboard(.interactively)
            .ninaScreenBackground()
            .navigationTitle("Casa")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Sair") {
                        Task {
                            onboardingStore.cancelReplay()
                            await authSession.signOut()
                        }
                    }
                    .disabled(authSession.isSigningIn)
                }
            }
        }
        .onChange(of: mode) { _, _ in
            errorMessage = nil
        }
        .onChange(of: homeName) { _, newValue in
            let norm = AppStore.normalizedHomeName(newValue)
            normalizedHomeName = norm
            canCreateHome = !norm.isEmpty
        }
        .onChange(of: inviteText) { _, newValue in
            let code = AppStore.normalizedInviteCode(from: newValue)
            normalizedInviteCode = code
            canJoinHome = code != nil
        }
    }

    private var header: some View {
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
                    Text("Escolha sua casa")
                        .font(.title2.weight(.black))
                        .foregroundStyle(NinaTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Crie uma casa ou entre por convite para continuar.")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(NinaTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var modePicker: some View {
        Picker("Casa", selection: $mode) {
            ForEach(HomeSetupMode.allCases) { option in
                Text(option.title).tag(option)
            }
        }
        .pickerStyle(.segmented)
        .padding(5)
        .background(NinaTheme.field, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityLabel("Escolher criação ou entrada em uma casa")
    }

    @ViewBuilder
    private var modeContent: some View {
        switch mode {
        case .create:
            createHomeContent
                .transition(.opacity.combined(with: .move(edge: .leading)))
        case .join:
            joinHomeContent
                .transition(.opacity.combined(with: .move(edge: .trailing)))
        }
    }

    private var createHomeContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(title: "Criar casa", subtitle: "Nomeie a casa e compartilhe o convite com quem participa.")

            SoftCard(padding: 16) {
                HomeSetupField(
                    title: "Nome",
                    systemName: "house.fill",
                    placeholder: "Casa da família",
                    text: $homeName
                )
                .focused($focusedField, equals: .homeName)
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
                .onSubmit(createHome)

                Divider()

                invitePreview
            }

            PrimaryCapsuleButton(title: "Criar casa", systemName: "checkmark.circle.fill") {
                createHome()
            }
            .disabled(!canCreateHome || store.isSyncingHome)
            .opacity(canCreateHome && !store.isSyncingHome ? 1 : 0.5)

            if let displayedError {
                Label(displayedError, systemImage: "exclamationmark.circle.fill")
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(NinaTheme.coral)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var invitePreview: some View {
        if canCreateHome {
            HStack(alignment: .top, spacing: 12) {
                IconBubble(systemName: "lock.shield.fill", tone: .sky, size: 40)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Convite protegido")
                        .font(.headline.weight(.black))
                        .foregroundStyle(NinaTheme.ink)

                    Text("A Nina cria um link seguro quando a casa estiver pronta.")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(NinaTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } else {
            HStack(spacing: 12) {
                IconBubble(systemName: "link", tone: .sky, size: 40)

                Text("Digite um nome para preparar a casa.")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(NinaTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var joinHomeContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(
                title: "Pedir entrada",
                subtitle: "Use o código ou link; uma pessoa responsável aprova seu acesso."
            )

            SoftCard(padding: 16) {
                HomeSetupField(
                    title: "Convite",
                    systemName: "link",
                    placeholder: "casa-47a9f2d0b3c1e8a4d6f2",
                    text: $inviteText
                )
                .focused($focusedField, equals: .invite)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.join)
                .onSubmit(joinHome)

                if let normalizedCode = normalizedInviteCode {
                    Divider()

                    HStack(spacing: 12) {
                        IconBubble(systemName: "checkmark.seal.fill", tone: .mint, size: 40)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Convite encontrado")
                                .font(.headline.weight(.black))
                                .foregroundStyle(NinaTheme.ink)

                            Text(normalizedCode)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(NinaTheme.muted)
                        }
                    }
                }
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(NinaTheme.coral)
                    .fixedSize(horizontal: false, vertical: true)
            }

            PrimaryCapsuleButton(title: "Pedir para entrar", systemName: "paperplane.fill") {
                joinHome()
            }
            .disabled(!canJoinHome || store.isSyncingHome)
            .opacity(canJoinHome && !store.isSyncingHome ? 1 : 0.5)

            if let displayedError {
                Label(displayedError, systemImage: "exclamationmark.circle.fill")
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(NinaTheme.coral)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func createHome() {
        guard canCreateHome else { return }
        focusedField = nil
        Task {
            _ = await store.createHome(named: homeName, owner: authSession.currentUser)
        }
    }

    private func joinHome() {
        guard canJoinHome else {
            errorMessage = "Cole um código ou link de convite válido."
            return
        }

        focusedField = nil
        errorMessage = nil

        Task {
            if !(await store.joinHome(with: inviteText, member: authSession.currentUser)) {
                errorMessage = store.syncErrorMessage ?? "Não foi possível abrir esse convite."
            }
        }
    }
}

private struct HomeSetupField: View {
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
                .font(.headline.weight(.bold))
                .foregroundStyle(NinaTheme.ink)
                .multilineTextAlignment(.trailing)
                .textFieldStyle(.plain)
                .lineLimit(1)
        }
        .padding(.vertical, 2)
    }
}
