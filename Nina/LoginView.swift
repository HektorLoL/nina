import AuthenticationServices
import SwiftUI

// Every age sees this screen: it names no friend and asks Apple for the name alone, never the email.
struct LoginView: View {
    @Environment(AuthSessionStore.self) private var authSession
    @Environment(InviteLinkStore.self) private var inviteLinkStore

    @State private var appleRawNonce: String?

    // Every account is asked the same: App Review 4.0 refuses asking later for a name Apple could share.
    static func configureAppleRequest(_ request: ASAuthorizationAppleIDRequest, rawNonce: String) {
        request.requestedScopes = [.fullName]
        request.nonce = AppleSignInNonce.sha256(rawNonce)
    }

    private var isInvited: Bool {
        inviteLinkStore.pendingCode != nil
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 32)
                    brandBlock
                    Spacer(minLength: 32)
                    actionGroup
                    legalFootnote
                        .padding(.top, 14)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
                .frame(minHeight: proxy.size.height)
                .animation(.easeInOut(duration: 0.18), value: authSession.errorMessage)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .ignoresSafeArea(.keyboard)
        .ninaScreenBackground()
    }

    private var brandBlock: some View {
        VStack(spacing: 16) {
            NinaMark(size: 64)

            VStack(spacing: 8) {
                Text(isInvited ? "Você tem um convite" : "Nina")
                    .ninaText(.display)

                // A link grants nothing on its own, so the invited line always names who approves.
                Text(isInvited ? "Quem convidou aprova sua entrada." : "A rotina da casa, dividida.")
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
                    Self.configureAppleRequest(request, rawNonce: rawNonce)
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

            #if DEBUG
            debugAccountRow
            #endif

            if let errorMessage = authSession.errorMessage {
                // A failed sign-in is an error, so it is red with its glyph and never terracotta.
                NinaErrorNote(text: errorMessage, alignment: .center)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("login-error")
            }
        }
    }

    private var legalFootnote: some View {
        VStack(spacing: 14) {
            Text(
                .init(
                    "Ao continuar, você aceita os [Termos](\(NinaLegalLinks.termsOfUse.absoluteString)) "
                        + "e a [Política de Privacidade](\(NinaLegalLinks.privacyPolicy.absoluteString)). "
                        + "Menores de 18 anos entram numa casa com aprovação de um responsável."
                )
            )
            .ninaText(.meta, NinaTheme.muted)
            .tint(NinaTheme.cobalt)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)

            ClassIndMark()
        }
    }

    #if DEBUG
    // Test doors never compile into Release, so a shipped welcome has only Apple's.
    private var debugAccountRow: some View {
        HStack(spacing: 12) {
            debugAccountButton(.testOne, identifier: "debug-sign-in-teste1")

            Text("·")
                .ninaText(.body, NinaTheme.muted)
                .accessibilityHidden(true)

            debugAccountButton(.testTwo, identifier: "debug-sign-in-teste2")
        }
        .frame(maxWidth: .infinity)
    }

    private func debugAccountButton(_ account: DebugAuthAccount, identifier: String) -> some View {
        NinaButton(
            title: account.user.displayName,
            kind: .quiet,
            isEnabled: !authSession.isSigningIn
        ) {
            authSession.signIn(as: account)
        }
        .accessibilityLabel("Entrar como \(account.user.displayName)")
        .accessibilityIdentifier(identifier)
    }
    #endif

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

            let appleCredential = AppleSignInCredential(
                identityToken: identityToken,
                rawNonce: rawNonce,
                appleUserID: credential.user,
                sharedName: credential.fullName
            )
            Task {
                await authSession.signInWithApple(credential: appleCredential)
                appleRawNonce = nil
            }
        }
    }
}

#Preview("Login") {
    LoginView()
        .environment(AuthSessionStore())
        .environment(InviteLinkStore())
}
