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
        VStack(spacing: 0) {
            header

            ScrollView {
                modeContent
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 34)
                    .frame(maxWidth: 520)
                    .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .ninaScreenBackground()
        .animation(.easeInOut(duration: 0.2), value: mode)
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
        HStack {
            NinaWordmark(size: 20)

            Spacer()

            Button {
                Task {
                    onboardingStore.cancelReplay()
                    await authSession.signOut()
                }
            } label: {
                Text("Sair").ninaText(.label, NinaTheme.muted, weight: .semibold)
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
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Toda casa começa com um nome.")
                    .ninaText(.display)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Crie a sua e chame o resto da família quando quiser. Uma casa de uma pessoa só já é uma casa.")
                    .ninaText(.label, NinaTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HomeSetupField(title: "Nome da casa") {
                TextField("Casa Castello", text: $homeName)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .focused($focusedField, equals: .homeName)
                    .onSubmit(createHome)
            }

            housePreview

            VStack(alignment: .leading, spacing: 10) {
                NinaButton(
                    title: store.isSyncingHome ? "Criando..." : "Criar a casa",
                    fillsWidth: true,
                    isEnabled: canCreateHome && !store.isSyncingHome
                ) {
                    createHome()
                }

                if let displayedError {
                    errorLine(displayedError)
                }
            }

            alternatePath(
                caption: "Alguém já te chamou para uma casa?",
                title: "Tenho um convite",
                target: .join
            )
        }
    }

    private var housePreview: some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow(text: "A sua casa")
                .padding(.bottom, 4)

            NinaRow(
                title: canCreateHome ? normalizedHomeName : "Sem nome ainda",
                subtitle: canCreateHome
                    ? "Você entra como responsável pela casa"
                    : "Escreva acima como ela se chama",
                titleColor: canCreateHome ? NinaTheme.ink : NinaTheme.muted
            ) {
                if canCreateHome {
                    MemberAvatar(initials: normalizedHomeName.ninaInitials, tone: .mint, size: 34)
                } else {
                    CategoryGlyph(systemName: "house", size: 20, tint: NinaTheme.muted)
                }
            } trailing: {
                EmptyView()
            }

            NinaDivider()

            NinaRow(
                title: "A Nina não ocupa vaga",
                subtitle: "Cabem 8 pessoas na casa, e ela não é uma delas."
            ) {
                NinaMark(size: 30)
            } trailing: {
                EmptyView()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ninaCard()
    }

    private var joinPath: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Entrar numa casa que já existe.")
                    .ninaText(.display)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Cole o link ou o código que te mandaram.")
                    .ninaText(.label, NinaTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HomeSetupField(title: "Convite") {
                TextField("casa-47a9f2d0b3c1e8a4d6f2", text: $inviteText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.join)
                    .focused($focusedField, equals: .invite)
                    .onSubmit(joinHome)
            }

            joinConsequence

            VStack(alignment: .leading, spacing: 10) {
                NinaButton(
                    title: store.isSyncingHome ? "Enviando..." : "Pedir para entrar",
                    fillsWidth: true,
                    isEnabled: canJoinHome && !store.isSyncingHome
                ) {
                    joinHome()
                }

                if let displayedError {
                    errorLine(displayedError)
                }
            }

            alternatePath(
                caption: "Ninguém te chamou ainda?",
                title: "Criar a minha casa",
                target: .create
            )
        }
    }

    private var joinConsequence: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: "O que este código faz")

            // Possessing an invite grants nothing: it opens a request an owner approves.
            Text("Ter o código não dá acesso a nada. Ele abre um pedido, e alguém da casa precisa aprovar. Até lá você não vê nenhuma tarefa, nenhuma conta, nenhuma criança de lá.")
                .ninaText(.label, NinaTheme.ink)
                .fixedSize(horizontal: false, vertical: true)

            if let normalizedInviteCode {
                NinaDivider(inset: 0)
                    .padding(.vertical, 2)

                VStack(alignment: .leading, spacing: 2) {
                    Text(normalizedInviteCode)
                        .ninaText(.caption, NinaTheme.ink, weight: .semibold)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    // The screen must never look like it validated a code: the app
                    // learns nothing about the house until the request is sent.
                    Text("A casa só confere este código quando você pedir entrada.")
                        .ninaText(.meta, NinaTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ninaCard()
    }

    private func alternatePath(
        caption: String,
        title: String,
        target: HomeSetupMode
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            NinaDivider(inset: 0)
                .padding(.bottom, 10)

            Text(caption)
                .ninaText(.caption, NinaTheme.muted)
                .fixedSize(horizontal: false, vertical: true)

            NinaButton(title: title, kind: .quiet) {
                Haptics.selection()
                focusedField = nil
                mode = target
            }
        }
    }

    private func errorLine(_ message: String) -> some View {
        Text(message)
            .ninaText(.caption, NinaTheme.ink, weight: .semibold)
            .fixedSize(horizontal: false, vertical: true)
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
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(NinaTheme.ink)
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
