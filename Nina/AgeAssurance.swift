import Foundation
import Observation
#if canImport(DeclaredAgeRange)
import DeclaredAgeRange
#endif
#if canImport(UIKit)
import UIKit
#endif

enum MinorConsentVersion {
    static let current = "2026-09-29"
}

enum AgeStatusKind: String, Hashable {
    case adult
    case minor
    case unknown
}

enum MinorBand: String, CaseIterable, Identifiable, Hashable, Comparable {
    case under12 = "under_12"
    case twelveToFifteen = "12_15"
    case sixteenToSeventeen = "16_17"

    var id: String { rawValue }

    var order: Int {
        switch self {
        case .under12: 0
        case .twelveToFifteen: 1
        case .sixteenToSeventeen: 2
        }
    }

    static func < (lhs: MinorBand, rhs: MinorBand) -> Bool {
        lhs.order < rhs.order
    }

    var chipTitle: String {
        switch self {
        case .under12: "Menos de 12"
        case .twelveToFifteen: "12 a 15"
        case .sixteenToSeventeen: "16 ou 17"
        }
    }

    var requesterTag: String {
        switch self {
        case .under12: "Menor de idade · menos de 12"
        case .twelveToFifteen: "Menor de idade · 12 a 15"
        case .sixteenToSeventeen: "Menor de idade · 16 ou 17"
        }
    }

    var householdRole: HouseholdRole {
        self == .under12 ? .child : .teen
    }

    var acknowledgementKind: MinorAcknowledgementKind {
        self == .sixteenToSeventeen ? .aceitar : .entendi
    }

    // A guardian may always choose the same band or a younger one, never an older one.
    func allowedChoices() -> [MinorBand] {
        MinorBand.allCases.filter { $0 <= self }
    }

    init?(wireValue: String?) {
        guard let wireValue, let band = MinorBand(rawValue: wireValue) else { return nil }
        self = band
    }
}

enum AgeAssuranceLevel: String, Hashable {
    case confirmed
    case selfDeclared = "self_declared"
    case guardianDeclared = "guardian_declared"
    case operatorSet = "operator"
    case none
}

enum AgeBandSource: String, Hashable {
    case apple
    case guardian
}

enum GuardianRelationship: String, CaseIterable, Identifiable, Hashable {
    case mae
    case pai
    case responsavelLegal = "responsavel_legal"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mae: "Mãe"
        case .pai: "Pai"
        case .responsavelLegal: "Responsável legal"
        }
    }
}

enum MinorAcknowledgementKind: String, Hashable {
    case entendi
    case aceitar
}

struct AgeTerms: Decodable, Hashable {
    var currentTermsVersion: String
    var currentPolicyVersion: String
    var currentMinorConsentVersion: String
    var acceptedCurrent: Bool
    var reachedMajority: Bool
    var formerGuardianNames: [String] = []

    static let unknown = AgeTerms(
        currentTermsVersion: MinorConsentVersion.current,
        currentPolicyVersion: PrivacyPolicyVersion.current,
        currentMinorConsentVersion: MinorConsentVersion.current,
        acceptedCurrent: false,
        reachedMajority: false
    )

    private enum CodingKeys: String, CodingKey {
        case currentTermsVersion = "current_terms_version"
        case currentPolicyVersion = "current_policy_version"
        case currentMinorConsentVersion = "current_minor_consent_version"
        case acceptedCurrent = "accepted_current"
        case reachedMajority = "reached_majority"
        case formerGuardianNames = "former_guardian_names"
    }

    init(
        currentTermsVersion: String,
        currentPolicyVersion: String,
        currentMinorConsentVersion: String,
        acceptedCurrent: Bool,
        reachedMajority: Bool,
        formerGuardianNames: [String] = []
    ) {
        self.currentTermsVersion = currentTermsVersion
        self.currentPolicyVersion = currentPolicyVersion
        self.currentMinorConsentVersion = currentMinorConsentVersion
        self.acceptedCurrent = acceptedCurrent
        self.reachedMajority = reachedMajority
        self.formerGuardianNames = formerGuardianNames
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        currentTermsVersion = try container.decodeIfPresent(String.self, forKey: .currentTermsVersion)
            ?? MinorConsentVersion.current
        currentPolicyVersion = try container.decodeIfPresent(String.self, forKey: .currentPolicyVersion)
            ?? PrivacyPolicyVersion.current
        currentMinorConsentVersion = try container.decodeIfPresent(
            String.self,
            forKey: .currentMinorConsentVersion
        ) ?? MinorConsentVersion.current
        acceptedCurrent = try container.decodeIfPresent(Bool.self, forKey: .acceptedCurrent) ?? false
        reachedMajority = try container.decodeIfPresent(Bool.self, forKey: .reachedMajority) ?? false
        formerGuardianNames = try container.decodeIfPresent(
            [String].self,
            forKey: .formerGuardianNames
        ) ?? []
    }

    var firstFormerGuardianName: String? {
        formerGuardianNames.first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}

// Every capability defaults to false: a missing or unreadable age reads as the most protective state.
struct AgeStatus: Decodable, Hashable {
    var status: AgeStatusKind
    var band: MinorBand?
    var bandSource: AgeBandSource?
    var assurance: AgeAssuranceLevel
    var parentalControlsActive: Bool
    var householdMarked: Bool
    var trustedAdult: Bool
    var mayUseAI: Bool
    var mayBuyPremium: Bool
    var aiBlocked: Bool
    var recordedAt: Date?
    var recheckAfter: Date?
    var guardianNames: [String]
    var terms: AgeTerms
    var needsName = false

    static let unknown = AgeStatus(
        status: .unknown,
        band: nil,
        bandSource: nil,
        assurance: .none,
        parentalControlsActive: false,
        householdMarked: false,
        trustedAdult: false,
        mayUseAI: false,
        mayBuyPremium: false,
        aiBlocked: false,
        recordedAt: nil,
        recheckAfter: nil,
        guardianNames: [],
        terms: .unknown
    )

    #if DEBUG
    static let localTrustedAdult = AgeStatus(
        status: .adult,
        band: nil,
        bandSource: .apple,
        assurance: .confirmed,
        parentalControlsActive: false,
        householdMarked: false,
        trustedAdult: true,
        mayUseAI: true,
        mayBuyPremium: true,
        aiBlocked: false,
        recordedAt: .now,
        recheckAfter: nil,
        guardianNames: [],
        terms: AgeTerms(
            currentTermsVersion: MinorConsentVersion.current,
            currentPolicyVersion: PrivacyPolicyVersion.current,
            currentMinorConsentVersion: MinorConsentVersion.current,
            acceptedCurrent: true,
            reachedMajority: false
        )
    )
    #endif

    private enum CodingKeys: String, CodingKey {
        case status
        case band
        case bandSource = "band_source"
        case assurance
        case parentalControlsActive = "parental_controls_active"
        case householdMarked = "household_marked"
        case trustedAdult = "trusted_adult"
        case mayUseAI = "may_use_ai"
        case mayBuyPremium = "may_buy_premium"
        case aiBlocked = "ai_blocked"
        case recordedAt = "recorded_at"
        case recheckAfter = "recheck_after"
        case guardianNames = "guardian_names"
        case terms
        case needsName = "needs_name"
    }

    init(
        status: AgeStatusKind,
        band: MinorBand?,
        bandSource: AgeBandSource?,
        assurance: AgeAssuranceLevel,
        parentalControlsActive: Bool,
        householdMarked: Bool,
        trustedAdult: Bool,
        mayUseAI: Bool,
        mayBuyPremium: Bool,
        aiBlocked: Bool,
        recordedAt: Date?,
        recheckAfter: Date?,
        guardianNames: [String],
        terms: AgeTerms,
        needsName: Bool = false
    ) {
        self.status = status
        self.band = status == .minor ? band : nil
        self.bandSource = bandSource
        self.assurance = assurance
        self.parentalControlsActive = parentalControlsActive
        self.householdMarked = householdMarked
        self.trustedAdult = status == .adult && trustedAdult
        self.mayUseAI = status == .adult && mayUseAI
        self.mayBuyPremium = status == .adult && mayBuyPremium
        self.aiBlocked = aiBlocked
        self.recordedAt = recordedAt
        self.recheckAfter = recheckAfter
        self.guardianNames = guardianNames
        self.terms = terms
        self.needsName = status != .adult && needsName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedStatus = AgeStatusKind(
            rawValue: try container.decodeIfPresent(String.self, forKey: .status) ?? ""
        ) ?? .unknown
        let decodedBand = MinorBand(wireValue: try container.decodeIfPresent(String.self, forKey: .band))
        // A minor without a readable band is still a minor, and the youngest band is the most protective reading.
        let status: AgeStatusKind = decodedStatus == .minor || decodedStatus == .adult ? decodedStatus : .unknown
        self.init(
            status: status,
            band: status == .minor ? (decodedBand ?? .under12) : nil,
            bandSource: AgeBandSource(
                rawValue: try container.decodeIfPresent(String.self, forKey: .bandSource) ?? ""
            ),
            assurance: AgeAssuranceLevel(
                rawValue: try container.decodeIfPresent(String.self, forKey: .assurance) ?? ""
            ) ?? .none,
            parentalControlsActive: try container.decodeIfPresent(
                Bool.self,
                forKey: .parentalControlsActive
            ) ?? false,
            householdMarked: try container.decodeIfPresent(Bool.self, forKey: .householdMarked) ?? false,
            trustedAdult: try container.decodeIfPresent(Bool.self, forKey: .trustedAdult) ?? false,
            mayUseAI: try container.decodeIfPresent(Bool.self, forKey: .mayUseAI) ?? false,
            mayBuyPremium: try container.decodeIfPresent(Bool.self, forKey: .mayBuyPremium) ?? false,
            aiBlocked: try container.decodeIfPresent(Bool.self, forKey: .aiBlocked) ?? false,
            recordedAt: try container.decodeIfPresent(Date.self, forKey: .recordedAt),
            recheckAfter: try container.decodeIfPresent(Date.self, forKey: .recheckAfter),
            guardianNames: try container.decodeIfPresent([String].self, forKey: .guardianNames) ?? [],
            terms: try container.decodeIfPresent(AgeTerms.self, forKey: .terms) ?? .unknown,
            needsName: try container.decodeIfPresent(Bool.self, forKey: .needsName) ?? false
        )
    }

    var isAdult: Bool {
        status == .adult
    }

    var isMinorView: Bool {
        !isAdult
    }

    var canActForMinors: Bool {
        isAdult && trustedAdult
    }

    var canUseAI: Bool {
        isAdult && mayUseAI && !aiBlocked
    }

    var canBuy: Bool {
        isAdult && mayBuyPremium
    }

    var hasNoAppleRecord: Bool {
        status == .unknown && recordedAt == nil && assurance == .none
    }

    func isDueForRecheck(now: Date = .now) -> Bool {
        guard assurance != .operatorSet, let recheckAfter else { return false }
        return recheckAfter <= now
    }

    var firstGuardianName: String? {
        guardianNames.first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    func withoutAI() -> AgeStatus {
        var copy = self
        copy.mayUseAI = false
        return copy
    }

    func blockingAI() -> AgeStatus {
        var copy = self
        copy.aiBlocked = true
        return copy
    }
}

// The exact seven keys age-signal verifies byte for byte: sorted, nulls explicit, no whitespace.
struct AgeSignal: Encodable, Equatable {
    enum Outcome: String, Encodable {
        case sharing
        case declined
    }

    var outcome: Outcome
    var declaration: String?
    var eligibleForAgeFeatures: Bool?
    var lowerBound: Int?
    var upperBound: Int?
    var parentalControls: [String]
    var regulatoryFeatures: [String]

    static let declined = AgeSignal(
        outcome: .declined,
        declaration: nil,
        eligibleForAgeFeatures: nil,
        lowerBound: nil,
        upperBound: nil,
        parentalControls: [],
        regulatoryFeatures: []
    )

    private enum CodingKeys: String, CodingKey {
        case declaration
        case eligibleForAgeFeatures = "eligible_for_age_features"
        case lowerBound = "lower_bound"
        case outcome
        case parentalControls = "parental_controls"
        case regulatoryFeatures = "regulatory_features"
        case upperBound = "upper_bound"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        let sharedDeclaration = outcome == .declined ? nil : declaration
        if let sharedDeclaration {
            try container.encode(sharedDeclaration, forKey: .declaration)
        } else {
            try container.encodeNil(forKey: .declaration)
        }
        if let eligibleForAgeFeatures {
            try container.encode(eligibleForAgeFeatures, forKey: .eligibleForAgeFeatures)
        } else {
            try container.encodeNil(forKey: .eligibleForAgeFeatures)
        }
        if let lowerBound {
            try container.encode(lowerBound, forKey: .lowerBound)
        } else {
            try container.encodeNil(forKey: .lowerBound)
        }
        try container.encode(outcome, forKey: .outcome)
        try container.encode(parentalControls.sorted(), forKey: .parentalControls)
        try container.encode(regulatoryFeatures.sorted(), forKey: .regulatoryFeatures)
        if let upperBound {
            try container.encode(upperBound, forKey: .upperBound)
        } else {
            try container.encodeNil(forKey: .upperBound)
        }
    }

    func canonicalJSON() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(self)
        guard let json = String(data: data, encoding: .utf8) else {
            throw AgeSignalError.unavailable
        }
        return json
    }
}

struct AgeMapping: Equatable {
    var status: AgeStatusKind
    var band: MinorBand?
    var assurance: AgeAssuranceLevel
    var parentalControlsActive: Bool

    // Acting for a child is hard-coded to an Apple-confirmed or operator record, whatever the policy row allows for chat.
    var isTrustedAdult: Bool {
        status == .adult
            && !parentalControlsActive
            && (assurance == .confirmed || assurance == .operatorSet)
    }
}

// Mirror of mapAgeRange in supabase/functions/_shared/age-assurance.ts; both sides assert the same table.
enum AgeAssurance {
    static let ageGates = (12, 16, 18)

    static let confirmedDeclarations: Set<String> = [
        "confirmed",
        "checked_by_other_method",
        "payment_checked",
        "government_id_checked"
    ]

    static func map(_ signal: AgeSignal) -> AgeMapping {
        guard signal.outcome == .sharing else {
            return AgeMapping(status: .unknown, band: nil, assurance: .none, parentalControlsActive: false)
        }

        let lower = signal.lowerBound ?? 0
        let parentalControlsActive = !signal.parentalControls.isEmpty
        let declaration = signal.declaration

        if lower >= 18 {
            let assurance: AgeAssuranceLevel = declaration.map(confirmedDeclarations.contains) == true
                ? .confirmed
                : .selfDeclared
            return AgeMapping(
                status: .adult,
                band: nil,
                assurance: assurance,
                parentalControlsActive: parentalControlsActive
            )
        }

        let band: MinorBand
        if lower < 12 {
            band = .under12
        } else if lower < 16 {
            band = .twelveToFifteen
        } else {
            band = .sixteenToSeventeen
        }

        let assurance: AgeAssuranceLevel
        switch declaration {
        case .some(let value) where confirmedDeclarations.contains(value):
            assurance = .confirmed
        case .some(let value) where value == "guardian_declared" || value.hasPrefix("guardian_"):
            assurance = .guardianDeclared
        case .some("self_declared"):
            assurance = .selfDeclared
        default:
            assurance = .none
        }

        return AgeMapping(
            status: .minor,
            band: band,
            assurance: assurance,
            parentalControlsActive: parentalControlsActive
        )
    }
}

enum AgeRangeRequestError: Error, Equatable {
    case unavailable
}

protocol AgeRangeProviding {
    func requestAgeRange() async throws -> AgeSignal
    func requiredRegulatoryFeatures() async -> [String]?
}

struct UnavailableAgeRangeProvider: AgeRangeProviding {
    func requestAgeRange() async throws -> AgeSignal {
        throw AgeRangeRequestError.unavailable
    }

    func requiredRegulatoryFeatures() async -> [String]? {
        nil
    }
}

#if canImport(DeclaredAgeRange) && canImport(UIKit)
struct DeclaredAgeRangeProvider: AgeRangeProviding {
    @MainActor
    func requestAgeRange() async throws -> AgeSignal {
        guard let presenter = Self.presentingViewController() else {
            throw AgeRangeRequestError.unavailable
        }

        let service = AgeRangeService.shared
        let response: AgeRangeService.Response
        do {
            response = try await service.requestAgeRange(
                ageGates: AgeAssurance.ageGates.0,
                AgeAssurance.ageGates.1,
                AgeAssurance.ageGates.2,
                in: presenter
            )
        } catch {
            throw AgeRangeRequestError.unavailable
        }

        let eligible = try? await service.isEligibleForAgeFeatures
        let regulatory = await requiredRegulatoryFeatures() ?? []

        switch response {
        case .declinedSharing:
            var signal = AgeSignal.declined
            signal.eligibleForAgeFeatures = eligible
            signal.regulatoryFeatures = regulatory
            return signal
        case .sharing(let range):
            return AgeSignal(
                outcome: .sharing,
                declaration: range.ageRangeDeclaration.flatMap(Self.wireDeclaration),
                eligibleForAgeFeatures: eligible,
                lowerBound: range.lowerBound,
                upperBound: range.upperBound,
                parentalControls: Self.wireParentalControls(range.activeParentalControls),
                regulatoryFeatures: regulatory
            )
        @unknown default:
            throw AgeRangeRequestError.unavailable
        }
    }

    func requiredRegulatoryFeatures() async -> [String]? {
        guard let features = try? await AgeRangeService.shared.requiredRegulatoryFeatures else { return nil }
        return features.map(Self.wireRegulatoryFeature).sorted()
    }

    private static func wireDeclaration(
        _ declaration: AgeRangeService.AgeRangeDeclaration
    ) -> String? {
        if #available(iOS 26.5, *), declaration == .confirmed {
            return "confirmed"
        }
        switch declaration {
        case .selfDeclared:
            return "self_declared"
        case .guardianDeclared:
            return "guardian_declared"
        case .checkedByOtherMethod:
            return "checked_by_other_method"
        case .guardianCheckedByOtherMethod:
            return "guardian_checked_by_other_method"
        case .governmentIDChecked:
            return "government_id_checked"
        case .guardianGovernmentIDChecked:
            return "guardian_government_id_checked"
        case .paymentChecked:
            return "payment_checked"
        case .guardianPaymentChecked:
            return "guardian_payment_checked"
        default:
            return nil
        }
    }

    private static func wireParentalControls(_ controls: AgeRangeService.ParentalControls) -> [String] {
        var names: [String] = []
        var remaining = controls.rawValue
        let communication = AgeRangeService.ParentalControls.communicationLimits.rawValue
        if remaining & communication != 0 {
            names.append("communication_limits")
            remaining &= ~communication
        }
        if remaining != 0 {
            names.append("other")
        }
        return names
    }

    private static func wireRegulatoryFeature(_ feature: AgeRangeService.RegulatoryFeature) -> String {
        switch feature {
        case .significantAppChangeRequiresAdultNotification:
            "significant_app_change_requires_adult_notification"
        case .significantAppChangeRequiresParentalConsent:
            "significant_app_change_requires_parental_consent"
        case .declaredAgeRangeRequired:
            "declared_age_range_required"
        @unknown default:
            "declared_age_range_required"
        }
    }

    @MainActor
    private static func presentingViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes
            .flatMap(\.windows)
            .first { $0.isKeyWindow } ?? scenes.first?.windows.first
        var controller = window?.rootViewController
        while let presented = controller?.presentedViewController {
            controller = presented
        }
        return controller
    }
}
#endif

enum AgeCheckPhase: Hashable {
    case idle
    case prompt
    case requesting
    case recording
    case declined
    case appleError
    case attestFailure
}

enum InlineAgeOutcome: Equatable {
    case updated
    case declined
    case appleError
    case attestFailure
    case rejected

    var line: String {
        switch self {
        case .updated: "Faixa atualizada."
        case .declined: "A faixa não foi compartilhada."
        case .appleError: "A Apple não respondeu agora. Tente de novo em instantes."
        case .attestFailure: "Não deu para confirmar este iPhone."
        case .rejected: RemoteRPCErrorCode.ageSignalRejected.userMessage()
        }
    }
}

@MainActor
@Observable
final class AgeCheckCoordinator {
    private(set) var phase: AgeCheckPhase = .idle
    private(set) var isRequestingInline = false
    private(set) var inlineOutcome: InlineAgeOutcome?
    @ObservationIgnored var onRejection: ((String) -> Void)?

    @ObservationIgnored private let provider: any AgeRangeProviding
    @ObservationIgnored private let submitter: any AgeSignalSubmitting
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let privateDataStore: any PrivateLocalDataStoring
    @ObservationIgnored private var settledUserIDs: Set<String> = []
    @ObservationIgnored private var generation: UInt64 = 0

    init(
        provider: any AgeRangeProviding = BackendServices.makeAgeRangeProvider(),
        submitter: any AgeSignalSubmitting = BackendServices.makeAgeSignalSubmitter(),
        defaults: UserDefaults = .standard,
        privateDataStore: any PrivateLocalDataStoring = ProtectedLocalDataStore.shared
    ) {
        self.provider = provider
        self.submitter = submitter
        self.defaults = defaults
        self.privateDataStore = privateDataStore
    }

    // An age share in flight or awaiting an answer holds the root.
    var needsAgeCheck: Bool {
        phase != .idle
    }

    func reset() {
        generation &+= 1
        phase = .idle
        isRequestingInline = false
        inlineOutcome = nil
        settledUserIDs = []
    }

    func evaluate(
        user: AuthUser?,
        age: AgeStatus,
        isVerified: Bool,
        isLocalContext: Bool,
        now: Date = .now
    ) async -> AgeStatus? {
        guard let user else {
            reset()
            return nil
        }
        guard !isLocalContext, !user.isDebugAccount else {
            settledUserIDs.insert(user.id)
            phase = .idle
            return nil
        }
        guard isVerified, !settledUserIDs.contains(user.id), phase == .idle else { return nil }
        if age.hasNoAppleRecord {
            phase = .prompt
            return nil
        }
        let regulatoryChanged = await regulatoryFeaturesChanged(for: user)
        if age.isDueForRecheck(now: now) || regulatoryChanged {
            return await requestAndRecord(for: user)
        }
        settledUserIDs.insert(user.id)
        return nil
    }

    func requestAndRecord(for user: AuthUser) async -> AgeStatus? {
        let token = generation
        phase = .requesting
        let signal: AgeSignal
        do {
            signal = try await provider.requestAgeRange()
        } catch {
            guard token == generation else { return nil }
            phase = .appleError
            return nil
        }
        guard token == generation else { return nil }
        return await record(signal, for: user)
    }

    // A share started from a screen inside the app stays on that screen: routing never sees it, and
    // its outcome is reported where the button was.
    func requestInline(for user: AuthUser) async -> AgeStatus? {
        guard !isRequestingInline, phase == .idle else { return nil }
        let token = generation
        isRequestingInline = true
        inlineOutcome = nil
        defer {
            if token == generation {
                isRequestingInline = false
            }
        }

        let signal: AgeSignal
        do {
            signal = try await provider.requestAgeRange()
        } catch {
            guard token == generation else { return nil }
            inlineOutcome = .appleError
            return nil
        }
        guard token == generation else { return nil }

        do {
            let status = try await submitter.submit(signal, for: user)
            guard token == generation else { return nil }
            storeRegulatoryFeatures(signal.regulatoryFeatures, for: user)
            settledUserIDs.insert(user.id)
            inlineOutcome = signal.outcome == .declined ? .declined : .updated
            return status
        } catch AgeSignalError.rejected(let status) {
            guard token == generation else { return nil }
            settledUserIDs.insert(user.id)
            inlineOutcome = .rejected
            return status
        } catch {
            guard token == generation else { return nil }
            inlineOutcome = .attestFailure
            return nil
        }
    }

    func clearInlineOutcome() {
        inlineOutcome = nil
    }

    func requestPrompt() {
        guard phase == .idle else { return }
        phase = .prompt
    }

    func continueWithout(for user: AuthUser?) {
        if let user {
            settledUserIDs.insert(user.id)
        }
        phase = .idle
    }

    private func record(_ signal: AgeSignal, for user: AuthUser) async -> AgeStatus? {
        let token = generation
        phase = .recording
        do {
            let status = try await submitter.submit(signal, for: user)
            guard token == generation else { return nil }
            storeRegulatoryFeatures(signal.regulatoryFeatures, for: user)
            if signal.outcome == .declined {
                phase = .declined
            } else {
                settledUserIDs.insert(user.id)
                phase = .idle
            }
            return status
        } catch AgeSignalError.rejected(let status) {
            guard token == generation else { return nil }
            settledUserIDs.insert(user.id)
            phase = .idle
            onRejection?(RemoteRPCErrorCode.ageSignalRejected.userMessage())
            return status
        } catch {
            guard token == generation else { return nil }
            phase = .attestFailure
            return nil
        }
    }

    private func regulatoryFeaturesChanged(for user: AuthUser) async -> Bool {
        guard let current = await provider.requiredRegulatoryFeatures() else { return false }
        let stored = PrivateLocalDataAccess.loadString(
            forKey: Self.regulatoryKey(for: user.id),
            ownerScope: PrivateLocalDataScope.ageAssurance(for: user.id),
            store: privateDataStore,
            legacyDefaults: defaults
        )
        guard let stored else {
            storeRegulatoryFeatures(current, for: user)
            return false
        }
        return stored != current.sorted().joined(separator: ",")
    }

    private func storeRegulatoryFeatures(_ features: [String], for user: AuthUser) {
        PrivateLocalDataAccess.writeStringBestEffort(
            features.sorted().joined(separator: ","),
            forKey: Self.regulatoryKey(for: user.id),
            ownerScope: PrivateLocalDataScope.ageAssurance(for: user.id),
            store: privateDataStore,
            legacyDefaults: defaults
        )
    }

    private static func regulatoryKey(for userID: String) -> String {
        "nina.age.regulatoryFeatures.\(userID)"
    }
}

// Postgres writes timestamps with microseconds and an offset, which the default decoder rejects.
enum NinaDateCoding {
    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            guard let date = date(from: value) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Invalid ISO-8601 date"
                )
            }
            return date
        }
        return decoder
    }

    static func date(from value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value) {
            return date
        }
        guard let regex = try? NSRegularExpression(pattern: #"\.(\d{3})\d+"#) else { return nil }
        let range = NSRange(location: 0, length: (value as NSString).length)
        let trimmed = regex.stringByReplacingMatches(in: value, range: range, withTemplate: ".$1")
        return fractional.date(from: trimmed)
    }
}
