import AuthenticationServices
import SwiftUI

struct LoginView: View {
    @Environment(AuthSessionStore.self) private var authSession
    @Environment(InviteLinkStore.self) private var inviteLinkStore
    @Environment(\.scenePhase) private var scenePhase

    @State private var appleRawNonce: String?
    @State private var isEmailSheetPresented = false
    @State private var isGoogleSignInPending = false
    @State private var hasPreparedSignInChoice = false

    private var isInvited: Bool {
        inviteLinkStore.pendingCode != nil
    }

    // While the email sheet is open it owns the error line, so the welcome never re-flows behind it.
    private var welcomeErrorMessage: String? {
        isEmailSheetPresented ? nil : authSession.errorMessage
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 32)
                    brandBlock
                    Spacer(minLength: 32)
                    actionGroup
                        .animation(.easeOut(duration: 0.18)) { content in
                            content.opacity(authSession.isSignInChoiceSettled ? 1 : 0)
                        }
                        .allowsHitTesting(authSession.isSignInChoiceSettled)
                        .accessibilityHidden(!authSession.isSignInChoiceSettled)
                    legalFootnote
                        .padding(.top, 14)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
                .frame(minHeight: proxy.size.height)
                .animation(.easeInOut(duration: 0.18), value: welcomeErrorMessage)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .ignoresSafeArea(.keyboard)
        .ninaScreenBackground()
        .onAppear {
            guard !hasPreparedSignInChoice else { return }
            hasPreparedSignInChoice = true
            authSession.prepareSignInChoice()
        }
        .task {
            await authSession.settleSignInChoice()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task {
                await authSession.refreshGoogleSignInAvailability()
            }
        }
        .sheet(isPresented: $isEmailSheetPresented, onDismiss: clearEmailFlowError) {
            EmailSignInSheet()
                .presentationDetents([.medium, .large])
                .presentationCornerRadius(NinaTheme.Radius.sheet)
                .presentationDragIndicator(.visible)
        }
    }

    private var brandBlock: some View {
        VStack(spacing: 16) {
            NinaMark(size: 64)

            VStack(spacing: 8) {
                Text(isInvited ? "Você tem um convite" : "Sua amiga Nina")
                    .ninaText(.display)

                // A link grants nothing on its own, so the invited line always names who approves.
                Text(isInvited ? "Quem convidou aprova sua entrada." : "Conta pra ela o que pesa.")
                    .ninaText(.label, NinaTheme.muted)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    private var actionGroup: some View {
        VStack(spacing: 12) {
            SignInWithAppleButton(.continue) { request in
                do {
                    let rawNonce = try AppleSignInNonce.make()
                    appleRawNonce = rawNonce
                    request.requestedScopes = [.fullName, .email]
                    request.nonce = AppleSignInNonce.sha256(rawNonce)
                } catch {
                    appleRawNonce = nil
                    authSession.report(.unavailable)
                }
            } onCompletion: { result in
                handleAppleCompletion(result)
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 52)
            .clipShape(RoundedRectangle(cornerRadius: NinaTheme.Radius.field, style: .continuous))
            .disabled(authSession.isSigningIn || !authSession.isBackendAvailable)
            .opacity(authSession.isSigningIn || !authSession.isBackendAvailable ? 0.4 : 1)
            .accessibilityIdentifier("apple-sign-in")

            if authSession.isGoogleSignInAvailable {
                NinaButton(
                    title: "Continuar com o Google",
                    kind: .outline,
                    assetName: "GoogleG",
                    fillsWidth: true,
                    isEnabled: !authSession.isSigningIn && authSession.isBackendAvailable,
                    isPending: isGoogleSignInPending,
                    action: signInWithGoogle
                )
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("google-sign-in")
            }

            NinaButton(title: "Entrar com email", kind: .outline, fillsWidth: true) {
                Haptics.lightImpact()
                isEmailSheetPresented = true
            }
            .fixedSize(horizontal: false, vertical: true)

            if let errorMessage = welcomeErrorMessage {
                // A failed sign-in is not lateness, so it never takes terracotta.
                Text(errorMessage)
                    .ninaText(.meta, NinaTheme.ink, weight: .medium)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("login-error")
            }
        }
    }

    private var legalFootnote: some View {
        Text(
            .init(
                "Ao continuar, você aceita os [Termos](\(NinaLegalLinks.termsOfUse.absoluteString)) "
                    + "e a [Política de Privacidade](\(NinaLegalLinks.privacyPolicy.absoluteString))."
            )
        )
        .ninaText(.meta, NinaTheme.muted)
        .tint(NinaTheme.cobalt)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity)
    }

    private func signInWithGoogle() {
        Haptics.lightImpact()
        isGoogleSignInPending = true
        Task {
            await authSession.signInWithGoogle()
            isGoogleSignInPending = false
        }
    }

    private func clearEmailFlowError() {
        guard authSession.isBackendAvailable else { return }
        authSession.errorMessage = nil
    }

    private func handleAppleCompletion(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .failure(let error):
            authSession.reportAppleAuthorizationError(error)
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let identityToken = String(data: tokenData, encoding: .utf8),
                  let rawNonce = appleRawNonce else {
                authSession.report(.appleCredentialInvalid)
                return
            }

            let fullName = credential.fullName.map {
                PersonNameComponentsFormatter().string(from: $0)
            }
            Task {
                await authSession.signInWithApple(
                    credential: AppleSignInCredential(
                        identityToken: identityToken,
                        rawNonce: rawNonce,
                        fullName: fullName
                    )
                )
                appleRawNonce = nil
            }
        }
    }
}

private struct EmailSignInSheet: View {
    @Environment(AuthSessionStore.self) private var authSession

    @State private var email = ""
    @State private var code = ""
    @State private var localError: String?
    @FocusState private var focusedField: Field?

    private enum Field {
        case email
        case code
    }

    private var isWaitingForCode: Bool {
        authSession.pendingLoginEmail != nil
    }

    private var displayedError: String? {
        localError ?? authSession.errorMessage
    }

    private var isDebugLoginEmail: Bool {
        #if DEBUG
        return DebugAuthAccount(email: email) != nil
        #else
        return false
        #endif
    }

    private var isLoadingAuth: Bool {
        authSession.isSigningIn || authSession.isRequestingCode
    }

    private var primaryTitle: String {
        if authSession.isRequestingCode {
            return "Enviando"
        }
        if authSession.isSigningIn {
            return "Confirmando"
        }
        if isDebugLoginEmail {
            return "Entrar para testar"
        }
        return isWaitingForCode ? "Confirmar" : "Enviar código"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                if isWaitingForCode {
                    codeField
                } else {
                    emailField
                }

                if let displayedError {
                    Text(displayedError)
                        .ninaText(.meta, NinaTheme.ink, weight: .medium)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("login-email-error")
                }

                #if DEBUG
                if !isWaitingForCode {
                    Text("Debug local: teste1@ninai.test ou teste2@ninai.test")
                        .ninaText(.meta, NinaTheme.muted)
                }
                #endif

                NinaButton(
                    title: primaryTitle,
                    fillsWidth: true,
                    isEnabled: !isLoadingAuth && (authSession.isBackendAvailable || isDebugLoginEmail),
                    action: isWaitingForCode ? verifyCode : requestCode
                )

                if isWaitingForCode {
                    codeLinks
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 28)
            .padding(.bottom, 20)
            .animation(.easeInOut(duration: 0.18), value: displayedError)
            .animation(.easeInOut(duration: 0.2), value: isWaitingForCode)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
        .ninaSheetBackground()
        .onChange(of: email) { _, _ in clearLocalError() }
        .onChange(of: code) { _, newValue in
            code = String(newValue.filter(\.isNumber).prefix(6))
            clearLocalError()
        }
        .task {
            email = authSession.pendingLoginEmail ?? email
            if authSession.isBackendAvailable {
                authSession.errorMessage = nil
            }
            await Task.yield()
            focusedField = isWaitingForCode ? .code : .email
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(isWaitingForCode ? "Código enviado" : "Entrar com email")
                .ninaText(.title)

            if let pendingLoginEmail = authSession.pendingLoginEmail {
                Text("Para " + pendingLoginEmail)
                    .ninaText(.label, NinaTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var emailField: some View {
        LoginInput {
            TextField("voce@exemplo.com", text: $email)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textContentType(.emailAddress)
                .submitLabel(.send)
                .focused($focusedField, equals: .email)
                .onSubmit(requestCode)
                .accessibilityLabel("Email")
        }
    }

    private var codeField: some View {
        LoginInput {
            TextField("000000", text: $code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .submitLabel(.go)
                .focused($focusedField, equals: .code)
                .onSubmit(verifyCode)
                .accessibilityLabel("Código")
        }
    }

    private var codeLinks: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                resendButton

                Text("·")
                    .ninaText(.body, NinaTheme.muted)
                    .accessibilityHidden(true)

                changeEmailButton
            }

            VStack(spacing: 0) {
                resendButton
                changeEmailButton
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var resendButton: some View {
        NinaButton(
            title: "Reenviar código",
            kind: .quiet,
            isEnabled: !isLoadingAuth && authSession.isBackendAvailable,
            action: resendCode
        )
    }

    private var changeEmailButton: some View {
        NinaButton(title: "Trocar email", kind: .quiet, action: changeEmail)
    }

    private func requestCode() {
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedEmail.contains("@"), normalizedEmail.contains(".") else {
            localError = AuthFlowError.invalidEmail.userMessage
            Haptics.error()
            return
        }

        focusedField = nil
        Task {
            if await authSession.requestEmailOTP(email: normalizedEmail) {
                email = authSession.pendingLoginEmail ?? normalizedEmail
                await Task.yield()
                focusedField = .code
            }
        }
    }

    private func resendCode() {
        email = authSession.pendingLoginEmail ?? email
        code = ""
        requestCode()
    }

    private func changeEmail() {
        authSession.pendingLoginEmail = nil
        code = ""
        Task {
            await Task.yield()
            focusedField = .email
        }
    }

    private func verifyCode() {
        guard code.count == 6 else {
            localError = AuthFlowError.invalidCode.userMessage
            Haptics.error()
            return
        }

        focusedField = nil
        Task {
            await authSession.verifyEmailOTP(email: email, code: code)
        }
    }

    private func clearLocalError() {
        guard localError != nil else { return }
        localError = nil
    }
}

private struct LoginInput<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .ninaText(.body, NinaTheme.ink)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .background(NinaTheme.grout, in: RoundedRectangle(cornerRadius: NinaTheme.Radius.field, style: .continuous))
    }
}

#Preview("Login") {
    LoginView()
        .environment(AuthSessionStore())
        .environment(InviteLinkStore())
}

#if DEBUG
#Preview("Login com Google") {
    LoginView()
        .environment(AuthSessionStore(authClient: GoogleOnPreviewAuthClient()))
        .environment(InviteLinkStore())
}

private struct GoogleOnPreviewAuthClient: AuthClient {
    private let mock = MockAuthClient()

    var projectHost: String? { "preview.supabase.co" }

    func googleSignInAvailability() async -> Bool? { true }

    func restoreSession() async -> AuthSessionRestoration { await mock.restoreSession() }

    func signInWithApple(credential: AppleSignInCredential) async throws -> AuthUser {
        try await mock.signInWithApple(credential: credential)
    }

    func requestEmailOTP(email: String) async throws { try await mock.requestEmailOTP(email: email) }

    func verifyEmailOTP(email: String, code: String) async throws -> AuthUser {
        try await mock.verifyEmailOTP(email: email, code: code)
    }

    func requestEmailChange(email: String) async throws { try await mock.requestEmailChange(email: email) }

    func verifyEmailChange(email: String, code: String) async throws -> AuthUser {
        try await mock.verifyEmailChange(email: email, code: code)
    }

    func signOut() async throws { try await mock.signOut() }
}
#endif
