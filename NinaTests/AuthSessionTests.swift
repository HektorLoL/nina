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
        let credential = AppleSignInCredential(identityToken: "identity-token", rawNonce: "raw-nonce")

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
        XCTAssertEqual(store.deletionFailure, .appleCancelled)
        XCTAssertEqual(
            AccountDeletionView.line(for: .appleCancelled),
            "A Apple não confirmou. Nada foi apagado."
        )
        XCTAssertNil(store.errorMessage)
        XCTAssertEqual(store.failedDeletionAttempts, 1)
        XCTAssertFalse(store.offersDeletionByMail)
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
            credential: AppleSignInCredential(identityToken: "token", rawNonce: "nonce")
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
            credential: AppleSignInCredential(identityToken: "token", rawNonce: "nonce")
        )

        XCTAssertNil(store.currentUser)
        XCTAssertNil(store.errorMessage)
        XCTAssertFalse(store.isSigningIn)
    }

    func testAServerOrDeviceFilledNameIsNeverReadAsOneThePersonChose() {
        for placeholder in ["Família", " família ", "FAMÍLIA", "Você", "", "  "] {
            XCTAssertTrue(ProfileNaming.isPlaceholder(placeholder), placeholder)
        }
        for chosen in ["Ana", "Família Souza", "Teste 1", "Vocês"] {
            XCTAssertFalse(ProfileNaming.isPlaceholder(chosen), chosen)
        }
    }

    func testANewAppleAccountIsAskedForItsNameAndANamedOrDebugAccountIsNot() {
        let fresh = AuthUser(id: UUID().uuidString, displayName: "Família", email: nil, provider: .apple)
        let offline = AuthUser(id: UUID().uuidString, displayName: "Você", email: nil, provider: .apple)
        let named = AuthUser(id: UUID().uuidString, displayName: "Ana", email: nil, provider: .apple)

        XCTAssertTrue(ProfileNaming.needsName(user: fresh, knownName: nil))
        XCTAssertTrue(ProfileNaming.needsName(user: named, knownName: "Família"))
        XCTAssertFalse(ProfileNaming.needsName(user: fresh, knownName: "Ana"))
        XCTAssertFalse(ProfileNaming.needsName(user: offline, knownName: "Ana"))
        XCTAssertFalse(ProfileNaming.needsName(user: named, knownName: nil))
        XCTAssertFalse(ProfileNaming.needsName(user: nil, knownName: nil))
        #if DEBUG
        for account in DebugAuthAccount.allCases {
            XCTAssertFalse(ProfileNaming.needsName(user: account.user, knownName: nil))
            XCTAssertFalse(ProfileNaming.needsName(user: account.user, knownName: "Família"))
        }
        #endif
    }

    @MainActor
    func testAChosenNameCountsOnlyOnceTheServerHoldsIt() async throws {
        let suiteName = "AuthSessionTests.\(#function).\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AuthSessionTests-\(UUID().uuidString)", isDirectory: true)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: directory)
        }
        let backend = ChosenNameBackendSpy()
        let profileStore = ProfileStore(
            defaults: defaults,
            privateDataStore: ProtectedLocalDataStore(directoryURL: directory),
            remoteProfileBackend: backend
        )
        let user = AuthUser(id: UUID().uuidString, displayName: "Família", email: nil, provider: .apple)
        let before = profileStore.profile(for: user)

        let placeholder = await profileStore.chooseDisplayName("  família ", for: user)
        XCTAssertFalse(placeholder)
        let afterPlaceholder = await backend.savedNames()
        XCTAssertEqual(afterPlaceholder, [])

        await backend.setFails(true)
        let failed = await profileStore.chooseDisplayName("Ana", for: user)
        XCTAssertFalse(failed)
        XCTAssertEqual(profileStore.profiles[user.id], before)
        XCTAssertTrue(ProfileNaming.needsName(user: user, knownName: profileStore.profiles[user.id]?.displayName))

        await backend.setFails(false)
        let chosen = await profileStore.chooseDisplayName(" Ana ", for: user)
        XCTAssertTrue(chosen)
        let saved = await backend.savedNames()
        XCTAssertEqual(saved, ["Ana"])
        XCTAssertEqual(profileStore.profiles[user.id]?.displayName, "Ana")
        XCTAssertFalse(ProfileNaming.needsName(user: user, knownName: profileStore.profiles[user.id]?.displayName))
    }

    @MainActor
    func testAChosenNameReachesTheSessionSoTheTutorialNamesThePerson() {
        let store = AuthSessionStore(authClient: AuthClientSpy())
        store.currentUser = AuthUser(id: "fresh", displayName: "Família", email: nil, provider: .apple)

        store.noteChosenDisplayName("Ana")

        XCTAssertEqual(store.currentUser?.displayName, "Ana")
        XCTAssertNil(store.interactiveSignInUserID)
    }

    @MainActor
    func testTheSignInAsksAppleForTheNameAloneAndNeverTheEmail() {
        let signIn = ASAuthorizationAppleIDProvider().createRequest()
        LoginView.configureAppleRequest(signIn, rawNonce: "nina")

        XCTAssertEqual(signIn.requestedScopes, [.fullName])
        XCTAssertFalse(signIn.requestedScopes?.contains(.email) ?? true)
        XCTAssertEqual(signIn.nonce, AppleSignInNonce.sha256("nina"))

        let deletion = AppleDeletionReauthorizer.makeRequest()
        XCTAssertEqual(deletion.requestedScopes ?? [], [])
    }

    @MainActor
    func testOnlyTheGivenNameAppleSharesIsKeptAndItIsTheOnlyNameTheServerReceives() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AuthSessionTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let deviceStore = ProtectedLocalDataStore(directoryURL: directory)
        let shared = PersonNameComponents(
            namePrefix: "Dra.",
            givenName: "  Ana  ",
            middleName: "Beatriz",
            familyName: "Souza",
            nameSuffix: "Neta",
            nickname: "Aninha"
        )
        let credential = AppleSignInCredential(
            identityToken: "token",
            rawNonce: "nonce",
            appleUserID: "apple-sub",
            sharedName: shared
        )
        let otherParts = ["Dra", "Beatriz", "Souza", "Neta", "Aninha"]

        XCTAssertEqual(credential.givenName, "Ana")
        XCTAssertEqual(
            Set(Mirror(reflecting: credential).children.compactMap(\.label)),
            ["identityToken", "rawNonce", "appleUserID", "givenName"]
        )

        let client = AuthClientSpy()
        let session = AuthSessionStore(authClient: client, sharedNameStore: deviceStore)
        await session.signInWithApple(credential: credential)
        let user = try XCTUnwrap(session.currentUser)
        XCTAssertEqual(user.displayName, "Família")
        XCTAssertEqual(session.sharedGivenName, "Ana")

        let held = try XCTUnwrap(
            deviceStore.data(forKey: "nina.auth.sharedAppleName", ownerScope: PrivateLocalDataScope.sharedAppleName)
        )
        let heldText = try XCTUnwrap(String(data: held, encoding: .utf8))
        XCTAssertTrue(heldText.contains("Ana"))
        for part in otherParts {
            XCTAssertFalse(heldText.contains(part), part)
        }

        let suiteName = "AuthSessionTests.\(#function).\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let backend = ChosenNameBackendSpy()
        let profileStore = ProfileStore(
            defaults: defaults,
            privateDataStore: ProtectedLocalDataStore(directoryURL: directory.appendingPathComponent("profiles")),
            remoteProfileBackend: backend
        )
        let name = try XCTUnwrap(
            ProfileNaming.nameToSave(
                user: user,
                knownName: "Família",
                sharedGivenName: session.sharedGivenName,
                typed: ""
            )
        )
        let saved = await profileStore.chooseDisplayName(name, for: user)
        XCTAssertTrue(saved)
        session.noteChosenDisplayName(name)

        let names = await backend.savedNames()
        XCTAssertEqual(names, ["Ana"])
        XCTAssertEqual(session.currentUser?.displayName, "Ana")
        XCTAssertNil(session.sharedGivenName)
        XCTAssertNil(
            try deviceStore.data(forKey: "nina.auth.sharedAppleName", ownerScope: PrivateLocalDataScope.sharedAppleName)
        )
    }

    @MainActor
    func testABlankOrMissingAppleNameLeavesTheTypedField() async {
        let unnamed: [PersonNameComponents?] = [
            nil,
            PersonNameComponents(),
            PersonNameComponents(givenName: "   "),
            PersonNameComponents(givenName: "Família"),
            PersonNameComponents(familyName: "Souza", nickname: "Aninha")
        ]

        for shared in unnamed {
            let store = AuthSessionStore(authClient: AuthClientSpy())
            let credential = AppleSignInCredential(
                identityToken: "token",
                rawNonce: "nonce",
                appleUserID: "apple-sub",
                sharedName: shared
            )
            XCTAssertNil(credential.givenName)

            await store.signInWithApple(credential: credential)

            let user = store.currentUser
            XCTAssertEqual(user?.displayName, "Família")
            XCTAssertNil(store.sharedGivenName)
            XCTAssertTrue(ProfileNaming.asksForName(user: user, knownName: nil, sharedGivenName: store.sharedGivenName))
            XCTAssertEqual(
                ProfileNaming.nameToSave(user: user, knownName: nil, sharedGivenName: nil, typed: "  Bia "),
                "Bia"
            )
        }
    }

    @MainActor
    func testAnAdultWhoSharedTheirNameIsNeverAskedAndItIsSavedBeforeTheHouseCopiesIt() async {
        let store = AuthSessionStore(authClient: AuthClientSpy())

        await store.signInWithApple(
            credential: AppleSignInCredential(
                identityToken: "token",
                rawNonce: "nonce",
                appleUserID: "apple-sub",
                sharedName: PersonNameComponents(givenName: "Ana", familyName: "Souza")
            )
        )

        let user = store.currentUser
        XCTAssertEqual(user?.displayName, "Família")
        XCTAssertEqual(store.sharedGivenName, "Ana")
        for knownName in [nil, "Família", "Ana"] as [String?] {
            XCTAssertFalse(ProfileNaming.asksForName(user: user, knownName: knownName, sharedGivenName: store.sharedGivenName))
            XCTAssertEqual(
                ProfileNaming.nameToSave(user: user, knownName: knownName, sharedGivenName: store.sharedGivenName, typed: ""),
                "Ana"
            )
        }

        store.noteChosenDisplayName("Ana")
        XCTAssertNil(store.sharedGivenName)
        XCTAssertNil(ProfileNaming.nameToSave(user: store.currentUser, knownName: "Ana", sharedGivenName: nil, typed: ""))
    }

    @MainActor
    func testANameThePersonAlreadyChoseOutranksTheOneAppleSharesAgain() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AuthSessionTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let deviceStore = ProtectedLocalDataStore(directoryURL: directory)
        let client = AuthClientSpy()
        client.serverChosenName = "Mãe"
        let store = AuthSessionStore(authClient: client, sharedNameStore: deviceStore)

        await store.signInWithApple(
            credential: AppleSignInCredential(
                identityToken: "token",
                rawNonce: "nonce",
                appleUserID: "apple-sub",
                sharedName: PersonNameComponents(givenName: "Ana")
            )
        )

        XCTAssertEqual(store.currentUser?.displayName, "Mãe")
        XCTAssertNil(store.sharedGivenName)
        XCTAssertNil(ProfileNaming.nameToSave(user: store.currentUser, knownName: "Mãe", sharedGivenName: nil, typed: ""))
        XCTAssertNil(
            try deviceStore.data(forKey: "nina.auth.sharedAppleName", ownerScope: PrivateLocalDataScope.sharedAppleName)
        )
    }

    @MainActor
    func testANameChosenInPerfilAfterApplesIsNeverOverwrittenWhenTheHouseIsSetUp() async {
        let store = AuthSessionStore(authClient: AuthClientSpy())
        await store.signInWithApple(
            credential: AppleSignInCredential(
                identityToken: "token",
                rawNonce: "nonce",
                appleUserID: "apple-sub",
                sharedName: PersonNameComponents(givenName: "Ana")
            )
        )
        let user = store.currentUser
        XCTAssertEqual(store.sharedGivenName, "Ana")

        XCTAssertFalse(ProfileNaming.asksForName(user: user, knownName: "Aninha", sharedGivenName: store.sharedGivenName))
        XCTAssertNil(
            ProfileNaming.nameToSave(user: user, knownName: "Aninha", sharedGivenName: store.sharedGivenName, typed: "")
        )
    }

    @MainActor
    func testApplesSharedNameSurvivesARelaunchUntilThePersonIsNamed() async {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AuthSessionTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let deviceStore = ProtectedLocalDataStore(directoryURL: directory)
        let unnamed = AuthUser(id: "apple-user", displayName: "Família", email: nil, provider: .apple)

        let first = AuthSessionStore(authClient: AuthClientSpy(), sharedNameStore: deviceStore)
        await first.signInWithApple(
            credential: AppleSignInCredential(
                identityToken: "token",
                rawNonce: "nonce",
                appleUserID: "apple-sub",
                sharedName: PersonNameComponents(givenName: "Ana")
            )
        )
        XCTAssertEqual(first.sharedGivenName, "Ana")

        let relaunched = AuthSessionStore(
            authClient: AuthClientSpy(restoration: .signedIn(unnamed)),
            sharedNameStore: deviceStore
        )
        XCTAssertNil(relaunched.sharedGivenName)
        await relaunched.restoreSession()
        XCTAssertEqual(relaunched.sharedGivenName, "Ana")

        let offline = AuthSessionStore(
            authClient: AuthClientSpy(
                restoration: .unreachable(AuthUser(id: "apple-user", displayName: "Você", email: nil, provider: .apple))
            ),
            sharedNameStore: deviceStore
        )
        await offline.restoreSession()
        XCTAssertEqual(offline.sharedGivenName, "Ana")

        relaunched.noteChosenDisplayName("Ana")
        let named = AuthSessionStore(
            authClient: AuthClientSpy(restoration: .signedIn(unnamed)),
            sharedNameStore: deviceStore
        )
        await named.restoreSession()
        XCTAssertNil(named.sharedGivenName)
    }

    @MainActor
    func testAFailedSignInKeepsApplesNameForTheRetryOfTheSameAppleIDOnly() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AuthSessionTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let deviceStore = ProtectedLocalDataStore(directoryURL: directory)

        func failedFirstAttempt() async -> AuthClientSpy {
            let client = AuthClientSpy()
            client.appleSignInError = URLError(.timedOut)
            let store = AuthSessionStore(authClient: client, sharedNameStore: deviceStore)
            await store.signInWithApple(
                credential: AppleSignInCredential(
                    identityToken: "token",
                    rawNonce: "nonce",
                    appleUserID: "apple-sub",
                    sharedName: PersonNameComponents(givenName: "Ana")
                )
            )
            XCTAssertNil(store.currentUser)
            XCTAssertNil(store.sharedGivenName)
            client.appleSignInError = nil
            return client
        }

        let retry = await failedFirstAttempt()
        let retrying = AuthSessionStore(authClient: retry, sharedNameStore: deviceStore)
        await retrying.signInWithApple(
            credential: AppleSignInCredential(identityToken: "token", rawNonce: "nonce", appleUserID: "apple-sub")
        )
        XCTAssertEqual(retrying.sharedGivenName, "Ana")
        await retrying.signOut()

        _ = await failedFirstAttempt()
        let restored = AuthSessionStore(
            authClient: AuthClientSpy(
                restoration: .signedIn(
                    AuthUser(
                        id: "apple-user",
                        displayName: "Família",
                        email: nil,
                        provider: .apple,
                        appleSubject: "apple-sub"
                    )
                )
            ),
            sharedNameStore: deviceStore
        )
        await restored.restoreSession()
        XCTAssertEqual(restored.sharedGivenName, "Ana")
        await restored.signOut()

        let other = await failedFirstAttempt()
        let otherAppleID = AuthSessionStore(authClient: other, sharedNameStore: deviceStore)
        await otherAppleID.signInWithApple(
            credential: AppleSignInCredential(identityToken: "token", rawNonce: "nonce", appleUserID: "another-sub")
        )
        let otherUser = try XCTUnwrap(otherAppleID.currentUser)
        XCTAssertNil(otherAppleID.sharedGivenName)
        let again = AuthSessionStore(
            authClient: AuthClientSpy(restoration: .signedIn(otherUser)),
            sharedNameStore: deviceStore
        )
        await again.restoreSession()
        XCTAssertNil(again.sharedGivenName)
    }

    @MainActor
    func testAMinorsFieldIsFilledFromApplesNameButNoCopyOfItStaysOnTheDevice() async {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AuthSessionTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let deviceStore = ProtectedLocalDataStore(directoryURL: directory)
        let store = AuthSessionStore(authClient: AuthClientSpy(), sharedNameStore: deviceStore)
        await store.signInWithApple(
            credential: AppleSignInCredential(
                identityToken: "token",
                rawNonce: "nonce",
                appleUserID: "apple-sub",
                sharedName: PersonNameComponents(givenName: "Bia", familyName: "Souza")
            )
        )

        store.keepSharedGivenNameOffDevice()

        XCTAssertEqual(store.sharedGivenName, "Bia")
        XCTAssertNil(
            try? deviceStore.data(forKey: "nina.auth.sharedAppleName", ownerScope: PrivateLocalDataScope.sharedAppleName)
        )
        let relaunched = AuthSessionStore(
            authClient: AuthClientSpy(
                restoration: .signedIn(AuthUser(id: "apple-user", displayName: "Família", email: nil, provider: .apple))
            ),
            sharedNameStore: deviceStore
        )
        await relaunched.restoreSession()
        XCTAssertNil(relaunched.sharedGivenName)
    }

    @MainActor
    func testApplesSharedNameIsForgottenWhenThePersonSignsOut() async {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AuthSessionTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let deviceStore = ProtectedLocalDataStore(directoryURL: directory)
        let store = AuthSessionStore(authClient: AuthClientSpy(), sharedNameStore: deviceStore)
        await store.signInWithApple(
            credential: AppleSignInCredential(
                identityToken: "token",
                rawNonce: "nonce",
                appleUserID: "apple-sub",
                sharedName: PersonNameComponents(givenName: "Ana")
            )
        )
        XCTAssertEqual(store.sharedGivenName, "Ana")

        await store.signOut()

        XCTAssertNil(store.sharedGivenName)
        store.currentUser = AuthUser(id: "apple-user", displayName: "Família", email: nil, provider: .apple)
        XCTAssertNil(store.sharedGivenName)
        XCTAssertNil(
            try? deviceStore.data(forKey: "nina.auth.sharedAppleName", ownerScope: PrivateLocalDataScope.sharedAppleName)
        )
    }

    func testAnAccountWithoutAnEmailShowsNoEmail() {
        func user(_ email: String?) -> AuthUser {
            AuthUser(id: "account", displayName: "Ana", email: email, provider: .apple)
        }

        XCTAssertNil(user(nil).shownEmail)
        XCTAssertNil(user("").shownEmail)
        XCTAssertNil(user("  ").shownEmail)
        XCTAssertEqual(user("x7k2@privaterelay.appleid.com").shownEmail, "x7k2@privaterelay.appleid.com")
    }

    func testEachDeleteAccountErrorCodeIsMatchedWholeAndAGatewayAnswerFallsBackToItsStatus() {
        func failure(_ status: Int, _ body: String?) -> AccountDeletionFailure {
            AccountDeletionFailure(status: status, body: Data((body ?? "").utf8))
        }

        XCTAssertEqual(failure(401, #"{"error":"not_authenticated"}"#), .sessionEnded)
        XCTAssertEqual(failure(401, #"{"code":401,"message":"Invalid JWT"}"#), .sessionEnded)
        XCTAssertEqual(failure(403, #"{"error":"guardian_access_denied"}"#), .guardianAccessDenied)
        XCTAssertEqual(failure(403, #"{"error":"something_else"}"#), .rejected)
        XCTAssertEqual(failure(403, #"{"error":"guardian_access_denied_later"}"#), .rejected)
        XCTAssertEqual(failure(500, #"{"error":"delete_account_failed"}"#), .serverUnavailable)
        XCTAssertEqual(failure(503, #"{"error":"service_not_configured"}"#), .serverUnavailable)
        for status in [500, 502, 503, 504, 546] {
            XCTAssertEqual(failure(status, "<html>Bad gateway</html>"), .unconfirmed, "\(status)")
        }
        XCTAssertEqual(failure(429, nil), .serverUnavailable)
        XCTAssertEqual(failure(408, nil), .serverUnavailable)
        XCTAssertEqual(failure(400, #"{"error":"confirmation_required"}"#), .rejected)
        XCTAssertEqual(failure(400, #"{"error":"invalid_request"}"#), .rejected)
        XCTAssertEqual(failure(413, #"{"error":"payload_too_large"}"#), .rejected)
        XCTAssertEqual(failure(415, #"{"error":"unsupported_media_type"}"#), .rejected)
        XCTAssertEqual(failure(405, #"{"error":"method_not_allowed"}"#), .rejected)
        XCTAssertEqual(failure(302, nil), .unconfirmed)
    }

    func testOnlyAConnectionThatNeverLeftThePhoneReadsAsOfflineAndAnyOtherDropIsUnconfirmed() {
        let beforeSending: [URLError.Code] = [.cannotFindHost, .dnsLookupFailed, .cannotConnectToHost]
        for code in beforeSending {
            XCTAssertEqual(AccountDeletionFailure(transportError: URLError(code)), .offline, "\(code)")
        }
        let mayHaveLeft: [URLError.Code] = [
            .notConnectedToInternet,
            .dataNotAllowed,
            .internationalRoamingOff,
            .timedOut,
            .networkConnectionLost
        ]
        for code in mayHaveLeft {
            XCTAssertEqual(AccountDeletionFailure(transportError: URLError(code)), .unconfirmed, "\(code)")
        }
        XCTAssertEqual(AccountDeletionFailure(transportError: NSError(domain: "test", code: 1)), .unconfirmed)
    }

    @MainActor
    func testAFailedDeletionKeepsTheSessionAndNeverWritesTheSignInErrorLine() async {
        let client = AuthClientSpy()
        client.deletionError = AccountDeletionFailure.serverUnavailable
        let store = AuthSessionStore(authClient: client)
        let user = AuthUser(id: "current", displayName: "Current", email: nil, provider: .apple)
        store.currentUser = user

        let deleted = await store.deleteAccount()

        XCTAssertFalse(deleted)
        XCTAssertEqual(store.currentUser, user)
        XCTAssertEqual(store.deletionFailure, .serverUnavailable)
        XCTAssertNil(store.errorMessage)
        XCTAssertEqual(store.failedDeletionAttempts, 1)
    }

    @MainActor
    func testAnUnrecognizedDeletionErrorReadsAsUnconfirmedAndNeverClaimsNothingWasDeleted() async {
        let client = AuthClientSpy()
        client.deletionError = NSError(domain: "test", code: 1)
        let store = AuthSessionStore(authClient: client)
        store.currentUser = AuthUser(id: "current", displayName: "Current", email: nil, provider: .apple)

        _ = await store.deleteAccount()

        XCTAssertEqual(store.deletionFailure, .unconfirmed)
        XCTAssertFalse(AccountDeletionView.line(for: .unconfirmed).contains("Nada foi apagado"))
    }

    func testOnlyALineThatCanProveItSaysNothingWasDeleted() {
        let all = Self.everyDeletionFailure
        let provable: [AccountDeletionFailure] = [.appleCancelled, .offline, .rejected]

        for failure in all {
            XCTAssertEqual(
                AccountDeletionView.line(for: failure).contains("Nada foi apagado"),
                provable.contains(failure),
                "\(failure)"
            )
        }
    }

    @MainActor
    func testARefusalOffersTheMailWayOutAtOnceAndATemporaryFailureOnlyFromTheSecondInARow() async {
        let refused = AuthClientSpy()
        refused.deletionError = AccountDeletionFailure.rejected
        let refusedStore = AuthSessionStore(authClient: refused)
        refusedStore.currentUser = AuthUser(id: "current", displayName: "Current", email: nil, provider: .apple)
        _ = await refusedStore.deleteAccount()
        XCTAssertTrue(refusedStore.offersDeletionByMail)

        let ended = AuthClientSpy()
        ended.deletionError = AccountDeletionFailure.sessionEnded
        let endedStore = AuthSessionStore(authClient: ended)
        endedStore.currentUser = AuthUser(id: "current", displayName: "Current", email: nil, provider: .apple)
        _ = await endedStore.deleteAccount()
        XCTAssertTrue(endedStore.offersDeletionByMail)

        let temporary = AuthClientSpy()
        temporary.deletionError = AccountDeletionFailure.offline
        let store = AuthSessionStore(authClient: temporary)
        store.currentUser = AuthUser(id: "current", displayName: "Current", email: nil, provider: .apple)
        _ = await store.deleteAccount()
        XCTAssertFalse(store.offersDeletionByMail)

        store.clearDeletionFailure()
        temporary.deletionError = AccountDeletionFailure.unconfirmed
        _ = await store.deleteAccount()
        XCTAssertEqual(store.failedDeletionAttempts, 2)
        XCTAssertTrue(store.offersDeletionByMail)
    }

    @MainActor
    func testOneCancelledAppleSheetSendsNothingAndARepeatedOneReachesTheMailWayOut() async {
        let client = AuthClientSpy()
        let store = AuthSessionStore(authClient: client)
        store.currentUser = AuthUser(id: "current", displayName: "Current", email: nil, provider: .apple)

        _ = await store.deleteAccount(reauthorizer: ScriptedReauthorizer(outcome: .cancelled))
        XCTAssertEqual(store.deletionFailure, .appleCancelled)
        XCTAssertFalse(store.offersDeletionByMail)

        store.clearDeletionFailure()
        _ = await store.deleteAccount(reauthorizer: ScriptedReauthorizer(outcome: .cancelled))
        XCTAssertEqual(store.deletionFailure, .appleCancelled)
        XCTAssertTrue(store.offersDeletionByMail)
        XCTAssertTrue(client.deletionRequests.isEmpty)
        XCTAssertEqual(
            AccountDeletionView.line(for: .appleCancelled),
            "A Apple não confirmou. Nada foi apagado."
        )
    }

    @MainActor
    func testAGuardianRefusalNeverOffersTheMailWayOutHoweverOftenItRepeats() async {
        let client = AuthClientSpy()
        client.deletionError = AccountDeletionFailure.guardianAccessDenied
        let store = AuthSessionStore(authClient: client)
        store.currentUser = AuthUser(id: "current", displayName: "Current", email: nil, provider: .apple)
        for _ in 0..<3 {
            _ = await store.deleteWardAccount(memberID: UUID())
        }
        XCTAssertEqual(store.deletionFailure, .guardianAccessDenied)
        XCTAssertFalse(store.offersDeletionByMail)
    }

    @MainActor
    func testASignedOutReplyAfterAnAnswerThatNeverArrivedReadsAsMaybeDeletedAndNeverSendsThePersonToSignIn() async {
        let client = AuthClientSpy()
        client.deletionError = AccountDeletionFailure.unconfirmed
        let store = AuthSessionStore(authClient: client)
        store.currentUser = AuthUser(id: "current", displayName: "Current", email: nil, provider: .apple)

        _ = await store.deleteAccount()
        XCTAssertEqual(store.deletionFailure, .unconfirmed)

        store.clearDeletionFailure()
        client.deletionError = AccountDeletionFailure.sessionEnded
        _ = await store.deleteAccount()

        XCTAssertEqual(store.deletionFailure, .mayAlreadyBeDeleted)
        XCTAssertTrue(store.offersDeletionByMail)
        XCTAssertNotNil(store.currentUser)
        let words = [
            AccountDeletionView.line(for: .mayAlreadyBeDeleted),
            AccountDeletionView.mailWayOut(for: .mayAlreadyBeDeleted)
        ].joined(separator: " ").lowercased()
        XCTAssertFalse(words.contains("entre"))
        XCTAssertFalse(words.contains("tente"))
        XCTAssertFalse(words.contains("nada foi apagado"))
    }

    @MainActor
    func testASignedOutReplyWithNoEarlierUnansweredAttemptIsAnEndedSession() async {
        let client = AuthClientSpy()
        client.deletionError = AccountDeletionFailure.serverUnavailable
        let store = AuthSessionStore(authClient: client)
        store.currentUser = AuthUser(id: "current", displayName: "Current", email: nil, provider: .apple)
        _ = await store.deleteAccount()

        client.deletionError = AccountDeletionFailure.sessionEnded
        _ = await store.deleteAccount()

        XCTAssertEqual(store.deletionFailure, .sessionEnded)
    }

    @MainActor
    func testLeavingAnAccountThatMayBeDeletedSignsOutEvenWhenTheServerCannotAnswer() async {
        let client = AuthClientSpy()
        client.deletionError = AccountDeletionFailure.unconfirmed
        let store = AuthSessionStore(authClient: client)
        store.currentUser = AuthUser(id: "current", displayName: "Current", email: nil, provider: .apple)

        await store.leaveAccountThatMayBeDeleted()
        XCTAssertNotNil(store.currentUser)
        XCTAssertEqual(client.signOutCallCount, 0)

        _ = await store.deleteAccount()
        client.deletionError = AccountDeletionFailure.sessionEnded
        _ = await store.deleteAccount()
        client.signOutError = URLError(.notConnectedToInternet)

        await store.leaveAccountThatMayBeDeleted()

        XCTAssertNil(store.currentUser)
        XCTAssertNil(store.deletionFailure)
        XCTAssertEqual(store.failedDeletionAttempts, 0)
        XCTAssertEqual(client.signOutCallCount, 1)
    }

    @MainActor
    func testTheVoiceOverAnnouncementCarriesTheMailWayOutWhenTheCardShowsIt() {
        XCTAssertEqual(
            AccountDeletionView.announcement(for: .rejected, offersMail: true),
            "Não deu para apagar por aqui. Nada foi apagado. Para apagar mesmo assim, escreva para privacidade@ninai.app."
        )
        XCTAssertEqual(
            AccountDeletionView.announcement(for: .offline, offersMail: false),
            "Sem internet. Nada foi apagado."
        )
    }

    @MainActor
    func testASuccessfulDeletionClearsTheFailureAndItsCount() async {
        let client = AuthClientSpy()
        client.deletionError = AccountDeletionFailure.serverUnavailable
        let store = AuthSessionStore(authClient: client)
        store.currentUser = AuthUser(id: "current", displayName: "Current", email: nil, provider: .apple)
        _ = await store.deleteAccount()
        _ = await store.deleteAccount()
        XCTAssertTrue(store.offersDeletionByMail)

        client.deletionError = nil
        let deleted = await store.deleteAccount()

        XCTAssertTrue(deleted)
        XCTAssertNil(store.deletionFailure)
        XCTAssertEqual(store.failedDeletionAttempts, 0)
        XCTAssertFalse(store.offersDeletionByMail)
    }

    func testTheDeletionMailGoesToThePrivacyMailboxWithOnlyASubjectAndTheAccountReference() throws {
        let mail = NinaLegalLinks.accountDeletionMail(reference: "1234-ABCD")
        let components = try XCTUnwrap(URLComponents(url: mail, resolvingAgainstBaseURL: false))

        XCTAssertEqual(components.scheme, "mailto")
        XCTAssertEqual(components.path, "privacidade@ninai.app")
        XCTAssertEqual(components.path, NinaLegalLinks.privacyEmail)
        XCTAssertEqual(
            components.queryItems,
            [
                URLQueryItem(name: "subject", value: "Apagar minha conta"),
                URLQueryItem(name: "body", value: "Referência: 1234-abcd")
            ]
        )

        let bare = NinaLegalLinks.accountDeletionMail(reference: nil)
        let bareComponents = try XCTUnwrap(URLComponents(url: bare, resolvingAgainstBaseURL: false))
        XCTAssertEqual(bareComponents.queryItems, [URLQueryItem(name: "subject", value: "Apagar minha conta")])
    }

    func testAGuardiansMailNamesTheWardAndTheGuardiansOwnAccountAndNothingElse() throws {
        let ward = try XCTUnwrap(UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF"))
        let mail = NinaLegalLinks.accountDeletionMail(ward: ward, guardianReference: "GUARDIAN-1")
        let components = try XCTUnwrap(URLComponents(url: mail, resolvingAgainstBaseURL: false))

        XCTAssertEqual(components.path, NinaLegalLinks.privacyEmail)
        XCTAssertEqual(
            components.queryItems,
            [
                URLQueryItem(name: "subject", value: "Apagar a conta de um menor"),
                URLQueryItem(
                    name: "body",
                    value: "Referência: 6f9619ff-8b86-d011-b42d-00c04fc964ff\nResponsável: guardian-1"
                )
            ]
        )
    }

    func testAnAgeContestMailCarriesTheAccountReferenceSoItCanBeFoundWithoutAnEmail() throws {
        let mail = NinaLegalLinks.ageContestMail(reference: "1234-abcd")
        let components = try XCTUnwrap(URLComponents(url: mail, resolvingAgainstBaseURL: false))

        XCTAssertEqual(components.path, NinaLegalLinks.privacyEmail)
        XCTAssertEqual(
            components.queryItems,
            [
                URLQueryItem(name: "subject", value: "Minha idade está errada"),
                URLQueryItem(name: "body", value: "Referência: 1234-abcd")
            ]
        )
    }

    func testNoDeletionLineNamesASignInDoorOrRaisesItsVoice() {
        let all = Self.everyDeletionFailure
        let lines = all.map(AccountDeletionView.line(for:))
        let mailLines = all.map(AccountDeletionView.mailWayOut(for:))

        for line in lines + mailLines {
            XCTAssertLessThanOrEqual(line.split(separator: " ").count, 10, line)
        }
        for line in lines + mailLines.map({ $0.replacingOccurrences(of: NinaLegalLinks.privacyEmail, with: "") }) {
            for forbidden in ["email", "código", "google", "!", "amiga", "se não der"] {
                XCTAssertFalse(line.lowercased().contains(forbidden), "\(line) says \(forbidden)")
            }
        }
        for line in mailLines {
            XCTAssertTrue(line.contains(NinaLegalLinks.privacyEmail), line)
        }
    }

    private static let everyDeletionFailure: [AccountDeletionFailure] = [
        .appleCancelled, .offline, .unconfirmed, .serverUnavailable,
        .sessionEnded, .mayAlreadyBeDeleted, .guardianAccessDenied, .rejected
    ]

    @MainActor
    func testAGuardianWhoNoLongerActsForTheWardSeesWhyAndKeepsTheirSession() async {
        let client = AuthClientSpy()
        client.deletionError = AccountDeletionFailure.guardianAccessDenied
        let store = AuthSessionStore(authClient: client)
        let guardian = AuthUser(id: "guardian", displayName: "Guardian", email: nil, provider: .apple)
        store.currentUser = guardian

        let deleted = await store.deleteWardAccount(memberID: UUID())

        XCTAssertFalse(deleted)
        XCTAssertEqual(store.currentUser, guardian)
        XCTAssertEqual(store.deletionFailure, .guardianAccessDenied)
        XCTAssertEqual(
            AccountDeletionView.line(for: .guardianAccessDenied),
            "Você não é mais responsável por esta conta."
        )
        XCTAssertFalse(store.offersDeletionByMail)
    }

    func testNoSignInLineNamesAnotherDoor() {
        let errors: [AuthFlowError] = [
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

private actor ChosenNameBackendSpy: RemoteProfileBackend {
    private struct Refused: Error {}

    private var names: [String] = []
    private var fails = false

    func setFails(_ value: Bool) {
        fails = value
    }

    func savedNames() -> [String] {
        names
    }

    func saveChosenName(_ name: String, for userID: String) async throws {
        if fails { throw Refused() }
        names.append(name)
    }

    func loadProfile(for user: AuthUser) async throws -> UserProfile? { nil }
    func saveProfile(_ profile: UserProfile, user: AuthUser?) async throws {}
    func loadPhotoData(for userID: String) async throws -> Data { throw Refused() }
    func savePhotoData(_ data: Data, for userID: String) async throws {}
    func deletePhoto(for userID: String) async throws {}
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
    var serverChosenName: String?
    var deleteAccountCallCount = 0
    var deletionRequests: [DeleteAccountRequest] = []
    var deletionError: Error?
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
            displayName: serverChosenName ?? "Família",
            email: nil,
            provider: .apple
        )
    }

    func deleteAccount(_ request: DeleteAccountRequest) async throws {
        deleteAccountCallCount += 1
        deletionRequests.append(request)
        if let deletionError {
            throw deletionError
        }
    }

    var signOutError: Error?

    func signOut() async throws {
        signOutCallCount += 1
        if let signOutError {
            throw signOutError
        }
    }
}
