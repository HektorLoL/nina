import AuthenticationServices
import SwiftUI

struct LoginView: View {
    @Environment(AuthSessionStore.self) private var authSession

    @State private var email = ""
    @State private var code = ""
    @State private var localError: String?
    @State private var appleRawNonce: String?
    @State private var isEmailFlowVisible = false
    @FocusState private var focusedField: LoginField?

    private enum LoginField {
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                hero
                form
                footer
            }
            .padding(.horizontal, 20)
            .padding(.top, 46)
            .padding(.bottom, 34)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .ninaScreenBackground()
        .onChange(of: email) { _, _ in clearLocalError() }
        .onChange(of: code) { _, newValue in
            code = String(newValue.filter(\.isNumber).prefix(6))
            clearLocalError()
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 18) {
            NinaMark(size: 64)

            VStack(alignment: .leading, spacing: 10) {
                Text("Sua amiga Nina")
                    .ninaText(.display)

                Text("Conta pra ela o que está pesando na casa. Ela monta as tarefas e espera você confirmar — nada entra sozinho.")
                    .ninaText(.label, NinaTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 12) {
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
            .opacity(authSession.isSigningIn || !authSession.isBackendAvailable ? 0.5 : 1)
            .accessibilityIdentifier("apple-sign-in")

            if isEmailFlowVisible {
                emailFields
            } else {
                NinaButton(title: "Usar meu e-mail", kind: .outline, fillsWidth: true) {
                    Haptics.lightImpact()
                    isEmailFlowVisible = true
                    focusedField = .email
                }
            }

            if let displayedError {
                // A failed sign-in is not lateness, so it never takes terracotta.
                Text(displayedError)
                    .ninaText(.caption, NinaTheme.ink, weight: .medium)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("login-error")
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isEmailFlowVisible)
        .animation(.easeInOut(duration: 0.18), value: displayedError)
        .animation(.easeInOut(duration: 0.2), value: isWaitingForCode)
    }

    @ViewBuilder
    private var emailFields: some View {
        LoginField_(title: "E-mail") {
            TextField("voce@exemplo.com", text: $email)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textContentType(.emailAddress)
                .submitLabel(isWaitingForCode ? .next : .send)
                .focused($focusedField, equals: .email)
                .disabled(isWaitingForCode)
                .onSubmit {
                    if isWaitingForCode {
                        focusedField = .code
                    } else {
                        requestCode()
                    }
                }
        }

        if isWaitingForCode {
            LoginField_(title: "Código") {
                TextField("000000", text: $code)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .submitLabel(.go)
                    .focused($focusedField, equals: .code)
                    .onSubmit(verifyCode)
            }

            NinaButton(title: "Usar outro e-mail", kind: .quiet) {
                authSession.pendingLoginEmail = nil
                code = ""
                focusedField = .email
            }
        }

        #if DEBUG
        Text("Debug local: teste1@ninai.test ou teste2@ninai.test")
            .ninaText(.meta, NinaTheme.muted)
        #endif

        NinaButton(
            title: isLoadingAuth
                ? "Aguarde..."
                : (isDebugLoginEmail
                    ? "Entrar para testar"
                    : (isWaitingForCode ? "Confirmar código" : "Enviar código")),
            fillsWidth: true,
            isEnabled: !isLoadingAuth && (authSession.isBackendAvailable || isDebugLoginEmail),
            action: isWaitingForCode ? verifyCode : requestCode
        )
    }

    private var isLoadingAuth: Bool {
        authSession.isSigningIn || authSession.isRequestingCode
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Ao continuar você aceita os Termos e a Política de Privacidade.")
                .ninaText(.meta, NinaTheme.muted)

            if !authSession.isBackendAvailable {
                Text("Configure o projeto Supabase para habilitar o acesso.")
                    .ninaText(.meta, NinaTheme.muted)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
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
                focusedField = .code
            }
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

private struct LoginField_<Field: View>: View {
    var title: String
    @ViewBuilder var field: Field

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).ninaText(.meta, NinaTheme.muted)
            field
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(NinaTheme.ink)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NinaTheme.grout, in: RoundedRectangle(cornerRadius: NinaTheme.Radius.field, style: .continuous))
    }
}

#Preview("Login") {
    LoginView()
        .environment(AuthSessionStore())
}
