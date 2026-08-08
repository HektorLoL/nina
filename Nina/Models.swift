import Foundation

enum HouseholdRole: String, CaseIterable, Identifiable, Codable, Hashable {
    case adult
    case child
    case pet
    case assistant

    var id: String { rawValue }

    var title: String {
        switch self {
        case .adult: "Adulto"
        case .child: "Criança"
        case .pet: "Pet"
        case .assistant: "Nina IA"
        }
    }

    var symbolName: String {
        switch self {
        case .adult: "person.fill"
        case .child: "figure.2.and.child.holdinghands"
        case .pet: "pawprint.fill"
        case .assistant: "sparkles"
        }
    }
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
}

enum FamilyPermissionRole: String, CaseIterable, Identifiable, Codable, Hashable {
    case owner
    case admin
    case member

    var id: String { rawValue }

    var title: String {
        switch self {
        case .owner: "Responsável"
        case .admin: "Administrador"
        case .member: "Participante"
        }
    }

    var summary: String {
        switch self {
        case .owner:
            "Controla convites, participantes, permissões e ajustes da casa."
        case .admin:
            "Aprova entradas e gerencia participantes, exceto responsáveis e outros administradores."
        case .member:
            "Participa das tarefas, compras e conversas da casa."
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
        petBreed: String = ""
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
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        userID = try container.decodeIfPresent(String.self, forKey: .userID)
        name = try container.decode(String.self, forKey: .name)
        relationship = try container.decodeIfPresent(String.self, forKey: .relationship) ?? ""
        role = try container.decodeIfPresent(HouseholdRole.self, forKey: .role) ?? .adult
        permissionRole = try container.decodeIfPresent(FamilyPermissionRole.self, forKey: .permissionRole) ?? .member
        identityState = try container.decodeIfPresent(MemberIdentityState.self, forKey: .identityState)
            ?? (userID == nil ? .unclaimed : .claimed)
        tone = try container.decodeIfPresent(MemberTone.self, forKey: .tone) ?? .mint
        taskCount = try container.decodeIfPresent(Int.self, forKey: .taskCount) ?? 0
        memoryNote = try container.decodeIfPresent(String.self, forKey: .memoryNote) ?? ""
        birthDate = try container.decodeIfPresent(Date.self, forKey: .birthDate)
        petSpecies = try container.decodeIfPresent(String.self, forKey: .petSpecies) ?? ""
        petBreed = try container.decodeIfPresent(String.self, forKey: .petBreed) ?? ""
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

struct FamilyJoinRequest: Identifiable, Codable, Hashable {
    var id: UUID
    var familyID: UUID
    var familyName: String
    var requesterUserID: UUID
    var requesterName: String
    var status: FamilyJoinRequestStatus
    var createdAt: Date
    var reviewedAt: Date?
}

struct TaskCategory: Identifiable, Codable, Hashable, CaseIterable {
    var id: String
    var title: String
    var symbolName: String
    var tone: MemberTone

    static let home = TaskCategory(id: "home", title: "Casa", symbolName: "house.fill", tone: .mint)
    static let bills = TaskCategory(id: "bills", title: "Contas", symbolName: "creditcard.fill", tone: .sky)
    static let health = TaskCategory(id: "health", title: "Saúde", symbolName: "cross.case.fill", tone: .coral)
    static let school = TaskCategory(id: "school", title: "Escola", symbolName: "backpack.fill", tone: .amber)
    static let pet = TaskCategory(id: "pet", title: "Pet", symbolName: "pawprint.fill", tone: .lavender)
    static let food = TaskCategory(id: "food", title: "Comida", symbolName: "fork.knife", tone: .mint)

    static let allCases: [TaskCategory] = [.home, .bills, .health, .school, .pet, .food]

    static func custom(id: String, title: String, tone: MemberTone) -> TaskCategory {
        TaskCategory(id: id, title: title, symbolName: "tag.fill", tone: tone)
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

    var explicitTitle: String {
        switch self {
        case .none: "Não se repete"
        case .daily: "Repete diariamente"
        case .weekly: "Repete semanalmente"
        case .monthly: "Repete mensalmente"
        case .yearly: "Repete anualmente"
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

    var editorDescription: String {
        switch self {
        case .task:
            "Algo que já tem um momento para acontecer."
        case .seed:
            "Uma intenção sem data definida. Guarde agora e plante quando estiver pronta."
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
    var dueLabel: String
    var dueAt: Date?
    var category: TaskCategory
    var priority: TaskPriority
    var recurrence: TaskRecurrence
    var snoozedUntil: Date?
    var isDone: Bool
    var createdBy: String
    var sectionID: String
    var version: Int

    init(
        id: UUID = UUID(),
        kind: TaskKind = .task,
        title: String,
        subtitle: String,
        owner: String,
        dueLabel: String,
        dueAt: Date? = nil,
        category: TaskCategory,
        priority: TaskPriority = .normal,
        recurrence: TaskRecurrence = .none,
        snoozedUntil: Date? = nil,
        isDone: Bool,
        createdBy: String,
        sectionID: String = TaskSectionDefaults.houseTasksID,
        version: Int = 1
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.owner = owner
        self.dueLabel = dueLabel
        self.dueAt = dueAt
        self.category = category
        self.priority = priority
        self.recurrence = recurrence
        self.snoozedUntil = snoozedUntil
        self.isDone = isDone
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
        case dueLabel
        case dueAt
        case category
        case priority
        case recurrence
        case snoozedUntil
        case isDone
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
        dueLabel = try container.decodeIfPresent(String.self, forKey: .dueLabel) ?? "Sem data"
        dueAt = try container.decodeIfPresent(Date.self, forKey: .dueAt)
        category = try container.decodeIfPresent(TaskCategory.self, forKey: .category) ?? .home
        priority = try container.decodeIfPresent(TaskPriority.self, forKey: .priority) ?? .normal
        recurrence = try container.decodeIfPresent(TaskRecurrence.self, forKey: .recurrence) ?? .none
        snoozedUntil = try container.decodeIfPresent(Date.self, forKey: .snoozedUntil)
        isDone = try container.decodeIfPresent(Bool.self, forKey: .isDone) ?? false
        createdBy = try container.decodeIfPresent(String.self, forKey: .createdBy) ?? "Manual"
        sectionID = try container.decodeIfPresent(String.self, forKey: .sectionID) ?? TaskSectionDefaults.houseTasksID
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
    }

    // A recurring task's stored dueAt goes stale as soon as one occurrence passes. Resolving the
    // current period here is what keeps the screen and the scheduled notifications agreeing.
    func displayDate(
        relativeTo referenceDate: Date = .now,
        calendar: Calendar = .current
    ) -> Date? {
        if let snoozedUntil, snoozedUntil > referenceDate {
            return snoozedUntil
        }

        guard recurrence != .none, dueAt != nil else { return effectiveDueDate }

        let periodStart = calendar.startOfDay(for: referenceDate).addingTimeInterval(-1)
        return scheduledOccurrence(after: periodStart, calendar: calendar) ?? effectiveDueDate
    }

    var effectiveDueDate: Date? {
        snoozedUntil ?? dueAt
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
        guard recurrence != .none else { return dueAt }
        guard dueAt <= referenceDate else { return dueAt }

        let components: DateComponents
        switch recurrence {
        case .none:
            return dueAt
        case .daily:
            components = calendar.dateComponents([.hour, .minute], from: dueAt)
        case .weekly:
            components = calendar.dateComponents([.weekday, .hour, .minute], from: dueAt)
        case .monthly:
            components = calendar.dateComponents([.day, .hour, .minute], from: dueAt)
        case .yearly:
            components = calendar.dateComponents([.month, .day, .hour, .minute], from: dueAt)
        }

        return calendar.nextDate(
            after: referenceDate,
            matching: components,
            matchingPolicy: .nextTimePreservingSmallerComponents,
            repeatedTimePolicy: .first,
            direction: .forward
        )
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
    var id = UUID()
    var title: String
    var amount: String
    var owner: String
    var isChecked: Bool
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

struct NinaProposalPayload: Codable, Hashable {
    var title: String
    var detail: String
    var owner: String
    var dueLabel: String
    var dueAt: String?
    var categoryID: String
    var symbolName: String
    var amount: String
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
        visibility = NinaMemoryVisibility(
            rawValue: try container.decodeIfPresent(String.self, forKey: .visibility) ?? ""
        )
        confidence = try container.decodeIfPresent(Double.self, forKey: .confidence)
        deduplicationKey = try container.decodeIfPresent(String.self, forKey: .deduplicationKey) ?? ""
    }

    var category: TaskCategory {
        TaskCategory.allCases.first(where: { $0.id == categoryID })
            ?? .custom(id: categoryID, title: categoryID.capitalized, tone: .lavender)
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
        kind = try container.decode(NinaProposalKind.self, forKey: .kind)
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
    var attachments: [ChatAttachment]

    init(
        id: UUID = UUID(),
        sender: MessageSender,
        text: String,
        timestamp: Date,
        suggestion: NinaSuggestion? = nil,
        proposals: [NinaProposal] = [],
        attachments: [ChatAttachment] = []
    ) {
        self.id = id
        self.sender = sender
        self.text = text
        self.timestamp = timestamp
        self.suggestion = suggestion
        self.proposals = proposals
        self.attachments = attachments
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case sender
        case text
        case timestamp
        case suggestion
        case proposals
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
}

enum NinaLegalLinks {
    static let privacyPolicy = URL(string: "https://ninai.app/privacidade/")!
    // Apple's standard EULA is the terms of use until a Brazilian legal entity exists to sign one.
    static let termsOfUse = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    static let manageSubscription = URL(string: "https://apps.apple.com/account/subscriptions")!
    static let support = URL(string: "mailto:oi@ninai.app")!
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
    var renewalLabel: String
    var heroTitle: String
    var heroSubtitle: String
    var benefits: [PremiumBenefit]

    static let mock = PremiumPlan(
        name: "Nina Premium",
        status: "Assinatura",
        priceLabel: "R$ 24,90/mês",
        renewalLabel: "Renovação automática pelo App Store",
        heroTitle: "Uma Nina mais esperta para a casa toda",
        heroSubtitle: "Rotinas, documentos, resumos e equilíbrio familiar em uma camada premium para a casa.",
        benefits: [
            PremiumBenefit(
                title: "Rotinas inteligentes",
                detail: "A Nina sugere sequências para escola, saúde, compras e contas sem você montar tudo manualmente.",
                systemName: "wand.and.stars",
                tone: .mint
            ),
            PremiumBenefit(
                title: "Leitura de documentos",
                detail: "Leitura de recibos, receitas e boletos para transformar detalhes em lembretes claros.",
                systemName: "doc.text.viewfinder",
                tone: .sky
            ),
            PremiumBenefit(
                title: "Resumo semanal",
                detail: "Um digest bonito com pendências, compras, vitórias da semana e sinais de sobrecarga.",
                systemName: "calendar.badge.clock",
                tone: .amber
            ),
            PremiumBenefit(
                title: "Divisão mais justa",
                detail: "Insights premium para enxergar quem está carregando mais tarefas e redistribuir com calma.",
                systemName: "chart.bar.fill",
                tone: .coral
            ),
            PremiumBenefit(
                title: "Prioridade da Nina",
                detail: "Sugestões mais visíveis, rápidas e contextuais para não deixar urgências escaparem.",
                systemName: "sparkles",
                tone: .lavender
            )
        ]
    )
}
