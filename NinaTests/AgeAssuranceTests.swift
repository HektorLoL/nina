import CryptoKit
import DeviceCheck
import XCTest
@testable import Nina

final class AgeAssuranceTests: XCTestCase {
    func testADeclinedShareIsUnknownNotAdult() {
        let mapping = AgeAssurance.map(.declined)

        XCTAssertEqual(
            mapping,
            AgeMapping(status: .unknown, band: nil, assurance: .none, parentalControlsActive: false)
        )
        XCTAssertFalse(mapping.isTrustedAdult)
    }

    func testARangeOutsideTheRequestedGatesMapsToTheYoungestBand() {
        XCTAssertEqual(AgeAssurance.map(sharing(lower: 13, upper: 17, "self_declared")).band, .twelveToFifteen)
        XCTAssertEqual(AgeAssurance.map(sharing(lower: 16, upper: 20, "self_declared")).band, .sixteenToSeventeen)
        XCTAssertEqual(AgeAssurance.map(sharing(lower: 16, upper: 20, "self_declared")).status, .minor)
        XCTAssertEqual(AgeAssurance.map(sharing(lower: 9, upper: 15, "guardian_declared")).band, .under12)
        XCTAssertEqual(AgeAssurance.map(sharing(lower: nil, upper: 17, nil)).band, .under12)
    }

    func testASelfDeclaredAdultIsNeverTrusted() {
        let selfDeclared = AgeAssurance.map(sharing(lower: 18, upper: nil, "self_declared"))
        let parentalControls = AgeAssurance.map(
            sharing(lower: 18, upper: nil, "confirmed", controls: ["communication_limits"])
        )

        XCTAssertEqual(selfDeclared.status, .adult)
        XCTAssertEqual(selfDeclared.assurance, .selfDeclared)
        XCTAssertFalse(selfDeclared.isTrustedAdult)
        XCTAssertEqual(parentalControls.assurance, .confirmed)
        XCTAssertTrue(parentalControls.parentalControlsActive)
        XCTAssertFalse(parentalControls.isTrustedAdult)
        XCTAssertTrue(AgeAssurance.map(sharing(lower: 18, upper: nil, "confirmed")).isTrustedAdult)
    }

    // The same ten rows supabase/functions/_shared/age-assurance.test.ts asserts.
    func testTheSharedMappingTable() {
        let rows: [(AgeSignal, AgeMapping)] = [
            (.declined, AgeMapping(status: .unknown, band: nil, assurance: .none, parentalControlsActive: false)),
            (sharing(lower: 18, upper: nil, "confirmed"),
             AgeMapping(status: .adult, band: nil, assurance: .confirmed, parentalControlsActive: false)),
            (sharing(lower: 18, upper: nil, "self_declared"),
             AgeMapping(status: .adult, band: nil, assurance: .selfDeclared, parentalControlsActive: false)),
            (sharing(lower: 18, upper: nil, "payment_checked"),
             AgeMapping(status: .adult, band: nil, assurance: .confirmed, parentalControlsActive: false)),
            (sharing(lower: 18, upper: nil, "confirmed", controls: ["communication_limits"]),
             AgeMapping(status: .adult, band: nil, assurance: .confirmed, parentalControlsActive: true)),
            (sharing(lower: 16, upper: 17, "guardian_declared"),
             AgeMapping(status: .minor, band: .sixteenToSeventeen, assurance: .guardianDeclared, parentalControlsActive: false)),
            (sharing(lower: nil, upper: 12, nil),
             AgeMapping(status: .minor, band: .under12, assurance: .none, parentalControlsActive: false)),
            (sharing(lower: 13, upper: 15, "self_declared"),
             AgeMapping(status: .minor, band: .twelveToFifteen, assurance: .selfDeclared, parentalControlsActive: false)),
            (sharing(lower: 16, upper: 20, "self_declared"),
             AgeMapping(status: .minor, band: .sixteenToSeventeen, assurance: .selfDeclared, parentalControlsActive: false)),
            (sharing(lower: 12, upper: 15, "guardian_checked_by_other_method"),
             AgeMapping(status: .minor, band: .twelveToFifteen, assurance: .guardianDeclared, parentalControlsActive: false))
        ]

        for (index, row) in rows.enumerated() {
            XCTAssertEqual(AgeAssurance.map(row.0), row.1, "row \(index)")
        }
    }

    func testEligibilityForAgeFeaturesNeverDecidesAnything() {
        var eligible = sharing(lower: 18, upper: nil, "confirmed")
        eligible.eligibleForAgeFeatures = true
        var ineligible = eligible
        ineligible.eligibleForAgeFeatures = false

        XCTAssertEqual(AgeAssurance.map(eligible), AgeAssurance.map(ineligible))
    }

    func testTheSignalJSONHasExactlySevenSortedKeysWithExplicitNulls() throws {
        let declined = try AgeSignal.declined.canonicalJSON()
        XCTAssertEqual(
            declined,
            #"{"declaration":null,"eligible_for_age_features":null,"lower_bound":null,"outcome":"declined","parental_controls":[],"regulatory_features":[],"upper_bound":null}"#
        )

        var shared = sharing(lower: 16, upper: 17, "guardian_declared", controls: ["other", "communication_limits"])
        shared.eligibleForAgeFeatures = false
        shared.regulatoryFeatures = ["declared_age_range_required"]
        XCTAssertEqual(
            try shared.canonicalJSON(),
            #"{"declaration":"guardian_declared","eligible_for_age_features":false,"lower_bound":16,"outcome":"sharing","parental_controls":["communication_limits","other"],"regulatory_features":["declared_age_range_required"],"upper_bound":17}"#
        )

        var declinedWithDeclaration = AgeSignal.declined
        declinedWithDeclaration.declaration = "confirmed"
        XCTAssertTrue(try declinedWithDeclaration.canonicalJSON().hasPrefix(#"{"declaration":null"#))
    }

    func testAMissingOrUnreadableAgeStatusHoldsNoCapability() throws {
        let empty = try JSONDecoder().decode(AgeStatus.self, from: Data("{}".utf8))
        let strange = try JSONDecoder().decode(
            AgeStatus.self,
            from: Data(#"{"status":"elder","trusted_adult":true,"may_use_ai":true,"may_buy_premium":true}"#.utf8)
        )
        let bandless = try JSONDecoder().decode(AgeStatus.self, from: Data(#"{"status":"minor"}"#.utf8))

        for status in [empty, strange] {
            XCTAssertEqual(status.status, .unknown)
            XCTAssertFalse(status.isAdult)
            XCTAssertFalse(status.trustedAdult)
            XCTAssertFalse(status.canUseAI)
            XCTAssertFalse(status.canBuy)
            XCTAssertFalse(status.canActForMinors)
        }
        XCTAssertEqual(bandless.band, .under12)
        XCTAssertTrue(empty.hasNoAppleRecord)
    }

    func testAnOperatorRecordIsNeverRecheckedFromTheDevice() {
        var status = AgeStatus.unknown
        status.recheckAfter = Date(timeIntervalSince1970: 0)
        XCTAssertTrue(status.isDueForRecheck(now: .now))
        status.assurance = .operatorSet
        XCTAssertFalse(status.isDueForRecheck(now: .now))
    }

    func testRegistrationAndSignalHashesBindTheChallengeToTheirPurpose() throws {
        let challenge = Data(repeating: 7, count: 32)
        let userID = "A1B2C3D4-0000-0000-0000-00000000000F"

        var registration = challenge
        registration.append(Data("register".utf8))
        registration.append(Data(userID.lowercased().utf8))
        XCTAssertEqual(
            AgeSignalClient.registrationClientDataHash(challenge: challenge, userID: userID),
            Data(SHA256.hash(data: registration))
        )

        let json = try AgeSignal.declined.canonicalJSON()
        var signal = challenge
        signal.append(Data(json.utf8))
        XCTAssertEqual(
            AgeSignalClient.signalClientDataHash(challenge: challenge, signalJSON: json),
            Data(SHA256.hash(data: signal))
        )

        let encoded = challenge.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        XCTAssertEqual(AgeSignalClient.base64URLDecoded(encoded), challenge)
    }

    func testTheFirstSignalRegistersTheKeyOnceAndSignsTheExactBytesSent() async throws {
        let transport = ScriptedAgeSignalTransport()
        let attest = FakeAppAttest()
        let keys = MemoryKeyStore()
        let client = AgeSignalClient(transport: transport, attest: attest, keyStore: keys, allowsInsecureLocal: false)
        let user = AuthUser(id: UUID().uuidString, displayName: "Ana", email: nil, provider: .apple)

        _ = try await client.submit(sharing(lower: 18, upper: nil, "confirmed"), for: user)
        _ = try await client.submit(sharing(lower: 18, upper: nil, "confirmed"), for: user)
        let steps = await transport.sentSteps()
        let signalJSON = await transport.lastSignalJSON()

        XCTAssertEqual(steps, [.challenge, .register, .challenge, .signal, .challenge, .signal])
        XCTAssertEqual(keys.keyID(for: user.id), "generated-key")
        XCTAssertEqual(signalJSON, try sharing(lower: 18, upper: nil, "confirmed").canonicalJSON())
        XCTAssertEqual(attest.generatedKeys, 1)
    }

    func testAKeyTheServerForgotIsRegisteredAgainOnceAndTheSignalRetried() async throws {
        let transport = ScriptedAgeSignalTransport(failFirstSignalWith: .keyUnknown)
        let attest = FakeAppAttest()
        let keys = MemoryKeyStore()
        let user = AuthUser(id: UUID().uuidString, displayName: "Ana", email: nil, provider: .apple)
        try keys.save("stale-key", for: user.id)
        let client = AgeSignalClient(transport: transport, attest: attest, keyStore: keys, allowsInsecureLocal: false)

        let status = try await client.submit(.declined, for: user)
        let steps = await transport.sentSteps()

        XCTAssertEqual(status.status, .unknown)
        XCTAssertEqual(steps, [.challenge, .signal, .challenge, .register, .challenge, .signal])
        XCTAssertEqual(keys.keyID(for: user.id), "generated-key")
    }

    func testAKeyTheDeviceLostToAReinstallIsReplacedOnceAndTheSignalRetried() async throws {
        let transport = ScriptedAgeSignalTransport()
        let attest = FakeAppAttest(lostKeyIDs: ["key-from-before-the-reinstall"])
        let keys = MemoryKeyStore()
        let user = AuthUser(id: UUID().uuidString, displayName: "Ana", email: nil, provider: .apple)
        try keys.save("key-from-before-the-reinstall", for: user.id)
        let client = AgeSignalClient(transport: transport, attest: attest, keyStore: keys, allowsInsecureLocal: false)

        let status = try await client.submit(sharing(lower: 18, upper: nil, "confirmed"), for: user)
        let steps = await transport.sentSteps()

        XCTAssertEqual(status.status, .unknown)
        XCTAssertEqual(steps, [.challenge, .challenge, .register, .challenge, .signal])
        XCTAssertEqual(attest.generatedKeys, 1)
        XCTAssertEqual(keys.keyID(for: user.id), "generated-key")
    }

    func testAServerOutageNeverDiscardsTheDeviceKey() async throws {
        let transport = ScriptedAgeSignalTransport()
        let attest = FakeAppAttest(outageKeyIDs: ["working-key"])
        let keys = MemoryKeyStore()
        let user = AuthUser(id: UUID().uuidString, displayName: "Ana", email: nil, provider: .apple)
        try keys.save("working-key", for: user.id)
        let client = AgeSignalClient(transport: transport, attest: attest, keyStore: keys, allowsInsecureLocal: false)

        do {
            _ = try await client.submit(.declined, for: user)
            XCTFail("An App Attest outage must not record a signal")
        } catch {
            XCTAssertEqual(error as? AgeSignalError, .attestInvalid)
        }
        XCTAssertEqual(attest.generatedKeys, 0)
        XCTAssertEqual(keys.keyID(for: user.id), "working-key")
    }

    func testAnUnsupportedDeviceNeverSendsASignalOutsideTheLocalDebugStack() async throws {
        let transport = ScriptedAgeSignalTransport()
        let attest = FakeAppAttest(isSupported: false)
        let user = AuthUser(id: UUID().uuidString, displayName: "Ana", email: nil, provider: .apple)

        let production = AgeSignalClient(transport: transport, attest: attest, keyStore: MemoryKeyStore(), allowsInsecureLocal: false)
        do {
            _ = try await production.submit(.declined, for: user)
            XCTFail("An unattested device must not record a signal")
        } catch {
            XCTAssertEqual(error as? AgeSignalError, .attestUnavailable)
        }
        let stepsAfterRefusal = await transport.sentSteps()
        XCTAssertFalse(stepsAfterRefusal.contains(.signal))

        let local = AgeSignalClient(transport: transport, attest: attest, keyStore: MemoryKeyStore(), allowsInsecureLocal: true)
        _ = try await local.submit(.declined, for: user)
        let keyIDs = await transport.sentKeyIDs()
        XCTAssertEqual(Set(keyIDs), [AgeSignalClient.insecureLocalKeyID])
    }

    @MainActor
    func testAnAppleErrorIsNeverRecordedAndADeclineIs() async {
        let submitter = RecordingSubmitter()
        let failing = AgeCheckCoordinator(
            provider: ScriptedAgeRangeProvider(result: .failure(AgeRangeRequestError.unavailable)),
            submitter: submitter,
            defaults: isolatedDefaults(),
            privateDataStore: InMemoryPrivateStore()
        )
        let user = AuthUser(id: UUID().uuidString, displayName: "Ana", email: nil, provider: .apple)

        let afterError = await failing.requestAndRecord(for: user)

        XCTAssertNil(afterError)
        XCTAssertEqual(failing.phase, .appleError)
        let submittedAfterError = await submitter.submitted()
        XCTAssertTrue(submittedAfterError.isEmpty)

        let declining = AgeCheckCoordinator(
            provider: ScriptedAgeRangeProvider(result: .success(.declined)),
            submitter: submitter,
            defaults: isolatedDefaults(),
            privateDataStore: InMemoryPrivateStore()
        )
        _ = await declining.requestAndRecord(for: user)

        let submittedAfterDecline = await submitter.submitted()
        XCTAssertEqual(submittedAfterDecline, [.declined])
        XCTAssertEqual(declining.phase, .declined)
    }

    @MainActor
    func testAShareStartedInsideTheAppNeverTakesOverTheRootAndSaysHowItWent() async {
        let user = AuthUser(id: UUID().uuidString, displayName: "Ana", email: nil, provider: .apple)
        let declining = AgeCheckCoordinator(
            provider: ScriptedAgeRangeProvider(result: .success(.declined)),
            submitter: RecordingSubmitter(),
            defaults: isolatedDefaults(),
            privateDataStore: InMemoryPrivateStore()
        )

        let recorded = await declining.requestInline(for: user)

        XCTAssertNotNil(recorded)
        XCTAssertFalse(declining.needsAgeCheck)
        XCTAssertEqual(declining.phase, .idle)
        XCTAssertFalse(declining.isRequestingInline)
        XCTAssertEqual(declining.inlineOutcome, .declined)

        let failing = AgeCheckCoordinator(
            provider: ScriptedAgeRangeProvider(result: .failure(AgeRangeRequestError.unavailable)),
            submitter: RecordingSubmitter(),
            defaults: isolatedDefaults(),
            privateDataStore: InMemoryPrivateStore()
        )

        let afterError = await failing.requestInline(for: user)

        XCTAssertNil(afterError)
        XCTAssertFalse(failing.needsAgeCheck)
        XCTAssertEqual(failing.inlineOutcome, .appleError)
        XCTAssertFalse(failing.inlineOutcome?.line.contains("!") ?? true)
    }

    @MainActor
    func testAnAccountWithNoAppleRecordIsAskedOnceAndCanContinueWithout() async {
        let coordinator = AgeCheckCoordinator(
            provider: ScriptedAgeRangeProvider(result: .success(.declined)),
            submitter: RecordingSubmitter(),
            defaults: isolatedDefaults(),
            privateDataStore: InMemoryPrivateStore()
        )
        let user = AuthUser(id: UUID().uuidString, displayName: "Ana", email: nil, provider: .apple)

        _ = await coordinator.evaluate(user: user, age: .unknown, isVerified: true, isLocalContext: false)
        XCTAssertEqual(coordinator.phase, .prompt)
        XCTAssertTrue(coordinator.needsAgeCheck)

        coordinator.continueWithout(for: user)
        _ = await coordinator.evaluate(user: user, age: .unknown, isVerified: true, isLocalContext: false)

        XCTAssertFalse(coordinator.needsAgeCheck)
    }

    private func sharing(
        lower: Int?,
        upper: Int?,
        _ declaration: String?,
        controls: [String] = []
    ) -> AgeSignal {
        AgeSignal(
            outcome: .sharing,
            declaration: declaration,
            eligibleForAgeFeatures: nil,
            lowerBound: lower,
            upperBound: upper,
            parentalControls: controls,
            regulatoryFeatures: []
        )
    }

    private func isolatedDefaults() -> UserDefaults {
        let name = "AgeAssuranceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}

private final class InMemoryPrivateStore: PrivateLocalDataStoring {
    private var values: [String: Data] = [:]

    func data(forKey key: String, ownerScope: String?) throws -> Data? {
        values[key]
    }

    func set(_ data: Data, forKey key: String, ownerScope: String?) throws {
        values[key] = data
    }

    func removeData(forKey key: String, ownerScope: String?) throws {
        values[key] = nil
    }

    func removeAllData(forOwnerScope ownerScope: String) throws {
        values = [:]
    }
}

private struct ScriptedAgeRangeProvider: AgeRangeProviding {
    var result: Result<AgeSignal, Error>

    func requestAgeRange() async throws -> AgeSignal {
        try result.get()
    }

    func requiredRegulatoryFeatures() async -> [String]? {
        nil
    }
}

private actor RecordingSubmitter: AgeSignalSubmitting {
    private var signals: [AgeSignal] = []

    func submitted() -> [AgeSignal] {
        signals
    }

    func submit(_ signal: AgeSignal, for user: AuthUser) async throws -> AgeStatus {
        signals.append(signal)
        return .unknown
    }
}

private final class MemoryKeyStore: AppAttestKeyStoring, @unchecked Sendable {
    private var keys: [String: String] = [:]

    func keyID(for userID: String) -> String? {
        keys[userID]
    }

    func save(_ keyID: String, for userID: String) throws {
        keys[userID] = keyID
    }

    func remove(for userID: String) {
        keys[userID] = nil
    }
}

private final class FakeAppAttest: AppAttestProviding, @unchecked Sendable {
    let isSupported: Bool
    private let lostKeyIDs: Set<String>
    private let outageKeyIDs: Set<String>
    private(set) var generatedKeys = 0

    init(isSupported: Bool = true, lostKeyIDs: Set<String> = [], outageKeyIDs: Set<String> = []) {
        self.isSupported = isSupported
        self.lostKeyIDs = lostKeyIDs
        self.outageKeyIDs = outageKeyIDs
    }

    func generateKey() async throws -> String {
        generatedKeys += 1
        return "generated-key"
    }

    func attestKey(_ keyID: String, clientDataHash: Data) async throws -> Data {
        Data("attestation".utf8)
    }

    func generateAssertion(_ keyID: String, clientDataHash: Data) async throws -> Data {
        if lostKeyIDs.contains(keyID) {
            throw DCError(.invalidKey)
        }
        if outageKeyIDs.contains(keyID) {
            throw DCError(.serverUnavailable)
        }
        return Data("assertion".utf8)
    }
}

private actor ScriptedAgeSignalTransport: AgeSignalTransport {
    private var steps: [AgeSignalRequest.Step] = []
    private var keyIDs: [String] = []
    private var signalJSON: String?
    private var pendingFailure: AgeSignalError?

    init(failFirstSignalWith failure: AgeSignalError? = nil) {
        pendingFailure = failure
    }

    func sentSteps() -> [AgeSignalRequest.Step] {
        steps
    }

    func sentKeyIDs() -> [String] {
        keyIDs
    }

    func lastSignalJSON() -> String? {
        signalJSON
    }

    func send(_ request: AgeSignalRequest) async throws -> AgeSignalResponse {
        steps.append(request.step)
        if let keyID = request.keyID {
            keyIDs.append(keyID)
        }
        switch request.step {
        case .challenge:
            let challenge = Data(repeating: 1, count: 32).base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
            return AgeSignalResponse(challenge: challenge, expiresAt: nil, registered: nil, ageStatus: nil)
        case .register:
            return AgeSignalResponse(challenge: nil, expiresAt: nil, registered: true, ageStatus: nil)
        case .signal:
            if let failure = pendingFailure {
                pendingFailure = nil
                throw failure
            }
            signalJSON = request.signalJSON
            return AgeSignalResponse(challenge: nil, expiresAt: nil, registered: nil, ageStatus: .unknown)
        }
    }
}
