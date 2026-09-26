import CryptoKit
import Foundation
import Observation
import Security

enum AuthProvider: String, Codable, Hashable {
    case email
    case apple

    var title: String {
        switch self {
        case .email: "Email"
        case .apple: "Apple"
        }
    }
}

enum AuthProviderResolver {
    static func resolve(
        identityProviders: [String],
        metadataProvider: String?,
        preferredProvider: AuthProvider? = nil
    ) -> (primary: AuthProvider, linked: Set<AuthProvider>) {
        let linked = Set(identityProviders.compactMap(AuthProvider.init(rawValue:)))
        let primary = preferredProvider
            ?? (linked.contains(.apple) ? .apple : nil)
            ?? metadataProvider.flatMap(AuthProvider.init(rawValue:))
            ?? .email

        return (primary, linked.isEmpty ? [primary] : linked)
    }
}

struct AuthUser: Codable, Hashable, Identifiable {
    var id: String
    var displayName: String
    var email: String?
    var provider: AuthProvider
    var isEmailVerified: Bool
    var linkedProviders: Set<AuthProvider>

    init(
        id: String,
        displayName: String,
        email: String?,
        provider: AuthProvider,
        isEmailVerified: Bool = false,
        linkedProviders: Set<AuthProvider>? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.email = email
        self.provider = provider
        self.isEmailVerified = isEmailVerified
        self.linkedProviders = linkedProviders ?? [provider]
    }
}

#if DEBUG
enum DebugAuthAccount: CaseIterable {
    case testOne
    case testTwo

    var email: String {
        switch self {
        case .testOne:
            "teste1@ninai.test"
        case .testTwo:
            "teste2@ninai.test"
        }
    }

    var user: AuthUser {
        switch self {
        case .testOne:
            AuthUser(
                id: "debug:test-one",
                displayName: "Teste 1",
                email: email,
                provider: .email,
                isEmailVerified: true,
                linkedProviders: [.email]
            )
        case .testTwo:
            AuthUser(
                id: "debug:test-two",
                displayName: "Teste 2",
                email: email,
                provider: .email,
                isEmailVerified: true,
                linkedProviders: [.email]
            )
        }
    }
}
#endif

extension AuthUser {
    var isDebugAccount: Bool {
        #if DEBUG
        return Self.isDebugAccountID(id)
        #else
        return false
        #endif
    }

    static func isDebugAccountID(_ id: String) -> Bool {
        #if DEBUG
        return DebugAuthAccount.allCases.contains { $0.user.id == id }
        #else
        return false
        #endif
    }
}

struct AppleSignInCredential: Sendable {
    var identityToken: String
    var rawNonce: String
    var fullName: String?
}

enum AppleSignInNonce {
    private static let characters = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")

    static func make(length: Int = 32) throws -> String {
        precondition(length > 0)

        var result = ""
        result.reserveCapacity(length)

        while result.count < length {
            var bytes = [UInt8](repeating: 0, count: 16)
            let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
            guard status == errSecSuccess else {
                throw AuthFlowError.unavailable
            }

            for byte in bytes where result.count < length {
                guard byte < characters.count else { continue }
                result.append(characters[Int(byte)])
            }
        }

        return result
    }

    static func sha256(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

enum AuthFlowError: Error {
    case deletionFailed
    case appleCredentialInvalid
    case configurationMissing
    case unavailable

    var userMessage: String {
        switch self {
        case .deletionFailed:
            "Não deu para apagar a conta agora. Nada foi apagado. Tente de novo."
        case .appleCredentialInvalid:
            "A Apple não retornou uma credencial válida. Tente novamente."
        case .configurationMissing:
            "Não dá para entrar agora. Tente mais tarde."
        case .unavailable:
            "Não foi possível entrar agora. Tente de novo."
        }
    }
}

enum AuthSessionRestoration {
    case unavailable
    case signedOut
    case signedIn(AuthUser)
    // The stored session is intact but the network could not confirm it.
    case unreachable(AuthUser)
}

protocol AuthClient {
    func restoreSession() async -> AuthSessionRestoration
    func signInWithApple(credential: AppleSignInCredential) async throws -> AuthUser
    func deleteCurrentAccount() async throws
    func signOut() async throws
}

extension AuthClient {
    func deleteCurrentAccount() async throws {
        throw AuthFlowError.unavailable
    }
}

struct MockAuthClient: AuthClient {
    func restoreSession() async -> AuthSessionRestoration {
        .signedOut
    }

    func signInWithApple(credential: AppleSignInCredential) async throws -> AuthUser {
        try await Task.sleep(nanoseconds: 320_000_000)

        return AuthUser(
            id: "apple:mock-family",
            displayName: credential.fullName ?? "Família Nina",
            email: "familia@nina.local",
            provider: .apple,
            isEmailVerified: true,
            linkedProviders: [.apple]
        )
    }

    func signOut() async throws {
        try await Task.sleep(nanoseconds: 120_000_000)
    }
}

struct UnavailableAuthClient: AuthClient {
    func restoreSession() async -> AuthSessionRestoration { .unavailable }
    func signInWithApple(credential: AppleSignInCredential) async throws -> AuthUser {
        throw AuthFlowError.configurationMissing
    }
    func signOut() async throws {}
}

@MainActor
@Observable
final class AuthSessionStore {
    var currentUser: AuthUser?
    var isSigningIn = false
    var isDeletingAccount = false
    var errorMessage: String?
    var isBackendAvailable = true

    var isSignedIn: Bool {
        currentUser != nil
    }

    @ObservationIgnored private var authClient: any AuthClient

    init(authClient: any AuthClient = MockAuthClient()) {
        self.authClient = authClient
    }

    func restoreSession() async {
        #if DEBUG
        if currentUser?.isDebugAccount == true {
            isBackendAvailable = true
            return
        }
        #endif

        switch await authClient.restoreSession() {
        case .unavailable:
            currentUser = nil
            isBackendAvailable = false
            errorMessage = AuthFlowError.configurationMissing.userMessage
        case .signedOut:
            currentUser = nil
            isBackendAvailable = true
        case .unreachable(let offlineUser):
            // A transport failure never signs anyone out; the home context decides access.
            if currentUser == nil {
                currentUser = offlineUser
            }
            isBackendAvailable = true
        case .signedIn(let user):
            currentUser = user
            isBackendAvailable = true
        }
    }

    func signInWithApple(credential: AppleSignInCredential) async {
        await performSignIn {
            try await authClient.signInWithApple(credential: credential)
        }
    }

    #if DEBUG
    func signIn(as account: DebugAuthAccount) {
        guard !isSigningIn else { return }
        currentUser = account.user
        errorMessage = nil
        isBackendAvailable = true
        Haptics.success()
    }
    #endif

    func reportAppleAuthorizationError(_ error: Error) {
        let nsError = error as NSError
        if nsError.domain == "com.apple.AuthenticationServices.AuthorizationError",
           nsError.code == 1001 {
            return
        }
        setError(.unavailable)
    }

    func report(_ error: AuthFlowError) {
        setError(error)
    }

    @discardableResult
    func signOut() async -> Bool {
        errorMessage = nil

        #if DEBUG
        if currentUser?.isDebugAccount == true {
            clearSessionState()
            return true
        }
        #endif

        do {
            try await authClient.signOut()
        } catch is CancellationError {
            return false
        } catch {
            handle(error)
            return false
        }

        clearSessionState()
        return true
    }

    @discardableResult
    func deleteAccount() async -> Bool {
        guard currentUser != nil, !isDeletingAccount else { return false }
        errorMessage = nil

        #if DEBUG
        if currentUser?.isDebugAccount == true {
            clearSessionState()
            Haptics.success()
            return true
        }
        #endif

        isDeletingAccount = true
        defer { isDeletingAccount = false }

        do {
            try await authClient.deleteCurrentAccount()
            clearSessionState()
            Haptics.success()
            return true
        } catch is CancellationError {
            return false
        } catch {
            handle(error)
            return false
        }
    }

    private func performSignIn(_ operation: () async throws -> AuthUser) async {
        guard !isSigningIn else { return }

        isSigningIn = true
        errorMessage = nil
        defer { isSigningIn = false }

        do {
            currentUser = try await operation()
            isBackendAvailable = true
            Haptics.success()
        } catch is CancellationError {
            return
        } catch {
            handle(error)
        }
    }

    private func handle(_ error: Error) {
        if let authError = error as? AuthFlowError {
            setError(authError)
        } else {
            setError(.unavailable)
        }
    }

    private func setError(_ error: AuthFlowError) {
        errorMessage = error.userMessage
        Haptics.error()
    }

    private func clearSessionState() {
        currentUser = nil
    }
}

@MainActor
@Observable
final class OnboardingStore {
    var isReplayingTutorial = false
    var completedTutorialUserIDs: Set<String> = []

    @ObservationIgnored private var defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func shouldShowTutorial(for user: AuthUser?) -> Bool {
        guard let user else { return false }
        return isReplayingTutorial || !hasCompletedTutorial(for: user)
    }

    func hasCompletedTutorial(for user: AuthUser?) -> Bool {
        guard let user else { return false }
        return completedTutorialUserIDs.contains(user.id) || defaults.bool(forKey: Self.completedKey(for: user.id))
    }

    func completeTutorial(for user: AuthUser?) {
        guard let user else { return }
        completedTutorialUserIDs.insert(user.id)
        defaults.set(true, forKey: Self.completedKey(for: user.id))
        isReplayingTutorial = false
    }

    func replayTutorial() {
        isReplayingTutorial = true
    }

    func cancelReplay() {
        isReplayingTutorial = false
    }

    func clearLocalData(for userID: String) {
        completedTutorialUserIDs.remove(userID)
        defaults.removeObject(forKey: Self.completedKey(for: userID))
        isReplayingTutorial = false
    }

    private static func completedKey(for userID: String) -> String {
        "nina.onboarding.completed.\(userID)"
    }
}
