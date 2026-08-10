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

    init?(
        rawURL: String,
        publishableKey rawPublishableKey: String,
        allowsInsecureLocalhost: Bool = false
    ) {
        guard let url = Self.validatedURL(
            rawURL,
            allowsInsecureLocalhost: allowsInsecureLocalhost
        ),
        let publishableKey = Self.validatedPublishableKey(rawPublishableKey) else {
            return nil
        }

        self.url = url
        self.publishableKey = publishableKey
    }

    static func fromBundle(_ bundle: Bundle = .main) -> SupabaseConfiguration? {
        guard let rawURL = bundle.nonEmptyString(forInfoKey: "NINASupabaseURL")
                ?? bundle.nonEmptyString(forInfoKey: "NINA_SUPABASE_URL"),
              let key = bundle.nonEmptyString(forInfoKey: "NINASupabasePublishableKey")
                ?? bundle.nonEmptyString(forInfoKey: "NINA_SUPABASE_PUBLISHABLE_KEY") else {
            return nil
        }

        #if DEBUG
        let allowsInsecureLocalhost = true
        #else
        let allowsInsecureLocalhost = false
        #endif

        return SupabaseConfiguration(
            rawURL: rawURL,
            publishableKey: key,
            allowsInsecureLocalhost: allowsInsecureLocalhost
        )
    }

    private static func validatedURL(
        _ rawValue: String,
        allowsInsecureLocalhost: Bool
    ) -> URL? {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty,
              !value.contains("$("),
              let components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(),
              let host = components.host?.lowercased(),
              !host.isEmpty,
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil,
              components.path.isEmpty || components.path == "/" else {
            return nil
        }

        let localHosts = ["localhost", "127.0.0.1", "::1"]
        let isSecure = scheme == "https"
        let isAllowedLocalHTTP = allowsInsecureLocalhost
            && scheme == "http"
            && localHosts.contains(host)

        guard isSecure || isAllowedLocalHTTP else { return nil }
        return components.url
    }

    private static func validatedPublishableKey(_ rawValue: String) -> String? {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count >= 24,
              value.count <= 4_096,
              !value.contains("$("),
              !value.unicodeScalars.contains(where: CharacterSet.whitespacesAndNewlines.contains)
        else {
            return nil
        }

        if value.hasPrefix("sb_publishable_") {
            let suffix = value.dropFirst("sb_publishable_".count)
            let isValidSuffix = suffix.utf8.count >= 16
                && suffix.utf8.allSatisfy { (33...126).contains($0) }
            return isValidSuffix ? value : nil
        }

        let segments = value.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count == 3,
              segments.allSatisfy({
                  !$0.isEmpty && $0.utf8.allSatisfy(isBase64URLByte)
              }),
              let payload = decodedBase64URL(String(segments[1])),
              let object = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
              object["role"] as? String == "anon" else {
            return nil
        }

        return value
    }

    private static func decodedBase64URL(_ value: String) -> Data? {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        guard remainder != 1 else { return nil }
        if remainder > 0 {
            base64.append(String(repeating: "=", count: 4 - remainder))
        }
        return Data(base64Encoded: base64)
    }

    private static func isBase64URLByte(_ byte: UInt8) -> Bool {
        (48...57).contains(byte)
            || (65...90).contains(byte)
            || (97...122).contains(byte)
            || byte == 45
            || byte == 95
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

struct NinaProposalGate {
    var isV2Enabled: Bool

    static var current: NinaProposalGate {
        NinaProposalGate(isV2Enabled: NinaAIConfiguration.isV2Enabled)
    }

    func visibleProposals(_ proposals: [NinaProposal]) -> [NinaProposal] {
        isV2Enabled ? proposals : []
    }

    func withholdsProposals(_ proposals: [NinaProposal]) -> Bool {
        !isV2Enabled && proposals.contains { $0.state == .pending }
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
