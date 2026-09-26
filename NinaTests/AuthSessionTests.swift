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

    func testProviderResolverReadsAGoogleOnlyAccountAsGoogle() {
        let result = AuthProviderResolver.resolve(
            identityProviders: ["google"],
            metadataProvider: nil
        )

        XCTAssertEqual(result.primary, .google)
        XCTAssertEqual(result.linked, [.google])
    }

    func testProviderResolverTrustsTheGoogleMetadataProvider() {
        let result = AuthProviderResolver.resolve(
            identityProviders: ["apple", "google"],
            metadataProvider: "google"
        )

        XCTAssertEqual(result.primary, .google)
        XCTAssertEqual(result.linked, [.apple, .google])
    }

    func testProviderResolverPrefersAppleOverGoogleWhenBothAreLinked() {
        let result = AuthProviderResolver.resolve(
            identityProviders: ["google", "apple"],
            metadataProvider: nil
        )

        XCTAssertEqual(result.primary, .apple)
        XCTAssertEqual(result.linked, [.apple, .google])
    }

    func testProviderResolverPrefersGoogleOverEmailWithoutMetadata() {
        let result = AuthProviderResolver.resolve(
            identityProviders: ["email", "google"],
            metadataProvider: nil
        )

        XCTAssertEqual(result.primary, .google)
        XCTAssertEqual(result.linked, [.email, .google])
    }

    func testTheSettingsPayloadOffersGoogleWhenTheProjectHasItOn() {
        XCTAssertEqual(
            GoogleSignIn.availability(statusCode: 200, body: settingsPayload(google: "true")),
            true
        )
    }

    func testASettingsPayloadWithGoogleOffIsADefiniteNo() {
        XCTAssertEqual(
            GoogleSignIn.availability(statusCode: 200, body: settingsPayload(google: "false")),
            false
        )
    }

    func testASettingsPayloadWithoutAGoogleKeyReadsAsOff() {
        XCTAssertEqual(
            GoogleSignIn.availability(statusCode: 200, body: settingsPayload(google: nil)),
            false
        )
        XCTAssertEqual(
            GoogleSignIn.availability(statusCode: 200, body: settingsPayload(google: "null")),
            false
        )
    }

    func testARefusedOrUnreadableSettingsAnswerIsUnknownRatherThanOff() {
        let oversized = settingsPayload(google: "true")
            + Data(repeating: 0x20, count: GoogleSignIn.maximumSettingsBytes + 1 - settingsPayload(google: "true").count)
        XCTAssertEqual(oversized.count, GoogleSignIn.maximumSettingsBytes + 1)

        let unknowns: [(Int, Data)] = [
            (401, Data(#"{"message":"No API key found in request"}"#.utf8)),
            (500, settingsPayload(google: "true")),
            (200, Data(#"{"external":{"google":tr"#.utf8)),
            (200, Data(#"{"disable_signup":false}"#.utf8)),
            (200, Data(#"{"external":{"google":"true"}}"#.utf8)),
            (200, oversized)
        ]

        for (statusCode, body) in unknowns {
            XCTAssertNil(
                GoogleSignIn.availability(statusCode: statusCode, body: body),
                "status \(statusCode), \(body.count) bytes"
            )
        }
    }

    @MainActor
    func testWithoutACachedAnswerTheLoginScreenHidesGoogle() throws {
        let suiteName = "AuthSessionTests.\(#function).\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = AuthSessionStore(
            authClient: AuthClientSpy(projectHost: "project.supabase.co", googleAvailability: true),
            defaults: defaults
        )

        XCTAssertFalse(store.isGoogleSignInAvailable)
        XCTAssertFalse(store.isSignInChoiceSettled)
    }

    @MainActor
    func testACachedYesShowsGoogleAtLaunchBeforeAnyNetworkAnswer() throws {
        let suiteName = "AuthSessionTests.\(#function).\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: GoogleSignIn.cacheKey(projectHost: "project.supabase.co"))
        let client = AuthClientSpy(projectHost: "project.supabase.co")

        let store = AuthSessionStore(authClient: client, defaults: defaults)

        XCTAssertTrue(store.isGoogleSignInAvailable)
        XCTAssertTrue(store.isSignInChoiceSettled)
        XCTAssertEqual(client.googleAvailabilityCallCount, 0)
    }

    @MainActor
    func testWithoutACachedAnswerTheFirstAnswerSettlesTheWelcome() async throws {
        let suiteName = "AuthSessionTests.\(#function).\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let client = AuthClientSpy(projectHost: "project.supabase.co", googleAvailability: true)
        let store = AuthSessionStore(authClient: client, defaults: defaults)

        await store.refreshGoogleSignInAvailability()

        XCTAssertTrue(store.isSignInChoiceSettled)
        XCTAssertTrue(store.isGoogleSignInAvailable)
        XCTAssertTrue(AuthSessionStore(authClient: client, defaults: defaults).isGoogleSignInAvailable)
    }

    @MainActor
    func testAFailedFirstCheckSettlesTheWelcomeWithoutGoogleAtOnceAndCachesNothing() async throws {
        let suiteName = "AuthSessionTests.\(#function).\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let client = AuthClientSpy(projectHost: "project.supabase.co", googleAvailability: nil)
        let store = AuthSessionStore(authClient: client, defaults: defaults)

        await store.refreshGoogleSignInAvailability()

        XCTAssertTrue(store.isSignInChoiceSettled)
        XCTAssertFalse(store.isGoogleSignInAvailable)
        XCTAssertNil(defaults.object(forKey: GoogleSignIn.cacheKey(projectHost: "project.supabase.co")))
    }

    @MainActor
    func testAFreshAnswerReplacesTheCacheInBothDirections() async throws {
        let suiteName = "AuthSessionTests.\(#function).\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let client = AuthClientSpy(projectHost: "project.supabase.co", googleAvailability: true)
        let store = AuthSessionStore(authClient: client, defaults: defaults)

        await store.refreshGoogleSignInAvailability()
        XCTAssertTrue(AuthSessionStore(authClient: client, defaults: defaults).isGoogleSignInAvailable)

        client.googleAvailability = false
        await store.refreshGoogleSignInAvailability()
        XCTAssertFalse(AuthSessionStore(authClient: client, defaults: defaults).isGoogleSignInAvailable)

        client.googleAvailability = true
        await store.refreshGoogleSignInAvailability()
        XCTAssertTrue(AuthSessionStore(authClient: client, defaults: defaults).isGoogleSignInAvailable)
        XCTAssertEqual(client.googleAvailabilityCallCount, 3)
    }

    @MainActor
    func testARefreshAfterTheWelcomeSettledWritesTheCacheButLeavesTheShownRow() async throws {
        let suiteName = "AuthSessionTests.\(#function).\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let key = GoogleSignIn.cacheKey(projectHost: "project.supabase.co")
        defaults.set(true, forKey: key)
        let client = AuthClientSpy(projectHost: "project.supabase.co", googleAvailability: false)
        let store = AuthSessionStore(authClient: client, defaults: defaults)

        await store.refreshGoogleSignInAvailability()

        XCTAssertTrue(store.isGoogleSignInAvailable)
        XCTAssertEqual(defaults.object(forKey: key) as? Bool, false)

        store.prepareSignInChoice()

        XCTAssertFalse(store.isGoogleSignInAvailable)
        XCTAssertTrue(store.isSignInChoiceSettled)

        client.googleAvailability = true
        await store.refreshGoogleSignInAvailability()

        XCTAssertFalse(store.isGoogleSignInAvailable)
        XCTAssertEqual(defaults.object(forKey: key) as? Bool, true)
    }

    @MainActor
    func testAnUnansweredCheckPersistsNothingAndLeavesTheSettledRow() async throws {
        let suiteName = "AuthSessionTests.\(#function).\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: GoogleSignIn.cacheKey(projectHost: "project.supabase.co"))
        let client = AuthClientSpy(projectHost: "project.supabase.co", googleAvailability: nil)
        let store = AuthSessionStore(authClient: client, defaults: defaults)
        XCTAssertTrue(store.isGoogleSignInAvailable)

        await store.refreshGoogleSignInAvailability()

        XCTAssertTrue(store.isGoogleSignInAvailable)
        XCTAssertTrue(store.isSignInChoiceSettled)
        XCTAssertEqual(client.googleAvailabilityCallCount, 1)
        XCTAssertTrue(AuthSessionStore(authClient: client, defaults: defaults).isGoogleSignInAvailable)
    }

    @MainActor
    func testTheDeadlineSettlesTheWelcomeWithoutGoogleAndALateYesWaitsForTheNextWelcome() async throws {
        let suiteName = "AuthSessionTests.\(#function).\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let client = AuthClientSpy(projectHost: "project.supabase.co")
        client.suspendsGoogleAvailability = true
        let suspended = expectation(description: "the check is in flight")
        client.onGoogleAvailabilitySuspended = { suspended.fulfill() }
        let store = AuthSessionStore(authClient: client, defaults: defaults)
        XCTAssertFalse(store.isSignInChoiceSettled)

        let check = Task { await store.refreshGoogleSignInAvailability() }
        await fulfillment(of: [suspended], timeout: 2)
        store.closeSignInChoice()

        XCTAssertTrue(store.isSignInChoiceSettled)
        XCTAssertFalse(store.isGoogleSignInAvailable)

        client.resumeGoogleAvailability(with: true)
        await check.value

        XCTAssertFalse(store.isGoogleSignInAvailable)
        XCTAssertEqual(
            defaults.object(forKey: GoogleSignIn.cacheKey(projectHost: "project.supabase.co")) as? Bool,
            true
        )

        store.prepareSignInChoice()

        XCTAssertTrue(store.isGoogleSignInAvailable)
        XCTAssertTrue(store.isSignInChoiceSettled)
    }

    @MainActor
    func testSettlingRevealsTheWelcomeAtTheDeadlineEvenWhenTheCheckNeverAnswers() async throws {
        let suiteName = "AuthSessionTests.\(#function).\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let client = AuthClientSpy(projectHost: "project.supabase.co")
        client.suspendsGoogleAvailability = true
        let suspended = expectation(description: "the check is in flight")
        client.onGoogleAvailabilitySuspended = { suspended.fulfill() }
        let store = AuthSessionStore(authClient: client, defaults: defaults)

        await store.settleSignInChoice(within: .milliseconds(20))

        XCTAssertTrue(store.isSignInChoiceSettled)
        XCTAssertFalse(store.isGoogleSignInAvailable)

        await fulfillment(of: [suspended], timeout: 2)
        client.resumeGoogleAvailability(with: nil)
    }

    @MainActor
    func testAClientWithoutAProjectNeverOffersGoogle() async throws {
        let suiteName = "AuthSessionTests.\(#function).\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: GoogleSignIn.cacheKey(projectHost: "other.supabase.co"))
        let client = AuthClientSpy(projectHost: nil, googleAvailability: true)
        let store = AuthSessionStore(authClient: client, defaults: defaults)

        await store.refreshGoogleSignInAvailability()
        await store.settleSignInChoice()

        XCTAssertFalse(store.isGoogleSignInAvailable)
        XCTAssertTrue(store.isSignInChoiceSettled)
        XCTAssertEqual(client.googleAvailabilityCallCount, 0)
    }

    @MainActor
    func testACachedAnswerBelongsToTheProjectThatGaveIt() throws {
        let suiteName = "AuthSessionTests.\(#function).\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: GoogleSignIn.cacheKey(projectHost: "project-a.supabase.co"))

        let storeA = AuthSessionStore(
            authClient: AuthClientSpy(projectHost: "PROJECT-A.supabase.co"),
            defaults: defaults
        )
        let storeB = AuthSessionStore(
            authClient: AuthClientSpy(projectHost: "project-b.supabase.co"),
            defaults: defaults
        )

        XCTAssertTrue(storeA.isGoogleSignInAvailable)
        XCTAssertFalse(storeB.isGoogleSignInAvailable)
    }

    func testTheMockAndUnavailableClientsNeverOfferGoogle() async {
        let clients: [any AuthClient] = [MockAuthClient(), UnavailableAuthClient()]

        for client in clients {
            XCTAssertNil(client.projectHost)
            let availability = await client.googleSignInAvailability()
            XCTAssertNil(availability)
            do {
                _ = try await client.signInWithGoogle()
                XCTFail("\(type(of: client)) signed in with Google")
            } catch {
                XCTAssertEqual(error as? AuthFlowError, .unavailable)
            }
        }
    }

    @MainActor
    func testAnAvailabilityCheckNeverStartsDuringASignIn() async throws {
        let suiteName = "AuthSessionTests.\(#function).\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: GoogleSignIn.cacheKey(projectHost: "project.supabase.co"))
        let client = AuthClientSpy(projectHost: "project.supabase.co", googleAvailability: nil)
        let store = AuthSessionStore(authClient: client, defaults: defaults)
        store.isSigningIn = true

        await store.refreshGoogleSignInAvailability()

        XCTAssertEqual(client.googleAvailabilityCallCount, 0)
        XCTAssertTrue(store.isGoogleSignInAvailable)
    }

    @MainActor
    func testACheckThatLandsDuringASignInNeverChangesTheShownRowOrTheCache() async throws {
        let suiteName = "AuthSessionTests.\(#function).\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let key = GoogleSignIn.cacheKey(projectHost: "project.supabase.co")
        defaults.set(true, forKey: key)
        let client = AuthClientSpy(projectHost: "project.supabase.co")
        client.suspendsGoogleAvailability = true
        let suspended = expectation(description: "the check is in flight")
        client.onGoogleAvailabilitySuspended = { suspended.fulfill() }
        let store = AuthSessionStore(authClient: client, defaults: defaults)

        let check = Task { await store.refreshGoogleSignInAvailability() }
        await fulfillment(of: [suspended], timeout: 2)
        store.isSigningIn = true
        client.resumeGoogleAvailability(with: nil)
        await check.value

        XCTAssertTrue(store.isGoogleSignInAvailable)
        XCTAssertTrue(store.isSignInChoiceSettled)
        XCTAssertEqual(defaults.object(forKey: key) as? Bool, true)
        XCTAssertEqual(client.googleAvailabilityCallCount, 1)
    }

    @MainActor
    func testGoogleSignInSignsInAsAGoogleUser() async {
        let store = AuthSessionStore(authClient: AuthClientSpy())

        await store.signInWithGoogle()

        XCTAssertEqual(store.currentUser?.provider, .google)
        XCTAssertFalse(store.isSigningIn)
        XCTAssertNil(store.errorMessage)
    }

    @MainActor
    func testCancellingTheGoogleSheetShowsNoError() async {
        let store = AuthSessionStore(
            authClient: AuthClientSpy(googleSignInResult: .failure(CancellationError()))
        )

        await store.signInWithGoogle()

        XCTAssertNil(store.currentUser)
        XCTAssertNil(store.errorMessage)
        XCTAssertFalse(store.isSigningIn)
    }

    @MainActor
    func testAFailedGoogleSignInShowsTheGenericLine() async {
        let store = AuthSessionStore(
            authClient: AuthClientSpy(
                googleSignInResult: .failure(URLError(.notConnectedToInternet))
            )
        )

        await store.signInWithGoogle()

        XCTAssertNil(store.currentUser)
        XCTAssertEqual(store.errorMessage, AuthFlowError.unavailable.userMessage)
    }

    func testTheSheetsCancelAndGooglesDenyBothReadAsCancellation() {
        XCTAssertTrue(
            GoogleSignIn.isCancellation(
                NSError(
                    domain: ASWebAuthenticationSessionError.errorDomain,
                    code: ASWebAuthenticationSessionError.canceledLogin.rawValue
                )
            )
        )
        XCTAssertTrue(GoogleSignIn.isCancellation(ASWebAuthenticationSessionError(.canceledLogin)))
        XCTAssertFalse(
            GoogleSignIn.isCancellation(
                NSError(domain: ASWebAuthenticationSessionError.errorDomain, code: 2)
            )
        )
        XCTAssertFalse(GoogleSignIn.isCancellation(URLError(.cancelled)))

        XCTAssertTrue(GoogleSignIn.isCancellation(oauthErrorCode: "access_denied"))
        XCTAssertFalse(GoogleSignIn.isCancellation(oauthErrorCode: "server_error"))
        XCTAssertFalse(GoogleSignIn.isCancellation(oauthErrorCode: nil))
    }

    func testTheGoogleNameHintPrefersTheFullNameAndSkipsBlanks() {
        XCTAssertEqual(
            GoogleSignIn.displayNameHint(displayName: nil, fullName: " ", name: "Ana"),
            "Ana"
        )
        XCTAssertEqual(
            GoogleSignIn.displayNameHint(displayName: nil, fullName: " Ana Souza ", name: "Ana"),
            "Ana Souza"
        )
        XCTAssertNil(GoogleSignIn.displayNameHint(displayName: "", fullName: nil, name: "\n"))
    }

    func testTheGoogleNameHintKeepsTheNameAlreadyOnTheAccount() {
        XCTAssertEqual(
            GoogleSignIn.displayNameHint(
                displayName: "Heitor",
                fullName: "Heitor C. França",
                name: "Heitor C. França"
            ),
            "Heitor"
        )
    }

    func testTheGoogleCallbackIsTheBundleSchemeTheAuthAllowListCarries() throws {
        let callback = try XCTUnwrap(GoogleSignIn.callbackURL)

        XCTAssertEqual(callback.scheme, "com.heitor.nina")
        XCTAssertEqual(callback.host, "login-callback")
        XCTAssertEqual(callback.absoluteString, "com.heitor.nina://login-callback")
    }

    @MainActor
    func testANewAddressIsToldToContinueWithAppleWhileGoogleIsOff() async {
        let store = AuthSessionStore(
            authClient: AuthClientSpy(emailOTPError: AuthFlowError.emailNotLinked)
        )

        let requested = await store.requestEmailOTP(email: "nova@example.com")

        XCTAssertFalse(requested)
        XCTAssertNil(store.pendingLoginEmail)
        XCTAssertEqual(store.errorMessage, "Esse email não tem conta. Continue com a Apple.")
    }

    @MainActor
    func testANewAddressIsOfferedGoogleOnlyWhileTheGoogleButtonIsShown() async {
        let store = AuthSessionStore(
            authClient: AuthClientSpy(emailOTPError: AuthFlowError.emailNotLinked)
        )
        store.isGoogleSignInAvailable = true

        await store.requestEmailOTP(email: "nova@example.com")

        XCTAssertEqual(
            store.errorMessage,
            "Esse email não tem conta. Continue com a Apple ou o Google."
        )
    }

    func testTheContextFreeEmailNotLinkedLineNeverMentionsGoogle() {
        XCTAssertEqual(
            AuthFlowError.emailNotLinked.userMessage,
            AuthFlowError.emailNotLinked.userMessage(offersGoogle: false)
        )
        XCTAssertFalse(AuthFlowError.emailNotLinked.userMessage.contains("Google"))
        for offersGoogle in [false, true] {
            XCTAssertFalse(AuthFlowError.emailNotLinked.userMessage(offersGoogle: offersGoogle).contains("!"))
        }
    }

    private func settingsPayload(google: String?) -> Data {
        let googleEntry = google.map { #","google":\#($0)"# } ?? ""
        return Data(
            (#"{"external":{"anonymous_users":false,"apple":true,"azure":false,"email":true"#
                + googleEntry
                + #","phone":false},"disable_signup":false,"mailer_autoconfirm":false,"#
                + #""phone_autoconfirm":false,"sms_provider":"twilio","saml_enabled":false}"#).utf8
        )
    }
}

private final class AuthClientSpy: AuthClient, @unchecked Sendable {
    var restoration: AuthSessionRestoration
    var lastAppleCredential: AppleSignInCredential?
    var lastRequestedEmail: String?
    var deleteAccountCallCount = 0
    var projectHost: String?
    var googleAvailability: Bool?
    var googleAvailabilityCallCount = 0
    var googleSignInResult: Result<AuthUser, Error>
    var emailOTPError: Error?
    var suspendsGoogleAvailability = false
    var onGoogleAvailabilitySuspended: (() -> Void)?
    private let pendingGoogleAvailabilityLock = NSLock()
    private var pendingGoogleAvailability: CheckedContinuation<Bool?, Never>?

    init(
        restoration: AuthSessionRestoration = .signedOut,
        projectHost: String? = nil,
        googleAvailability: Bool? = nil,
        googleSignInResult: Result<AuthUser, Error> = .success(
            AuthUser(
                id: "google-user",
                displayName: "Google User",
                email: "google@example.com",
                provider: .google,
                isEmailVerified: true
            )
        ),
        emailOTPError: Error? = nil
    ) {
        self.restoration = restoration
        self.projectHost = projectHost
        self.googleAvailability = googleAvailability
        self.googleSignInResult = googleSignInResult
        self.emailOTPError = emailOTPError
    }

    func googleSignInAvailability() async -> Bool? {
        googleAvailabilityCallCount += 1
        guard suspendsGoogleAvailability else { return googleAvailability }
        return await withCheckedContinuation { continuation in
            pendingGoogleAvailabilityLock.withLock { pendingGoogleAvailability = continuation }
            onGoogleAvailabilitySuspended?()
        }
    }

    func resumeGoogleAvailability(with answer: Bool?) {
        let continuation = pendingGoogleAvailabilityLock.withLock {
            defer { pendingGoogleAvailability = nil }
            return pendingGoogleAvailability
        }
        continuation?.resume(returning: answer)
    }

    func signInWithGoogle() async throws -> AuthUser {
        try googleSignInResult.get()
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
        if let emailOTPError {
            throw emailOTPError
        }
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
