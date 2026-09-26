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
    func testAnUnreachableRestorationKeepsTheSignedInUserInsteadOfBouncingToLogin() async {
        let kept = AuthUser(id: "kept", displayName: "Kept", email: nil, provider: .apple)
        let offline = AuthUser(id: "kept", displayName: "kept@nina.local", email: "kept@nina.local", provider: .apple)
        let store = AuthSessionStore(authClient: AuthClientSpy(restoration: .unreachable(offline)))
        store.currentUser = kept
        store.isBackendAvailable = false

        await store.restoreSession()

        XCTAssertEqual(store.currentUser, kept)
        XCTAssertTrue(store.isBackendAvailable)
        XCTAssertNil(store.errorMessage)
    }

    @MainActor
    func testAnUnreachableRestorationOnColdStartSignsInFromTheStoredSession() async {
        let offline = AuthUser(id: "stored", displayName: "Stored", email: nil, provider: .apple)
        let store = AuthSessionStore(authClient: AuthClientSpy(restoration: .unreachable(offline)))

        await store.restoreSession()

        XCTAssertEqual(store.currentUser, offline)
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

    func testANewAppleSignInIsReadAsAppleEvenWhenTheAccountAlsoHasAnEmailIdentity() {
        let result = AuthProviderResolver.resolve(
            identityProviders: ["email", "apple"],
            metadataProvider: "email",
            preferredProvider: .apple
        )

        XCTAssertEqual(result.primary, .apple)
        XCTAssertEqual(result.linked, [.email, .apple])
    }

    func testARestoredAccountWithAnAppleIdentityReadsAsAppleWhateverItFirstSignedInWith() {
        let result = AuthProviderResolver.resolve(
            identityProviders: ["email", "apple"],
            metadataProvider: "email"
        )

        XCTAssertEqual(result.primary, .apple)
        XCTAssertEqual(result.linked, [.email, .apple])
    }

    func testALegacyEmailOnlyAccountStillResolvesToEmailRatherThanFailing() {
        let emailOnly = AuthProviderResolver.resolve(
            identityProviders: ["email"],
            metadataProvider: "email"
        )
        XCTAssertEqual(emailOnly.primary, .email)
        XCTAssertEqual(emailOnly.linked, [.email])

        let noIdentity = AuthProviderResolver.resolve(identityProviders: [], metadataProvider: nil)
        XCTAssertEqual(noIdentity.primary, .email)
        XCTAssertEqual(noIdentity.linked, [.email])

        let retiredProvider = AuthProviderResolver.resolve(
            identityProviders: ["google"],
            metadataProvider: "google"
        )
        XCTAssertEqual(retiredProvider.primary, .email)
        XCTAssertEqual(retiredProvider.linked, [.email])
    }

    func testALegacyEmailProviderUserStillEncodesAndDecodes() throws {
        let user = AuthUser(
            id: UUID().uuidString,
            displayName: "Conta antiga",
            email: "antiga@example.invalid",
            provider: .email,
            isEmailVerified: true,
            linkedProviders: [.apple, .email]
        )

        let decoded = try JSONDecoder().decode(AuthUser.self, from: JSONEncoder().encode(user))

        XCTAssertEqual(decoded, user)
        XCTAssertEqual(decoded.provider, .email)
        XCTAssertEqual(decoded.linkedProviders, [.apple, .email])
        XCTAssertEqual(decoded.email, "antiga@example.invalid")
    }

    @MainActor
    func testAFailedAppleExchangeShowsTheGenericLineAndSignsNobodyIn() async {
        let client = AuthClientSpy()
        client.appleSignInError = URLError(.notConnectedToInternet)
        let store = AuthSessionStore(authClient: client)

        await store.signInWithApple(
            credential: AppleSignInCredential(identityToken: "token", rawNonce: "nonce", fullName: nil)
        )

        XCTAssertNil(store.currentUser)
        XCTAssertEqual(store.errorMessage, AuthFlowError.unavailable.userMessage)
        XCTAssertFalse(store.isSigningIn)
    }

    @MainActor
    func testACancelledAppleExchangeShowsNoError() async {
        let client = AuthClientSpy()
        client.appleSignInError = CancellationError()
        let store = AuthSessionStore(authClient: client)

        await store.signInWithApple(
            credential: AppleSignInCredential(identityToken: "token", rawNonce: "nonce", fullName: nil)
        )

        XCTAssertNil(store.currentUser)
        XCTAssertNil(store.errorMessage)
        XCTAssertFalse(store.isSigningIn)
    }

    func testNoSignInLineNamesAnotherDoor() {
        let errors: [AuthFlowError] = [
            .deletionFailed,
            .appleCredentialInvalid,
            .configurationMissing,
            .unavailable
        ]

        for error in errors {
            let line = error.userMessage.lowercased()
            for forbidden in ["email", "código", "google", "!"] {
                XCTAssertFalse(line.contains(forbidden), "\(error) says \(forbidden)")
            }
        }
    }

    #if DEBUG
    @MainActor
    func testTheDebugTestAccountsSignInLocallyWithoutTouchingTheBackend() async {
        let client = AuthClientSpy()
        let store = AuthSessionStore(authClient: client)
        store.isBackendAvailable = false
        store.errorMessage = "x"

        store.signIn(as: .testTwo)

        XCTAssertEqual(store.currentUser, DebugAuthAccount.testTwo.user)
        XCTAssertTrue(store.isBackendAvailable)
        XCTAssertNil(store.errorMessage)
        XCTAssertNil(client.lastAppleCredential)

        await store.restoreSession()
        XCTAssertEqual(store.currentUser, DebugAuthAccount.testTwo.user)
        XCTAssertEqual(client.restoreCallCount, 0)

        let signedOut = await store.signOut()
        XCTAssertTrue(signedOut)
        XCTAssertEqual(client.signOutCallCount, 0)
        XCTAssertNil(store.currentUser)
    }

    func testEachDebugTestAccountIsADistinctLocalAccountOnAReservedDomain() {
        let users = DebugAuthAccount.allCases.map(\.user)

        XCTAssertEqual(Set(users.map(\.id)).count, DebugAuthAccount.allCases.count)
        for user in users {
            XCTAssertTrue(user.isDebugAccount)
            XCTAssertNil(UUID(uuidString: user.id))
            XCTAssertTrue(user.email?.hasSuffix(".test") == true)
        }
    }
    #endif
}

private final class AuthClientSpy: AuthClient, @unchecked Sendable {
    var restoration: AuthSessionRestoration
    var lastAppleCredential: AppleSignInCredential?
    var appleSignInError: Error?
    var deleteAccountCallCount = 0
    var restoreCallCount = 0
    var signOutCallCount = 0

    init(restoration: AuthSessionRestoration = .signedOut) {
        self.restoration = restoration
    }

    func restoreSession() async -> AuthSessionRestoration {
        restoreCallCount += 1
        return restoration
    }

    func signInWithApple(credential: AppleSignInCredential) async throws -> AuthUser {
        lastAppleCredential = credential
        if let appleSignInError {
            throw appleSignInError
        }
        return AuthUser(
            id: "apple-user",
            displayName: credential.fullName ?? "Apple User",
            email: nil,
            provider: .apple
        )
    }

    func deleteCurrentAccount() async throws {
        deleteAccountCallCount += 1
    }

    func signOut() async throws {
        signOutCallCount += 1
    }
}
