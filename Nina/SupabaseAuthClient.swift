import Foundation
import Network

// Exactly one of three bodies reaches delete-account; an absent key is omitted, never sent as null.
struct DeleteAccountRequest: Encodable, Equatable {
    let confirmation = "delete"
    private(set) var appleAuthorizationCode: String?
    private(set) var memberID: UUID?

    init() {}

    private init(appleAuthorizationCode: String?, memberID: UUID?) {
        self.appleAuthorizationCode = appleAuthorizationCode
        self.memberID = memberID
    }

    static func revoking(appleAuthorizationCode code: String) -> DeleteAccountRequest? {
        guard isValidAuthorizationCode(code) else { return nil }
        return DeleteAccountRequest(appleAuthorizationCode: code, memberID: nil)
    }

    static func guardian(memberID: UUID) -> DeleteAccountRequest {
        DeleteAccountRequest(appleAuthorizationCode: nil, memberID: memberID)
    }

    static func isValidAuthorizationCode(_ code: String) -> Bool {
        code.range(of: #"^[A-Za-z0-9._-]{1,512}$"#, options: .regularExpression) != nil
    }

    private enum CodingKeys: String, CodingKey {
        case confirmation
        case appleAuthorizationCode = "apple_authorization_code"
        case memberID = "member_id"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(confirmation, forKey: .confirmation)
        if let memberID {
            try container.encode(memberID.uuidString.lowercased(), forKey: .memberID)
        } else if let appleAuthorizationCode {
            try container.encode(appleAuthorizationCode, forKey: .appleAuthorizationCode)
        }
    }
}

// Codes are matched whole; an answer without a code (the gateway's) falls back to its status.
enum AccountDeletionFailure: Error, Equatable {
    case appleCancelled
    case offline
    case unconfirmed
    case serverUnavailable
    case sessionEnded
    case mayAlreadyBeDeleted
    case guardianAccessDenied
    case rejected

    init(status: Int, body: Data) {
        switch (try? JSONDecoder().decode(DeleteAccountErrorBody.self, from: body))?.error {
        case "not_authenticated":
            self = .sessionEnded
        case "guardian_access_denied":
            self = .guardianAccessDenied
        case "delete_account_failed", "service_not_configured":
            self = .serverUnavailable
        case "confirmation_required", "invalid_request", "payload_too_large",
             "unsupported_media_type", "method_not_allowed":
            self = .rejected
        default:
            // A gateway 5xx can arrive after the function finished, so it proves nothing either way.
            switch status {
            case 401: self = .sessionEnded
            case 408, 429: self = .serverUnavailable
            case 400...499: self = .rejected
            default: self = .unconfirmed
            }
        }
    }

    // Only a failure before any byte left the phone may be called offline; any later drop may have deleted.
    init(transportError error: Error) {
        switch (error as? URLError)?.code {
        case .cannotFindHost?, .dnsLookupFailed?, .cannotConnectToHost?:
            self = .offline
        default:
            self = .unconfirmed
        }
    }
}

private struct DeleteAccountErrorBody: Decodable {
    var error: String
}

enum NetworkPathProbe {
    static func isSatisfied() async -> Bool {
        await withCheckedContinuation { continuation in
            let monitor = NWPathMonitor()
            let queue = DispatchQueue(label: "com.heitor.nina.network-path")
            let once = ResumeOnce()
            monitor.pathUpdateHandler = { path in
                guard once.claim() else { return }
                monitor.cancel()
                continuation.resume(returning: path.status == .satisfied)
            }
            monitor.start(queue: queue)
            queue.asyncAfter(deadline: .now() + 2) {
                guard once.claim() else { return }
                monitor.cancel()
                continuation.resume(returning: true)
            }
        }
    }

    private final class ResumeOnce: @unchecked Sendable {
        private let lock = NSLock()
        private var claimed = false

        func claim() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            guard !claimed else { return false }
            claimed = true
            return true
        }
    }
}

#if canImport(Supabase)
import Supabase

struct SupabaseAuthClient: AuthClient {
    var client: SupabaseClient
    var diagnostics: BackendDiagnosticsStore? = nil
    var networkIsReachable: @Sendable () async -> Bool = { await NetworkPathProbe.isSatisfied() }

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

        let profile = try await ensureProfile(displayNameHint: nil)
        return AuthUser(supabaseUser: session.user, profile: profile, preferredProvider: .apple)
    }

    func deleteAccount(_ request: DeleteAccountRequest) async throws {
        // "Sem internet" is said only when the phone had no path before sending, so nothing reached the server.
        guard await networkIsReachable() else {
            throw AccountDeletionFailure.offline
        }

        let response: DeleteAccountResponse
        do {
            response = try await BackendRequestLogger.perform(
                component: "auth",
                operation: "delete_account",
                diagnostics: diagnostics
            ) {
                try await client.functions.invoke(
                    "delete-account",
                    options: FunctionInvokeOptions(body: request)
                )
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch FunctionsError.httpError(let status, let data) {
            throw AccountDeletionFailure(status: status, body: data)
        } catch FunctionsError.relayError {
            throw AccountDeletionFailure.serverUnavailable
        } catch {
            throw AccountDeletionFailure(transportError: error)
        }

        // A non-deleting response must not let the caller erase local data.
        guard response.deleted else {
            throw AccountDeletionFailure.unconfirmed
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
            email: Self.nonEmpty(profile.email) ?? Self.nonEmpty(user.email),
            provider: providerResolution.primary,
            isEmailVerified: user.emailConfirmedAt != nil,
            linkedProviders: providerResolution.linked,
            appleSubject: Self.appleSubject(of: user)
        )
    }

    private static func appleSubject(of user: User) -> String? {
        user.identities?.first { $0.provider == AuthProvider.apple.rawValue }?.id
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
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
            displayName: metadataName ?? Self.nonEmpty(user.email) ?? "Você",
            email: Self.nonEmpty(user.email),
            provider: providerResolution.primary,
            isEmailVerified: user.emailConfirmedAt != nil,
            linkedProviders: providerResolution.linked,
            appleSubject: Self.appleSubject(of: user)
        )
    }
}
#endif
