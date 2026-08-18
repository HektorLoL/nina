import StoreKit
import XCTest
@testable import Nina

final class PremiumSubscriptionTests: XCTestCase {
    func testTheHouseholdPremiumBlockDecodesTheShapeGetCurrentHomeContextReturns() throws {
        let json = """
        {"is_active":true,"status":"grace_period","expires_at":"2026-09-01T03:00:00Z"}
        """

        let premium = try Self.makeDecoder().decode(HouseholdPremium.self, from: Data(json.utf8))

        XCTAssertTrue(premium.isActive)
        XCTAssertEqual(premium.status, .gracePeriod)
        XCTAssertEqual(premium.expiresAt?.timeIntervalSince1970, 1_788_231_600)
    }

    func testTheHouseholdPremiumBlockDefaultsToInactiveWhenTheServerOmitsEveryField() throws {
        let premium = try Self.makeDecoder().decode(HouseholdPremium.self, from: Data("{}".utf8))

        XCTAssertFalse(premium.isActive)
        XCTAssertEqual(premium.status, .inactive)
        XCTAssertNil(premium.expiresAt)
    }

    func testAnUnrecognizedStatusNeverRevokesAHouseholdThatTheServerCallsActive() throws {
        let json = #"{"is_active":true,"status":"introductory_offer","expires_at":null}"#

        let premium = try Self.makeDecoder().decode(HouseholdPremium.self, from: Data(json.utf8))

        XCTAssertTrue(premium.isActive)
        XCTAssertEqual(premium.status, .inactive)
    }

    func testTheHouseholdPremiumBlockCarriesNoPurchaseIdentifiers() {
        let fields = Mirror(reflecting: HouseholdPremium.inactive).children.compactMap(\.label).sorted()

        XCTAssertEqual(fields, ["expiresAt", "isActive", "status"])
    }

    func testAPurchaseIdentifierSentAlongsideTheHouseholdBlockIsDiscarded() throws {
        let json = """
        {"is_active":true,"status":"active","expires_at":null,
         "original_transaction_id":"2000000123456789","user_id":"1B1E9E9A-0000-4000-8000-000000000001"}
        """

        let premium = try Self.makeDecoder().decode(HouseholdPremium.self, from: Data(json.utf8))
        let encoded = String(describing: premium)

        XCTAssertFalse(encoded.contains("2000000123456789"))
        XCTAssertFalse(encoded.contains("1B1E9E9A"))
    }

    @MainActor
    func testAVerifiedHomeContextGrantsHouseholdPremiumToTheMemberWhoDidNotPay() async {
        let environment = TestEnvironment(function: #function)
        defer { environment.tearDown() }

        let expiresAt = Date(timeIntervalSince1970: 1_788_231_600)
        let store = environment.makeStore(
            backend: HouseholdPremiumHomeBackend(
                familyName: "Casa Premium",
                permissionRole: .member,
                householdPremium: HouseholdPremium(
                    isActive: true,
                    status: .active,
                    expiresAt: expiresAt
                )
            )
        )

        await store.activateHomeContext(for: environment.user)

        XCTAssertEqual(store.homeAccessState, .authorized)
        XCTAssertTrue(store.householdPremium.isActive)
        XCTAssertEqual(store.householdPremium.status, .active)
        XCTAssertEqual(store.householdPremium.expiresAt, expiresAt)
    }

    @MainActor
    func testAFailedMembershipVerificationLeavesTheHouseholdWithoutPremium() async {
        let environment = TestEnvironment(function: #function)
        defer { environment.tearDown() }

        let store = environment.makeStore(backend: UnreachableHomeBackend())

        await store.activateHomeContext(for: environment.user)

        XCTAssertEqual(store.homeAccessState, .unavailable)
        XCTAssertFalse(store.householdPremium.isActive)
        XCTAssertEqual(store.householdPremium.status, .inactive)
    }

    @MainActor
    func testACachedHomeNeverRestoresHouseholdPremiumWithoutAFreshContext() async {
        let environment = TestEnvironment(function: #function)
        defer { environment.tearDown() }

        let paidStore = environment.makeStore(
            backend: HouseholdPremiumHomeBackend(
                familyName: "Casa Premium",
                permissionRole: .owner,
                householdPremium: HouseholdPremium(isActive: true, status: .active, expiresAt: nil)
            )
        )
        await paidStore.activateHomeContext(for: environment.user)
        XCTAssertTrue(paidStore.householdPremium.isActive)

        let offlineStore = environment.makeStore(backend: UnreachableHomeBackend())
        await offlineStore.activateHomeContext(for: environment.user)

        XCTAssertEqual(offlineStore.homeAccessState, .unavailable)
        XCTAssertFalse(offlineStore.householdPremium.isActive)
    }

    @MainActor
    func testSigningOutClearsHouseholdPremium() async {
        let environment = TestEnvironment(function: #function)
        defer { environment.tearDown() }

        let store = environment.makeStore(
            backend: HouseholdPremiumHomeBackend(
                familyName: "Casa Premium",
                permissionRole: .owner,
                householdPremium: HouseholdPremium(isActive: true, status: .active, expiresAt: nil)
            )
        )

        await store.activateHomeContext(for: environment.user)
        XCTAssertTrue(store.householdPremium.isActive)

        await store.activateHomeContext(for: nil)

        XCTAssertFalse(store.householdPremium.isActive)
    }

    @MainActor
    func testTheRemainingMembersLosePremiumAtTheNextRefreshWhenThePayerLeavesTheHouse() async {
        let environment = TestEnvironment(function: #function)
        defer { environment.tearDown() }

        let backend = HouseholdPremiumHomeBackend(
            familyName: "Casa Premium",
            permissionRole: .member,
            householdPremium: HouseholdPremium(isActive: true, status: .active, expiresAt: nil)
        )
        let store = environment.makeStore(backend: backend)

        await store.activateHomeContext(for: environment.user)
        XCTAssertTrue(store.householdPremium.isActive)

        await backend.setHouseholdPremium(.inactive)
        await store.refreshHomeFromRemote(for: environment.user)

        XCTAssertEqual(store.homeAccessState, .authorized)
        XCTAssertFalse(store.householdPremium.isActive)
        XCTAssertEqual(store.householdPremium.status, .inactive)
    }

    func testThePaywallOnlyMarketsBenefitsTheAppCanDeliverToday() {
        let titles = PremiumPlan.mock.benefits.map(\.title)
        let readsDocuments = NinaAttachmentGate.current.isEnabled
        let deliverable = readsDocuments
            ? ["Leitura de documentos", "Resumo semanal", "Prioridade da Nina"]
            : ["Resumo semanal", "Prioridade da Nina"]

        // Document reading is a release decision, so the sheet has to follow the
        // build rather than a fixed list a disabled flag would turn into a lie.
        XCTAssertEqual(titles, deliverable)
        XCTAssertEqual(
            PremiumPlan.mock.heroSubtitle.contains("Leitura de documentos"),
            readsDocuments
        )
        XCTAssertFalse(titles.contains("Rotinas inteligentes"))
        XCTAssertFalse(titles.contains("Divisão mais justa"))
    }

    func testNoPaywallCopyPromisesTheProposalsThatTheDisabledAIFlagDiscards() {
        let copy = ([PremiumPlan.mock.heroTitle, PremiumPlan.mock.heroSubtitle]
            + PremiumPlan.mock.benefits.map(\.title)
            + PremiumPlan.mock.benefits.map(\.detail))
            .joined(separator: " ")
            .lowercased()

        XCTAssertFalse(copy.contains("rotina"))
        XCTAssertFalse(copy.contains("divisão"))
        XCTAssertFalse(copy.contains("equilíbrio"))
    }

    func testThePaywallStatesTheSubscriptionTitleLengthAndPricePerPeriod() {
        let disclosure = PremiumPlan.mock.subscriptionDisclosure

        XCTAssertTrue(disclosure.contains("Nina Premium"))
        XCTAssertTrue(disclosure.contains("1 mês"))
        XCTAssertTrue(disclosure.contains("R$ 24,90/mês"))
        XCTAssertTrue(disclosure.contains("Renovação automática pelo App Store"))
    }

    func testThePaywallLinksToTheTermsAndPrivacyPagesNinaPublishesItself() {
        XCTAssertEqual(NinaLegalLinks.termsOfUse.absoluteString, "https://ninai.app/termos")
        XCTAssertEqual(NinaLegalLinks.privacyPolicy.absoluteString, "https://ninai.app/privacidade")
    }

    func testTheTeaserStopsSellingOnceTheHouseholdIsPremium() {
        XCTAssertNotEqual(PremiumTeaserCopy.activeTitle, PremiumTeaserCopy.title)
        XCTAssertNotEqual(PremiumTeaserCopy.activeSubtitle, PremiumTeaserCopy.subtitle)
        XCTAssertTrue(PremiumTeaserCopy.activeTitle.contains("ativo"))
        XCTAssertFalse(PremiumTeaserCopy.activeSubtitle.contains("!"))
    }

    func testAHomeCachedBeforeTheWeeklyDigestSettingExistedKeepsTheDigestOn() throws {
        let json = #"{"name":"Casa Castello","inviteCode":"casa-antiga","members":[]}"#

        let family = try Self.makeDecoder().decode(FamilyGroup.self, from: Data(json.utf8))

        XCTAssertTrue(family.weeklyDigestEnabled)
    }

    func testAHomeThatTurnedTheWeeklyDigestOffStaysOffAcrossACachedLaunch() throws {
        let family = FamilyGroup(
            name: "Casa Castello",
            inviteCode: "casa-antiga",
            members: [],
            weeklyDigestEnabled: false
        )

        let encoded = try JSONEncoder().encode(family)
        let restored = try Self.makeDecoder().decode(FamilyGroup.self, from: encoded)

        XCTAssertFalse(restored.weeklyDigestEnabled)
    }

    @MainActor
    func testAManagerTurningTheWeeklyDigestOffWritesItToTheHouseholdSetting() async {
        let environment = TestEnvironment(function: #function)
        defer { environment.tearDown() }

        let backend = HouseholdPremiumHomeBackend(
            familyName: "Casa Premium",
            permissionRole: .owner,
            householdPremium: HouseholdPremium(isActive: true, status: .active, expiresAt: nil)
        )
        let store = environment.makeStore(backend: backend)
        await store.activateHomeContext(for: environment.user)
        XCTAssertTrue(store.isWeeklyDigestEnabled)

        store.setWeeklyDigestEnabled(false)
        await store.waitForPendingRemoteMutations()

        let writes = await backend.recordedDigestWrites()
        XCTAssertEqual(writes, [false])
        XCTAssertFalse(store.isWeeklyDigestEnabled)
        XCTAssertNil(store.syncErrorMessage)
    }

    @MainActor
    func testAParticipantNeverWritesTheWeeklyDigestSettingOfTheHouse() async {
        let environment = TestEnvironment(function: #function)
        defer { environment.tearDown() }

        let backend = HouseholdPremiumHomeBackend(
            familyName: "Casa Premium",
            permissionRole: .member,
            householdPremium: HouseholdPremium(isActive: true, status: .active, expiresAt: nil)
        )
        let store = environment.makeStore(backend: backend)
        await store.activateHomeContext(for: environment.user)

        store.setWeeklyDigestEnabled(false)
        await store.waitForPendingRemoteMutations()

        let writes = await backend.recordedDigestWrites()
        XCTAssertTrue(writes.isEmpty)
        XCTAssertTrue(store.isWeeklyDigestEnabled)
    }

    @MainActor
    func testAFailedWeeklyDigestWriteRestoresTheSwitchTheHouseActuallyHas() async {
        let environment = TestEnvironment(function: #function)
        defer { environment.tearDown() }

        let backend = HouseholdPremiumHomeBackend(
            familyName: "Casa Premium",
            permissionRole: .owner,
            householdPremium: HouseholdPremium(isActive: true, status: .active, expiresAt: nil)
        )
        await backend.setDigestWriteFails(true)
        let store = environment.makeStore(backend: backend)
        await store.activateHomeContext(for: environment.user)

        store.setWeeklyDigestEnabled(false)
        XCTAssertFalse(store.isWeeklyDigestEnabled)
        await store.waitForPendingRemoteMutations()

        XCTAssertTrue(store.isWeeklyDigestEnabled)
        XCTAssertEqual(store.syncErrorMessage, "Não foi possível salvar o resumo semanal.")
    }

    func testTheServerCodeForPremiumOnlyAttachmentsGetsItsOwnEngineError() {
        XCTAssertEqual(
            NinaEngineError(code: "attachments_require_premium"),
            .attachmentsRequirePremium
        )
        XCTAssertNotEqual(NinaEngineError(code: "attachments_require_premium"), .unavailable)
    }

    func testThePremiumOnlyAttachmentMessageNamesPremiumWithoutBlamingTheUser() {
        let message = NinaEngineError.attachmentsRequirePremium.userMessage

        XCTAssertTrue(message.contains("Premium"))
        XCTAssertFalse(message.contains("!"))
    }

    @MainActor
    func testASubscriberWhoseSyncNeverReachedTheServerIsRepairedInsteadOfDowngradedToInactive() async {
        let environment = TestEnvironment(function: #function)
        defer { environment.tearDown() }

        let backend = RecordingPremiumBackend(status: .inactive)
        await backend.setSyncResult(.success(TestEnvironment.activeEntitlement))
        let store = environment.makePremiumStore(
            backend: backend,
            localTransactions: StubLocalTransactionSource([TestEnvironment.liveTransaction()])
        )

        await store.configure(for: environment.user)

        XCTAssertTrue(store.entitlement.isActive)
        XCTAssertEqual(store.entitlement.status, .active)
        XCTAssertNil(store.errorMessage)
        let calls = await backend.recordedSyncCalls()
        XCTAssertEqual(
            calls,
            [RecordingPremiumBackend.SyncCall(
                signedTransactionInfo: TestEnvironment.liveTransaction().signedTransactionInfo,
                source: "entitlement_repair"
            )]
        )
    }

    @MainActor
    func testAServerThatAlreadySawTheTransactionKeepsItsInactiveAnswerWithoutASecondPost() async {
        let environment = TestEnvironment(function: #function)
        defer { environment.tearDown() }

        let backend = RecordingPremiumBackend(status: .inactive)
        await backend.setSyncResult(.success(.inactive))
        let store = environment.makePremiumStore(
            backend: backend,
            localTransactions: StubLocalTransactionSource([TestEnvironment.liveTransaction()])
        )

        await store.configure(for: environment.user)
        await store.refreshEntitlement()

        XCTAssertFalse(store.entitlement.isActive)
        XCTAssertEqual(store.entitlement.status, .inactive)
        let calls = await backend.recordedSyncCalls()
        XCTAssertEqual(calls.count, 1)
    }

    @MainActor
    func testAnActiveServerAnswerNeverPostsTheTransactionAgainOnEveryForeground() async {
        let environment = TestEnvironment(function: #function)
        defer { environment.tearDown() }

        let backend = RecordingPremiumBackend(status: TestEnvironment.activeEntitlement)
        let store = environment.makePremiumStore(
            backend: backend,
            localTransactions: StubLocalTransactionSource([TestEnvironment.liveTransaction()])
        )

        await store.configure(for: environment.user)
        await store.refreshEntitlement()
        await store.refreshEntitlement()

        XCTAssertTrue(store.entitlement.isActive)
        let calls = await backend.recordedSyncCalls()
        let loads = await backend.recordedStatusLoads()
        XCTAssertTrue(calls.isEmpty)
        XCTAssertEqual(loads, 3)
    }

    @MainActor
    func testARepairThatFailedOnceIsRetriedOnTheNextForeground() async {
        let environment = TestEnvironment(function: #function)
        defer { environment.tearDown() }

        let backend = RecordingPremiumBackend(status: .inactive)
        await backend.setSyncResult(.failure)
        let store = environment.makePremiumStore(
            backend: backend,
            localTransactions: StubLocalTransactionSource([TestEnvironment.liveTransaction()])
        )

        await store.configure(for: environment.user)
        XCTAssertEqual(store.entitlement.status, .reconciling)

        await backend.setSyncResult(.success(TestEnvironment.activeEntitlement))
        await store.refreshEntitlement()

        XCTAssertTrue(store.entitlement.isActive)
        let calls = await backend.recordedSyncCalls()
        XCTAssertEqual(calls.count, 2)
    }

    @MainActor
    func testARenewalWithANewTransactionIdIsSentEvenAfterTheEarlierOneSynced() async {
        let environment = TestEnvironment(function: #function)
        defer { environment.tearDown() }

        let backend = RecordingPremiumBackend(status: .inactive)
        await backend.setSyncResult(.success(.inactive))
        let source = StubLocalTransactionSource([TestEnvironment.liveTransaction()])
        let store = environment.makePremiumStore(backend: backend, localTransactions: source)

        await store.configure(for: environment.user)

        let renewal = TestEnvironment.liveTransaction(
            transactionID: "2000000000000002",
            expiresAt: Date(timeIntervalSinceNow: 60 * 24 * 60 * 60),
            signedTransactionInfo: "signed-renewal-2000000000000002"
        )
        source.transactions = [renewal]
        await store.refreshEntitlement()

        let calls = await backend.recordedSyncCalls()
        XCTAssertEqual(calls.count, 2)
        XCTAssertEqual(calls.last?.signedTransactionInfo, renewal.signedTransactionInfo)
    }

    @MainActor
    func testARevokedLocalTransactionNeverTriggersARepair() async {
        let environment = TestEnvironment(function: #function)
        defer { environment.tearDown() }

        let backend = RecordingPremiumBackend(status: .inactive)
        let store = environment.makePremiumStore(
            backend: backend,
            localTransactions: StubLocalTransactionSource([
                TestEnvironment.liveTransaction(revokedAt: Date(timeIntervalSinceNow: -60))
            ])
        )

        await store.configure(for: environment.user)

        XCTAssertFalse(store.entitlement.isActive)
        XCTAssertEqual(store.entitlement.status, .inactive)
        let calls = await backend.recordedSyncCalls()
        XCTAssertTrue(calls.isEmpty)
    }

    @MainActor
    func testAnExpiredLocalTransactionNeverTriggersARepair() async {
        let environment = TestEnvironment(function: #function)
        defer { environment.tearDown() }

        let backend = RecordingPremiumBackend(status: .inactive)
        let store = environment.makePremiumStore(
            backend: backend,
            localTransactions: StubLocalTransactionSource([
                TestEnvironment.liveTransaction(expiresAt: Date(timeIntervalSinceNow: -60))
            ])
        )

        await store.configure(for: environment.user)

        XCTAssertEqual(store.entitlement.status, .inactive)
        let calls = await backend.recordedSyncCalls()
        XCTAssertTrue(calls.isEmpty)
    }

    @MainActor
    func testATransactionForAnUnconfiguredProductNeverTriggersARepair() async {
        let environment = TestEnvironment(function: #function)
        defer { environment.tearDown() }

        let backend = RecordingPremiumBackend(status: .inactive)
        let store = environment.makePremiumStore(
            backend: backend,
            localTransactions: StubLocalTransactionSource([
                TestEnvironment.liveTransaction(productID: "com.heitor.nina.premium.lifetime")
            ])
        )

        await store.configure(for: environment.user)

        XCTAssertEqual(store.entitlement.status, .inactive)
        let calls = await backend.recordedSyncCalls()
        XCTAssertTrue(calls.isEmpty)
    }

    @MainActor
    func testAnUnreachableServerLeavesASubscriberReconcilingInsteadOfInactive() async {
        let environment = TestEnvironment(function: #function)
        defer { environment.tearDown() }

        let backend = RecordingPremiumBackend(status: .inactive)
        await backend.setStatusFails(true)
        let store = environment.makePremiumStore(
            backend: backend,
            localTransactions: StubLocalTransactionSource([TestEnvironment.liveTransaction()])
        )

        await store.configure(for: environment.user)

        XCTAssertEqual(store.entitlement.status, .reconciling)
        XCTAssertNil(store.errorMessage)
        let calls = await backend.recordedSyncCalls()
        XCTAssertTrue(calls.isEmpty)
    }

    @MainActor
    func testTheReconcilingSurfaceNeitherClaimsPremiumNorReportsAFailure() async {
        let environment = TestEnvironment(function: #function)
        defer { environment.tearDown() }

        let backend = RecordingPremiumBackend(status: .inactive)
        await backend.setSyncResult(.failure)
        let store = environment.makePremiumStore(
            backend: backend,
            localTransactions: StubLocalTransactionSource([TestEnvironment.liveTransaction()])
        )

        await store.configure(for: environment.user)

        XCTAssertFalse(store.entitlement.isActive)
        XCTAssertTrue(store.entitlement.isReconciling)
        XCTAssertNil(store.errorMessage)
        XCTAssertNotEqual(store.entitlement.statusTitle, PremiumSubscriptionStatus.inactive.title)
        XCTAssertEqual(store.entitlement.statusTone, .sky)
    }

    func testTheReconcilingCopyTellsTheHouseThePurchaseIsBeingRegistered() {
        let entitlement = PremiumEntitlement(
            isActive: false,
            status: .reconciling,
            productID: "com.heitor.nina.premium.monthly",
            expiresAt: nil,
            willRenew: nil,
            environment: nil,
            originalTransactionID: nil,
            latestTransactionID: nil,
            lastVerifiedAt: nil
        )
        let copy = [
            entitlement.statusTitle,
            entitlement.renewalSummary,
            PremiumReconciliationCopy.purchaseRecorded,
        ].joined(separator: " ")

        XCTAssertTrue(entitlement.statusTitle.contains("Confirmando"))
        XCTAssertTrue(entitlement.renewalSummary.contains("servidor"))
        XCTAssertFalse(copy.lowercased().contains("inativo"))
        XCTAssertFalse(copy.lowercased().contains("erro"))
        XCTAssertFalse(copy.contains("!"))
    }

    @MainActor
    func testAForcedRestoreRepairsTheServerEvenAfterTheLedgerRecordedASync() async {
        let environment = TestEnvironment(function: #function)
        defer { environment.tearDown() }

        let backend = RecordingPremiumBackend(status: .inactive)
        await backend.setSyncResult(.success(.inactive))
        let store = environment.makePremiumStore(
            backend: backend,
            localTransactions: StubLocalTransactionSource([TestEnvironment.liveTransaction()])
        )

        await store.configure(for: environment.user)
        await store.refreshEntitlement(forcingTransactionSync: true)

        let calls = await backend.recordedSyncCalls()
        XCTAssertEqual(calls.count, 2)
        XCTAssertEqual(calls.last?.source, "restore")
    }

    @MainActor
    func testTheSyncLedgerIsWrittenToProtectedStorageAndNeverToUserDefaults() async throws {
        let environment = TestEnvironment(function: #function)
        defer { environment.tearDown() }

        let backend = RecordingPremiumBackend(status: .inactive)
        await backend.setSyncResult(.success(TestEnvironment.activeEntitlement))
        let store = environment.makePremiumStore(
            backend: backend,
            localTransactions: StubLocalTransactionSource([TestEnvironment.liveTransaction()])
        )

        await store.configure(for: environment.user)

        let key = "nina.premium.transactionSync.\(environment.user.id)"
        let stored = try environment.privateDataStore.data(
            forKey: key,
            ownerScope: PrivateLocalDataScope.premium(for: environment.user.id)
        )
        XCTAssertNotNil(stored)
        XCTAssertNil(environment.defaults.data(forKey: key))
        XCTAssertTrue(
            environment.defaults.dictionaryRepresentation().keys
                .filter { $0.hasPrefix("nina.premium") }
                .isEmpty
        )
    }

    @MainActor
    func testALedgerWrittenBeforeRelaunchStillBoundsTheRepairAfterRelaunch() async {
        let environment = TestEnvironment(function: #function)
        defer { environment.tearDown() }

        let backend = RecordingPremiumBackend(status: .inactive)
        await backend.setSyncResult(.success(.inactive))
        let firstLaunch = environment.makePremiumStore(
            backend: backend,
            localTransactions: StubLocalTransactionSource([TestEnvironment.liveTransaction()])
        )
        await firstLaunch.configure(for: environment.user)

        let secondLaunch = environment.makePremiumStore(
            backend: backend,
            localTransactions: StubLocalTransactionSource([TestEnvironment.liveTransaction()])
        )
        await secondLaunch.configure(for: environment.user)

        let calls = await backend.recordedSyncCalls()
        XCTAssertEqual(calls.count, 1)
    }

    @MainActor
    func testSigningOutLeavesNoEntitlementAndNoServerTraffic() async {
        let environment = TestEnvironment(function: #function)
        defer { environment.tearDown() }

        let backend = RecordingPremiumBackend(status: TestEnvironment.activeEntitlement)
        let store = environment.makePremiumStore(
            backend: backend,
            localTransactions: StubLocalTransactionSource([TestEnvironment.liveTransaction()])
        )

        await store.configure(for: environment.user)
        XCTAssertTrue(store.entitlement.isActive)

        await store.configure(for: nil)

        XCTAssertFalse(store.entitlement.isActive)
        XCTAssertEqual(store.entitlement.status, .inactive)
        let loads = await backend.recordedStatusLoads()
        XCTAssertEqual(loads, 1)
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private struct TestEnvironment {
    let user: AuthUser
    let defaults: UserDefaults
    let privateDataStore: ProtectedLocalDataStore

    private let suiteName: String
    private let directory: URL

    init(function: String) {
        suiteName = "\(function)-\(UUID().uuidString)"
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "nina-premium-tests-\(UUID().uuidString)",
            isDirectory: true
        )
        defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        privateDataStore = ProtectedLocalDataStore(directoryURL: directory)
        user = AuthUser(
            id: UUID().uuidString,
            displayName: "Paula",
            email: "paula@example.com",
            provider: .apple
        )
    }

    @MainActor
    func makeStore(backend: any RemoteHomeBackend) -> Nina.AppStore {
        Nina.AppStore(
            defaults: defaults,
            privateDataStore: privateDataStore,
            remoteHomeBackend: backend,
            ninaEngine: MockNinaEngine()
        )
    }

    @MainActor
    func makePremiumStore(
        backend: (any PremiumSubscriptionBackend)?,
        localTransactions: any PremiumLocalTransactionSource
    ) -> PremiumSubscriptionStore {
        PremiumSubscriptionStore(
            backend: backend,
            productIDs: Self.configuredProductIDs,
            localTransactions: localTransactions,
            catalog: EmptyPremiumProductCatalog(),
            defaults: defaults,
            privateDataStore: privateDataStore
        )
    }

    static let configuredProductIDs = [
        "com.heitor.nina.premium.monthly",
        "com.heitor.nina.premium.yearly",
    ]

    static let activeEntitlement = PremiumEntitlement(
        isActive: true,
        status: .active,
        productID: "com.heitor.nina.premium.monthly",
        expiresAt: Date(timeIntervalSince1970: 1_788_231_600),
        willRenew: true,
        environment: "Production",
        originalTransactionID: "2000000000000001",
        latestTransactionID: "2000000000000001",
        lastVerifiedAt: Date(timeIntervalSince1970: 1_785_639_600)
    )

    static func liveTransaction(
        productID: String = "com.heitor.nina.premium.monthly",
        transactionID: String = "2000000000000001",
        expiresAt: Date? = Date(timeIntervalSinceNow: 30 * 24 * 60 * 60),
        revokedAt: Date? = nil,
        signedTransactionInfo: String = "signed-transaction-2000000000000001"
    ) -> PremiumLocalTransaction {
        PremiumLocalTransaction(
            productID: productID,
            transactionID: transactionID,
            originalTransactionID: "2000000000000001",
            purchaseDate: Date(timeIntervalSinceNow: -24 * 60 * 60),
            expirationDate: expiresAt,
            revocationDate: revokedAt,
            signedTransactionInfo: signedTransactionInfo
        )
    }

    func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: directory)
    }
}

private final class StubLocalTransactionSource: PremiumLocalTransactionSource {
    var transactions: [PremiumLocalTransaction]

    init(_ transactions: [PremiumLocalTransaction]) {
        self.transactions = transactions
    }

    func currentEntitlements() async -> [PremiumLocalTransaction] {
        transactions
    }
}

private struct EmptyPremiumProductCatalog: PremiumProductCatalog {
    func products(for identifiers: [String]) async throws -> [Product] {
        []
    }
}

private actor RecordingPremiumBackend: PremiumSubscriptionBackend {
    struct SyncCall: Equatable {
        var signedTransactionInfo: String
        var source: String
    }

    enum SyncResult {
        case success(PremiumEntitlement)
        case failure
    }

    struct BackendError: Error {}

    private let status: PremiumEntitlement
    private var statusFails = false
    private var syncResult: SyncResult = .failure
    private var statusLoads = 0
    private var syncCalls: [SyncCall] = []

    init(status: PremiumEntitlement) {
        self.status = status
    }

    func setStatusFails(_ shouldFail: Bool) {
        statusFails = shouldFail
    }

    func setSyncResult(_ result: SyncResult) {
        syncResult = result
    }

    func recordedStatusLoads() -> Int {
        statusLoads
    }

    func recordedSyncCalls() -> [SyncCall] {
        syncCalls
    }

    func loadStatus() async throws -> PremiumEntitlement {
        statusLoads += 1
        if statusFails {
            throw BackendError()
        }
        return status
    }

    func syncTransaction(signedTransactionInfo: String, source: String) async throws -> PremiumEntitlement {
        syncCalls.append(SyncCall(signedTransactionInfo: signedTransactionInfo, source: source))
        switch syncResult {
        case .success(let entitlement):
            return entitlement
        case .failure:
            throw BackendError()
        }
    }
}

private actor HouseholdPremiumHomeBackend: RemoteHomeBackend {
    enum BackendError: Error {
        case unsupported
    }

    private var familyGroup: FamilyGroup
    private let permissionRole: FamilyPermissionRole
    private var householdPremium: HouseholdPremium
    private var digestWrites: [Bool] = []
    private var digestWriteFails = false

    init(
        familyName: String,
        permissionRole: FamilyPermissionRole,
        householdPremium: HouseholdPremium
    ) {
        familyGroup = FamilyGroup(name: familyName, inviteCode: "casa-premium", members: [])
        self.permissionRole = permissionRole
        self.householdPremium = householdPremium
    }

    func setHouseholdPremium(_ premium: HouseholdPremium) {
        householdPremium = premium
    }

    func setDigestWriteFails(_ shouldFail: Bool) {
        digestWriteFails = shouldFail
    }

    func recordedDigestWrites() -> [Bool] {
        digestWrites
    }

    func loadHome(for user: AuthUser) async throws -> RemoteHomeState? {
        currentState()
    }

    func createHome(named name: String, owner: AuthUser?) async throws -> RemoteHomeState {
        currentState()
    }

    func joinHome(with inviteCode: String, member: AuthUser?) async throws -> RemoteHomeState {
        currentState()
    }

    func updateFamilySettings(familyID: UUID, name: String) async throws -> RemoteHomeState {
        currentState()
    }

    func updateFamilySettings(
        familyID: UUID,
        name: String,
        weeklyDigestEnabled: Bool
    ) async throws -> RemoteHomeState {
        digestWrites.append(weeklyDigestEnabled)
        if digestWriteFails {
            throw BackendError.unsupported
        }
        familyGroup.weeklyDigestEnabled = weeklyDigestEnabled
        return currentState()
    }

    func addUnclaimedMember(_ member: HouseholdMember, familyID: UUID) async throws -> RemoteHomeState {
        currentState()
    }

    func updateFamilyMember(_ member: HouseholdMember) async throws -> RemoteHomeState {
        currentState()
    }

    func createTaskSection(_ section: TaskSection, sortOrder: Int, familyID: UUID) async throws {}
    func createTaskCategory(_ category: TaskCategory, familyID: UUID) async throws {}
    func createTask(_ task: TaskItem, familyID: UUID, currentUser: AuthUser) async throws {}
    func updateTask(_ task: TaskItem, familyID: UUID) async throws {}
    func createShoppingItem(_ item: ShoppingItem, familyID: UUID, currentUser: AuthUser) async throws {}
    func updateShoppingItem(_ item: ShoppingItem, familyID: UUID) async throws {}
    func createChatMessage(_ message: ChatMessage, familyID: UUID, currentUser: AuthUser) async throws {}

    private func currentState() -> RemoteHomeState {
        RemoteHomeState(
            familyGroup: familyGroup,
            permissionRole: permissionRole,
            snapshot: AppDataSnapshot(
                messages: [],
                taskSections: PreviewData.taskSections,
                tasks: [],
                shoppingItems: [],
                insights: []
            ),
            householdPremium: householdPremium
        )
    }
}

private struct UnreachableHomeBackend: RemoteHomeBackend {
    struct VerificationError: Error {}

    func loadHome(for user: AuthUser) async throws -> RemoteHomeState? {
        throw VerificationError()
    }

    func createHome(named name: String, owner: AuthUser?) async throws -> RemoteHomeState {
        throw VerificationError()
    }

    func joinHome(with inviteCode: String, member: AuthUser?) async throws -> RemoteHomeState {
        throw VerificationError()
    }

    func updateFamilySettings(familyID: UUID, name: String) async throws -> RemoteHomeState {
        throw VerificationError()
    }

    func addUnclaimedMember(_ member: HouseholdMember, familyID: UUID) async throws -> RemoteHomeState {
        throw VerificationError()
    }

    func updateFamilyMember(_ member: HouseholdMember) async throws -> RemoteHomeState {
        throw VerificationError()
    }

    func createTaskSection(_ section: TaskSection, sortOrder: Int, familyID: UUID) async throws {}
    func createTaskCategory(_ category: TaskCategory, familyID: UUID) async throws {}
    func createTask(_ task: TaskItem, familyID: UUID, currentUser: AuthUser) async throws {}
    func updateTask(_ task: TaskItem, familyID: UUID) async throws {}
    func createShoppingItem(_ item: ShoppingItem, familyID: UUID, currentUser: AuthUser) async throws {}
    func updateShoppingItem(_ item: ShoppingItem, familyID: UUID) async throws {}
    func createChatMessage(_ message: ChatMessage, familyID: UUID, currentUser: AuthUser) async throws {}
}
