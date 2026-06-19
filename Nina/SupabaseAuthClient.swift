import Foundation

#if canImport(Supabase)
import Supabase

struct SupabaseAuthClient: AuthClient {
    var client: SupabaseClient
    var diagnostics: BackendDiagnosticsStore? = nil

    func restoreSession() async -> AuthSessionRestoration {
        guard let storedSession = client.auth.currentSession else {
            return .signedOut
        }

        do {
            let session: Session
            if storedSession.isExpired {
                session = try await BackendRequestLogger.perform(
                    component: "auth",
                    operation: "refresh_session",
                    diagnostics: diagnostics
                ) {
                    try await client.auth.session
                }
            } else {
                session = storedSession
            }
            let profile = try await ensureProfile(displayNameHint: nil)
            return .signedIn(AuthUser(supabaseUser: session.user, profile: profile))
        } catch {
            return .signedOut
        }
    }

    func signInWithApple(credential: AppleSignInCredential) async throws -> AuthUser {
        let session = try await BackendRequestLogger.perform(
            component: "auth",
            operation: "sign_in_apple",
            diagnostics: diagnostics
        ) {
            try await client.auth.signInWithIdToken(
                credentials: OpenIDConnectCredentials(
                    provider: .apple,
                    idToken: credential.identityToken,
                    nonce: credential.rawNonce
                )
            )
        }

        if let fullName = credential.fullName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !fullName.isEmpty {
            _ = try? await BackendRequestLogger.perform(
                component: "auth",
                operation: "update_user_metadata",
                diagnostics: diagnostics
            ) {
                try await client.auth.update(
                    user: UserAttributes(
                        data: [
                            "full_name": .string(fullName),
                            "display_name": .string(fullName)
                        ]
                    )
                )
            }
        }

        let refreshedUser = (
            try? await BackendRequestLogger.perform(
                component: "auth",
                operation: "get_current_user",
                diagnostics: diagnostics
            ) {
                try await client.auth.user()
            }
        ) ?? session.user
        let profile = try await ensureProfile(displayNameHint: credential.fullName)
        return AuthUser(supabaseUser: refreshedUser, profile: profile, preferredProvider: .apple)
    }

    func requestEmailOTP(email: String) async throws {
        do {
            try await BackendRequestLogger.perform(
                component: "auth",
                operation: "request_email_otp",
                diagnostics: diagnostics
            ) {
                try await client.auth.signInWithOTP(email: email, shouldCreateUser: false)
            }
        } catch {
            throw mapEmailError(error)
        }
    }

    func verifyEmailOTP(email: String, code: String) async throws -> AuthUser {
        do {
            _ = try await BackendRequestLogger.perform(
                component: "auth",
                operation: "verify_email_otp",
                diagnostics: diagnostics
            ) {
                try await client.auth.verifyOTP(email: email, token: code, type: .email)
            }
            let user = try await BackendRequestLogger.perform(
                component: "auth",
                operation: "get_current_user",
                diagnostics: diagnostics
            ) {
                try await client.auth.user()
            }
            let profile = try await ensureProfile(displayNameHint: nil)
            return AuthUser(supabaseUser: user, profile: profile, preferredProvider: .email)
        } catch {
            throw mapCodeError(error)
        }
    }

    func requestEmailChange(email: String) async throws {
        do {
            _ = try await BackendRequestLogger.perform(
                component: "auth",
                operation: "request_email_change",
                diagnostics: diagnostics
            ) {
                try await client.auth.update(user: UserAttributes(email: email))
            }
        } catch {
            throw mapEmailError(error)
        }
    }

    func verifyEmailChange(email: String, code: String) async throws -> AuthUser {
        do {
            _ = try await BackendRequestLogger.perform(
                component: "auth",
                operation: "verify_email_change",
                diagnostics: diagnostics
            ) {
                try await client.auth.verifyOTP(email: email, token: code, type: .emailChange)
            }
            let user = try await BackendRequestLogger.perform(
                component: "auth",
                operation: "get_current_user",
                diagnostics: diagnostics
            ) {
                try await client.auth.user()
            }
            let profile = try await ensureProfile(displayNameHint: nil)
            return AuthUser(supabaseUser: user, profile: profile, preferredProvider: .apple)
        } catch {
            throw mapCodeError(error)
        }
    }

    func deleteCurrentAccount() async throws {
        do {
            let _: DeleteAccountResponse = try await BackendRequestLogger.perform(
                component: "auth",
                operation: "delete_account",
                diagnostics: diagnostics
            ) {
                try await client.functions.invoke(
                    "delete-account",
                    options: FunctionInvokeOptions(body: DeleteAccountRequest())
                )
            }
        } catch {
            throw AuthFlowError.unavailable
        }
    }

    func signOut() async throws {
        try await BackendRequestLogger.perform(
            component: "auth",
            operation: "sign_out",
            diagnostics: diagnostics
        ) {
            try await client.auth.signOut()
        }
    }

    private func ensureProfile(displayNameHint: String?) async throws -> AuthProfileRow {
        try await BackendRequestLogger.perform(
            component: "profile",
            operation: "ensure_current_profile",
            diagnostics: diagnostics
        ) {
            try await client
                .rpc(
                    "ensure_current_profile",
                    params: EnsureProfileParams(displayNameHint: displayNameHint)
                )
                .execute()
                .value
        }
    }

    private func mapEmailError(_ error: Error) -> AuthFlowError {
        let message = String(describing: error).lowercased()
        if message.contains("signup") || message.contains("user not found") {
            return .emailNotLinked
        }
        return .unavailable
    }

    private func mapCodeError(_ error: Error) -> AuthFlowError {
        let message = String(describing: error).lowercased()
        if message.contains("otp") || message.contains("token") || message.contains("expired") {
            return .invalidCode
        }
        return .unavailable
    }
}

private struct EnsureProfileParams: Encodable {
    var displayNameHint: String?

    private enum CodingKeys: String, CodingKey {
        case displayNameHint = "display_name_hint"
    }
}

private struct DeleteAccountRequest: Encodable {}

private struct DeleteAccountResponse: Decodable {
    var deleted: Bool
}

struct AuthProfileRow: Decodable {
    var id: UUID
    var displayName: String
    var email: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case email
    }
}

extension AuthUser {
    init(
        supabaseUser user: User,
        profile: AuthProfileRow,
        preferredProvider: AuthProvider? = nil
    ) {
        let providerResolution = AuthProviderResolver.resolve(
            identityProviders: (user.identities ?? []).map(\.provider),
            metadataProvider: user.appMetadata["provider"]?.stringValue,
            preferredProvider: preferredProvider
        )

        self.init(
            id: user.id.uuidString,
            displayName: profile.displayName,
            email: profile.email ?? user.email,
            provider: providerResolution.primary,
            isEmailVerified: user.emailConfirmedAt != nil,
            linkedProviders: providerResolution.linked
        )
    }
}
#endif
