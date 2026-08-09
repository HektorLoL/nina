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

        XCTAssertEqual(titles, ["Leitura de documentos", "Resumo semanal", "Prioridade da Nina"])
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

    func testTheFeaturedTeaserStopsSellingOnceTheHouseholdIsPremium() {
        XCTAssertNotEqual(PremiumTeaserStyle.featured.activeTitle, PremiumTeaserStyle.featured.title)
        XCTAssertNotEqual(
            PremiumTeaserStyle.featured.activeSubtitle,
            PremiumTeaserStyle.featured.subtitle
        )
        XCTAssertTrue(PremiumTeaserStyle.featured.activeTitle.contains("ativo"))
        XCTAssertFalse(PremiumTeaserStyle.featured.activeSubtitle.contains("!"))
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
    func makeStore(backend: any RemoteHomeBackend) -> AppStore {
        AppStore(
            defaults: defaults,
            privateDataStore: privateDataStore,
            remoteHomeBackend: backend,
            ninaEngine: MockNinaEngine()
        )
    }

    func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: directory)
    }
}

private actor HouseholdPremiumHomeBackend: RemoteHomeBackend {
    enum BackendError: Error {
        case unsupported
    }

    private let familyGroup: FamilyGroup
    private let permissionRole: FamilyPermissionRole
    private var householdPremium: HouseholdPremium

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
