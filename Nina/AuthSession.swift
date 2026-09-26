import AuthenticationServices
import CryptoKit
import Foundation
import Observation
import Security

enum AuthProvider: String, Codable, Hashable {
    case email
    case apple
    case google

    var title: String {
        switch self {
        case .email: "Email"
        case .apple: "Apple"
        case .google: "Google"
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
        let metadata = metadataProvider.flatMap(AuthProvider.init(rawValue:))
        let primary = preferredProvider
            ?? metadata
            ?? [AuthProvider.apple, .google].first(where: linked.contains)
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

    init?(email: String) {
        let normalizedEmail = email
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard let account = Self.allCases.first(where: { $0.email == normalizedEmail }) else {
            return nil
        }
        self = account
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

enum GoogleSignIn {
    static let callbackURL = URL(string: "com.heitor.nina://login-callback")
    static let settingsTimeout: TimeInterval = 6
    static let choiceDeadline: Duration = .milliseconds(1_500)
    static let maximumSettingsBytes = 16_384

    // nil means unknown: it hides the button but never overwrites the last real answer.
    static func availability(statusCode: Int, body: Data) -> Bool? {
        guard (200..<300).contains(statusCode),
              body.count <= maximumSettingsBytes,
              let settings = try? JSONDecoder().decode(Settings.self, from: body) else {
            return nil
        }
        return settings.external.google == true
    }

    static func cacheKey(projectHost: String) -> String {
        "nina.auth.googleSignInEnabled.\(projectHost.lowercased())"
    }

    static func isCancellation(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == ASWebAuthenticationSessionError.errorDomain
            && nsError.code == ASWebAuthenticationSessionError.canceledLogin.rawValue
    }

    static func isCancellation(oauthErrorCode: String?) -> Bool {
        oauthErrorCode == "access_denied"
    }

    // Same order as auth_user_display_name, so a Google sign-in never renames a linked Apple account.
    static func displayNameHint(displayName: String?, fullName: String?, name: String?) -> String? {
        [displayName, fullName, name]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    private struct Settings: Decodable {
        struct External: Decodable {
            var google: Bool?
        }

        var external: External
    }
}

enum AuthFlowError: Error {
    case invalidEmail
    case invalidCode
    case emailNotLinked
    case codeRejected
    case emailAlreadyUsed
    case emailChangeFailed
    case deletionFailed
    case appleCredentialInvalid
    case configurationMissing
    case unavailable

    var userMessage: String {
        userMessage(offersGoogle: false)
    }

    // Email never creates an account, so a new address is sent only to the doors on screen.
    func userMessage(offersGoogle: Bool) -> String {
        switch self {
        case .invalidEmail:
            "Use um email válido."
        case .invalidCode:
            "Digite o código de 6 números enviado por email."
        case .codeRejected:
            "Esse código venceu ou não bate. Peça um novo."
        case .emailNotLinked:
            offersGoogle
                ? "Esse email não tem conta. Continue com a Apple ou o Google."
                : "Esse email não tem conta. Continue com a Apple."
        case .emailAlreadyUsed:
            "Esse email já está em outra conta Nina."
        case .emailChangeFailed:
            "Não deu para trocar o email agora. Tente de novo."
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
    func requestEmailOTP(email: String) async throws
    func verifyEmailOTP(email: String, code: String) async throws -> AuthUser
    func requestEmailChange(email: String) async throws
    func verifyEmailChange(email: String, code: String) async throws -> AuthUser
    func deleteCurrentAccount() async throws
    func signOut() async throws
    var projectHost: String? { get }
    func googleSignInAvailability() async -> Bool?
    func signInWithGoogle() async throws -> AuthUser
}

extension AuthClient {
    func deleteCurrentAccount() async throws {
        throw AuthFlowError.unavailable
    }

    var projectHost: String? {
        nil
    }

    func googleSignInAvailability() async -> Bool? {
        nil
    }

    func signInWithGoogle() async throws -> AuthUser {
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
            linkedProviders: [.apple, .email]
        )
    }

    func requestEmailOTP(email: String) async throws {
        try validateEmail(email)
        try await Task.sleep(nanoseconds: 220_000_000)
    }

    func verifyEmailOTP(email: String, code: String) async throws -> AuthUser {
        try validateEmail(email)
        guard code.filter(\.isNumber).count == 6 else {
            throw AuthFlowError.invalidCode
        }
        try await Task.sleep(nanoseconds: 260_000_000)

        return AuthUser(
            id: "email:\(email.lowercased())",
            displayName: "Família Nina",
            email: email.lowercased(),
            provider: .email,
            isEmailVerified: true,
            linkedProviders: [.apple, .email]
        )
    }

    func requestEmailChange(email: String) async throws {
        try await requestEmailOTP(email: email)
    }

    func verifyEmailChange(email: String, code: String) async throws -> AuthUser {
        try await verifyEmailOTP(email: email, code: code)
    }

    func signOut() async throws {
        try await Task.sleep(nanoseconds: 120_000_000)
    }

    private func validateEmail(_ email: String) throws {
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedEmail.contains("@"), normalizedEmail.contains(".") else {
            throw AuthFlowError.invalidEmail
        }
    }
}

struct UnavailableAuthClient: AuthClient {
    func restoreSession() async -> AuthSessionRestoration { .unavailable }
    func signInWithApple(credential: AppleSignInCredential) async throws -> AuthUser {
        throw AuthFlowError.configurationMissing
    }
    func requestEmailOTP(email: String) async throws {
        throw AuthFlowError.configurationMissing
    }
    func verifyEmailOTP(email: String, code: String) async throws -> AuthUser {
        throw AuthFlowError.configurationMissing
    }
    func requestEmailChange(email: String) async throws {
        throw AuthFlowError.configurationMissing
    }
    func verifyEmailChange(email: String, code: String) async throws -> AuthUser {
        throw AuthFlowError.configurationMissing
    }
    func signOut() async throws {}
}

@MainActor
@Observable
final class AuthSessionStore {
    var currentUser: AuthUser?
    var isSigningIn = false
    var isRequestingCode = false
    var isDeletingAccount = false
    var pendingLoginEmail: String?
    var pendingEmailChange: String?
    var errorMessage: String?
    var isBackendAvailable = true
    var isGoogleSignInAvailable: Bool
    private(set) var isSignInChoiceSettled: Bool

    var isSignedIn: Bool {
        currentUser != nil
    }

    @ObservationIgnored private var authClient: any AuthClient
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var isCheckingGoogleSignIn = false

    init(authClient: any AuthClient = MockAuthClient(), defaults: UserDefaults = .standard) {
        self.authClient = authClient
        self.defaults = defaults
        let cached = authClient.projectHost.flatMap {
            defaults.object(forKey: GoogleSignIn.cacheKey(projectHost: $0)) as? Bool
        }
        isGoogleSignInAvailable = cached ?? false
        isSignInChoiceSettled = authClient.projectHost == nil || cached != nil
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

    func signInWithGoogle() async {
        await performSignIn {
            try await authClient.signInWithGoogle()
        }
    }

    func prepareSignInChoice() {
        guard let host = authClient.projectHost else {
            isGoogleSignInAvailable = false
            isSignInChoiceSettled = true
            return
        }
        let cached = defaults.object(forKey: GoogleSignIn.cacheKey(projectHost: host)) as? Bool
        isGoogleSignInAvailable = cached ?? false
        isSignInChoiceSettled = cached != nil
    }

    func settleSignInChoice(within deadline: Duration = GoogleSignIn.choiceDeadline) async {
        Task { await refreshGoogleSignInAvailability() }
        guard !isSignInChoiceSettled else { return }
        try? await Task.sleep(for: deadline)
        closeSignInChoice()
    }

    func closeSignInChoice() {
        guard !isSignInChoiceSettled else { return }
        isGoogleSignInAvailable = false
        isSignInChoiceSettled = true
    }

    // Once the welcome's doors can be tapped a check only writes the cache, so the Google row never moves under a finger.
    func refreshGoogleSignInAvailability() async {
        guard let host = authClient.projectHost, !isCheckingGoogleSignIn, !isSigningIn else { return }
        isCheckingGoogleSignIn = true
        defer { isCheckingGoogleSignIn = false }

        let answer = await authClient.googleSignInAvailability()
        if let answer {
            defaults.set(answer, forKey: GoogleSignIn.cacheKey(projectHost: host))
        }
        guard !isSignInChoiceSettled else { return }
        isGoogleSignInAvailable = answer ?? false
        isSignInChoiceSettled = true
    }

    @discardableResult
    func requestEmailOTP(email: String) async -> Bool {
        let normalizedEmail = normalized(email)
        guard isValidEmail(normalizedEmail) else {
            setError(.invalidEmail)
            return false
        }

        #if DEBUG
        if let debugAccount = DebugAuthAccount(email: normalizedEmail) {
            currentUser = debugAccount.user
            pendingLoginEmail = nil
            errorMessage = nil
            isBackendAvailable = true
            Haptics.success()
            return true
        }
        #endif

        guard !isRequestingCode else { return false }
        isRequestingCode = true
        errorMessage = nil
        defer { isRequestingCode = false }

        do {
            try await authClient.requestEmailOTP(email: normalizedEmail)
            pendingLoginEmail = normalizedEmail
            Haptics.success()
            return true
        } catch {
            handle(error)
            return false
        }
    }

    func verifyEmailOTP(email: String, code: String) async {
        let normalizedEmail = normalized(email)
        let normalizedCode = code.filter(\.isNumber)
        guard isValidEmail(normalizedEmail), normalizedCode.count == 6 else {
            setError(normalizedCode.count == 6 ? .invalidEmail : .invalidCode)
            return
        }

        await performSignIn {
            try await authClient.verifyEmailOTP(email: normalizedEmail, code: normalizedCode)
        }

        if isSignedIn {
            pendingLoginEmail = nil
        }
    }

    @discardableResult
    func requestEmailChange(email: String) async -> Bool {
        let normalizedEmail = normalized(email)
        guard isValidEmail(normalizedEmail) else {
            setError(.invalidEmail)
            return false
        }

        guard !isRequestingCode else { return false }
        isRequestingCode = true
        errorMessage = nil
        defer { isRequestingCode = false }

        do {
            try await authClient.requestEmailChange(email: normalizedEmail)
            pendingEmailChange = normalizedEmail
            Haptics.success()
            return true
        } catch {
            handle(error)
            return false
        }
    }

    @discardableResult
    func verifyEmailChange(email: String, code: String) async -> Bool {
        let normalizedEmail = normalized(email)
        let normalizedCode = code.filter(\.isNumber)
        guard isValidEmail(normalizedEmail), normalizedCode.count == 6 else {
            setError(normalizedCode.count == 6 ? .invalidEmail : .invalidCode)
            return false
        }

        guard !isSigningIn else { return false }
        isSigningIn = true
        errorMessage = nil
        defer { isSigningIn = false }

        do {
            currentUser = try await authClient.verifyEmailChange(email: normalizedEmail, code: normalizedCode)
            pendingEmailChange = nil
            Haptics.success()
            return true
        } catch {
            handle(error)
            return false
        }
    }

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
        errorMessage = error.userMessage(offersGoogle: isGoogleSignInAvailable)
        Haptics.error()
    }

    private func clearSessionState() {
        currentUser = nil
        pendingLoginEmail = nil
        pendingEmailChange = nil
    }

    private func normalized(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func isValidEmail(_ email: String) -> Bool {
        email.contains("@") && email.contains(".")
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
