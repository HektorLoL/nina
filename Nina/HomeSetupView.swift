import SwiftUI

private enum HomeSetupMode {
    case create
    case join
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

    @State private var canCreateHome = false
    @State private var canJoinHome = false

    private enum FocusedField {
        case homeName
        case invite
    }

    private var displayedError: String? {
        errorMessage ?? store.syncErrorMessage ?? authSession.errorMessage
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            GeometryReader { proxy in
                ScrollView {
                    modeContent
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                        .padding(.bottom, 16)
                        .frame(minHeight: proxy.size.height)
                }
                .scrollDismissesKeyboard(.interactively)
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .ninaScreenBackground()
        .animation(.easeInOut(duration: 0.2), value: mode)
        .onChange(of: mode) { _, _ in
            errorMessage = nil
        }
        .onChange(of: homeName) { _, newValue in
            canCreateHome = !AppStore.normalizedHomeName(newValue).isEmpty
        }
        .onChange(of: inviteText) { _, newValue in
            canJoinHome = AppStore.normalizedInviteCode(from: newValue) != nil
        }
    }

    private var header: some View {
        HStack {
            NinaWordmark(size: 20)

            Spacer()

            Button {
                Haptics.warning()
                Task {
                    onboardingStore.cancelReplay()
                    await authSession.signOut()
                }
            } label: {
                Text("Sair da conta")
                    .ninaText(.label, NinaTheme.muted, weight: .semibold)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .disabled(authSession.isSigningIn)
            .opacity(authSession.isSigningIn ? 0.4 : 1)
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
    }

    @ViewBuilder
    private var modeContent: some View {
        switch mode {
        case .create:
            createPath
        case .join:
            joinPath
        }
    }

    private var createPath: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 22) {
                Text("Toda casa começa com um nome.")
                    .ninaText(.display)
                    .fixedSize(horizontal: false, vertical: true)

                HomeSetupField(title: "Nome da casa") {
                    TextField("Casa Castello", text: $homeName)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .focused($focusedField, equals: .homeName)
                        .onSubmit(createHome)
                }
            }

            Spacer(minLength: 32)

            actionGroup(
                title: store.isSyncingHome ? "Criando" : "Criar",
                isEnabled: canCreateHome && !store.isSyncingHome,
                action: createHome,
                alternateTitle: "Tenho um convite",
                alternateTarget: .join
            )
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
                            .submitLabel(.join)
                            .focused($focusedField, equals: .invite)
                            .onSubmit(joinHome)
                    }

                    // Possessing an invite grants nothing: it opens a request an owner approves.
                    Text("Ter o convite não dá acesso. Alguém da casa aprova.")
                        .ninaText(.label, NinaTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 32)

            actionGroup(
                title: store.isSyncingHome ? "Enviando" : "Pedir para entrar",
                isEnabled: canJoinHome && !store.isSyncingHome,
                action: joinHome,
                alternateTitle: "Criar minha casa",
                alternateTarget: .create
            )
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
                focusedField = nil
                mode = alternateTarget
            }
        }
    }

    private func errorLine(_ message: String) -> some View {
        Text(message)
            .ninaText(.caption, NinaTheme.ink, weight: .semibold)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
    }

    private func createHome() {
        guard canCreateHome else { return }
        focusedField = nil
        Task {
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

        focusedField = nil
        errorMessage = nil

        Task {
            if await store.joinHome(with: inviteText, member: authSession.currentUser) {
                Haptics.success()
            } else {
                errorMessage = store.syncErrorMessage ?? "Não foi possível abrir esse convite."
            }
        }
    }
}

private struct HomeSetupField<Field: View>: View {
    var title: String
    @ViewBuilder var field: Field

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).ninaText(.meta, NinaTheme.muted)

            field
                .ninaText(.body, NinaTheme.ink)
                .textFieldStyle(.plain)
                .lineLimit(1)
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
