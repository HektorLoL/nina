import AuthenticationServices
import Foundation
import XCTest
@testable import Nina

final class AuthSessionTests: XCTestCase {
    func testNonceHashMatchesKnownSHA256Value() {
        XCTAssertEqual(
            AppleSignInNonce.sha256("nina"),
            "a5c299e2fdd21869360a5e52cb764eafc7b94bd0eed0a2080c427684024242e0"
        )
    }

    @MainActor
    func testAppleCredentialIsForwardedToClient() async {
        let client = AuthClientSpy()
        let store = AuthSessionStore(authClient: client)
        let credential = AppleSignInCredential(
            identityToken: "identity-token",
            rawNonce: "raw-nonce",
            fullName: "Nina Owner"
        )

        await store.signInWithApple(credential: credential)

        XCTAssertEqual(client.lastAppleCredential?.identityToken, "identity-token")
        XCTAssertEqual(client.lastAppleCredential?.rawNonce, "raw-nonce")
        XCTAssertEqual(store.currentUser?.provider, .apple)
    }

    @MainActor
    func testEmailOTPRequestNormalizesAddressAndTracksPendingState() async {
        let client = AuthClientSpy()
        let store = AuthSessionStore(authClient: client)

        let requested = await store.requestEmailOTP(email: " Owner@Example.COM ")

        XCTAssertTrue(requested)
        XCTAssertEqual(client.lastRequestedEmail, "owner@example.com")
        XCTAssertEqual(store.pendingLoginEmail, "owner@example.com")
    }

    #if DEBUG
    @MainActor
    func testDebugEmailSignsInWithoutRequestingOTP() async {
        let client = AuthClientSpy()
        let store = AuthSessionStore(authClient: client)

        let requested = await store.requestEmailOTP(email: " Teste1@NINAI.test ")

        XCTAssertTrue(requested)
        XCTAssertEqual(store.currentUser, DebugAuthAccount.testOne.user)
        XCTAssertNil(store.pendingLoginEmail)
        XCTAssertNil(client.lastRequestedEmail)
    }
    #endif

    @MainActor
    func testRestorationUsesOnlyClientSession() async {
        let expectedUser = AuthUser(
            id: "restored",
            displayName: "Restored",
            email: nil,
            provider: .apple
        )
        let client = AuthClientSpy(restoration: .signedIn(expectedUser))
        let store = AuthSessionStore(authClient: client)

        XCTAssertNil(store.currentUser)
        await store.restoreSession()
        XCTAssertEqual(store.currentUser, expectedUser)
    }

    @MainActor
    func testSignedOutRestorationClearsStaleUser() async {
        let store = AuthSessionStore(authClient: AuthClientSpy(restoration: .signedOut))
        store.currentUser = AuthUser(
            id: "stale",
            displayName: "Stale",
            email: nil,
            provider: .apple
        )
        store.isBackendAvailable = false

        await store.restoreSession()

        XCTAssertNil(store.currentUser)
        XCTAssertTrue(store.isBackendAvailable)
    }

    @MainActor
    func testUnavailableRestorationClearsStaleUserAndMarksBackendUnavailable() async {
        let store = AuthSessionStore(authClient: AuthClientSpy(restoration: .unavailable))
        store.currentUser = AuthUser(
            id: "stale",
            displayName: "Stale",
            email: nil,
            provider: .apple
        )

        await store.restoreSession()

        XCTAssertNil(store.currentUser)
        XCTAssertFalse(store.isBackendAvailable)
        XCTAssertEqual(store.errorMessage, AuthFlowError.configurationMissing.userMessage)
    }

    @MainActor
    func testAppleCancellationDoesNotShowError() {
        let store = AuthSessionStore(authClient: AuthClientSpy())
        let cancellation = NSError(
            domain: ASAuthorizationError.errorDomain,
            code: ASAuthorizationError.canceled.rawValue
        )

        store.reportAppleAuthorizationError(cancellation)

        XCTAssertNil(store.errorMessage)
    }

    @MainActor
    func testAppleFailureShowsError() {
        let store = AuthSessionStore(authClient: AuthClientSpy())

        store.reportAppleAuthorizationError(NSError(domain: "test", code: 1))

        XCTAssertNotNil(store.errorMessage)
    }

    @MainActor
    func testDeleteAccountCallsClientAndClearsSession() async {
        let client = AuthClientSpy()
        let store = AuthSessionStore(authClient: client)
        store.currentUser = AuthUser(
            id: "current",
            displayName: "Current",
            email: "current@example.com",
            provider: .apple
        )

        let deleted = await store.deleteAccount()

        XCTAssertTrue(deleted)
        XCTAssertEqual(client.deleteAccountCallCount, 1)
        XCTAssertNil(store.currentUser)
        XCTAssertNil(store.pendingLoginEmail)
        XCTAssertNil(store.pendingEmailChange)
    }

    func testDeleteAccountRequestCarriesExplicitDestructiveConfirmation() throws {
        let data = try JSONEncoder().encode(DeleteAccountRequest())
        let payload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: String]
        )

        XCTAssertEqual(payload, ["confirmation": "delete"])
    }

    @MainActor
    func testClearingDeletedAccountAlsoRemovesOnboardingMarker() throws {
        let suiteName = "AuthSessionTests.\(#function).\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let user = AuthUser(
            id: UUID().uuidString,
            displayName: "Deleted",
            email: "deleted@example.com",
            provider: .apple
        )
        let store = OnboardingStore(defaults: defaults)
        store.completeTutorial(for: user)
        XCTAssertTrue(store.hasCompletedTutorial(for: user))

        store.clearLocalData(for: user.id)

        XCTAssertFalse(store.hasCompletedTutorial(for: user))
        XCTAssertNil(defaults.object(forKey: "nina.onboarding.completed.\(user.id)"))
        XCTAssertFalse(store.isReplayingTutorial)
    }

    func testProviderResolverPrefersAppleForRestoredLinkedIdentity() {
        let result = AuthProviderResolver.resolve(
            identityProviders: ["email", "apple"],
            metadataProvider: nil
        )

        XCTAssertEqual(result.primary, .apple)
        XCTAssertEqual(result.linked, [.email, .apple])
    }
}

private final class AuthClientSpy: AuthClient, @unchecked Sendable {
    var restoration: AuthSessionRestoration
    var lastAppleCredential: AppleSignInCredential?
    var lastRequestedEmail: String?
    var deleteAccountCallCount = 0

    init(restoration: AuthSessionRestoration = .signedOut) {
        self.restoration = restoration
    }

    func restoreSession() async -> AuthSessionRestoration {
        restoration
    }

    func signInWithApple(credential: AppleSignInCredential) async throws -> AuthUser {
        lastAppleCredential = credential
        return AuthUser(
            id: "apple-user",
            displayName: credential.fullName ?? "Apple User",
            email: nil,
            provider: .apple
        )
    }

    func requestEmailOTP(email: String) async throws {
        lastRequestedEmail = email
    }

    func verifyEmailOTP(email: String, code: String) async throws -> AuthUser {
        AuthUser(
            id: "email-user",
            displayName: "Email User",
            email: email,
            provider: .email,
            isEmailVerified: true,
            linkedProviders: [.apple, .email]
        )
    }

    func requestEmailChange(email: String) async throws {}

    func verifyEmailChange(email: String, code: String) async throws -> AuthUser {
        try await verifyEmailOTP(email: email, code: code)
    }

    func deleteCurrentAccount() async throws {
        deleteAccountCallCount += 1
    }

    func signOut() async throws {}
}
