import Foundation
import Observation
import StoreKit

enum PremiumSubscriptionStatus: String, Codable, Hashable {
    case unknown
    case inactive
    case active
    case gracePeriod = "grace_period"
    case billingRetry = "billing_retry"
    case expired
    case revoked
    case reconciling

    var title: String {
        switch self {
        case .unknown:
            "Verificando"
        case .inactive:
            "Premium inativo"
        case .active:
            "Premium ativo"
        case .gracePeriod:
            "Premium em período de graça"
        case .billingRetry:
            "Pagamento em nova tentativa"
        case .expired:
            "Premium expirado"
        case .revoked:
            "Premium revogado"
        case .reconciling:
            "Confirmando sua assinatura"
        }
    }
}

struct PremiumEntitlement: Codable, Hashable {
    var isActive: Bool
    var status: PremiumSubscriptionStatus
    var productID: String?
    var expiresAt: Date?
    var willRenew: Bool?
    var environment: String?
    var originalTransactionID: String?
    var latestTransactionID: String?
    var lastVerifiedAt: Date?

    static let inactive = PremiumEntitlement(
        isActive: false,
        status: .inactive,
        productID: nil,
        expiresAt: nil,
        willRenew: nil,
        environment: nil,
        originalTransactionID: nil,
        latestTransactionID: nil,
        lastVerifiedAt: nil
    )

    private enum CodingKeys: String, CodingKey {
        case isActive = "is_active"
        case status
        case productID = "product_id"
        case expiresAt = "expires_at"
        case willRenew = "will_renew"
        case environment
        case originalTransactionID = "original_transaction_id"
        case latestTransactionID = "latest_transaction_id"
        case lastVerifiedAt = "last_verified_at"
    }

    var statusTitle: String {
        status.title
    }

    var isReconciling: Bool {
        status == .reconciling
    }

    var statusSymbolName: String {
        if isReconciling { return "arrow.triangle.2.circlepath" }
        return isActive ? "checkmark.seal.fill" : "creditcard.fill"
    }

    var statusTone: MemberTone {
        if isReconciling { return .sky }
        return isActive ? .mint : .amber
    }

    var renewalSummary: String {
        if isReconciling {
            return "A compra está confirmada no aparelho. A Nina está registrando no servidor."
        }

        guard isActive else { return "Assine para liberar os recursos Premium." }

        if let expiresAt {
            let date = expiresAt.formatted(date: .abbreviated, time: .omitted)
            if willRenew == true {
                return "Renova em \(date)."
            }
            return "Acesso até \(date)."
        }

        return "Acesso Premium liberado."
    }
}

struct PremiumLocalTransaction: Hashable {
    var productID: String
    var transactionID: String
    var originalTransactionID: String
    var purchaseDate: Date
    var expirationDate: Date?
    var revocationDate: Date?
    var signedTransactionInfo: String

    func isUsable(at date: Date) -> Bool {
        guard revocationDate == nil else { return false }
        guard let expirationDate else { return true }
        return expirationDate > date
    }
}

protocol PremiumLocalTransactionSource {
    func currentEntitlements() async -> [PremiumLocalTransaction]
}

struct StoreKitPremiumLocalTransactionSource: PremiumLocalTransactionSource {
    func currentEntitlements() async -> [PremiumLocalTransaction] {
        var transactions: [PremiumLocalTransaction] = []

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            transactions.append(
                PremiumLocalTransaction(
                    transaction: transaction,
                    signedTransactionInfo: result.jwsRepresentation
                )
            )
        }

        return transactions
    }
}

extension PremiumLocalTransaction {
    init(transaction: Transaction, signedTransactionInfo: String) {
        self.init(
            productID: transaction.productID,
            transactionID: String(transaction.id),
            originalTransactionID: String(transaction.originalID),
            purchaseDate: transaction.purchaseDate,
            expirationDate: transaction.expirationDate,
            revocationDate: transaction.revocationDate,
            signedTransactionInfo: signedTransactionInfo
        )
    }
}

struct PremiumTransactionSyncLedger: Codable, Hashable {
    var syncedTransactionID: String?
    var lastSyncFailed: Bool

    static let empty = PremiumTransactionSyncLedger(syncedTransactionID: nil, lastSyncFailed: false)

    init(syncedTransactionID: String?, lastSyncFailed: Bool) {
        self.syncedTransactionID = syncedTransactionID
        self.lastSyncFailed = lastSyncFailed
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        syncedTransactionID = try container.decodeIfPresent(String.self, forKey: .syncedTransactionID)
        lastSyncFailed = try container.decodeIfPresent(Bool.self, forKey: .lastSyncFailed) ?? false
    }

    func needsSync(for transactionID: String) -> Bool {
        lastSyncFailed || syncedTransactionID != transactionID
    }
}

protocol PremiumSubscriptionBackend {
    func loadStatus() async throws -> PremiumEntitlement
    func syncTransaction(signedTransactionInfo: String, source: String) async throws -> PremiumEntitlement
}

protocol PremiumProductCatalog {
    func products(for identifiers: [String]) async throws -> [Product]
}

struct StoreKitPremiumProductCatalog: PremiumProductCatalog {
    func products(for identifiers: [String]) async throws -> [Product] {
        try await Product.products(for: identifiers)
    }
}

enum PremiumConfiguration {
    static let defaultProductIDs = [
        "com.heitor.nina.premium.monthly",
        "com.heitor.nina.premium.yearly",
    ]

    static var productIDs: [String] {
        let value = Bundle.main.object(forInfoDictionaryKey: "NINA_PREMIUM_PRODUCT_IDS")

        let rawIDs: [String]
        if let strings = value as? [String] {
            rawIDs = strings
        } else if let string = value as? String {
            rawIDs = string.components(separatedBy: CharacterSet(charactersIn: ",; \n\t"))
        } else {
            rawIDs = []
        }

        let normalized = rawIDs
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.contains("$(") }

        return normalized.isEmpty ? defaultProductIDs : Array(NSOrderedSet(array: normalized)) as? [String] ?? defaultProductIDs
    }

    static func sortRank(for productID: String) -> Int {
        productIDs.firstIndex(of: productID) ?? Int.max
    }
}

enum PremiumPurchaseError: LocalizedError {
    case notSignedIn
    case onlineAccountRequired
    case unverifiedTransaction

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            "Entre na sua conta para assinar o Premium."
        case .onlineAccountRequired:
            "Use uma conta online da Nina para assinar. Contas de debug local não podem ser associadas ao App Store."
        case .unverifiedTransaction:
            "A compra não pôde ser verificada pelo App Store."
        }
    }
}

enum PremiumReconciliationCopy {
    static let purchaseRecorded =
        "A compra está confirmada no aparelho. A Nina termina o registro no servidor."
}

@MainActor
@Observable
final class PremiumSubscriptionStore {
    var products: [Product] = []
    var entitlement: PremiumEntitlement = .inactive
    var isLoadingProducts = false
    var isPurchasing = false
    var isRestoring = false
    var isSyncingBackend = false
    var productLoadMessage: String?
    var statusMessage: String?
    /// Whether `statusMessage` reports something that actually completed. Moss is
    /// reserved for confirmed states, and "nothing was found" is not one.
    var statusIsConfirmation = false
    var errorMessage: String?

    @ObservationIgnored private let backend: (any PremiumSubscriptionBackend)?
    @ObservationIgnored private let productIDs: [String]
    @ObservationIgnored private let localTransactions: any PremiumLocalTransactionSource
    @ObservationIgnored private let catalog: any PremiumProductCatalog
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let privateDataStore: any PrivateLocalDataStoring
    @ObservationIgnored private var currentUser: AuthUser?
    @ObservationIgnored private var transactionUpdatesTask: Task<Void, Never>?

    init(
        backend: (any PremiumSubscriptionBackend)? = BackendServices.makePremiumSubscriptionBackend(),
        productIDs: [String] = PremiumConfiguration.productIDs,
        localTransactions: any PremiumLocalTransactionSource = StoreKitPremiumLocalTransactionSource(),
        catalog: any PremiumProductCatalog = StoreKitPremiumProductCatalog(),
        defaults: UserDefaults = .standard,
        privateDataStore: any PrivateLocalDataStoring = ProtectedLocalDataStore.shared
    ) {
        self.backend = backend
        self.productIDs = productIDs
        self.localTransactions = localTransactions
        self.catalog = catalog
        self.defaults = defaults
        self.privateDataStore = privateDataStore
        startTransactionListener()
    }

    deinit {
        transactionUpdatesTask?.cancel()
    }

    var hasProducts: Bool {
        !products.isEmpty
    }

    var primaryPriceLabel: String? {
        products.first?.displayPrice
    }

    var configuredProductIDsLabel: String {
        productIDs.joined(separator: ", ")
    }

    func configure(for user: AuthUser?) async {
        currentUser = user
        await loadProducts()
        await refreshEntitlement()
    }

    func loadProducts() async {
        guard !isLoadingProducts else { return }
        isLoadingProducts = true
        defer { isLoadingProducts = false }

        do {
            let fetchedProducts = try await catalog.products(for: productIDs)
            products = fetchedProducts.sorted {
                let lhsRank = PremiumConfiguration.sortRank(for: $0.id)
                let rhsRank = PremiumConfiguration.sortRank(for: $1.id)
                if lhsRank == rhsRank { return $0.displayName < $1.displayName }
                return lhsRank < rhsRank
            }
            productLoadMessage = products.isEmpty
                ? "Nenhum plano Premium foi encontrado para estes IDs: \(configuredProductIDsLabel)."
                : nil
        } catch {
            productLoadMessage = "Não foi possível carregar os planos Premium agora."
        }
    }

    func refreshEntitlement(forcingTransactionSync: Bool = false) async {
        errorMessage = nil
        await reconcileEntitlement(forcingTransactionSync: forcingTransactionSync)
    }

    func purchase(_ product: Product) async {
        guard !isPurchasing else { return }
        guard let currentUser else {
            errorMessage = PremiumPurchaseError.notSignedIn.localizedDescription
            return
        }
        guard let accountToken = UUID(uuidString: currentUser.id) else {
            errorMessage = PremiumPurchaseError.onlineAccountRequired.localizedDescription
            return
        }

        isPurchasing = true
        errorMessage = nil
        statusMessage = nil
        statusIsConfirmation = false
        defer { isPurchasing = false }

        do {
            let result = try await product.purchase(options: [.appAccountToken(accountToken)])
            switch result {
            case .success(let verification):
                let verifiedTransaction = try verifiedTransaction(from: verification)
                let transaction = verifiedTransaction.transaction
                let local = PremiumLocalTransaction(
                    transaction: transaction,
                    signedTransactionInfo: verifiedTransaction.signedTransactionInfo
                )
                applyLocal(local)

                guard backend != nil else {
                    statusMessage = "Premium ativado."
                    statusIsConfirmation = true
                    return
                }

                isSyncingBackend = true
                let didRecord = await recordOnServer(local, for: currentUser.id, source: "purchase")
                isSyncingBackend = false

                if didRecord {
                    await transaction.finish()
                    statusMessage = "Premium ativado."
                    statusIsConfirmation = true
                } else {
                    statusMessage = PremiumReconciliationCopy.purchaseRecorded
                    statusIsConfirmation = true
                }
            case .pending:
                statusMessage = "A compra está pendente de aprovação."
                statusIsConfirmation = false
            case .userCancelled:
                break
            @unknown default:
                statusMessage = "A compra não foi concluída."
                statusIsConfirmation = false
            }
        } catch {
            errorMessage = userMessage(for: error)
        }
    }

    func restorePurchases() async {
        guard !isRestoring else { return }
        isRestoring = true
        errorMessage = nil
        statusMessage = nil
        statusIsConfirmation = false
        defer { isRestoring = false }

        do {
            try await StoreKit.AppStore.sync()
            await refreshEntitlement(forcingTransactionSync: true)
            if entitlement.isActive {
                statusMessage = "Premium restaurado."
                statusIsConfirmation = true
            } else if entitlement.isReconciling {
                statusMessage = PremiumReconciliationCopy.purchaseRecorded
                statusIsConfirmation = true
            } else {
                statusMessage = "Nenhuma assinatura Premium ativa foi encontrada."
                statusIsConfirmation = false
            }
        } catch {
            errorMessage = userMessage(for: error)
        }
    }

    private func startTransactionListener() {
        transactionUpdatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                await self?.handle(transactionUpdate: update)
            }
        }
    }

    // An unfinished transaction is App Store redelivery: never spend it without a server record.
    private func handle(transactionUpdate update: VerificationResult<Transaction>) async {
        do {
            let verifiedTransaction = try verifiedTransaction(from: update)
            let transaction = verifiedTransaction.transaction
            guard productIDs.contains(transaction.productID) else { return }

            let local = PremiumLocalTransaction(
                transaction: transaction,
                signedTransactionInfo: verifiedTransaction.signedTransactionInfo
            )
            applyLocal(local)

            guard backend != nil, let currentUser else { return }

            isSyncingBackend = true
            let didRecord = await recordOnServer(
                local,
                for: currentUser.id,
                source: "transaction_update"
            )
            isSyncingBackend = false

            if didRecord {
                await transaction.finish()
            }
        } catch {
            errorMessage = userMessage(for: error)
        }
    }

    // A device-verified transaction proves purchase: repair the server row, never downgrade.
    private func reconcileEntitlement(forcingTransactionSync: Bool) async {
        let local = await latestUsableLocalTransaction()
        if let local {
            applyLocal(local)
        }

        guard let currentUser else {
            entitlement = .inactive
            return
        }

        guard let backend else {
            if local == nil {
                entitlement = .inactive
            }
            return
        }

        isSyncingBackend = true
        defer { isSyncingBackend = false }

        if let local, forcingTransactionSync {
            await recordOnServer(local, for: currentUser.id, source: "restore")
            return
        }

        do {
            let remote = try await backend.loadStatus()
            guard !remote.isActive,
                  let local,
                  syncLedger(for: currentUser.id).needsSync(for: local.transactionID) else {
                entitlement = remote
                return
            }

            await recordOnServer(local, for: currentUser.id, source: "entitlement_repair")
        } catch {
            guard let local else {
                errorMessage = "Não foi possível atualizar o status Premium no servidor."
                return
            }
            entitlement = reconciling(for: local)
        }
    }

    @discardableResult
    private func recordOnServer(
        _ local: PremiumLocalTransaction,
        for userID: String,
        source: String
    ) async -> Bool {
        guard let backend else { return false }

        do {
            entitlement = try await backend.syncTransaction(
                signedTransactionInfo: local.signedTransactionInfo,
                source: source
            )
            writeSyncLedger(
                PremiumTransactionSyncLedger(
                    syncedTransactionID: local.transactionID,
                    lastSyncFailed: false
                ),
                for: userID
            )
            return true
        } catch {
            var ledger = syncLedger(for: userID)
            ledger.lastSyncFailed = true
            writeSyncLedger(ledger, for: userID)
            entitlement = reconciling(for: local)
            return false
        }
    }

    private func latestUsableLocalTransaction() async -> PremiumLocalTransaction? {
        let now = Date()
        var latest: PremiumLocalTransaction?

        for transaction in await localTransactions.currentEntitlements() {
            guard productIDs.contains(transaction.productID), transaction.isUsable(at: now) else {
                continue
            }

            if isNewer(transaction, than: latest) {
                latest = transaction
            }
        }

        return latest
    }

    private func syncLedger(for userID: String) -> PremiumTransactionSyncLedger {
        guard let data = PrivateLocalDataAccess.loadData(
            forKey: Self.syncLedgerKey(for: userID),
            ownerScope: PrivateLocalDataScope.premium(for: userID),
            store: privateDataStore,
            legacyDefaults: defaults
        ) else { return .empty }

        return (try? JSONDecoder().decode(PremiumTransactionSyncLedger.self, from: data)) ?? .empty
    }

    private func writeSyncLedger(_ ledger: PremiumTransactionSyncLedger, for userID: String) {
        guard let data = try? JSONEncoder().encode(ledger) else { return }
        PrivateLocalDataAccess.writeDataBestEffort(
            data,
            forKey: Self.syncLedgerKey(for: userID),
            ownerScope: PrivateLocalDataScope.premium(for: userID),
            store: privateDataStore,
            legacyDefaults: defaults
        )
    }

    private static func syncLedgerKey(for userID: String) -> String {
        "nina.premium.transactionSync.\(userID)"
    }

    private func reconciling(for local: PremiumLocalTransaction) -> PremiumEntitlement {
        PremiumEntitlement(
            isActive: false,
            status: .reconciling,
            productID: local.productID,
            expiresAt: local.expirationDate,
            willRenew: nil,
            environment: nil,
            originalTransactionID: local.originalTransactionID,
            latestTransactionID: local.transactionID,
            lastVerifiedAt: Date()
        )
    }

    private func applyLocal(_ local: PremiumLocalTransaction) {
        let now = Date()
        let isCurrentlyActive = local.isUsable(at: now)

        entitlement = PremiumEntitlement(
            isActive: isCurrentlyActive,
            status: isCurrentlyActive ? .active : .expired,
            productID: local.productID,
            expiresAt: local.expirationDate,
            willRenew: nil,
            environment: nil,
            originalTransactionID: local.originalTransactionID,
            latestTransactionID: local.transactionID,
            lastVerifiedAt: now
        )
    }

    private func verified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let value):
            return value
        case .unverified:
            throw PremiumPurchaseError.unverifiedTransaction
        }
    }

    private func verifiedTransaction(
        from result: VerificationResult<Transaction>
    ) throws -> (transaction: Transaction, signedTransactionInfo: String) {
        let signedTransactionInfo = result.jwsRepresentation
        return (try verified(result), signedTransactionInfo)
    }

    private func isNewer(
        _ transaction: PremiumLocalTransaction,
        than other: PremiumLocalTransaction?
    ) -> Bool {
        guard let other else { return true }
        return (transaction.expirationDate ?? transaction.purchaseDate) > (other.expirationDate ?? other.purchaseDate)
    }

    private func userMessage(for error: Error) -> String {
        if let premiumError = error as? PremiumPurchaseError {
            return premiumError.localizedDescription
        }

        if let storeKitError = error as? StoreKitError {
            switch storeKitError {
            case .userCancelled:
                return ""
            case .networkError:
                return "Sem conexão com o App Store. Tente novamente."
            case .notAvailableInStorefront:
                return "Este plano ainda não está disponível na sua loja."
            case .notEntitled:
                return "Esta assinatura não está disponível para esta conta."
            case .systemError:
                return "O App Store não concluiu a operação agora."
            case .unknown, .unsupported:
                return "Não foi possível concluir a operação no App Store."
            @unknown default:
                return "Não foi possível concluir a operação no App Store."
            }
        }

        return "Não foi possível concluir a operação agora."
    }
}

private struct PremiumSyncResponse: Decodable {
    var entitlement: PremiumEntitlement
}

private enum PremiumBackendRequestError: Error {
    case missingSession
    case invalidResponse
    case server(String)
}

private enum PremiumDateCoding {
    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            if let date = Self.fractionalFormatter.date(from: value) ?? Self.standardFormatter.date(from: value) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid ISO-8601 date: \(value)"
            )
        }
        return decoder
    }

    private static let fractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let standardFormatter = ISO8601DateFormatter()
}

#if canImport(Supabase)
import Supabase

struct SupabasePremiumSubscriptionBackend: PremiumSubscriptionBackend {
    var client: SupabaseClient
    var configuration: SupabaseConfiguration
    var diagnostics: BackendDiagnosticsStore? = nil

    func loadStatus() async throws -> PremiumEntitlement {
        try await BackendRequestLogger.perform(
            component: "premium",
            operation: "load_status",
            diagnostics: diagnostics
        ) {
            let response = try await client
                .rpc("get_current_premium_status")
                .execute()
            return try PremiumDateCoding.makeDecoder()
                .decode(PremiumEntitlement.self, from: response.data)
        }
    }

    func syncTransaction(signedTransactionInfo: String, source: String) async throws -> PremiumEntitlement {
        try await BackendRequestLogger.perform(
            component: "premium",
            operation: "sync_transaction",
            diagnostics: diagnostics
        ) {
            let session = try await authenticatedSession()
            let endpoint = configuration.url
                .appendingPathComponent("functions")
                .appendingPathComponent("v1")
                .appendingPathComponent("premium-subscription-sync")

            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.addValue("application/json", forHTTPHeaderField: "Accept")
            request.addValue(configuration.publishableKey, forHTTPHeaderField: "apikey")
            request.addValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
            request.httpBody = try JSONEncoder().encode(
                PremiumSyncRequest(
                    signedTransactionInfo: signedTransactionInfo,
                    source: source
                )
            )

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw PremiumBackendRequestError.invalidResponse
            }

            guard (200..<300).contains(httpResponse.statusCode) else {
                let serverError = (try? JSONDecoder().decode(PremiumServerError.self, from: data).error)
                    ?? "premium_sync_failed"
                throw PremiumBackendRequestError.server(serverError)
            }

            return try PremiumDateCoding.makeDecoder()
                .decode(PremiumSyncResponse.self, from: data)
                .entitlement
        }
    }

    private func authenticatedSession() async throws -> Session {
        if let session = client.auth.currentSession, !session.isExpired {
            return session
        }

        return try await client.auth.session
    }
}

private struct PremiumSyncRequest: Encodable {
    var signedTransactionInfo: String
    var source: String

    private enum CodingKeys: String, CodingKey {
        case signedTransactionInfo = "signed_transaction_info"
        case source
    }
}

private struct PremiumServerError: Decodable {
    var error: String
}
#endif

extension BackendServices {
    static func makePremiumSubscriptionBackend(
        diagnostics: BackendDiagnosticsStore? = nil
    ) -> (any PremiumSubscriptionBackend)? {
        #if canImport(Supabase)
        if let client = SupabaseClientFactory.shared,
           let configuration = SupabaseConfiguration.fromBundle() {
            return SupabasePremiumSubscriptionBackend(
                client: client,
                configuration: configuration,
                diagnostics: diagnostics
            )
        }
        #endif

        return nil
    }
}
