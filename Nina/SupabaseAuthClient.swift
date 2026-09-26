import Foundation

#if canImport(Supabase)
import AuthenticationServices
import Supabase

struct SupabaseAuthClient: AuthClient {
    var client: SupabaseClient
    var configuration: SupabaseConfiguration
    var diagnostics: BackendDiagnosticsStore? = nil

    var projectHost: String? {
        configuration.url.host
    }

    private static let settingsSession: URLSession = {
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.timeoutIntervalForRequest = GoogleSignIn.settingsTimeout
        sessionConfiguration.timeoutIntervalForResource = GoogleSignIn.settingsTimeout + 2
        sessionConfiguration.requestCachePolicy = .reloadIgnoringLocalCacheData
        sessionConfiguration.urlCache = nil
        sessionConfiguration.httpCookieStorage = nil
        return URLSession(configuration: sessionConfiguration)
    }()

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

    func googleSignInAvailability() async -> Bool? {
        let endpoint = configuration.url
            .appendingPathComponent("auth")
            .appendingPathComponent("v1")
            .appendingPathComponent("settings")
        var request = URLRequest(
            url: endpoint,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: GoogleSignIn.settingsTimeout
        )
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(configuration.publishableKey, forHTTPHeaderField: "apikey")

        do {
            return try await BackendRequestLogger.perform(
                component: "auth",
                operation: "load_provider_settings",
                diagnostics: diagnostics
            ) { () async throws -> Bool? in
                let (bytes, response) = try await Self.settingsSession.bytes(for: request)
                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.expectedContentLength <= Int64(GoogleSignIn.maximumSettingsBytes) else {
                    return nil
                }

                var body = Data()
                for try await byte in bytes {
                    guard body.count < GoogleSignIn.maximumSettingsBytes else { return nil }
                    body.append(byte)
                }
                return GoogleSignIn.availability(statusCode: httpResponse.statusCode, body: body)
            }
        } catch {
            return nil
        }
    }

    func signInWithGoogle() async throws -> AuthUser {
        guard let redirectURL = GoogleSignIn.callbackURL else {
            throw AuthFlowError.configurationMissing
        }

        let session: Session
        do {
            session = try await BackendRequestLogger.perform(
                component: "auth",
                operation: "sign_in_google",
                diagnostics: diagnostics
            ) {
                try await client.auth.signInWithOAuth(
                    provider: .google,
                    redirectTo: redirectURL,
                    configure: { webSession in
                        webSession.prefersEphemeralWebBrowserSession = true
                    }
                )
            }
        } catch {
            if GoogleSignIn.isCancellation(error) {
                throw CancellationError()
            }
            if let authError = error as? AuthError,
               case let .pkceGrantCodeExchange(_, oauthError, _) = authError,
               GoogleSignIn.isCancellation(oauthErrorCode: oauthError) {
                throw CancellationError()
            }
            throw AuthFlowError.unavailable
        }

        let metadata = session.user.userMetadata
        let hint = GoogleSignIn.displayNameHint(
            displayName: metadata["display_name"]?.stringValue,
            fullName: metadata["full_name"]?.stringValue,
            name: metadata["name"]?.stringValue
        )
        let profile = try await ensureProfile(displayNameHint: hint)
        return AuthUser(supabaseUser: session.user, profile: profile, preferredProvider: .google)
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
            throw mapEmailChangeError(error)
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
            return AuthUser(supabaseUser: user, profile: profile)
        } catch {
            throw mapCodeError(error)
        }
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
            return .codeRejected
        }
        return .unavailable
    }

    private func mapEmailChangeError(_ error: Error) -> AuthFlowError {
        let message = String(describing: error).lowercased()
        if message.contains("already") || message.contains("exists") {
            return .emailAlreadyUsed
        }
        return .emailChangeFailed
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
