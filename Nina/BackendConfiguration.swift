import Foundation
import Observation
import OSLog
#if canImport(Supabase)
import Supabase
#endif

enum BackendEnvironment: Equatable {
    case supabase(host: String)
    case localSupabase(host: String)
    case mock
    case unavailable

    var title: String {
        switch self {
        case .supabase:
            "Supabase"
        case .localSupabase:
            "Supabase local"
        case .mock:
            "Mock local"
        case .unavailable:
            "Indisponível"
        }
    }

    var detail: String {
        switch self {
        case .supabase(let host), .localSupabase(let host):
            host
        case .mock:
            "Sem chamadas de rede"
        case .unavailable:
            "Configuração ausente"
        }
    }
}

@MainActor
@Observable
final class BackendDiagnosticsStore {
    let environment: BackendEnvironment
    var activeRequestCount = 0
    var lastOperation: String?
    var lastSyncAt: Date?
    var lastError: String?
    var lastErrorAt: Date?

    init(environment: BackendEnvironment) {
        self.environment = environment
    }

    func requestStarted(operation: String) {
        activeRequestCount += 1
        lastOperation = operation
    }

    func requestSucceeded(operation: String, at date: Date) {
        activeRequestCount = max(activeRequestCount - 1, 0)
        lastOperation = operation
        lastSyncAt = date
    }

    func requestFailed(operation: String, error: Error, at date: Date) {
        activeRequestCount = max(activeRequestCount - 1, 0)
        lastOperation = operation
        lastError = "\(operation): \(String(describing: error))"
        lastErrorAt = date
    }
}

enum BackendRequestLogger {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.heitor.nina",
        category: "Backend"
    )

    static func perform<Value>(
        component: String,
        operation: String,
        diagnostics: BackendDiagnosticsStore?,
        request: () async throws -> Value
    ) async throws -> Value {
        let requestID = UUID().uuidString
        let startedAt = Date()
        let operationName = "\(component).\(operation)"

        logger.info(
            "backend_request event=start component=\(component, privacy: .public) operation=\(operation, privacy: .public) request_id=\(requestID, privacy: .public)"
        )
        await diagnostics?.requestStarted(operation: operationName)

        do {
            let value = try await request()
            let finishedAt = Date()
            let durationMS = Int(finishedAt.timeIntervalSince(startedAt) * 1_000)
            logger.info(
                "backend_request event=success component=\(component, privacy: .public) operation=\(operation, privacy: .public) request_id=\(requestID, privacy: .public) duration_ms=\(durationMS, privacy: .public)"
            )
            await diagnostics?.requestSucceeded(operation: operationName, at: finishedAt)
            return value
        } catch {
            let finishedAt = Date()
            let durationMS = Int(finishedAt.timeIntervalSince(startedAt) * 1_000)
            logger.error(
                "backend_request event=failure component=\(component, privacy: .public) operation=\(operation, privacy: .public) request_id=\(requestID, privacy: .public) duration_ms=\(durationMS, privacy: .public) error=\(String(describing: error), privacy: .private)"
            )
            await diagnostics?.requestFailed(operation: operationName, error: error, at: finishedAt)
            throw error
        }
    }
}

struct SupabaseConfiguration: Equatable {
    var url: URL
    var publishableKey: String

    static func fromBundle(_ bundle: Bundle = .main) -> SupabaseConfiguration? {
        guard let rawURL = bundle.nonEmptyString(forInfoKey: "NINASupabaseURL")
                ?? bundle.nonEmptyString(forInfoKey: "NINA_SUPABASE_URL"),
              let url = URL(string: rawURL),
              let key = bundle.nonEmptyString(forInfoKey: "NINASupabasePublishableKey")
                ?? bundle.nonEmptyString(forInfoKey: "NINA_SUPABASE_PUBLISHABLE_KEY") else {
            return nil
        }

        return SupabaseConfiguration(url: url, publishableKey: key)
    }
}

enum NinaAIConfiguration {
    static var isV2Enabled: Bool {
        let rawValue = Bundle.main.object(
            forInfoDictionaryKey: "NINA_AI_V2_ENABLED"
        )

        if let value = rawValue as? Bool {
            return value
        }

        guard let value = rawValue as? String else { return false }
        return ["1", "true", "yes"].contains(value.lowercased())
    }
}

enum BackendServices {
    static var environment: BackendEnvironment {
        #if canImport(Supabase)
        if let configuration = SupabaseConfiguration.fromBundle() {
            let host = configuration.url.host ?? configuration.url.absoluteString
            if host == "localhost" || host == "127.0.0.1" {
                return .localSupabase(host: host)
            }
            return .supabase(host: host)
        }
        #endif

        #if DEBUG
        return .mock
        #else
        return .unavailable
        #endif
    }

    static func makeAuthClient(diagnostics: BackendDiagnosticsStore? = nil) -> any AuthClient {
        #if canImport(Supabase)
        if let client = SupabaseClientFactory.shared {
            return SupabaseAuthClient(client: client, diagnostics: diagnostics)
        }
        #endif

        #if DEBUG
        return MockAuthClient()
        #else
        return UnavailableAuthClient()
        #endif
    }

    static func makeRemoteHomeBackend(diagnostics: BackendDiagnosticsStore? = nil) -> (any RemoteHomeBackend)? {
        #if canImport(Supabase)
        if let client = SupabaseClientFactory.shared {
            return SupabaseRemoteHomeBackend(client: client, diagnostics: diagnostics)
        }
        #endif

        return nil
    }

    static func makeRemoteProfileBackend(diagnostics: BackendDiagnosticsStore? = nil) -> (any RemoteProfileBackend)? {
        #if canImport(Supabase)
        if let client = SupabaseClientFactory.shared {
            return SupabaseRemoteProfileBackend(client: client, diagnostics: diagnostics)
        }
        #endif

        return nil
    }

    static func makeNinaEngine(diagnostics: BackendDiagnosticsStore? = nil) -> any NinaEngine {
        #if canImport(Supabase)
        if let client = SupabaseClientFactory.shared {
            return SupabaseNinaEngine(client: client, diagnostics: diagnostics)
        }
        #endif

        return MockNinaEngine()
    }
}

private extension Bundle {
    func nonEmptyString(forInfoKey key: String) -> String? {
        guard let value = object(forInfoDictionaryKey: key) as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

#if canImport(Supabase)
enum SupabaseClientFactory {
    static let shared: SupabaseClient? = {
        guard let configuration = SupabaseConfiguration.fromBundle() else { return nil }

        return SupabaseClient(
            supabaseURL: configuration.url,
            supabaseKey: configuration.publishableKey,
            options: SupabaseClientOptions(
                auth: SupabaseClientOptions.AuthOptions(
                    emitLocalSessionAsInitialSession: true
                )
            )
        )
    }()
}
#endif
