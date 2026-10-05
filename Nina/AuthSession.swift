import AuthenticationServices
import CryptoKit
import Foundation
import Observation
import Security
#if canImport(UIKit)
import UIKit
#endif

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
    var appleSubject: String?

    init(
        id: String,
        displayName: String,
        email: String?,
        provider: AuthProvider,
        isEmailVerified: Bool = false,
        linkedProviders: Set<AuthProvider>? = nil,
        appleSubject: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.email = email
        self.provider = provider
        self.isEmailVerified = isEmailVerified
        self.linkedProviders = linkedProviders ?? [provider]
        self.appleSubject = appleSubject
    }

    var signedInWithApple: Bool {
        provider == .apple || linkedProviders.contains(.apple)
    }

    // An account made with no Apple scope has no email, and no row stands in for one.
    var shownEmail: String? {
        guard let trimmed = email?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
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
    case appleCredentialInvalid
    case configurationMissing
    case unavailable

    var userMessage: String {
        switch self {
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
    func deleteAccount(_ request: DeleteAccountRequest) async throws
    func signOut() async throws
}

extension AuthClient {
    func deleteAccount(_ request: DeleteAccountRequest) async throws {
        throw AccountDeletionFailure.serverUnavailable
    }
}

enum AppleReauthorizationOutcome: Equatable {
    case code(String, user: String)
    case cancelled
    case failed
}

protocol AppleReauthorizing {
    @MainActor
    func freshAuthorizationCode() async -> AppleReauthorizationOutcome
}

struct NoAppleReauthorization: AppleReauthorizing {
    @MainActor
    func freshAuthorizationCode() async -> AppleReauthorizationOutcome {
        .failed
    }
}

// The first authorization code was never kept, so deletion asks Apple for a fresh one to revoke the token.
final class AppleDeletionReauthorizer: AppleReauthorizing {
    private var session: AppleReauthorizationSession?
    private var controller: ASAuthorizationController?

    @MainActor
    func freshAuthorizationCode() async -> AppleReauthorizationOutcome {
        guard session == nil, let anchor = Self.keyWindow() else { return .failed }
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = []
        let controller = ASAuthorizationController(authorizationRequests: [request])
        self.controller = controller
        let outcome = await withCheckedContinuation { continuation in
            let session = AppleReauthorizationSession(anchor: anchor, continuation: continuation)
            self.session = session
            controller.delegate = session
            controller.presentationContextProvider = session
            controller.performRequests()
        }
        session = nil
        self.controller = nil
        return outcome
    }

    @MainActor
    private static func keyWindow() -> UIWindow? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? scenes.first?.windows.first
    }
}

private final class AppleReauthorizationSession: NSObject,
    ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding {
    private let anchor: ASPresentationAnchor
    private var continuation: CheckedContinuation<AppleReauthorizationOutcome, Never>?

    init(anchor: ASPresentationAnchor, continuation: CheckedContinuation<AppleReauthorizationOutcome, Never>) {
        self.anchor = anchor
        self.continuation = continuation
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let codeData = credential.authorizationCode,
              let code = String(data: codeData, encoding: .utf8) else {
            finish(.failed)
            return
        }
        finish(.code(code, user: credential.user))
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        let nsError = error as NSError
        let isCancel = nsError.domain == ASAuthorizationError.errorDomain
            && nsError.code == ASAuthorizationError.canceled.rawValue
        finish(isCancel ? .cancelled : .failed)
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        anchor
    }

    private func finish(_ outcome: AppleReauthorizationOutcome) {
        continuation?.resume(returning: outcome)
        continuation = nil
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
            displayName: "Família",
            email: nil,
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
    // Set only by a sign-in made on the welcome screen, whose footnote states the Terms; a restore never sets it.
    private(set) var interactiveSignInUserID: String?
    var isSigningIn = false
    var isDeletingAccount = false
    var errorMessage: String?
    var isBackendAvailable = true
    private(set) var deletionFailure: AccountDeletionFailure?
    private(set) var failedDeletionAttempts = 0
    @ObservationIgnored private var ownDeletionMayHaveRun = false
    static let failedDeletionAttemptsBeforeMail = 2

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

    func noteChosenDisplayName(_ name: String) {
        currentUser?.displayName = name
    }

    // App Store 5.1.1(v): a refusal, an ended session or a second failure in a row always leaves a way out.
    var offersDeletionByMail: Bool {
        switch deletionFailure {
        case nil, .guardianAccessDenied?:
            false
        case .sessionEnded?, .rejected?, .mayAlreadyBeDeleted?:
            true
        case .appleCancelled?, .offline?, .unconfirmed?, .serverUnavailable?:
            failedDeletionAttempts >= Self.failedDeletionAttemptsBeforeMail
        }
    }

    func clearDeletionFailure() {
        deletionFailure = nil
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

    // A cancelled Apple sheet stops the deletion; any other Apple failure still deletes, only without revocation.
    @discardableResult
    func deleteAccount(reauthorizer: any AppleReauthorizing = NoAppleReauthorization()) async -> Bool {
        guard let user = currentUser, !isDeletingAccount else { return false }
        deletionFailure = nil

        #if DEBUG
        if user.isDebugAccount {
            clearSessionState()
            Haptics.success()
            return true
        }
        #endif

        isDeletingAccount = true
        defer { isDeletingAccount = false }

        guard let request = await deletionRequest(for: user, reauthorizer: reauthorizer) else {
            return false
        }

        do {
            try await authClient.deleteAccount(request)
            clearSessionState()
            Haptics.success()
            return true
        } catch is CancellationError {
            return false
        } catch {
            recordOwnDeletionFailure(error)
            return false
        }
    }

    // The account may be gone already, so leaving never depends on the server answering.
    func leaveAccountThatMayBeDeleted() async {
        guard deletionFailure == .mayAlreadyBeDeleted else { return }
        try? await authClient.signOut()
        clearSessionState()
    }

    // A guardian deletes a claimed ward's account and stays signed in.
    @discardableResult
    func deleteWardAccount(memberID: UUID) async -> Bool {
        guard currentUser != nil, !isDeletingAccount else { return false }
        deletionFailure = nil
        isDeletingAccount = true
        defer { isDeletingAccount = false }

        do {
            try await authClient.deleteAccount(.guardian(memberID: memberID))
            failedDeletionAttempts = 0
            Haptics.success()
            return true
        } catch is CancellationError {
            return false
        } catch {
            recordDeletionFailure(error)
            return false
        }
    }

    private func deletionRequest(
        for user: AuthUser,
        reauthorizer: any AppleReauthorizing
    ) async -> DeleteAccountRequest? {
        guard user.signedInWithApple else { return DeleteAccountRequest() }
        switch await reauthorizer.freshAuthorizationCode() {
        case .cancelled:
            // A cancelled sheet sends nothing, but it still counts: a sheet that never completes must reach the mail.
            failedDeletionAttempts += 1
            deletionFailure = .appleCancelled
            return nil
        case .failed:
            return DeleteAccountRequest()
        case .code(let code, let appleUser):
            if let subject = user.appleSubject, subject != appleUser {
                return DeleteAccountRequest()
            }
            return DeleteAccountRequest.revoking(appleAuthorizationCode: code) ?? DeleteAccountRequest()
        }
    }

    private func performSignIn(_ operation: () async throws -> AuthUser) async {
        guard !isSigningIn else { return }

        isSigningIn = true
        errorMessage = nil
        defer { isSigningIn = false }

        do {
            let user = try await operation()
            interactiveSignInUserID = user.id
            currentUser = user
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

    private func recordDeletionFailure(_ error: Error) {
        failedDeletionAttempts += 1
        deletionFailure = (error as? AccountDeletionFailure) ?? .unconfirmed
        Haptics.error()
    }

    // After an answer that never arrived, a signed-out reply most likely means the deletion finished.
    private func recordOwnDeletionFailure(_ error: Error) {
        let failure = (error as? AccountDeletionFailure) ?? .unconfirmed
        if failure == .sessionEnded, ownDeletionMayHaveRun {
            recordDeletionFailure(AccountDeletionFailure.mayAlreadyBeDeleted)
            return
        }
        if failure == .unconfirmed {
            ownDeletionMayHaveRun = true
        }
        recordDeletionFailure(failure)
    }

    private func clearSessionState() {
        currentUser = nil
        interactiveSignInUserID = nil
        deletionFailure = nil
        failedDeletionAttempts = 0
        ownDeletionMayHaveRun = false
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
