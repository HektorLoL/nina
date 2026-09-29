import CryptoKit
import Foundation
import Security
#if canImport(DeviceCheck)
import DeviceCheck
#endif
#if canImport(Supabase)
import Supabase
#endif

enum AgeSignalError: Error, Equatable {
    case attestUnavailable
    case attestInvalid
    case keyUnknown
    case challengeExpired
    case rejected(AgeStatus?)
    case rateLimited
    case unavailable

    init(code: String, ageStatus: AgeStatus? = nil) {
        switch code {
        case "app_attest_invalid": self = .attestInvalid
        case "app_attest_key_unknown": self = .keyUnknown
        case "challenge_expired": self = .challengeExpired
        case "age_signal_rejected": self = .rejected(ageStatus)
        case "rate_limited": self = .rateLimited
        default: self = .unavailable
        }
    }
}

protocol AgeSignalSubmitting {
    func submit(_ signal: AgeSignal, for user: AuthUser) async throws -> AgeStatus
}

struct UnavailableAgeSignalSubmitter: AgeSignalSubmitting {
    func submit(_ signal: AgeSignal, for user: AuthUser) async throws -> AgeStatus {
        throw AgeSignalError.attestUnavailable
    }
}

protocol AppAttestProviding {
    var isSupported: Bool { get }
    func generateKey() async throws -> String
    func attestKey(_ keyID: String, clientDataHash: Data) async throws -> Data
    func generateAssertion(_ keyID: String, clientDataHash: Data) async throws -> Data
}

#if canImport(DeviceCheck)
struct DeviceAppAttestService: AppAttestProviding {
    var isSupported: Bool {
        DCAppAttestService.shared.isSupported
    }

    func generateKey() async throws -> String {
        try await DCAppAttestService.shared.generateKey()
    }

    func attestKey(_ keyID: String, clientDataHash: Data) async throws -> Data {
        try await DCAppAttestService.shared.attestKey(keyID, clientDataHash: clientDataHash)
    }

    func generateAssertion(_ keyID: String, clientDataHash: Data) async throws -> Data {
        try await DCAppAttestService.shared.generateAssertion(keyID, clientDataHash: clientDataHash)
    }
}
#endif

protocol AppAttestKeyStoring {
    func keyID(for userID: String) -> String?
    func save(_ keyID: String, for userID: String) throws
    func remove(for userID: String)
}

// The key id lives in the Keychain, bound to this device, never in UserDefaults or a backup.
struct KeychainAppAttestKeyStore: AppAttestKeyStoring {
    static let service = "com.heitor.nina.app-attest"

    enum KeychainError: Error {
        case writeFailed(OSStatus)
    }

    func keyID(for userID: String) -> String? {
        var query = baseQuery(for: userID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    func save(_ keyID: String, for userID: String) throws {
        remove(for: userID)
        var query = baseQuery(for: userID)
        query[kSecValueData as String] = Data(keyID.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.writeFailed(status) }
    }

    func remove(for userID: String) {
        SecItemDelete(baseQuery(for: userID) as CFDictionary)
    }

    private func baseQuery(for userID: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: "app-attest-key.\(userID)"
        ]
    }
}

struct AgeSignalRequest: Encodable, Equatable {
    enum Step: String, Encodable {
        case challenge
        case register
        case signal
    }

    var step: Step
    var challenge: String?
    var keyID: String?
    var attestation: String?
    var assertion: String?
    var signalJSON: String?

    private enum CodingKeys: String, CodingKey {
        case step
        case challenge
        case keyID = "key_id"
        case attestation
        case assertion
        case signalJSON = "signal_json"
    }

    // Unknown or null keys are refused by age-signal, so absent fields are omitted rather than sent as null.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(step, forKey: .step)
        try container.encodeIfPresent(challenge, forKey: .challenge)
        try container.encodeIfPresent(keyID, forKey: .keyID)
        try container.encodeIfPresent(attestation, forKey: .attestation)
        try container.encodeIfPresent(assertion, forKey: .assertion)
        try container.encodeIfPresent(signalJSON, forKey: .signalJSON)
    }
}

struct AgeSignalResponse: Decodable {
    var challenge: String?
    var expiresAt: String?
    var registered: Bool?
    var ageStatus: AgeStatus?

    private enum CodingKeys: String, CodingKey {
        case challenge
        case expiresAt = "expires_at"
        case registered
        case ageStatus = "age_status"
    }
}

struct AgeSignalErrorBody: Decodable {
    var error: String
    var ageStatus: AgeStatus?

    private enum CodingKeys: String, CodingKey {
        case error
        case ageStatus = "age_status"
    }
}

protocol AgeSignalTransport {
    func send(_ request: AgeSignalRequest) async throws -> AgeSignalResponse
}

struct AgeSignalClient: AgeSignalSubmitting {
    static let insecureLocalKeyID = "insecure-local"

    var transport: any AgeSignalTransport
    var attest: any AppAttestProviding
    var keyStore: any AppAttestKeyStoring
    var allowsInsecureLocal: Bool

    // A key the server forgot, or one this device lost to a reinstall or a restore, is replaced once:
    // App Attest keys never survive either, while the Keychain entry naming them can.
    func submit(_ signal: AgeSignal, for user: AuthUser) async throws -> AgeStatus {
        let signalJSON = try signal.canonicalJSON()
        do {
            return try await sendSignal(signalJSON, for: user)
        } catch AgeSignalError.keyUnknown {
            keyStore.remove(for: user.id)
            return try await sendSignal(signalJSON, for: user)
        }
    }

    static func isLostDeviceKey(_ error: Error) -> Bool {
        #if canImport(DeviceCheck)
        if let error = error as? DCError {
            return error.code == .invalidKey
        }
        #endif
        return false
    }

    private var usesInsecureLocal: Bool {
        allowsInsecureLocal && !attest.isSupported
    }

    private func sendSignal(_ signalJSON: String, for user: AuthUser) async throws -> AgeStatus {
        let storedKeyID = usesInsecureLocal ? nil : keyStore.keyID(for: user.id)
        let keyID = try await registeredKeyID(for: user)
        let challenge = try await freshChallenge()
        let assertion: String
        if usesInsecureLocal {
            assertion = ""
        } else {
            let clientDataHash = Self.signalClientDataHash(challenge: challenge.bytes, signalJSON: signalJSON)
            do {
                assertion = try await attest.generateAssertion(keyID, clientDataHash: clientDataHash)
                    .base64EncodedString()
            } catch {
                if storedKeyID == keyID, Self.isLostDeviceKey(error) {
                    throw AgeSignalError.keyUnknown
                }
                throw AgeSignalError.attestInvalid
            }
        }

        let response = try await transport.send(
            AgeSignalRequest(
                step: .signal,
                challenge: challenge.encoded,
                keyID: keyID,
                assertion: assertion,
                signalJSON: signalJSON
            )
        )
        guard let status = response.ageStatus else { throw AgeSignalError.unavailable }
        return status
    }

    private func registeredKeyID(for user: AuthUser) async throws -> String {
        if usesInsecureLocal {
            let challenge = try await freshChallenge()
            _ = try await transport.send(
                AgeSignalRequest(
                    step: .register,
                    challenge: challenge.encoded,
                    keyID: Self.insecureLocalKeyID,
                    attestation: ""
                )
            )
            return Self.insecureLocalKeyID
        }

        guard attest.isSupported else { throw AgeSignalError.attestUnavailable }
        if let stored = keyStore.keyID(for: user.id) {
            return stored
        }

        let keyID: String
        let attestation: Data
        let challenge = try await freshChallenge()
        do {
            keyID = try await attest.generateKey()
            attestation = try await attest.attestKey(
                keyID,
                clientDataHash: Self.registrationClientDataHash(challenge: challenge.bytes, userID: user.id)
            )
        } catch {
            throw AgeSignalError.attestInvalid
        }

        _ = try await transport.send(
            AgeSignalRequest(
                step: .register,
                challenge: challenge.encoded,
                keyID: keyID,
                attestation: attestation.base64EncodedString()
            )
        )
        try? keyStore.save(keyID, for: user.id)
        return keyID
    }

    private func freshChallenge() async throws -> (encoded: String, bytes: Data) {
        let response = try await transport.send(AgeSignalRequest(step: .challenge))
        guard let encoded = response.challenge, let bytes = Self.base64URLDecoded(encoded) else {
            throw AgeSignalError.unavailable
        }
        return (encoded, bytes)
    }

    static func registrationClientDataHash(challenge: Data, userID: String) -> Data {
        var material = challenge
        material.append(Data("register".utf8))
        material.append(Data(userID.lowercased().utf8))
        return Data(SHA256.hash(data: material))
    }

    static func signalClientDataHash(challenge: Data, signalJSON: String) -> Data {
        var material = challenge
        material.append(Data(signalJSON.utf8))
        return Data(SHA256.hash(data: material))
    }

    static func base64URLDecoded(_ value: String) -> Data? {
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
}

#if canImport(Supabase)
struct SupabaseAgeSignalTransport: AgeSignalTransport {
    var client: SupabaseClient
    var diagnostics: BackendDiagnosticsStore? = nil

    func send(_ request: AgeSignalRequest) async throws -> AgeSignalResponse {
        do {
            return try await BackendRequestLogger.perform(
                component: "age",
                operation: "age_signal.\(request.step.rawValue)",
                diagnostics: diagnostics
            ) {
                try await client.functions.invoke(
                    "age-signal",
                    options: FunctionInvokeOptions(body: request),
                    decoder: NinaDateCoding.decoder()
                )
            }
        } catch FunctionsError.httpError(_, let data) {
            let body = try? NinaDateCoding.decoder().decode(AgeSignalErrorBody.self, from: data)
            throw AgeSignalError(code: body?.error ?? "unavailable", ageStatus: body?.ageStatus)
        } catch let error as AgeSignalError {
            throw error
        } catch {
            throw AgeSignalError.unavailable
        }
    }
}
#endif
