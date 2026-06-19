import AuthenticationServices
import SwiftUI

struct LoginView: View {
    @Environment(AuthSessionStore.self) private var authSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var email = ""
    @State private var code = ""
    @State private var localError: String?
    @State private var appleRawNonce: String?
    @State private var didAppear = false
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
        ZStack {
            NinaTheme.screenGradient
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    hero
                    formCard
                    footer
                }
                .padding(.horizontal, 22)
                .padding(.top, 42)
                .padding(.bottom, 34)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .onAppear {
            guard !didAppear else { return }
            withAnimation(reduceMotion ? nil : .spring(response: 0.58, dampingFraction: 0.84)) {
                didAppear = true
            }
        }
        .onChange(of: email) { _, _ in clearLocalError() }
        .onChange(of: code) { _, newValue in
            code = String(newValue.filter(\.isNumber).prefix(6))
            clearLocalError()
        }
    }

    private var hero: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(NinaTheme.mint.opacity(0.16))
                    .frame(width: 142, height: 142)
                    .scaleEffect(didAppear && !reduceMotion ? 1 : 0.9)

                Circle()
                    .stroke(NinaTheme.sky.opacity(0.22), lineWidth: 14)
                    .frame(width: 118, height: 118)
                    .scaleEffect(didAppear && !reduceMotion ? 1.05 : 0.92)

                NinaAvatarView(size: 86)
                    .offset(y: didAppear && !reduceMotion ? 0 : 8)
            }

            VStack(spacing: 8) {
                Text("Sua amiga Nina")
                    .font(.system(size: 34, weight: .black, design: .rounded))
                    .foregroundStyle(NinaTheme.ink)
                    .multilineTextAlignment(.center)

                Text("Sua casa, tarefas e lembretes ficam organizados em um espaço seguro.")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(NinaTheme.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .opacity(didAppear ? 1 : 0)
        .offset(y: didAppear || reduceMotion ? 0 : 18)
    }

    private var formCard: some View {
        SoftCard(padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                SectionTitle(
                    title: "Acesso",
                    subtitle: "Crie sua conta com Apple. Um email já vinculado também pode receber um código."
                )

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
                .clipShape(Capsule())
                .disabled(authSession.isSigningIn || !authSession.isBackendAvailable)
                .opacity(authSession.isSigningIn || !authSession.isBackendAvailable ? 0.62 : 1)
                .accessibilityIdentifier("apple-sign-in")

                HStack(spacing: 12) {
                    Rectangle()
                        .fill(NinaTheme.line)
                        .frame(height: 1)

                    Text("email vinculado")
                        .font(.caption.weight(.black))
                        .foregroundStyle(NinaTheme.muted)

                    Rectangle()
                        .fill(NinaTheme.line)
                        .frame(height: 1)
                }

                LoginInputRow(
                    title: "Email",
                    systemName: "envelope.fill",
                    tone: .mint
                ) {
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
                    LoginInputRow(
                        title: "Código",
                        systemName: "number.circle.fill",
                        tone: .lavender
                    ) {
                        TextField("000000", text: $code)
                            .keyboardType(.numberPad)
                            .textContentType(.oneTimeCode)
                            .submitLabel(.go)
                            .focused($focusedField, equals: .code)
                            .onSubmit(verifyCode)
                    }

                    Button("Usar outro email") {
                        authSession.pendingLoginEmail = nil
                        code = ""
                        focusedField = .email
                    }
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(NinaTheme.sky)
                }

                #if DEBUG
                Text("Acesso local de Debug: teste1@ninai.test ou teste2@ninai.test")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(NinaTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                #endif

                if let displayedError {
                    Label(displayedError, systemImage: "exclamationmark.circle.fill")
                        .font(.caption.weight(.heavy))
                        .foregroundStyle(NinaTheme.coral)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                        .accessibilityIdentifier("login-error")
                }

                LoginPrimaryButton(
                    title: isDebugLoginEmail
                        ? "Entrar para testar"
                        : (isWaitingForCode ? "Confirmar código" : "Enviar código"),
                    systemName: isDebugLoginEmail
                        ? "arrow.right"
                        : (isWaitingForCode ? "checkmark" : "paperplane.fill"),
                    isLoading: authSession.isSigningIn || authSession.isRequestingCode,
                    action: isWaitingForCode ? verifyCode : requestCode
                )
                .disabled(!authSession.isBackendAvailable && !isDebugLoginEmail)
            }
        }
        .opacity(didAppear ? 1 : 0)
        .offset(y: didAppear || reduceMotion ? 0 : 28)
        .animation(reduceMotion ? nil : .spring(response: 0.52, dampingFraction: 0.86).delay(0.08), value: didAppear)
        .animation(.easeInOut(duration: 0.18), value: displayedError)
        .animation(.easeInOut(duration: 0.2), value: isWaitingForCode)
    }

    private var footer: some View {
        VStack(spacing: 8) {
            Label("Sua sessão e sua participação na casa são verificadas pelo Supabase.", systemImage: "lock.shield.fill")
                .font(.caption.weight(.heavy))
                .foregroundStyle(NinaTheme.muted)
                .multilineTextAlignment(.center)

            if !authSession.isBackendAvailable {
                Text("Configure o projeto Supabase para habilitar o acesso.")
                    .font(.caption)
                    .foregroundStyle(NinaTheme.coral)
            }
        }
        .opacity(didAppear ? 1 : 0)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.28).delay(0.18), value: didAppear)
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

private struct LoginInputRow<Field: View>: View {
    var title: String
    var systemName: String
    var tone: MemberTone
    @ViewBuilder var field: Field

    var body: some View {
        HStack(spacing: 12) {
            IconBubble(systemName: systemName, tone: tone, size: 42)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption.weight(.black))
                    .foregroundStyle(NinaTheme.muted)

                field
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(NinaTheme.ink)
            }
        }
        .padding(14)
        .background(NinaTheme.field, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(NinaTheme.line, lineWidth: 1)
        )
    }
}

private struct LoginPrimaryButton: View {
    var title: String
    var systemName: String
    var isLoading: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if isLoading {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: systemName)
                        .font(.headline.weight(.black))
                }

                Text(isLoading ? "Aguarde..." : title)
                    .font(.headline.weight(.heavy))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(NinaTheme.mint, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .accessibilityLabel(isLoading ? "Aguarde" : title)
    }
}

#Preview("Login") {
    LoginView()
        .environment(AuthSessionStore())
}
