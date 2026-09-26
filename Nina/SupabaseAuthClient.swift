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
        } catch is AuthError {
            return .signedOut
        } catch {
            // Only Auth itself may end a session; a refresh the network dropped keeps it.
            return .unreachable(AuthUser(offlineSupabaseUser: storedSession.user))
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

    func deleteCurrentAccount() async throws {
        let response: DeleteAccountResponse
        do {
            response = try await BackendRequestLogger.perform(
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
            throw AuthFlowError.deletionFailed
        }

        // A non-deleting response must not let the caller erase local data.
        guard response.deleted else {
            throw AuthFlowError.deletionFailed
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
}

private struct EnsureProfileParams: Encodable {
    var displayNameHint: String?

    private enum CodingKeys: String, CodingKey {
        case displayNameHint = "display_name_hint"
    }
}

struct DeleteAccountRequest: Encodable {
    let confirmation = "delete"
}

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

    init(offlineSupabaseUser user: User) {
        let providerResolution = AuthProviderResolver.resolve(
            identityProviders: (user.identities ?? []).map(\.provider),
            metadataProvider: user.appMetadata["provider"]?.stringValue,
            preferredProvider: nil
        )
        let metadataName = user.userMetadata["display_name"]?.stringValue
            ?? user.userMetadata["full_name"]?.stringValue

        self.init(
            id: user.id.uuidString,
            displayName: metadataName ?? user.email ?? "Você",
            email: user.email,
            provider: providerResolution.primary,
            isEmailVerified: user.emailConfirmedAt != nil,
            linkedProviders: providerResolution.linked
        )
    }
}
#endif
