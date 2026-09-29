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

    func testAppleIsAskedForANameAndAnEmailOnlyWhenTheDeviceReportedAnAdult() {
        let adult = AgeReadingResult.reading(
            AgeMapping(status: .adult, band: nil, assurance: .selfDeclared, parentalControlsActive: false)
        )
        let minor = AgeReadingResult.reading(
            AgeMapping(status: .minor, band: .twelveToFifteen, assurance: .none, parentalControlsActive: false)
        )
        let unknown = AgeReadingResult.reading(
            AgeMapping(status: .unknown, band: nil, assurance: .none, parentalControlsActive: false)
        )

        XCTAssertEqual(LoginView.requestedScopes(for: adult), [.fullName, .email])
        XCTAssertEqual(LoginView.requestedScopes(for: minor), [])
        XCTAssertEqual(LoginView.requestedScopes(for: unknown), [])
        XCTAssertEqual(LoginView.requestedScopes(for: .unavailable), [])
        XCTAssertEqual(LoginView.requestedScopes(for: nil), [])
    }

    func testEachDeletionBodyCarriesOnlyItsOwnKeysAndNeverANull() throws {
        func payload(_ request: DeleteAccountRequest) throws -> [String: String] {
            let data = try JSONEncoder().encode(request)
            return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])
        }
        let memberID = try XCTUnwrap(UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"))
        let revoking = try XCTUnwrap(DeleteAccountRequest.revoking(appleAuthorizationCode: "c0de.abc_-123"))

        XCTAssertEqual(try payload(DeleteAccountRequest()), ["confirmation": "delete"])
        XCTAssertEqual(
            try payload(revoking),
            ["confirmation": "delete", "apple_authorization_code": "c0de.abc_-123"]
        )
        XCTAssertEqual(
            try payload(.guardian(memberID: memberID)),
            ["confirmation": "delete", "member_id": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"]
        )
        XCTAssertNil(DeleteAccountRequest.revoking(appleAuthorizationCode: "has space"))
        XCTAssertNil(DeleteAccountRequest.revoking(appleAuthorizationCode: ""))
        XCTAssertNil(DeleteAccountRequest.revoking(appleAuthorizationCode: String(repeating: "a", count: 513)))
    }

    @MainActor
    func testACancelledAppleReauthorizationDeletesNothingAndSaysSo() async {
        let client = AuthClientSpy()
        let store = AuthSessionStore(authClient: client)
        store.currentUser = AuthUser(
            id: "current",
            displayName: "Current",
            email: nil,
            provider: .apple,
            appleSubject: "apple-subject"
        )

        let deleted = await store.deleteAccount(reauthorizer: ScriptedReauthorizer(outcome: .cancelled))

        XCTAssertFalse(deleted)
        XCTAssertTrue(client.deletionRequests.isEmpty)
        XCTAssertNotNil(store.currentUser)
        XCTAssertEqual(store.errorMessage, "A Apple não confirmou. Nada foi apagado.")
    }

    @MainActor
    func testAFreshAppleCodeTravelsWithTheDeletionOnlyForTheSameAppleAccount() async throws {
        let matching = AuthClientSpy()
        let store = AuthSessionStore(authClient: matching)
        store.currentUser = AuthUser(
            id: "current",
            displayName: "Current",
            email: nil,
            provider: .apple,
            appleSubject: "apple-subject"
        )
        _ = await store.deleteAccount(
            reauthorizer: ScriptedReauthorizer(outcome: .code("fresh.code", user: "apple-subject"))
        )
        XCTAssertEqual(
            matching.deletionRequests,
            [try XCTUnwrap(DeleteAccountRequest.revoking(appleAuthorizationCode: "fresh.code"))]
        )

        let mismatched = AuthClientSpy()
        let otherStore = AuthSessionStore(authClient: mismatched)
        otherStore.currentUser = AuthUser(
            id: "current",
            displayName: "Current",
            email: nil,
            provider: .apple,
            appleSubject: "apple-subject"
        )
        _ = await otherStore.deleteAccount(
            reauthorizer: ScriptedReauthorizer(outcome: .code("fresh.code", user: "someone-else"))
        )
        XCTAssertEqual(mismatched.deletionRequests, [DeleteAccountRequest()])

        let failed = AuthClientSpy()
        let failedStore = AuthSessionStore(authClient: failed)
        failedStore.currentUser = AuthUser(id: "current", displayName: "Current", email: nil, provider: .apple)
        _ = await failedStore.deleteAccount(reauthorizer: ScriptedReauthorizer(outcome: .failed))
        XCTAssertEqual(failed.deletionRequests, [DeleteAccountRequest()])
    }

    @MainActor
    func testAGuardianDeletesAWardWithoutLeavingTheirOwnSession() async throws {
        let client = AuthClientSpy()
        let store = AuthSessionStore(authClient: client)
        let guardian = AuthUser(id: "guardian", displayName: "Guardian", email: nil, provider: .apple)
        store.currentUser = guardian
        let wardMemberID = UUID()

        let deleted = await store.deleteWardAccount(memberID: wardMemberID)

        XCTAssertTrue(deleted)
        XCTAssertEqual(client.deletionRequests, [.guardian(memberID: wardMemberID)])
        XCTAssertEqual(store.currentUser, guardian)
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

private struct ScriptedReauthorizer: AppleReauthorizing {
    var outcome: AppleReauthorizationOutcome

    @MainActor
    func freshAuthorizationCode() async -> AppleReauthorizationOutcome {
        outcome
    }
}

private final class AuthClientSpy: AuthClient, @unchecked Sendable {
    var restoration: AuthSessionRestoration
    var lastAppleCredential: AppleSignInCredential?
    var appleSignInError: Error?
    var deleteAccountCallCount = 0
    var deletionRequests: [DeleteAccountRequest] = []
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

    func deleteAccount(_ request: DeleteAccountRequest) async throws {
        deleteAccountCallCount += 1
        deletionRequests.append(request)
    }

    func signOut() async throws {
        signOutCallCount += 1
    }
}
