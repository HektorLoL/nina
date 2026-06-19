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

    var renewalSummary: String {
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

protocol PremiumSubscriptionBackend {
    func loadStatus() async throws -> PremiumEntitlement
    func syncTransaction(signedTransactionInfo: String, source: String) async throws -> PremiumEntitlement
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
    case backendSyncRequired

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            "Entre na sua conta para assinar o Premium."
        case .onlineAccountRequired:
            "Use uma conta online da Nina para assinar. Contas de debug local não podem ser associadas ao App Store."
        case .unverifiedTransaction:
            "A compra não pôde ser verificada pelo App Store."
        case .backendSyncRequired:
            "A compra foi validada, mas ainda não conseguimos registrar no servidor. Tente restaurar em instantes."
        }
    }
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
    var errorMessage: String?

    @ObservationIgnored private let backend: (any PremiumSubscriptionBackend)?
    @ObservationIgnored private let productIDs: [String]
    @ObservationIgnored private var currentUser: AuthUser?
    @ObservationIgnored private var transactionUpdatesTask: Task<Void, Never>?

    init(
        backend: (any PremiumSubscriptionBackend)? = BackendServices.makePremiumSubscriptionBackend(),
        productIDs: [String] = PremiumConfiguration.productIDs
    ) {
        self.backend = backend
        self.productIDs = productIDs
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
            let fetchedProducts = try await Product.products(for: productIDs)
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

    func refreshEntitlement() async {
        errorMessage = nil
        await refreshLocalStoreKitEntitlements(syncWithBackend: true)
        await refreshBackendStatus()
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
        defer { isPurchasing = false }

        do {
            let result = try await product.purchase(options: [.appAccountToken(accountToken)])
            switch result {
            case .success(let verification):
                let verifiedTransaction = try verifiedTransaction(from: verification)
                let transaction = verifiedTransaction.transaction
                applyLocal(transaction: transaction)
                let didSync = await sync(
                    transaction: transaction,
                    signedTransactionInfo: verifiedTransaction.signedTransactionInfo,
                    source: "purchase"
                )
                if didSync || backend == nil {
                    await transaction.finish()
                    statusMessage = "Premium ativado."
                } else {
                    errorMessage = PremiumPurchaseError.backendSyncRequired.localizedDescription
                }
            case .pending:
                statusMessage = "A compra está pendente de aprovação."
            case .userCancelled:
                break
            @unknown default:
                statusMessage = "A compra não foi concluída."
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
        defer { isRestoring = false }

        do {
            try await StoreKit.AppStore.sync()
            await refreshEntitlement()
            statusMessage = entitlement.isActive
                ? "Premium restaurado."
                : "Nenhuma assinatura Premium ativa foi encontrada."
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

    private func handle(transactionUpdate update: VerificationResult<Transaction>) async {
        do {
            let verifiedTransaction = try verifiedTransaction(from: update)
            let transaction = verifiedTransaction.transaction
            guard productIDs.contains(transaction.productID) else {
                await transaction.finish()
                return
            }

            applyLocal(transaction: transaction)
            let didSync = await sync(
                transaction: transaction,
                signedTransactionInfo: verifiedTransaction.signedTransactionInfo,
                source: "transaction_update"
            )
            if didSync || backend == nil {
                await transaction.finish()
            }
        } catch {
            errorMessage = userMessage(for: error)
        }
    }

    private func refreshLocalStoreKitEntitlements(syncWithBackend: Bool) async {
        var latestVerifiedTransaction: (transaction: Transaction, signedTransactionInfo: String)?

        for await result in Transaction.currentEntitlements {
            guard let verifiedTransaction = try? verifiedTransaction(from: result),
                  productIDs.contains(verifiedTransaction.transaction.productID),
                  verifiedTransaction.transaction.revocationDate == nil else {
                continue
            }

            if isNewer(verifiedTransaction.transaction, than: latestVerifiedTransaction?.transaction) {
                latestVerifiedTransaction = verifiedTransaction
            }
        }

        guard let latestVerifiedTransaction else {
            if !entitlement.isActive {
                entitlement = .inactive
            }
            return
        }

        applyLocal(transaction: latestVerifiedTransaction.transaction)
        if syncWithBackend {
            _ = await sync(
                transaction: latestVerifiedTransaction.transaction,
                signedTransactionInfo: latestVerifiedTransaction.signedTransactionInfo,
                source: "current_entitlement"
            )
        }
    }

    private func refreshBackendStatus() async {
        guard let backend, currentUser != nil else { return }
        isSyncingBackend = true
        defer { isSyncingBackend = false }

        do {
            entitlement = try await backend.loadStatus()
        } catch {
            errorMessage = "Não foi possível atualizar o status Premium no servidor."
        }
    }

    private func sync(
        transaction: Transaction,
        signedTransactionInfo: String,
        source: String
    ) async -> Bool {
        guard let backend, currentUser != nil else { return backend == nil }
        isSyncingBackend = true
        defer { isSyncingBackend = false }

        do {
            entitlement = try await backend.syncTransaction(
                signedTransactionInfo: signedTransactionInfo,
                source: source
            )
            return true
        } catch {
            errorMessage = "Premium foi validado no aparelho, mas o servidor ainda não confirmou."
            return false
        }
    }

    private func applyLocal(transaction: Transaction) {
        let now = Date()
        let expirationDate = transaction.expirationDate
        let isCurrentlyActive = transaction.revocationDate == nil
            && (expirationDate == nil || expirationDate ?? .distantPast > now)

        entitlement = PremiumEntitlement(
            isActive: isCurrentlyActive,
            status: isCurrentlyActive ? .active : .expired,
            productID: transaction.productID,
            expiresAt: expirationDate,
            willRenew: nil,
            environment: nil,
            originalTransactionID: String(transaction.originalID),
            latestTransactionID: String(transaction.id),
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

    private func isNewer(_ transaction: Transaction, than other: Transaction?) -> Bool {
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
