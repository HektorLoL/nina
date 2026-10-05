import Foundation

enum HouseholdRole: String, CaseIterable, Identifiable, Codable, Hashable {
    case adult
    case teen
    case child
    case pet
    case assistant
    case unrecognized

    var id: String { rawValue }

    // A role this build cannot read is never an adult: an unknown or missing value holds no adult power.
    init(wireValue: String?) {
        guard let wireValue, let role = HouseholdRole(rawValue: wireValue), role != .unrecognized else {
            self = .unrecognized
            return
        }
        self = role
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(wireValue: try? container.decode(String.self))
    }

    var title: String {
        switch self {
        case .adult: "Adulto"
        case .teen: "Adolescente"
        case .child: "Criança"
        case .pet: "Pet"
        case .assistant: "Nina"
        case .unrecognized: "Pessoa"
        }
    }

    var symbolName: String {
        switch self {
        case .adult: "person.fill"
        case .teen: "figure.stand"
        case .child: "figure.2.and.child.holdinghands"
        case .pet: "pawprint.fill"
        case .assistant: "sparkles"
        case .unrecognized: "person"
        }
    }

    var isMinorRole: Bool {
        self == .child || self == .teen
    }

    // A role this build could not read is never written back as if it were known.
    var wireValue: String {
        self == .unrecognized ? "" : rawValue
    }

    // Only these three ever carry household load; a minor, an unreadable role or Nina never does.
    var isWorkloadCarrier: Bool {
        self == .adult || self == .pet
    }

    static let editorRoles: [HouseholdRole] = [.adult, .teen, .child, .pet]
}

enum MemberTone: String, CaseIterable, Identifiable, Codable, Hashable {
    case mint
    case coral
    case sky
    case amber
    case lavender

    var id: String { rawValue }
}

enum TaskSectionDefaults {
    static let houseTasksID = "house-tasks"
}

struct TaskSection: Identifiable, Codable, Hashable {
    var id: String
    var title: String
    var symbolName: String
    var tone: MemberTone
}

struct FamilyGroup: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var inviteCode: String
    var members: [HouseholdMember]
    var weeklyDigestEnabled: Bool

    init(
        id: UUID = UUID(),
        name: String,
        inviteCode: String,
        members: [HouseholdMember],
        weeklyDigestEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.inviteCode = inviteCode
        self.members = members
        self.weeklyDigestEnabled = weeklyDigestEnabled
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case inviteCode
        case members
        case weeklyDigestEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        inviteCode = try container.decodeIfPresent(String.self, forKey: .inviteCode) ?? ""
        members = try container.decodeIfPresent([HouseholdMember].self, forKey: .members) ?? []
        weeklyDigestEnabled = try container.decodeIfPresent(Bool.self, forKey: .weeklyDigestEnabled) ?? true
    }
}

// The owner's offer of the house to another adult; it changes nothing until that person accepts.
struct HouseOwnershipOffer: Equatable {
    var memberID: UUID
    var offeredBy: String
    var offeredAt: Date
    var expiresAt: Date
}

enum FamilyPermissionRole: String, CaseIterable, Identifiable, Codable, Hashable {
    case owner
    case admin
    case member

    var id: String { rawValue }

    var title: String {
        switch self {
        case .owner: "Titular"
        case .admin: "Administrador"
        case .member: "Participante"
        }
    }

    var summary: String {
        switch self {
        case .owner:
            "Convites, permissões e ajustes da casa."
        case .admin:
            "Aprova entradas, edita e remove participantes."
        case .member:
            "Tarefas, compras e conversa da casa."
        }
    }

    var symbolName: String {
        switch self {
        case .owner: "crown.fill"
        case .admin: "person.badge.key.fill"
        case .member: "person.fill"
        }
    }

    var canManageFamily: Bool {
        self == .owner || self == .admin
    }

    var canChangePermissions: Bool {
        self == .owner
    }
}

enum MemberIdentityState: String, Codable, Hashable {
    case claimed
    case unclaimed
}

struct HouseholdMember: Identifiable, Codable, Hashable {
    var id: UUID
    var userID: String?
    var name: String
    var relationship: String
    var role: HouseholdRole
    var permissionRole: FamilyPermissionRole
    var identityState: MemberIdentityState
    var tone: MemberTone
    var taskCount: Int
    var memoryNote: String
    var birthDate: Date?
    var petSpecies: String
    var petBreed: String
    var minorAccess: MinorAccess?

    init(
        id: UUID = UUID(),
        userID: String? = nil,
        name: String,
        relationship: String,
        role: HouseholdRole,
        permissionRole: FamilyPermissionRole = .member,
        identityState: MemberIdentityState? = nil,
        tone: MemberTone,
        taskCount: Int,
        memoryNote: String,
        birthDate: Date? = nil,
        petSpecies: String = "",
        petBreed: String = "",
        minorAccess: MinorAccess? = nil
    ) {
        self.id = id
        self.userID = userID
        self.name = name
        self.relationship = relationship
        self.role = role
        self.permissionRole = permissionRole
        self.identityState = identityState ?? (userID == nil ? .unclaimed : .claimed)
        self.tone = tone
        self.taskCount = taskCount
        self.memoryNote = memoryNote
        self.birthDate = birthDate
        self.petSpecies = petSpecies
        self.petBreed = petBreed
        self.minorAccess = minorAccess
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case userID
        case name
        case relationship
        case role
        case permissionRole
        case identityState
        case tone
        case taskCount
        case memoryNote
        case birthDate
        case petSpecies
        case petBreed
        case minorAccess
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        userID = try container.decodeIfPresent(String.self, forKey: .userID)
        name = try container.decode(String.self, forKey: .name)
        relationship = try container.decodeIfPresent(String.self, forKey: .relationship) ?? ""
        role = try container.decodeIfPresent(HouseholdRole.self, forKey: .role) ?? .unrecognized
        permissionRole = try container.decodeIfPresent(FamilyPermissionRole.self, forKey: .permissionRole) ?? .member
        identityState = try container.decodeIfPresent(MemberIdentityState.self, forKey: .identityState)
            ?? (userID == nil ? .unclaimed : .claimed)
        tone = try container.decodeIfPresent(MemberTone.self, forKey: .tone) ?? .mint
        taskCount = try container.decodeIfPresent(Int.self, forKey: .taskCount) ?? 0
        memoryNote = try container.decodeIfPresent(String.self, forKey: .memoryNote) ?? ""
        birthDate = try container.decodeIfPresent(Date.self, forKey: .birthDate)
        petSpecies = try container.decodeIfPresent(String.self, forKey: .petSpecies) ?? ""
        petBreed = try container.decodeIfPresent(String.self, forKey: .petBreed) ?? ""
        minorAccess = try container.decodeIfPresent(MinorAccess.self, forKey: .minorAccess)
    }

    var isMinorProfile: Bool {
        role.isMinorRole || minorAccess?.isMinor == true
    }

    var isClaimed: Bool {
        userID != nil || identityState == .claimed
    }
}

struct MinorUsageDay: Codable, Hashable, Identifiable {
    var day: String
    var minutes: Int

    var id: String { day }
}

struct MinorSupervision: Codable, Hashable {
    var band: MinorBand
    var bandSource: AgeBandSource
    var nicknames: [String]
    var alertsEnabled: Bool
    var quietStart: Int
    var quietEnd: Int
    var dailyLimitMinutes: Int?
    var usageTodayMinutes: Int?
    var usageLast7Days: [MinorUsageDay]
    var viewerRelationship: GuardianRelationship?

    private enum CodingKeys: String, CodingKey {
        case band
        case bandSource = "band_source"
        case nicknames
        case alertsEnabled = "alerts_enabled"
        case quietStart = "quiet_start"
        case quietEnd = "quiet_end"
        case dailyLimitMinutes = "daily_limit_minutes"
        case usageTodayMinutes = "usage_today_minutes"
        case usageLast7Days = "usage_last_7_days"
        case viewerRelationship = "viewer_relationship"
    }

    init(
        band: MinorBand,
        bandSource: AgeBandSource = .guardian,
        nicknames: [String] = [],
        alertsEnabled: Bool = true,
        quietStart: Int = MinorSupervisionDefaults.quietStart,
        quietEnd: Int = MinorSupervisionDefaults.quietEnd,
        dailyLimitMinutes: Int? = MinorSupervisionDefaults.dailyLimitMinutes,
        usageTodayMinutes: Int? = nil,
        usageLast7Days: [MinorUsageDay] = [],
        viewerRelationship: GuardianRelationship? = nil
    ) {
        self.band = band
        self.bandSource = bandSource
        self.nicknames = nicknames
        self.alertsEnabled = alertsEnabled
        self.quietStart = quietStart
        self.quietEnd = quietEnd
        self.dailyLimitMinutes = dailyLimitMinutes
        self.usageTodayMinutes = usageTodayMinutes
        self.usageLast7Days = usageLast7Days
        self.viewerRelationship = viewerRelationship
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        band = MinorBand(wireValue: try container.decodeIfPresent(String.self, forKey: .band)) ?? .under12
        bandSource = AgeBandSource(
            rawValue: try container.decodeIfPresent(String.self, forKey: .bandSource) ?? ""
        ) ?? .guardian
        nicknames = try container.decodeIfPresent([String].self, forKey: .nicknames) ?? []
        alertsEnabled = try container.decodeIfPresent(Bool.self, forKey: .alertsEnabled) ?? true
        quietStart = try container.decodeIfPresent(Int.self, forKey: .quietStart)
            ?? MinorSupervisionDefaults.quietStart
        quietEnd = try container.decodeIfPresent(Int.self, forKey: .quietEnd)
            ?? MinorSupervisionDefaults.quietEnd
        dailyLimitMinutes = try container.decodeIfPresent(Int.self, forKey: .dailyLimitMinutes)
        usageTodayMinutes = try container.decodeIfPresent(Int.self, forKey: .usageTodayMinutes)
        usageLast7Days = try container.decodeIfPresent([MinorUsageDay].self, forKey: .usageLast7Days) ?? []
        viewerRelationship = GuardianRelationship(
            rawValue: try container.decodeIfPresent(String.self, forKey: .viewerRelationship) ?? ""
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(band.rawValue, forKey: .band)
        try container.encode(bandSource.rawValue, forKey: .bandSource)
        try container.encode(nicknames, forKey: .nicknames)
        try container.encode(alertsEnabled, forKey: .alertsEnabled)
        try container.encode(quietStart, forKey: .quietStart)
        try container.encode(quietEnd, forKey: .quietEnd)
        try container.encodeIfPresent(dailyLimitMinutes, forKey: .dailyLimitMinutes)
        try container.encodeIfPresent(usageTodayMinutes, forKey: .usageTodayMinutes)
        try container.encode(usageLast7Days, forKey: .usageLast7Days)
        try container.encodeIfPresent(viewerRelationship?.rawValue, forKey: .viewerRelationship)
    }
}

enum MinorSupervisionDefaults {
    static let quietStart = 1_260
    static let quietEnd = 420
    static let dailyLimitMinutes: Int? = 30
    static let dailyLimitChoices: [Int?] = [15, 30, 60, nil]
    static let maximumNicknames = 8
    static let maximumNicknameLength = 40

    static func limitTitle(_ minutes: Int?) -> String {
        switch minutes {
        case .none: "Sem limite"
        case .some(60): "1 hora"
        case .some(let value): "\(value) min"
        }
    }

    static func clockLabel(minutes: Int) -> String {
        let hour = (minutes / 60) % 24
        let minute = minutes % 60
        return minute == 0 ? "\(hour):00" : String(format: "%d:%02d", hour, minute)
    }

    static func quietWindowLabel(start: Int, end: Int) -> String {
        "\(clockLabel(minutes: start)) às \(clockLabel(minutes: end))"
    }

    // A nickname list never grows past what the server accepts.
    static func normalizedNicknames(_ raw: String) -> [String] {
        normalizedNicknames(raw.split(separator: ",").map(String.init))
    }

    static func normalizedNicknames(_ raw: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for value in raw {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed.count <= maximumNicknameLength else { continue }
            let key = trimmed.lowercased()
            guard seen.insert(key).inserted else { continue }
            result.append(trimmed)
            if result.count == maximumNicknames { break }
        }
        return result
    }
}

// Present only on child and teen rows; a band appears only inside supervision, which only a live guardian receives.
struct MinorAccess: Codable, Hashable {
    var isMinor: Bool
    var isClaimed: Bool
    var guardianNames: [String]
    var isViewerGuardian: Bool
    var hasProfileConsent: Bool
    var hasHealthConsent: Bool
    var pendingDeletionAt: Date?
    var supervision: MinorSupervision?

    private enum CodingKeys: String, CodingKey {
        case isMinor = "is_minor"
        case isClaimed = "is_claimed"
        case guardianNames = "guardian_names"
        case isViewerGuardian = "is_viewer_guardian"
        case hasProfileConsent = "has_profile_consent"
        case hasHealthConsent = "has_health_consent"
        case pendingDeletionAt = "pending_deletion_at"
        case supervision
    }

    init(
        isMinor: Bool = true,
        isClaimed: Bool = false,
        guardianNames: [String] = [],
        isViewerGuardian: Bool = false,
        hasProfileConsent: Bool = false,
        hasHealthConsent: Bool = false,
        pendingDeletionAt: Date? = nil,
        supervision: MinorSupervision? = nil
    ) {
        self.isMinor = isMinor
        self.isClaimed = isClaimed
        self.guardianNames = guardianNames
        self.isViewerGuardian = isViewerGuardian
        self.hasProfileConsent = hasProfileConsent
        self.hasHealthConsent = hasHealthConsent
        self.pendingDeletionAt = pendingDeletionAt
        self.supervision = isViewerGuardian ? supervision : nil
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let isViewerGuardian = try container.decodeIfPresent(Bool.self, forKey: .isViewerGuardian) ?? false
        self.init(
            isMinor: try container.decodeIfPresent(Bool.self, forKey: .isMinor) ?? true,
            isClaimed: try container.decodeIfPresent(Bool.self, forKey: .isClaimed) ?? false,
            guardianNames: try container.decodeIfPresent([String].self, forKey: .guardianNames) ?? [],
            isViewerGuardian: isViewerGuardian,
            hasProfileConsent: try container.decodeIfPresent(Bool.self, forKey: .hasProfileConsent) ?? false,
            hasHealthConsent: try container.decodeIfPresent(Bool.self, forKey: .hasHealthConsent) ?? false,
            pendingDeletionAt: try container.decodeIfPresent(Date.self, forKey: .pendingDeletionAt),
            supervision: try container.decodeIfPresent(MinorSupervision.self, forKey: .supervision)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isMinor, forKey: .isMinor)
        try container.encode(isClaimed, forKey: .isClaimed)
        try container.encode(guardianNames, forKey: .guardianNames)
        try container.encode(isViewerGuardian, forKey: .isViewerGuardian)
        try container.encode(hasProfileConsent, forKey: .hasProfileConsent)
        try container.encode(hasHealthConsent, forKey: .hasHealthConsent)
        try container.encodeIfPresent(pendingDeletionAt, forKey: .pendingDeletionAt)
        try container.encodeIfPresent(supervision, forKey: .supervision)
    }

    var hasGuardian: Bool {
        !guardianNames.isEmpty
    }
}

enum FamilyInviteLifecycleStatus: String, Codable, Hashable {
    case active
    case expired
    case exhausted
    case revoked

    var title: String {
        switch self {
        case .active: "Ativo"
        case .expired: "Expirado"
        case .exhausted: "Limite atingido"
        case .revoked: "Revogado"
        }
    }

    var tone: MemberTone {
        switch self {
        case .active: .mint
        case .expired, .exhausted: .amber
        case .revoked: .coral
        }
    }
}

struct FamilyInviteStatus: Codable, Hashable {
    var code: String
    var status: FamilyInviteLifecycleStatus
    var expiresAt: Date
    var maxUses: Int
    var uses: Int
    var usesRemaining: Int

    var isActive: Bool {
        status == .active && usesRemaining > 0 && expiresAt > .now
    }
}

enum FamilyJoinRequestStatus: String, Codable, Hashable {
    case pending
    case approved
    case declined
    case cancelled

    var title: String {
        switch self {
        case .pending: "Aguardando aprovação"
        case .approved: "Aprovado"
        case .declined: "Recusado"
        case .cancelled: "Cancelado"
        }
    }
}

enum JoinRequesterAge: Hashable {
    case adult
    case minor(MinorBand)
    case unknown

    init(status: String?, band: String?) {
        switch status {
        case "adult":
            self = .adult
        case "minor":
            self = .minor(MinorBand(wireValue: band) ?? .under12)
        default:
            self = .unknown
        }
    }

    var tag: String {
        switch self {
        case .adult: "Maior de idade"
        case .minor(let band): band.requesterTag
        case .unknown: "Idade não informada"
        }
    }

    var isAdult: Bool {
        self == .adult
    }

    // The band Apple reported caps what a guardian may choose; an unknown requester has no cap and no preselection.
    var appleBand: MinorBand? {
        if case .minor(let band) = self { return band }
        return nil
    }
}

struct FamilyJoinRequest: Identifiable, Hashable {
    var id: UUID
    var familyID: UUID
    var familyName: String
    var requesterUserID: UUID
    var requesterName: String
    var status: FamilyJoinRequestStatus
    var createdAt: Date
    var reviewedAt: Date?
    var requesterAge: JoinRequesterAge = .unknown
}

enum FamilyAccessOutcome: String, Hashable {
    case declined
    case removed
}

// get_family_access_decision never returns who decided, so this model has nowhere to put it.
struct FamilyAccessDecision: Identifiable, Decodable, Hashable {
    var id: UUID
    var familyName: String
    var outcome: FamilyAccessOutcome
    var decidedAt: Date

    private enum CodingKeys: String, CodingKey {
        case id
        case familyName = "family_name"
        case outcome
        case decidedAt = "decided_at"
    }

    init(id: UUID, familyName: String, outcome: FamilyAccessOutcome, decidedAt: Date) {
        self.id = id
        self.familyName = familyName
        self.outcome = outcome
        self.decidedAt = decidedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        familyName = try container.decodeIfPresent(String.self, forKey: .familyName) ?? ""
        let rawOutcome = try container.decodeIfPresent(String.self, forKey: .outcome)
        outcome = rawOutcome.flatMap(FamilyAccessOutcome.init(rawValue:)) ?? .declined
        decidedAt = try container.decodeIfPresent(Date.self, forKey: .decidedAt) ?? .now
    }
}

struct TaskCategory: Identifiable, Codable, Hashable, CaseIterable {
    var id: String
    var title: String
    var symbolName: String
    var tone: MemberTone

    // Outline glyphs, never filled: category is a glyph and colour is spent on
    // lateness alone, so the drawing has to carry the whole distinction.
    static let home = TaskCategory(id: "home", title: "Casa", symbolName: "house", tone: .mint)
    static let bills = TaskCategory(id: "bills", title: "Contas", symbolName: "creditcard", tone: .sky)
    static let health = TaskCategory(id: "health", title: "Saúde", symbolName: "cross.case", tone: .coral)
    static let school = TaskCategory(id: "school", title: "Escola", symbolName: "backpack", tone: .amber)
    static let pet = TaskCategory(id: "pet", title: "Pet", symbolName: "pawprint", tone: .lavender)
    static let food = TaskCategory(id: "food", title: "Comida", symbolName: "fork.knife", tone: .mint)
    // The six above are a taxonomy of logistics. Cuidado names the labour the
    // product most wants to make visible: remembering, scheduling, following up.
    static let care = TaskCategory(id: "care", title: "Cuidado", symbolName: "heart", tone: .coral)

    static let allCases: [TaskCategory] = [.home, .bills, .health, .school, .pet, .food, .care]

    static func custom(id: String, title: String, tone: MemberTone) -> TaskCategory {
        TaskCategory(id: id, title: title, symbolName: "tag", tone: tone)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case symbolName
        case tone
    }

    init(id: String, title: String, symbolName: String, tone: MemberTone) {
        self.id = id
        self.title = title
        self.symbolName = symbolName
        self.tone = tone
    }

    init(from decoder: Decoder) throws {
        if let rawValue = try? decoder.singleValueContainer().decode(String.self) {
            self = Self.allCases.first { $0.id == rawValue } ?? TaskCategory.custom(
                id: rawValue,
                title: rawValue.capitalized,
                tone: .lavender
            )
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        symbolName = try container.decodeIfPresent(String.self, forKey: .symbolName) ?? "tag.fill"
        tone = try container.decodeIfPresent(MemberTone.self, forKey: .tone) ?? .lavender
    }

    func encode(to encoder: Encoder) throws {
        if Self.allCases.contains(where: { $0.id == id }) {
            var container = encoder.singleValueContainer()
            try container.encode(id)
            return
        }

        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(symbolName, forKey: .symbolName)
        try container.encode(tone, forKey: .tone)
    }
}

enum TaskPriority: String, CaseIterable, Identifiable, Codable, Hashable {
    case normal
    case high
    case urgent

    var id: String { rawValue }

    var title: String {
        switch self {
        case .normal: "Normal"
        case .high: "Alta"
        case .urgent: "Urgente"
        }
    }

    var symbolName: String {
        switch self {
        case .normal: "minus.circle.fill"
        case .high: "exclamationmark.circle.fill"
        case .urgent: "exclamationmark.triangle.fill"
        }
    }

    var tone: MemberTone {
        switch self {
        case .normal: .mint
        case .high: .amber
        case .urgent: .coral
        }
    }

    var sortRank: Int {
        switch self {
        case .normal: 0
        case .high: 1
        case .urgent: 2
        }
    }
}

enum TaskRecurrence: String, CaseIterable, Identifiable, Codable, Hashable {
    case none
    case daily
    case weekly
    case monthly
    case yearly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: "Não repetir"
        case .daily: "Todos os dias"
        case .weekly: "Toda semana"
        case .monthly: "Todo mês"
        case .yearly: "Todo ano"
        }
    }

    var shortTitle: String {
        switch self {
        case .none: "Uma vez"
        case .daily: "Diário"
        case .weekly: "Semanal"
        case .monthly: "Mensal"
        case .yearly: "Anual"
        }
    }
}

// The raw values are the closed set tasks_remind_offset_minutes_check accepts; a value outside it
// is rejected by the database, so nothing on the client may invent one.
enum TaskReminderLead: Int, CaseIterable, Identifiable, Codable, Hashable {
    case atTime = 0
    case fiveMinutes = 5
    case tenMinutes = 10
    case fifteenMinutes = 15
    case thirtyMinutes = 30
    case oneHour = 60
    case twoHours = 120
    case oneDay = 1440

    static let editorOptions: [TaskReminderLead] = [
        .atTime,
        .fiveMinutes,
        .thirtyMinutes,
        .oneHour,
        .oneDay
    ]

    init(minutes: Int) {
        self = TaskReminderLead(rawValue: minutes) ?? .atTime
    }

    var id: Int { rawValue }

    var minutes: Int { rawValue }

    var title: String {
        switch self {
        case .atTime: "Na hora"
        case .fiveMinutes: "5 minutos antes"
        case .tenMinutes: "10 minutos antes"
        case .fifteenMinutes: "15 minutos antes"
        case .thirtyMinutes: "30 minutos antes"
        case .oneHour: "1 hora antes"
        case .twoHours: "2 horas antes"
        case .oneDay: "1 dia antes"
        }
    }
}

enum TaskKind: String, CaseIterable, Identifiable, Codable, Hashable {
    case task
    case seed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .task: "Tarefa"
        case .seed: "Semente"
        }
    }

    var symbolName: String {
        switch self {
        case .task: "checkmark.circle.fill"
        case .seed: "leaf.fill"
        }
    }
}

struct TaskItem: Identifiable, Codable, Hashable {
    var id: UUID
    var kind: TaskKind
    var title: String
    var subtitle: String
    var owner: String
    var ownerMemberID: UUID?
    var dueLabel: String
    var dueAt: Date?
    var category: TaskCategory
    var priority: TaskPriority
    var recurrence: TaskRecurrence
    var remindOffsetMinutes: Int
    var snoozedUntil: Date?
    var isDone: Bool
    var completedAt: Date?
    var createdBy: String
    var sectionID: String
    var version: Int

    init(
        id: UUID = UUID(),
        kind: TaskKind = .task,
        title: String,
        subtitle: String,
        owner: String,
        ownerMemberID: UUID? = nil,
        dueLabel: String,
        dueAt: Date? = nil,
        category: TaskCategory,
        priority: TaskPriority = .normal,
        recurrence: TaskRecurrence = .none,
        reminderLead: TaskReminderLead = .atTime,
        snoozedUntil: Date? = nil,
        isDone: Bool,
        completedAt: Date? = nil,
        createdBy: String,
        sectionID: String = TaskSectionDefaults.houseTasksID,
        version: Int = 1
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.owner = owner
        self.ownerMemberID = ownerMemberID
        self.dueLabel = dueLabel
        self.dueAt = dueAt
        self.category = category
        self.priority = priority
        self.recurrence = recurrence
        remindOffsetMinutes = reminderLead.minutes
        self.snoozedUntil = snoozedUntil
        self.isDone = isDone
        self.completedAt = completedAt
        self.createdBy = createdBy
        self.sectionID = sectionID
        self.version = version
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case kind
        case title
        case subtitle
        case owner
        case ownerMemberID
        case dueLabel
        case dueAt
        case category
        case priority
        case recurrence
        case remindOffsetMinutes
        case snoozedUntil
        case isDone
        case completedAt
        case createdBy
        case sectionID
        case version
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind = try container.decodeIfPresent(TaskKind.self, forKey: .kind) ?? .task
        title = try container.decode(String.self, forKey: .title)
        subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle) ?? ""
        owner = try container.decodeIfPresent(String.self, forKey: .owner) ?? "Casa"
        ownerMemberID = try container.decodeIfPresent(UUID.self, forKey: .ownerMemberID) ?? nil
        dueLabel = try container.decodeIfPresent(String.self, forKey: .dueLabel) ?? "Sem data"
        dueAt = try container.decodeIfPresent(Date.self, forKey: .dueAt)
        category = try container.decodeIfPresent(TaskCategory.self, forKey: .category) ?? .home
        priority = try container.decodeIfPresent(TaskPriority.self, forKey: .priority) ?? .normal
        recurrence = try container.decodeIfPresent(TaskRecurrence.self, forKey: .recurrence) ?? .none
        remindOffsetMinutes = TaskReminderLead(
            minutes: try container.decodeIfPresent(Int.self, forKey: .remindOffsetMinutes) ?? 0
        ).minutes
        snoozedUntil = try container.decodeIfPresent(Date.self, forKey: .snoozedUntil)
        isDone = try container.decodeIfPresent(Bool.self, forKey: .isDone) ?? false
        completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
        createdBy = try container.decodeIfPresent(String.self, forKey: .createdBy) ?? "Manual"
        sectionID = try container.decodeIfPresent(String.self, forKey: .sectionID) ?? TaskSectionDefaults.houseTasksID
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
    }

    // A missed occurrence of a repeating task stays late until a person marks it; only a task
    // that is current shows its next occurrence.
    func displayDate(
        relativeTo referenceDate: Date = .now,
        calendar: Calendar = .current
    ) -> Date? {
        if let snoozedUntil, snoozedUntil > referenceDate {
            return snoozedUntil
        }

        guard recurrence != .none, let dueAt else { return effectiveDueDate }
        guard dueAt <= referenceDate else { return dueAt }

        return latestOccurrence(onOrBefore: referenceDate, calendar: calendar) ?? dueAt
    }

    var effectiveDueDate: Date? {
        snoozedUntil ?? dueAt
    }

    var reminderLead: TaskReminderLead {
        get { TaskReminderLead(minutes: remindOffsetMinutes) }
        set { remindOffsetMinutes = newValue.minutes }
    }

    func isDue(
        on date: Date,
        calendar: Calendar = .current
    ) -> Bool {
        guard !isDone,
              let displayDate = displayDate(relativeTo: date, calendar: calendar) else {
            return false
        }
        return calendar.isDate(displayDate, inSameDayAs: date)
    }

    // A repeating task is never closed by one tap: the label must promise the
    // roll-forward that toggleTask performs, not a completion it never records.
    var completionActionTitle: String {
        if isDone { return "Reabrir" }
        return recurrence == .none ? "Marcar como feita" : "Feita por hoje"
    }

    // A label the date reader could not place books no reminder, and the task must say so
    // wherever its label reads like a date.
    var namesADayWithoutAReminder: Bool {
        guard kind == .task, !isDone, dueAt == nil, snoozedUntil == nil else { return false }
        let label = dueLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        return !label.isEmpty && label.caseInsensitiveCompare("Sem data") != .orderedSame
    }

    /// The label to draw. `dueLabel` is stored at write time and never recomputed,
    /// so a snoozed or recurring task keeps showing the date it used to have —
    /// while lateness colour is computed from `displayDate`. Both must agree.
    func effectiveDueLabel(
        relativeTo referenceDate: Date = .now,
        calendar: Calendar = .current
    ) -> String {
        guard kind == .task,
              let date = displayDate(relativeTo: referenceDate, calendar: calendar) else {
            return dueLabel
        }
        return AppStore.taskDueLabel(for: date, relativeTo: referenceDate, calendar: calendar)
    }

    func isOverdue(
        relativeTo referenceDate: Date = .now,
        calendar: Calendar = .current
    ) -> Bool {
        guard !isDone,
              let displayDate = displayDate(relativeTo: referenceDate, calendar: calendar) else {
            return false
        }
        return displayDate < referenceDate
    }

    /// Due today or already past — the set a daily agenda must never drop.
    func belongsOnAgenda(
        for referenceDate: Date = .now,
        calendar: Calendar = .current
    ) -> Bool {
        guard !isDone, kind == .task,
              let displayDate = displayDate(relativeTo: referenceDate, calendar: calendar) else {
            return false
        }

        guard let endOfDay = calendar.date(
            byAdding: .day,
            value: 1,
            to: calendar.startOfDay(for: referenceDate)
        ) else {
            return calendar.isDate(displayDate, inSameDayAs: referenceDate)
        }

        return displayDate < endOfDay
    }

    func scheduledOccurrence(
        after referenceDate: Date,
        calendar: Calendar = .current
    ) -> Date? {
        guard let dueAt else { return nil }
        guard let components = recurrenceComponents(calendar: calendar) else { return dueAt }
        guard dueAt <= referenceDate else { return dueAt }

        return calendar.nextDate(
            after: referenceDate,
            matching: components,
            matchingPolicy: .nextTimePreservingSmallerComponents,
            repeatedTimePolicy: .first,
            direction: .forward
        )
    }

    private func latestOccurrence(
        onOrBefore referenceDate: Date,
        calendar: Calendar
    ) -> Date? {
        guard let dueAt, dueAt <= referenceDate,
              let components = recurrenceComponents(calendar: calendar),
              let occurrence = calendar.nextDate(
                  after: referenceDate.addingTimeInterval(1),
                  matching: components,
                  matchingPolicy: .previousTimePreservingSmallerComponents,
                  repeatedTimePolicy: .first,
                  direction: .backward
              ),
              occurrence <= referenceDate else {
            return nil
        }
        return max(occurrence, dueAt)
    }

    private func recurrenceComponents(calendar: Calendar) -> DateComponents? {
        guard let dueAt else { return nil }
        switch recurrence {
        case .none:
            return nil
        case .daily:
            return calendar.dateComponents([.hour, .minute], from: dueAt)
        case .weekly:
            return calendar.dateComponents([.weekday, .hour, .minute], from: dueAt)
        case .monthly:
            return calendar.dateComponents([.day, .hour, .minute], from: dueAt)
        case .yearly:
            return calendar.dateComponents([.month, .day, .hour, .minute], from: dueAt)
        }
    }

    func scheduledOccurrences(
        after referenceDate: Date,
        limit: Int,
        calendar: Calendar = .current
    ) -> [Date] {
        guard limit > 0 else { return [] }
        guard recurrence != .none else {
            guard let dueAt, dueAt > referenceDate else { return [] }
            return [dueAt]
        }

        var dates: [Date] = []
        var cursor = referenceDate

        while dates.count < limit,
              let nextDate = scheduledOccurrence(after: cursor, calendar: calendar) {
            guard nextDate > cursor else { break }
            dates.append(nextDate)
            cursor = nextDate.addingTimeInterval(1)
        }

        return dates
    }
}

struct ShoppingItem: Identifiable, Codable, Hashable {
    var id: UUID
    var title: String
    var amount: String
    var owner: String
    var ownerMemberID: UUID?
    var isChecked: Bool

    init(
        id: UUID = UUID(),
        title: String,
        amount: String,
        owner: String,
        ownerMemberID: UUID? = nil,
        isChecked: Bool
    ) {
        self.id = id
        self.title = title
        self.amount = amount
        self.owner = owner
        self.ownerMemberID = ownerMemberID
        self.isChecked = isChecked
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case amount
        case owner
        case ownerMemberID
        case isChecked
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try container.decode(String.self, forKey: .title)
        amount = try container.decodeIfPresent(String.self, forKey: .amount) ?? ""
        owner = try container.decodeIfPresent(String.self, forKey: .owner) ?? "Casa"
        ownerMemberID = try container.decodeIfPresent(UUID.self, forKey: .ownerMemberID) ?? nil
        isChecked = try container.decodeIfPresent(Bool.self, forKey: .isChecked) ?? false
    }
}

enum MessageSender: String, Codable, Hashable {
    case user
    case nina
}

enum ChatAttachmentKind: String, Codable, Hashable {
    case image
    case document
}

struct ChatAttachment: Identifiable, Codable, Hashable {
    var id: UUID
    var kind: ChatAttachmentKind
    var filename: String
    var mimeType: String
    var byteCount: Int
    var thumbnailData: Data?

    private enum CodingKeys: String, CodingKey {
        case id
        case kind
        case filename
        case mimeType = "mime_type"
        case byteCount = "byte_count"
        case thumbnailData = "thumbnail_data"
    }

    private enum LocalCacheCodingKeys: String, CodingKey {
        case mimeType
        case byteCount
        case thumbnailData
    }

    init(
        id: UUID = UUID(),
        kind: ChatAttachmentKind,
        filename: String,
        mimeType: String,
        byteCount: Int,
        thumbnailData: Data? = nil
    ) {
        self.id = id
        self.kind = kind
        self.filename = filename
        self.mimeType = mimeType
        self.byteCount = byteCount
        self.thumbnailData = thumbnailData
    }

    // Server rows carry only {kind, filename, mime_type, byte_count}; a required field here would
    // fail the whole household snapshot and lock the user out of their home.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let cached = try? decoder.container(keyedBy: LocalCacheCodingKeys.self)

        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind = ChatAttachmentKind(
            rawValue: try container.decodeIfPresent(String.self, forKey: .kind) ?? ""
        ) ?? .document
        filename = try container.decodeIfPresent(String.self, forKey: .filename) ?? "Anexo"
        mimeType = try container.decodeIfPresent(String.self, forKey: .mimeType)
            ?? (cached.flatMap { try? $0.decodeIfPresent(String.self, forKey: .mimeType) } ?? nil)
            ?? ""
        byteCount = try container.decodeIfPresent(Int.self, forKey: .byteCount)
            ?? (cached.flatMap { try? $0.decodeIfPresent(Int.self, forKey: .byteCount) } ?? nil)
            ?? 0
        thumbnailData = try container.decodeIfPresent(Data.self, forKey: .thumbnailData)
            ?? (cached.flatMap { try? $0.decodeIfPresent(Data.self, forKey: .thumbnailData) } ?? nil)
    }
}

enum NinaSuggestionKind: String, Codable, Hashable {
    case task
    case seed
    case reminder
    case gift
    case document
    case redistribution
}

struct NinaSuggestion: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var detail: String
    var actionTitle: String
    var kind: NinaSuggestionKind
    var payloadTitle: String
    var payloadDetail: String
    var payloadOwner: String
    var payloadDueLabel: String
    var category: TaskCategory
    var symbolName: String
}

struct NinaThread: Identifiable, Codable, Hashable {
    var id: UUID
    var familyID: UUID
    var ownerUserID: UUID

    private enum CodingKeys: String, CodingKey {
        case id
        case familyID = "family_id"
        case ownerUserID = "owner_user_id"
    }
}

enum NinaProposalKind: String, Codable, Hashable {
    case task
    case reminder
    case shopping
    case memory
    case seed
}

enum NinaProposalState: String, Codable, Hashable {
    case pending
    case accepted
    case rejected
}

enum NinaMemoryVisibility: String, Codable, CaseIterable, Hashable {
    case privateMemory = "private"
    case shared

    var title: String {
        switch self {
        case .privateMemory: "Só para mim"
        case .shared: "Compartilhada"
        }
    }
}

enum NinaProposalSource: String, Codable, Hashable {
    case message = "mensagem"
    case attachment = "anexo"
    case existingTask = "tarefa_existente"
    case memory = "memoria"
    case routine = "rotina"

    var title: String {
        switch self {
        case .message: "Da conversa"
        case .attachment: "Do anexo"
        case .existingTask: "De uma tarefa"
        case .memory: "De uma memória"
        case .routine: "Da rotina"
        }
    }

    var symbolName: String {
        switch self {
        case .message: "bubble.left.fill"
        case .attachment: "paperclip"
        case .existingTask: "checklist"
        case .memory: "brain.head.profile"
        case .routine: "repeat"
        }
    }

    var tone: MemberTone {
        switch self {
        case .message: .mint
        case .attachment: .sky
        case .existingTask: .amber
        case .memory, .routine: .lavender
        }
    }
}

struct NinaExtractedReading: Codable, Hashable {
    var label: String
    var value: String

    private enum CodingKeys: String, CodingKey {
        case label
        case value
    }

    init(label: String, value: String) {
        self.label = label
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        label = (try container.decodeIfPresent(String.self, forKey: .label) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        value = (try container.decodeIfPresent(String.self, forKey: .value) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct NinaProposalPayload: Codable, Hashable {
    var title: String
    var detail: String
    var owner: String
    var dueLabel: String
    var dueAt: String?
    var categoryID: String
    var symbolName: String
    var amount: String
    var extracted: [NinaExtractedReading]
    var rationale: String
    var source: NinaProposalSource?
    var visibility: NinaMemoryVisibility?
    var confidence: Double?
    var deduplicationKey: String

    private enum CodingKeys: String, CodingKey {
        case title
        case detail
        case owner
        case dueLabel = "due_label"
        case dueAt = "due_at"
        case categoryID = "category"
        case symbolName = "symbol_name"
        case amount
        case extracted
        case rationale
        case source
        case visibility
        case confidence
        case deduplicationKey = "deduplication_key"
    }

    init(
        title: String,
        detail: String,
        owner: String = "Casa",
        dueLabel: String = "Sem data",
        dueAt: String? = nil,
        categoryID: String = TaskCategory.home.id,
        symbolName: String = "sparkles",
        amount: String = "",
        extracted: [NinaExtractedReading] = [],
        rationale: String = "",
        source: NinaProposalSource? = nil,
        visibility: NinaMemoryVisibility? = nil,
        confidence: Double? = nil,
        deduplicationKey: String = ""
    ) {
        self.title = title
        self.detail = detail
        self.owner = owner
        self.dueLabel = dueLabel
        self.dueAt = dueAt
        self.categoryID = categoryID
        self.symbolName = symbolName
        self.amount = amount
        self.extracted = extracted
        self.rationale = rationale
        self.source = source
        self.visibility = visibility
        self.confidence = confidence
        self.deduplicationKey = deduplicationKey
    }

    // Shares the household snapshot decode path with ChatAttachment: a required field here would
    // turn one malformed proposal into a total loss of home access.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        detail = try container.decodeIfPresent(String.self, forKey: .detail) ?? ""
        owner = try container.decodeIfPresent(String.self, forKey: .owner) ?? "Casa"
        dueLabel = try container.decodeIfPresent(String.self, forKey: .dueLabel) ?? "Sem data"
        dueAt = try container.decodeIfPresent(String.self, forKey: .dueAt)
        categoryID = try container.decodeIfPresent(String.self, forKey: .categoryID) ?? TaskCategory.home.id
        symbolName = try container.decodeIfPresent(String.self, forKey: .symbolName) ?? "sparkles"
        amount = try container.decodeIfPresent(String.self, forKey: .amount) ?? ""
        // A half-read line is not something the card may present as what Nina read off the document.
        extracted = (try container.decodeIfPresent([NinaExtractedReading].self, forKey: .extracted) ?? [])
            .filter { !$0.label.isEmpty && !$0.value.isEmpty }
        rationale = (try container.decodeIfPresent(String.self, forKey: .rationale) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        source = NinaProposalSource(
            rawValue: try container.decodeIfPresent(String.self, forKey: .source) ?? ""
        )
        visibility = NinaMemoryVisibility(
            rawValue: try container.decodeIfPresent(String.self, forKey: .visibility) ?? ""
        )
        confidence = try container.decodeIfPresent(Double.self, forKey: .confidence)
        deduplicationKey = try container.decodeIfPresent(String.self, forKey: .deduplicationKey) ?? ""
    }

    // due_at is always written, so an undated confirmation overrides the date stored with the proposal.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(title, forKey: .title)
        try container.encode(detail, forKey: .detail)
        try container.encode(owner, forKey: .owner)
        try container.encode(dueLabel, forKey: .dueLabel)
        try container.encode(dueAt, forKey: .dueAt)
        try container.encode(categoryID, forKey: .categoryID)
        try container.encode(symbolName, forKey: .symbolName)
        try container.encode(amount, forKey: .amount)
        try container.encode(extracted, forKey: .extracted)
        try container.encode(rationale, forKey: .rationale)
        try container.encodeIfPresent(source, forKey: .source)
        try container.encodeIfPresent(visibility, forKey: .visibility)
        try container.encodeIfPresent(confidence, forKey: .confidence)
        try container.encode(deduplicationKey, forKey: .deduplicationKey)
    }

    var category: TaskCategory {
        TaskCategory.allCases.first(where: { $0.id == categoryID })
            ?? .custom(id: categoryID, title: categoryID.capitalized, tone: .lavender)
    }

    private static let dueAtFormatter = ISO8601DateFormatter()

    private static let fractionalDueAtFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let minuteDueAtFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mmXXXXX"
        return formatter
    }()

    var scheduledDate: Date? {
        guard let dueAt else { return nil }
        return Self.dueAtFormatter.date(from: dueAt)
            ?? Self.fractionalDueAtFormatter.date(from: dueAt)
            ?? Self.minuteDueAtFormatter.date(from: dueAt)
    }

    // Confirming a corrected label has to move the scheduled date with it, and a correction
    // Nina cannot parse lands undated rather than keeping the date she originally proposed.
    func edited(
        title: String,
        detail: String,
        owner: String,
        dueLabel: String,
        amount: String,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> NinaProposalPayload {
        var result = self
        result.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        result.detail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        result.owner = owner.trimmingCharacters(in: .whitespacesAndNewlines)
        result.amount = amount.trimmingCharacters(in: .whitespacesAndNewlines)

        let trimmedDueLabel = dueLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedDueLabel != self.dueLabel {
            result.dueAt = AppStore.inferredDueAt(from: trimmedDueLabel, now: now, calendar: calendar)
                .map(Self.dueAtFormatter.string(from:))
        }
        result.dueLabel = trimmedDueLabel

        return result
    }

    func datedFromLabelIfUndated(now: Date = .now, calendar: Calendar = .current) -> NinaProposalPayload {
        guard scheduledDate == nil else { return self }
        var result = self
        result.dueAt = AppStore.inferredDueAt(from: dueLabel, now: now, calendar: calendar)
            .map(Self.dueAtFormatter.string(from:))
        return result
    }
}

struct NinaProposal: Identifiable, Codable, Hashable {
    var id: UUID
    var kind: NinaProposalKind
    var state: NinaProposalState
    var title: String
    var detail: String
    var actionTitle: String
    var payload: NinaProposalPayload
    var allowedMemoryVisibilities: [NinaMemoryVisibility]

    private enum CodingKeys: String, CodingKey {
        case id
        case kind
        case state
        case title
        case detail
        case actionTitle = "action_title"
        case payload
        case allowedMemoryVisibilities = "allowed_memory_visibilities"
    }

    init(
        id: UUID = UUID(),
        kind: NinaProposalKind,
        state: NinaProposalState = .pending,
        title: String,
        detail: String,
        actionTitle: String,
        payload: NinaProposalPayload,
        allowedMemoryVisibilities: [NinaMemoryVisibility] = []
    ) {
        self.id = id
        self.kind = kind
        self.state = state
        self.title = title
        self.detail = detail
        self.actionTitle = actionTitle
        self.payload = payload
        self.allowedMemoryVisibilities = allowedMemoryVisibilities
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind = NinaProposalKind(
            rawValue: try container.decodeIfPresent(String.self, forKey: .kind) ?? ""
        ) ?? .task
        state = try container.decodeIfPresent(NinaProposalState.self, forKey: .state) ?? .pending
        title = try container.decode(String.self, forKey: .title)
        detail = try container.decodeIfPresent(String.self, forKey: .detail) ?? ""
        actionTitle = try container.decodeIfPresent(String.self, forKey: .actionTitle) ?? "Confirmar"
        payload = try container.decode(NinaProposalPayload.self, forKey: .payload)
        allowedMemoryVisibilities = try container.decodeIfPresent(
            [NinaMemoryVisibility].self,
            forKey: .allowedMemoryVisibilities
        ) ?? []
    }

    var confirmationPayload: NinaProposalPayload {
        confirmationPayload(
            title: payload.title,
            detail: payload.detail,
            owner: payload.owner,
            dueLabel: payload.dueLabel,
            amount: payload.amount
        )
    }

    // The card renders this payload and confirming sends this same payload, so the wording that was
    // approved is the wording that gets created; the blank fallbacks and the undated semente mirror
    // resolve_nina_proposal.
    func confirmationPayload(
        title: String,
        detail: String,
        owner: String,
        dueLabel: String,
        amount: String,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> NinaProposalPayload {
        var resolved = payload.edited(
            title: title,
            detail: detail,
            owner: owner,
            dueLabel: dueLabel,
            amount: amount,
            now: now,
            calendar: calendar
        )
        if resolved.title.isEmpty {
            resolved.title = self.title
        }
        if resolved.detail.isEmpty {
            resolved.detail = self.detail
        }
        if resolved.owner.isEmpty {
            resolved.owner = "Casa"
        }
        if resolved.dueLabel.isEmpty {
            resolved.dueLabel = "Sem data"
        }
        if kind == .seed {
            resolved.dueLabel = "Sem data"
            resolved.dueAt = nil
        } else if kind == .task || kind == .reminder {
            // A label that names a day never confirms undated: the card shows, and the server books, that day.
            resolved = resolved.datedFromLabelIfUndated(now: now, calendar: calendar)
        }
        return resolved
    }
}

struct NinaMemory: Identifiable, Codable, Hashable {
    var id: UUID
    var familyID: UUID
    var ownerUserID: UUID?
    var title: String
    var body: String
    var visibility: NinaMemoryVisibility
    var confidence: Double
    var createdAt: Date
    var updatedAt: Date

    private enum CodingKeys: String, CodingKey {
        case id
        case familyID = "family_id"
        case ownerUserID = "owner_user_id"
        case title
        case body
        case visibility
        case confidence
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct ChatMessage: Identifiable, Codable, Hashable {
    var id: UUID
    var sender: MessageSender
    var text: String
    var timestamp: Date
    var suggestion: NinaSuggestion?
    var proposals: [NinaProposal]
    var hasWithheldProposals: Bool
    var attachments: [ChatAttachment]

    init(
        id: UUID = UUID(),
        sender: MessageSender,
        text: String,
        timestamp: Date,
        suggestion: NinaSuggestion? = nil,
        proposals: [NinaProposal] = [],
        hasWithheldProposals: Bool = false,
        attachments: [ChatAttachment] = []
    ) {
        self.id = id
        self.sender = sender
        self.text = text
        self.timestamp = timestamp
        self.suggestion = suggestion
        self.proposals = proposals
        self.hasWithheldProposals = hasWithheldProposals
        self.attachments = attachments
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case sender
        case text
        case timestamp
        case suggestion
        case proposals
        case hasWithheldProposals
        case attachments
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        sender = try container.decode(MessageSender.self, forKey: .sender)
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        timestamp = try container.decodeIfPresent(Date.self, forKey: .timestamp) ?? .now
        suggestion = try container.decodeIfPresent(NinaSuggestion.self, forKey: .suggestion)
        proposals = try container.decodeIfPresent([NinaProposal].self, forKey: .proposals) ?? []
        hasWithheldProposals = try container.decodeIfPresent(
            Bool.self,
            forKey: .hasWithheldProposals
        ) ?? false
        attachments = try container.decodeIfPresent([ChatAttachment].self, forKey: .attachments) ?? []
    }
}

struct HouseholdInsight: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var message: String
    var metric: String
    var symbolName: String
    var tone: MemberTone
    var periodStart: Date? = nil

    // The week is the São Paulo date the server computed, so it never drifts with the phone's zone.
    static func periodStart(fromServerDate value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "America/Sao_Paulo")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: String(value.prefix(10)))
    }

    var weekLabel: String? {
        guard let periodStart else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.timeZone = TimeZone(identifier: "America/Sao_Paulo")
        formatter.dateFormat = "d 'de' MMMM"
        return "Semana de \(formatter.string(from: periodStart))"
    }
}

struct HouseholdPremium: Decodable, Hashable {
    var isActive: Bool
    var status: PremiumSubscriptionStatus
    var expiresAt: Date?

    static let inactive = HouseholdPremium(isActive: false, status: .inactive, expiresAt: nil)

    private enum CodingKeys: String, CodingKey {
        case isActive = "is_active"
        case status
        case expiresAt = "expires_at"
    }

    init(isActive: Bool, status: PremiumSubscriptionStatus, expiresAt: Date?) {
        self.isActive = isActive
        self.status = status
        self.expiresAt = expiresAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isActive = try container.decodeIfPresent(Bool.self, forKey: .isActive) ?? false
        let rawStatus = try container.decodeIfPresent(String.self, forKey: .status) ?? ""
        status = PremiumSubscriptionStatus(rawValue: rawStatus) ?? .inactive
        expiresAt = try container.decodeIfPresent(Date.self, forKey: .expiresAt)
    }
}

struct NinaAIConsent: Decodable, Hashable {
    var isGranted: Bool
    var policyVersion: String?
    var acceptedAt: Date?
    var transferConsented: Bool
    var isCurrent: Bool
    var currentPolicyVersion: String?
    var lastRevokeReason: String?

    static let withheld = NinaAIConsent(isGranted: false, policyVersion: nil, acceptedAt: nil)

    private enum CodingKeys: String, CodingKey {
        case isGranted = "is_granted"
        case policyVersion = "policy_version"
        case acceptedAt = "accepted_at"
        case transferConsented = "transfer_consented"
        case isCurrent = "is_current"
        case currentPolicyVersion = "current_policy_version"
        case lastRevokeReason = "last_revoke_reason"
    }

    init(
        isGranted: Bool,
        policyVersion: String?,
        acceptedAt: Date?,
        transferConsented: Bool = false,
        isCurrent: Bool = false,
        currentPolicyVersion: String? = nil,
        lastRevokeReason: String? = nil
    ) {
        self.isGranted = isGranted
        self.policyVersion = policyVersion
        self.acceptedAt = acceptedAt
        self.transferConsented = transferConsented
        self.isCurrent = isCurrent
        self.currentPolicyVersion = currentPolicyVersion
        self.lastRevokeReason = lastRevokeReason
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isGranted = try container.decodeIfPresent(Bool.self, forKey: .isGranted) ?? false
        policyVersion = try container.decodeIfPresent(String.self, forKey: .policyVersion)
        acceptedAt = try container.decodeIfPresent(Date.self, forKey: .acceptedAt)
        transferConsented = try container.decodeIfPresent(Bool.self, forKey: .transferConsented) ?? false
        isCurrent = try container.decodeIfPresent(Bool.self, forKey: .isCurrent) ?? false
        currentPolicyVersion = try container.decodeIfPresent(String.self, forKey: .currentPolicyVersion)
        lastRevokeReason = try container.decodeIfPresent(String.self, forKey: .lastRevokeReason)
    }

    // A grant counts only at this build's policy version and with its separate transfer consent.
    var countsAsConsent: Bool {
        isGranted
            && isCurrent
            && transferConsented
            && policyVersion == PrivacyPolicyVersion.current
    }

    var wasWithdrawnByPolicyChange: Bool {
        !isGranted && lastRevokeReason == "policy_changed"
    }
}

enum NinaReplyReportReason: String, CaseIterable, Identifiable, Hashable {
    case inappropriate
    case riskToSomeone = "risk_to_someone"
    case healthOrMedicine = "health_or_medicine"
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .inappropriate: "Conteúdo impróprio"
        case .riskToSomeone: "Risco para alguém"
        case .healthOrMedicine: "Saúde ou remédio"
        case .other: "Outro"
        }
    }
}

enum NinaLegalLinks {
    // App Store Review 3.1.2 rejects a paywall without reachable terms and privacy links.
    static let privacyPolicy = URL(string: "https://ninai.app/privacidade")!
    static let termsOfUse = URL(string: "https://ninai.app/termos")!
    static let support = URL(string: "mailto:oi@ninai.app")!
    static let families = URL(string: "https://ninai.app/familias/")!
    static let reportPolicy = URL(string: "https://ninai.app/denuncia/")!
    static let manageSubscriptions = URL(string: "https://apps.apple.com/account/subscriptions")!
    static let privacyEmail = "privacidade@ninai.app"
    static let reportEmail = "privacidade@ninai.app"

    // The report leaves from the person's own mail app, carries no household data, and is never anonymous.
    static var reportMail: URL {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = reportEmail
        components.queryItems = [URLQueryItem(name: "subject", value: "Denúncia ECA Digital")]
        return components.url ?? privacyMail
    }

    static let privacyMail = URL(string: "mailto:privacidade@ninai.app")!

    static func accountDeletionMail(reference: String?) -> URL {
        accountRequestMail(subject: "Apagar minha conta", lines: [("Referência", reference)])
    }

    static func accountDeletionMail(ward memberID: UUID, guardianReference: String?) -> URL {
        accountRequestMail(
            subject: "Apagar a conta de um menor",
            lines: [("Referência", memberID.uuidString), ("Responsável", guardianReference)]
        )
    }

    static func ageContestMail(reference: String?) -> URL {
        accountRequestMail(subject: "Minha idade está errada", lines: [("Referência", reference)])
    }

    // Only references, never house data; a reference finds an account and never proves who wrote.
    private static func accountRequestMail(subject: String, lines: [(label: String, value: String?)]) -> URL {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = privacyEmail
        var items = [URLQueryItem(name: "subject", value: subject)]
        let body = lines.compactMap { line -> String? in
            guard let value = line.value?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty else { return nil }
            return "\(line.label): \(value.lowercased())"
        }
        if !body.isEmpty {
            items.append(URLQueryItem(name: "body", value: body.joined(separator: "\n")))
        }
        components.queryItems = items
        return components.url ?? privacyMail
    }
}

struct PremiumBenefit: Identifiable, Hashable {
    var title: String
    var detail: String
    var systemName: String
    var tone: MemberTone

    var id: String { title }
}

struct PremiumPlan: Hashable {
    var name: String
    var status: String
    var priceLabel: String
    var periodLabel: String
    var renewalLabel: String
    var heroTitle: String
    var heroSubtitle: String
    var benefits: [PremiumBenefit]

    var subscriptionDisclosure: String {
        "\(name): assinatura de \(periodLabel) por \(priceLabel). \(renewalLabel)."
    }

    // A benefit the build withholds is never priced: the sheet sells only what a
    // purchase can actually unlock.
    static var mock: PremiumPlan {
        let readsDocuments = NinaAttachmentGate.current.isEnabled
        let documentBenefit = PremiumBenefit(
            title: "Leitura de documentos",
            detail: "Recibos, receitas e boletos lidos por foto.",
            systemName: "doc.text.viewfinder",
            tone: .sky
        )

        return PremiumPlan(
            name: "Nina Premium",
            status: "Assinatura",
            priceLabel: "R$ 24,90/mês",
            periodLabel: "1 mês",
            renewalLabel: "Renovação automática pela App Store",
            heroTitle: "Premium para a casa toda",
            heroSubtitle: readsDocuments
                ? "Leitura de documentos, resumo semanal e prioridade da Nina, para a casa toda."
                : "Resumo semanal e prioridade da Nina, para a casa toda.",
            benefits: (readsDocuments ? [documentBenefit] : []) + [
                PremiumBenefit(
                    title: "Resumo semanal",
                    detail: "Pendências, conclusões e onde a casa pesa mais.",
                    systemName: "calendar.badge.clock",
                    tone: .amber
                ),
                PremiumBenefit(
                    title: "Prioridade da Nina",
                    detail: "Mais conversa com a Nina, 50 por dia.",
                    systemName: "sparkles",
                    tone: .lavender
                )
            ]
        )
    }
}

enum MinorViewerState: String, Hashable {
    case active
    case noGuardian = "no_guardian"
    case noHome = "no_home"
    case ageRequired = "age_required"

    var isMember: Bool {
        self != .noHome
    }
}

struct MinorSupervisionSettings: Decodable, Hashable {
    var alertsEnabled: Bool
    var quietStart: Int
    var quietEnd: Int
    var dailyLimitMinutes: Int?

    static let defaults = MinorSupervisionSettings(
        alertsEnabled: true,
        quietStart: MinorSupervisionDefaults.quietStart,
        quietEnd: MinorSupervisionDefaults.quietEnd,
        dailyLimitMinutes: MinorSupervisionDefaults.dailyLimitMinutes
    )

    private enum CodingKeys: String, CodingKey {
        case alertsEnabled = "alerts_enabled"
        case quietStart = "quiet_start"
        case quietEnd = "quiet_end"
        case dailyLimitMinutes = "daily_limit_minutes"
    }

    init(alertsEnabled: Bool, quietStart: Int, quietEnd: Int, dailyLimitMinutes: Int?) {
        self.alertsEnabled = alertsEnabled
        self.quietStart = quietStart
        self.quietEnd = quietEnd
        self.dailyLimitMinutes = dailyLimitMinutes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        alertsEnabled = try container.decodeIfPresent(Bool.self, forKey: .alertsEnabled) ?? true
        quietStart = try container.decodeIfPresent(Int.self, forKey: .quietStart)
            ?? MinorSupervisionDefaults.quietStart
        quietEnd = try container.decodeIfPresent(Int.self, forKey: .quietEnd)
            ?? MinorSupervisionDefaults.quietEnd
        dailyLimitMinutes = try container.decodeIfPresent(Int.self, forKey: .dailyLimitMinutes)
    }
}

struct MinorViewer: Decodable, Hashable {
    var memberID: UUID?
    var firstName: String
    var guardianNames: [String]
    var state: MinorViewerState
    var supervision: MinorSupervisionSettings
    var usageTodayMinutes: Int
    var needsAcknowledgement: Bool
    var acknowledgementKind: MinorAcknowledgementKind?

    private enum CodingKeys: String, CodingKey {
        case memberID = "member_id"
        case firstName = "first_name"
        case guardianNames = "guardian_names"
        case state
        case supervision
        case usageTodayMinutes = "usage_today_minutes"
        case needsAcknowledgement = "needs_acknowledgement"
        case acknowledgementKind = "acknowledgement_kind"
    }

    init(
        memberID: UUID?,
        firstName: String,
        guardianNames: [String],
        state: MinorViewerState,
        supervision: MinorSupervisionSettings = .defaults,
        usageTodayMinutes: Int = 0,
        needsAcknowledgement: Bool = false,
        acknowledgementKind: MinorAcknowledgementKind? = nil
    ) {
        self.memberID = memberID
        self.firstName = firstName
        self.guardianNames = guardianNames
        self.state = state
        self.supervision = supervision
        self.usageTodayMinutes = usageTodayMinutes
        self.needsAcknowledgement = needsAcknowledgement
        self.acknowledgementKind = acknowledgementKind
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        memberID = try container.decodeIfPresent(UUID.self, forKey: .memberID)
        firstName = try container.decodeIfPresent(String.self, forKey: .firstName) ?? ""
        guardianNames = try container.decodeIfPresent([String].self, forKey: .guardianNames) ?? []
        state = MinorViewerState(
            rawValue: try container.decodeIfPresent(String.self, forKey: .state) ?? ""
        ) ?? .noHome
        supervision = try container.decodeIfPresent(MinorSupervisionSettings.self, forKey: .supervision)
            ?? .defaults
        usageTodayMinutes = try container.decodeIfPresent(Int.self, forKey: .usageTodayMinutes) ?? 0
        needsAcknowledgement = try container.decodeIfPresent(Bool.self, forKey: .needsAcknowledgement) ?? false
        acknowledgementKind = MinorAcknowledgementKind(
            rawValue: try container.decodeIfPresent(String.self, forKey: .acknowledgementKind) ?? ""
        )
    }

    var guardianName: String? {
        guardianNames.first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    var guardianList: String {
        ListFormatter.localizedString(byJoining: guardianNames)
    }
}

struct MinorFamily: Decodable, Hashable {
    var id: UUID
    var name: String
}

// A minor's task carries no detail line, no owner label and nobody else's work.
struct MinorTask: Decodable, Identifiable, Hashable {
    var id: UUID
    var kind: TaskKind
    var title: String
    var dueAt: Date?
    var dueLabel: String
    var categoryID: String
    var recurrence: TaskRecurrence
    var remindOffsetMinutes: Int?
    var isDone: Bool
    var completedAt: Date?
    var version: Int

    private enum CodingKeys: String, CodingKey {
        case id
        case kind = "task_kind"
        case title
        case dueAt = "due_at"
        case dueLabel = "due_label"
        case categoryID = "category_id"
        case recurrence = "recurrence_rule"
        case remindOffsetMinutes = "remind_offset_minutes"
        case isDone = "is_done"
        case completedAt = "completed_at"
        case version
    }

    init(
        id: UUID = UUID(),
        kind: TaskKind = .task,
        title: String,
        dueAt: Date?,
        dueLabel: String = "Sem data",
        categoryID: String = TaskCategory.home.id,
        recurrence: TaskRecurrence = .none,
        remindOffsetMinutes: Int? = nil,
        isDone: Bool = false,
        completedAt: Date? = nil,
        version: Int = 1
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.dueAt = dueAt
        self.dueLabel = dueLabel
        self.categoryID = categoryID
        self.recurrence = recurrence
        self.remindOffsetMinutes = remindOffsetMinutes
        self.isDone = isDone
        self.completedAt = completedAt
        self.version = version
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        kind = TaskKind(rawValue: try container.decodeIfPresent(String.self, forKey: .kind) ?? "") ?? .task
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        dueAt = try container.decodeIfPresent(Date.self, forKey: .dueAt)
        dueLabel = try container.decodeIfPresent(String.self, forKey: .dueLabel) ?? "Sem data"
        categoryID = try container.decodeIfPresent(String.self, forKey: .categoryID) ?? TaskCategory.home.id
        recurrence = TaskRecurrence(
            rawValue: try container.decodeIfPresent(String.self, forKey: .recurrence) ?? ""
        ) ?? .none
        remindOffsetMinutes = try container.decodeIfPresent(Int.self, forKey: .remindOffsetMinutes)
        isDone = try container.decodeIfPresent(Bool.self, forKey: .isDone) ?? false
        completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
    }

    var category: TaskCategory {
        TaskCategory.allCases.first { $0.id == categoryID } ?? .home
    }

    func taskItem(ownerMemberID: UUID?, ownerName: String) -> TaskItem {
        TaskItem(
            id: id,
            kind: kind,
            title: title,
            subtitle: "",
            owner: ownerName,
            ownerMemberID: ownerMemberID,
            dueLabel: dueLabel,
            dueAt: dueAt,
            category: category,
            recurrence: recurrence,
            reminderLead: TaskReminderLead(minutes: remindOffsetMinutes ?? 0),
            isDone: isDone,
            completedAt: completedAt,
            createdBy: "",
            version: version
        )
    }
}

struct MinorHome: Decodable, Hashable {
    var viewer: MinorViewer
    var family: MinorFamily?
    var tasks: [MinorTask]
    var serverTime: Date?

    private enum CodingKeys: String, CodingKey {
        case viewer
        case family
        case tasks
        case serverTime = "server_time"
    }

    init(viewer: MinorViewer, family: MinorFamily?, tasks: [MinorTask], serverTime: Date? = nil) {
        self.viewer = viewer
        self.family = family
        self.tasks = tasks
        self.serverTime = serverTime
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        viewer = try container.decodeIfPresent(MinorViewer.self, forKey: .viewer)
            ?? MinorViewer(memberID: nil, firstName: "", guardianNames: [], state: .noHome)
        family = try container.decodeIfPresent(MinorFamily.self, forKey: .family)
        tasks = try container.decodeIfPresent([MinorTask].self, forKey: .tasks) ?? []
        serverTime = try container.decodeIfPresent(Date.self, forKey: .serverTime)
    }

    var ownerName: String {
        viewer.firstName.isEmpty ? "Você" : viewer.firstName
    }

    var taskItems: [TaskItem] {
        tasks.map { $0.taskItem(ownerMemberID: viewer.memberID, ownerName: ownerName) }
    }

    var ownerMember: HouseholdMember {
        HouseholdMember(
            id: viewer.memberID ?? UUID(),
            name: ownerName,
            relationship: "",
            role: .child,
            tone: .mint,
            taskCount: 0,
            memoryNote: ""
        )
    }

    var isOverDailyLimit: Bool {
        guard let limit = viewer.supervision.dailyLimitMinutes else { return false }
        return viewer.usageTodayMinutes >= limit
    }
}

struct MinorUsageResult: Decodable, Hashable {
    var usageTodayMinutes: Int
    var dailyLimitMinutes: Int?

    private enum CodingKeys: String, CodingKey {
        case usageTodayMinutes = "usage_today_minutes"
        case dailyLimitMinutes = "daily_limit_minutes"
    }

    init(usageTodayMinutes: Int, dailyLimitMinutes: Int?) {
        self.usageTodayMinutes = usageTodayMinutes
        self.dailyLimitMinutes = dailyLimitMinutes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        usageTodayMinutes = try container.decodeIfPresent(Int.self, forKey: .usageTodayMinutes) ?? 0
        dailyLimitMinutes = try container.decodeIfPresent(Int.self, forKey: .dailyLimitMinutes)
    }
}
