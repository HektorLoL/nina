import Foundation
import Observation

enum PrivacyPolicyVersion {
    static let current = "2026-09-29"
}

struct AIMemoryConsentRecord: Codable, Hashable {
    var acceptedAt: Date
    var policyVersion: String
    var transferConsented: Bool

    init(acceptedAt: Date, policyVersion: String, transferConsented: Bool) {
        self.acceptedAt = acceptedAt
        self.policyVersion = policyVersion
        self.transferConsented = transferConsented
    }

    private enum CodingKeys: String, CodingKey {
        case acceptedAt
        case policyVersion
        case transferConsented
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        acceptedAt = try container.decodeIfPresent(Date.self, forKey: .acceptedAt) ?? .distantPast
        policyVersion = try container.decodeIfPresent(String.self, forKey: .policyVersion) ?? ""
        transferConsented = try container.decodeIfPresent(Bool.self, forKey: .transferConsented) ?? false
    }

    // A grant given on an older text, or without the separate transfer consent, is no grant at all.
    var isCurrent: Bool {
        policyVersion == PrivacyPolicyVersion.current && transferConsented
    }
}

// Days are counted on Brazil's clock, the same clock record_minor_usage validates against.
enum MinorUsageClock {
    static let timeZone = TimeZone(identifier: "America/Sao_Paulo") ?? .current

    static func day(for date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 1970,
            components.month ?? 1,
            components.day ?? 1
        )
    }
}

struct MinorUsageLedger: Codable, Hashable {
    var day: String
    var seconds: Int

    var minutes: Int {
        min(seconds / 60, 1_440)
    }

    func adding(seconds extra: Int, on day: String) -> MinorUsageLedger {
        guard day == self.day else {
            return MinorUsageLedger(day: day, seconds: max(extra, 0))
        }
        return MinorUsageLedger(day: day, seconds: seconds + max(extra, 0))
    }
}

private struct LegacyReminderItem: Decodable {
    var id: UUID
    var title: String
    var detail: String
    var dateLabel: String
    var dueAt: Date?
    var recurrence: TaskRecurrence
    var snoozedUntil: Date?
    var symbolName: String
    var tone: MemberTone

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case detail
        case dateLabel
        case dueAt
        case recurrence
        case snoozedUntil
        case symbolName
        case tone
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try container.decode(String.self, forKey: .title)
        detail = try container.decodeIfPresent(String.self, forKey: .detail) ?? ""
        dateLabel = try container.decodeIfPresent(String.self, forKey: .dateLabel) ?? "Sem data"
        dueAt = try container.decodeIfPresent(Date.self, forKey: .dueAt)
        recurrence = try container.decodeIfPresent(TaskRecurrence.self, forKey: .recurrence) ?? .none
        snoozedUntil = try container.decodeIfPresent(Date.self, forKey: .snoozedUntil)
        symbolName = try container.decodeIfPresent(String.self, forKey: .symbolName) ?? "bell.fill"
        tone = try container.decodeIfPresent(MemberTone.self, forKey: .tone) ?? .amber
    }

    var task: TaskItem {
        TaskItem(
            id: id,
            title: title,
            subtitle: detail,
            owner: "Casa",
            dueLabel: dateLabel,
            dueAt: dueAt,
            category: TaskCategory(
                id: TaskCategory.home.id,
                title: TaskCategory.home.title,
                symbolName: symbolName,
                tone: tone
            ),
            recurrence: recurrence,
            snoozedUntil: snoozedUntil,
            isDone: false,
            createdBy: "Nina"
        )
    }
}

struct AppDataSnapshot: Codable {
    var messages: [ChatMessage]
    var taskSections: [TaskSection]
    var customTaskCategories: [TaskCategory]
    var tasks: [TaskItem]
    var shoppingItems: [ShoppingItem]
    var insights: [HouseholdInsight]
    var ninaThread: NinaThread?
    var ninaMemories: [NinaMemory]

    init(
        messages: [ChatMessage],
        taskSections: [TaskSection],
        customTaskCategories: [TaskCategory] = [],
        tasks: [TaskItem],
        shoppingItems: [ShoppingItem],
        insights: [HouseholdInsight],
        ninaThread: NinaThread? = nil,
        ninaMemories: [NinaMemory] = []
    ) {
        self.messages = messages
        self.taskSections = taskSections
        self.customTaskCategories = customTaskCategories
        self.tasks = tasks
        self.shoppingItems = shoppingItems
        self.insights = insights
        self.ninaThread = ninaThread
        self.ninaMemories = ninaMemories
    }

    private enum CodingKeys: String, CodingKey {
        case messages
        case taskSections
        case customTaskCategories
        case tasks
        case shoppingItems
        case reminders
        case insights
        case ninaThread
        case ninaMemories
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        messages = try container.decodeIfPresent([ChatMessage].self, forKey: .messages) ?? []
        taskSections = try container.decodeIfPresent([TaskSection].self, forKey: .taskSections) ?? []
        customTaskCategories = try container.decodeIfPresent([TaskCategory].self, forKey: .customTaskCategories) ?? []
        let decodedTasks = try container.decodeIfPresent([TaskItem].self, forKey: .tasks) ?? []
        let legacyReminders = try container.decodeIfPresent([LegacyReminderItem].self, forKey: .reminders) ?? []
        let taskIDs = Set(decodedTasks.map(\.id))
        tasks = decodedTasks + legacyReminders.map(\.task).filter { !taskIDs.contains($0.id) }
        shoppingItems = try container.decodeIfPresent([ShoppingItem].self, forKey: .shoppingItems) ?? []
        insights = try container.decodeIfPresent([HouseholdInsight].self, forKey: .insights) ?? []
        ninaThread = try container.decodeIfPresent(NinaThread.self, forKey: .ninaThread)
        ninaMemories = try container.decodeIfPresent([NinaMemory].self, forKey: .ninaMemories) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(messages, forKey: .messages)
        try container.encode(taskSections, forKey: .taskSections)
        try container.encode(customTaskCategories, forKey: .customTaskCategories)
        try container.encode(tasks, forKey: .tasks)
        try container.encode(shoppingItems, forKey: .shoppingItems)
        try container.encode(insights, forKey: .insights)
        try container.encodeIfPresent(ninaThread, forKey: .ninaThread)
        try container.encode(ninaMemories, forKey: .ninaMemories)
    }

    static let preview = AppDataSnapshot(
        messages: PreviewData.messages,
        taskSections: PreviewData.taskSections,
        customTaskCategories: PreviewData.customTaskCategories,
        tasks: PreviewData.tasks,
        shoppingItems: PreviewData.shoppingItems,
        insights: PreviewData.insights
    )
}

enum HomeAccessState: Hashable {
    case loading
    case authorized
    case minorMember
    case pendingApproval
    case accessDecision
    case noHome
    case unavailable
}

struct TaskEditConflict: Identifiable {
    var id: TaskItem.ID { remoteTask.id }
    var localTask: TaskItem
    var remoteTask: TaskItem
}

private struct HomeContextToken {
    var userID: String?
    var generation: UInt64
}

private enum HomeMembershipOutcome {
    case member(RemoteHomeState)
    case minor(MinorHome)
    case awaitingApproval(FamilyJoinRequest)
    case notAMember(FamilyAccessDecision?)
    case unverifiable
}

private struct HomeMembershipLoad {
    var outcome: HomeMembershipOutcome
    var viewerAge: AgeStatus
}

@MainActor
@Observable
final class AppStore {
    nonisolated static let maxFamilyPeople = 8
    static let houseTasksSectionID = TaskSectionDefaults.houseTasksID

    var familyGroup: FamilyGroup
    var homeAccessState: HomeAccessState = .loading
    var currentPermissionRole: FamilyPermissionRole = .member
    var inviteStatus: FamilyInviteStatus?
    var pendingJoinRequest: FamilyJoinRequest?
    var familyAccessDecision: FamilyAccessDecision?
    var joinRequests: [FamilyJoinRequest] = []
    var houseOwnershipOffer: HouseOwnershipOffer?
    var messages: [ChatMessage]
    var taskSections: [TaskSection]
    var customTaskCategories: [TaskCategory]
    var tasks: [TaskItem]
    var shoppingItems: [ShoppingItem]
    var insights: [HouseholdInsight]
    // Household premium is never cached: only a freshly verified home context can grant it.
    var householdPremium: HouseholdPremium = .inactive
    var ninaThread: NinaThread?
    var ninaMemories: [NinaMemory]
    private var seenInsightRevision = 0
    var isNinaResponding = false
    var ninaConnectionNotice: String?
    var taskEditConflict: TaskEditConflict?
    // One action can meet several clashes; each waits its turn and none is replaced unseen.
    @ObservationIgnored private var queuedTaskEditConflicts: [TaskEditConflict] = []
    @ObservationIgnored private var lastFailureHapticAt = Date.distantPast
    // Only the hold or a change of account closes a child's list; losing the home for a moment never does.
    var childDayPresentation: ChildDayPresentation?
    var aiMemoryConsent: AIMemoryConsentRecord?
    var aiConsentStatus: NinaAIConsent = .withheld
    var hasStaleLocalConsent = false
    var notificationAuthorizationStatus: HomeNotificationAuthorizationStatus = .notDetermined
    // Capabilities come from the server's age record, never from a household role.
    var viewerAge: AgeStatus = .unknown
    var minorHome: MinorHome?
    var ageCheckRequested = false
    private(set) var isRecordingFootnoteAcceptance = false
    // What the person typed before the chat closed on them, kept in memory only and never in a snapshot.
    var restorableDraft: String?

    @ObservationIgnored private let ninaEngine: any NinaEngine
    @ObservationIgnored private let fallbackNinaEngine = MockNinaEngine()
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let privateDataStore: any PrivateLocalDataStoring
    @ObservationIgnored private let remoteHomeBackend: (any RemoteHomeBackend)?
    @ObservationIgnored private let notificationScheduler: any HomeNotificationScheduling
    @ObservationIgnored var attachmentGate = NinaAttachmentGate.current
    @ObservationIgnored private var activeHomeUserID: String?
    @ObservationIgnored private var activeUser: AuthUser?
    @ObservationIgnored private var homeContextGeneration: UInt64 = 0
    @ObservationIgnored private var messagesContext: HomeContextToken?
    @ObservationIgnored private var localStateRevision: UInt64 = 0
    @ObservationIgnored private var remoteMutationGeneration: UInt64 = 0
    @ObservationIgnored private var remoteMutationTask: Task<Void, Never>?
    @ObservationIgnored private var realtimeListenerTask: Task<Void, Never>?
    @ObservationIgnored private var realtimeRefreshTask: Task<Void, Never>?
    @ObservationIgnored private var notificationSyncTask: Task<Void, Never>?
    @ObservationIgnored private var minorSessionStartedAt: Date?
    @ObservationIgnored private var termsFootnote: TermsFootnote?
    private(set) var hasUnrecordedTermsFootnote = false

    private struct TermsFootnote {
        let userID: String
        let shownAt: Date
        let wasRestored: Bool
    }
    @ObservationIgnored private(set) var lastMutationErrorCode: RemoteRPCErrorCode?

    var undoableCompletionID: TaskItem.ID?
    // Counts closings on this phone, so the mark in the tab bar can notice each one.
    private(set) var completionPulse = 0
    @ObservationIgnored private var undoExpiryTask: Task<Void, Never>?
    @ObservationIgnored private var undoableRoll: (before: TaskItem, after: TaskItem)?
    var isSyncingHome = false
    var syncErrorMessage: String?

    var hasActiveHome: Bool {
        homeAccessState == .authorized
    }

    var canManageFamily: Bool {
        currentPermissionRole.canManageFamily
    }

    var pendingJoinRequestCount: Int {
        canManageFamily ? joinRequests.count : 0
    }

    // The weekly portrait is written while nobody is looking, so Casa marks a new one until it is seen.
    var hasUnseenInsight: Bool {
        _ = seenInsightRevision
        guard !isUsingLocalContext, hasActiveHome, let newest = insights.first else { return false }
        return defaults.string(forKey: Self.seenInsightKey(for: familyGroup.id)) != newest.id.uuidString
    }

    func markInsightsSeen() {
        guard hasUnseenInsight, let newest = insights.first else { return }
        defaults.set(newest.id.uuidString, forKey: Self.seenInsightKey(for: familyGroup.id))
        seenInsightRevision &+= 1
    }

    static func seenInsightKey(for familyID: UUID) -> String {
        "nina.seenInsight.\(familyID.uuidString)"
    }

    // Nina proposes and a person decides, so a card still waiting is shown outside the chat too.
    var waitingProposalCount: Int {
        guard canUseNinaAI else { return 0 }
        return messages.reduce(0) { total, message in
            total + message.proposals.count { $0.state == .pending }
        }
    }

    var canChangeFamilyPermissions: Bool {
        currentPermissionRole.canChangePermissions
    }

    var isWeeklyDigestEnabled: Bool {
        familyGroup.weeklyDigestEnabled
    }

    var currentFamilyMember: HouseholdMember? {
        guard let activeHomeUserID else { return nil }
        return familyGroup.members.first { $0.userID == activeHomeUserID }
    }

    var isUsingLocalNina: Bool {
        usesLocalDebugBackend(for: activeUser)
            || (remoteHomeBackend == nil && BackendServices.environment == .mock)
    }

    var isUsingLocalContext: Bool {
        isUsingLocalNina || (activeUser != nil && remoteHomeBackend == nil)
    }

    var isAdultViewer: Bool {
        viewerAge.isAdult
    }

    var isMinorView: Bool {
        !viewerAge.isAdult
    }

    var canActForMinors: Bool {
        viewerAge.canActForMinors
    }

    var canBuyPremium: Bool {
        viewerAge.canBuy
    }

    var canBuy: Bool {
        canBuyPremium
    }

    var canUseAI: Bool {
        viewerAge.canUseAI
    }

    var isAIBlocked: Bool {
        viewerAge.aiBlocked
    }

    private var isAdultHouseholdMember: Bool {
        guard let activeUser else { return false }
        return familyGroup.members.contains {
            $0.userID == activeUser.id && $0.role == .adult
        }
    }

    // A declared adult runs the house but sees the confirmation gate where the conversation would be.
    var needsConfirmedAgeForChat: Bool {
        !isUsingLocalNina
            && activeUser != nil
            && viewerAge.isAdult
            && !viewerAge.mayUseAI
            && isAdultHouseholdMember
    }

    var canUseNinaAI: Bool {
        if isUsingLocalNina {
            return true
        }
        guard activeUser != nil else {
            return remoteHomeBackend == nil
        }
        return viewerAge.canUseAI && isAdultHouseholdMember
    }

    var requiresAIMemoryConsent: Bool {
        canUseNinaAI
            && !isUsingLocalNina
            && activeUser != nil
            && remoteHomeBackend != nil
    }

    var hasAIMemoryConsent: Bool {
        aiMemoryConsent?.isCurrent == true
    }

    var aiConsentNoticeChanged: Bool {
        aiConsentStatus.wasWithdrawnByPolicyChange || hasStaleLocalConsent
    }

    var canSendNinaMessages: Bool {
        canUseNinaAI && (!requiresAIMemoryConsent || hasAIMemoryConsent)
    }

    init(
        defaults: UserDefaults = .standard,
        privateDataStore: any PrivateLocalDataStoring = ProtectedLocalDataStore.shared,
        remoteHomeBackend: (any RemoteHomeBackend)? = BackendServices.makeRemoteHomeBackend(),
        ninaEngine: any NinaEngine = BackendServices.makeNinaEngine(),
        notificationScheduler: (any HomeNotificationScheduling)? = nil
    ) {
        self.defaults = defaults
        self.privateDataStore = privateDataStore
        self.remoteHomeBackend = remoteHomeBackend
        self.ninaEngine = ninaEngine
        self.notificationScheduler = notificationScheduler ?? LocalHomeNotificationScheduler(defaults: defaults)
        familyGroup = PreviewData.familyGroup
        messages = PreviewData.messages
        taskSections = PreviewData.taskSections
        customTaskCategories = PreviewData.customTaskCategories
        tasks = PreviewData.tasks
        shoppingItems = PreviewData.shoppingItems
        insights = PreviewData.insights
        ninaThread = nil
        ninaMemories = []
        aiMemoryConsent = nil
        inviteStatus = nil
        pendingJoinRequest = nil
    }

    var openTasks: [TaskItem] {
        tasks.filter { !$0.isDone }
    }

    var openSeeds: [TaskItem] {
        openTasks.filter { $0.kind == .seed }
    }

    var completedTasks: [TaskItem] {
        tasks.filter(\.isDone)
    }

    var workloadSnapshot: HouseholdWorkloadSnapshot {
        HouseholdWorkload.snapshot(tasks: tasks, members: familyGroup.members)
    }

    func openTaskCount(for member: HouseholdMember) -> Int {
        HouseholdWorkload.openTaskCount(for: member, in: tasks, members: familyGroup.members)
    }

    func recollection(for member: HouseholdMember) -> MemberRecollectionSummary {
        MemberRecollection.summary(
            for: member,
            members: familyGroup.members,
            memories: ninaMemories,
            tasks: tasks,
            viewerUserID: activeUser.flatMap { UUID(uuidString: $0.id) }
        )
    }

    func tasks(in sectionID: String) -> [TaskItem] {
        tasks.filter { $0.sectionID == sectionID }
    }

    func openTasks(in sectionID: String) -> [TaskItem] {
        tasks(in: sectionID).filter { !$0.isDone }
    }

    func completedTasks(in sectionID: String) -> [TaskItem] {
        tasks(in: sectionID)
            .filter(\.isDone)
            .sorted { left, right in
                let leftCompletion = left.completedAt ?? .distantFuture
                let rightCompletion = right.completedAt ?? .distantFuture
                guard leftCompletion == rightCompletion else {
                    return leftCompletion > rightCompletion
                }
                return left.id.uuidString < right.id.uuidString
            }
    }

    func taskCounts(in sectionID: String) -> (open: Int, completed: Int) {
        tasks.reduce(into: (open: 0, completed: 0)) { counts, task in
            guard task.sectionID == sectionID else { return }

            if task.isDone {
                counts.completed += 1
            } else {
                counts.open += 1
            }
        }
    }

    var pendingShoppingItems: [ShoppingItem] {
        shoppingItems.filter { !$0.isChecked }
    }

    var availableTaskCategories: [TaskCategory] {
        TaskCategory.allCases + customTaskCategories
    }

    var familyPeopleCount: Int {
        familyGroup.members.filter { $0.role != .assistant }.count
    }

    var remainingFamilySlots: Int {
        max(Self.maxFamilyPeople - familyPeopleCount, 0)
    }

    var canInviteMorePeople: Bool {
        remainingFamilySlots > 0
    }

    var inviteURL: URL {
        URL(string: "https://ninai.app/invite/\(familyGroup.inviteCode)")!
    }

    var familyLimitLabel: String {
        familyPeopleCount == 1 ? "1 pessoa + Nina" : "\(familyPeopleCount) pessoas + Nina"
    }

    func canEditFamilyMember(_ member: HouseholdMember) -> Bool {
        guard member.role != .assistant else { return false }
        if member.userID == activeHomeUserID {
            return true
        }
        if member.role.isMinorRole, member.minorAccess?.isViewerGuardian == true {
            return true
        }
        guard canManageFamily else { return false }
        if currentPermissionRole == .admin,
           member.userID != activeHomeUserID,
           (member.permissionRole == .owner || member.permissionRole == .admin) {
            return false
        }
        return true
    }

    func canRemoveFamilyMember(_ member: HouseholdMember) -> Bool {
        if member.minorAccess?.isViewerGuardian == true,
           member.role.isMinorRole,
           member.userID != activeHomeUserID {
            return true
        }
        guard canManageFamily,
              member.role != .assistant,
              member.permissionRole != .owner,
              member.userID != activeHomeUserID else {
            return false
        }
        if currentPermissionRole == .admin, member.permissionRole == .admin {
            return false
        }
        return true
    }

    func canChangePermissionRole(for member: HouseholdMember) -> Bool {
        canChangeFamilyPermissions
            && member.role == .adult
            && member.identityState == .claimed
            && member.userID != activeHomeUserID
            && member.permissionRole != .owner
    }

    func activateHomeContext(for user: AuthUser?) async {
        if user?.id != activeHomeUserID {
            childDayPresentation = nil
            minorSessionStartedAt = nil
            restorableDraft = nil
            isRecordingFootnoteAcceptance = false
            if let previousUserID = activeHomeUserID {
                removeStoredTermsFootnote(for: previousUserID)
            }
            if termsFootnote?.userID != user?.id {
                termsFootnote = user.flatMap { storedTermsFootnote(for: $0.id) }
            }
            hasUnrecordedTermsFootnote = termsFootnote != nil
        }
        homeContextGeneration &+= 1
        remoteMutationTask?.cancel()
        remoteMutationTask = nil
        remoteMutationGeneration = 0
        stopRealtimeSync()
        activeHomeUserID = user?.id
        activeUser = user
        let contextToken = currentHomeContextToken
        loadAIMemoryConsent(for: user?.id)
        taskEditConflict = nil
        queuedTaskEditConflicts = []
        syncErrorMessage = nil
        inviteStatus = nil
        pendingJoinRequest = nil
        familyAccessDecision = nil
        joinRequests = []
        houseOwnershipOffer = nil
        householdPremium = .inactive
        aiConsentStatus = .withheld
        viewerAge = .unknown
        minorHome = nil

        guard let user else {
            homeAccessState = .noHome
            currentPermissionRole = .member
            familyGroup = PreviewData.familyGroup
            resetActivityState()
            return
        }

        homeAccessState = .loading

        #if DEBUG
        if user.isDebugAccount {
            activateLocalHomeContext(for: user)
            return
        }
        #endif

        if let remoteHomeBackend {
            isSyncingHome = true
            defer { finishSyncingHome(ifCurrent: contextToken) }

            guard let load = await loadMembershipOutcome(
                for: user,
                from: remoteHomeBackend,
                contextToken: contextToken
            ) else {
                return
            }

            viewerAge = load.viewerAge
            switch load.outcome {
            case .member(let state):
                apply(state)
                homeAccessState = .authorized
                cacheActiveHomeLocally()
                cacheAppSnapshotLocally()
                startRealtimeSync()
            case .minor(let home):
                enterMinorView(home, for: user.id)
            case .awaitingApproval(let request):
                pendingJoinRequest = request
                homeAccessState = .pendingApproval
                currentPermissionRole = .member
                familyGroup = PreviewData.familyGroup
                resetActivityState()
            case .notAMember(let decision):
                currentPermissionRole = .member
                familyGroup = PreviewData.familyGroup
                resetActivityState()
                familyAccessDecision = decision
                homeAccessState = decision == nil ? .noHome : .accessDecision
            case .unverifiable:
                homeAccessState = .unavailable
                currentPermissionRole = .member
                familyGroup = PreviewData.familyGroup
                resetActivityState()
                syncErrorMessage = "Não foi possível verificar sua participação nesta casa."
                return
            }
            recordTermsAcceptanceIfNeeded()
            return
        }

        #if DEBUG
        activateLocalHomeContext(for: user)
        #else
        homeAccessState = .unavailable
        syncErrorMessage = "Não dá para fazer isso agora. Tente mais tarde."
        #endif
    }

    func refreshHomeFromRemote(for user: AuthUser?) async {
        guard let user,
              user.id == activeHomeUserID,
              !usesLocalDebugBackend(for: user),
              let remoteHomeBackend,
              !isSyncingHome else {
            return
        }

        await waitForPendingRemoteMutations()
        guard user.id == activeHomeUserID else { return }

        let contextToken = currentHomeContextToken
        let requestedRevision = localStateRevision
        isSyncingHome = true
        syncErrorMessage = nil
        defer { finishSyncingHome(ifCurrent: contextToken) }

        guard let load = await loadMembershipOutcome(
            for: user,
            from: remoteHomeBackend,
            contextToken: contextToken
        ) else {
            return
        }

        if case .unverifiable = load.outcome {
            // An unreachable server says nothing about age, so the last verified reading stands.
        } else {
            viewerAge = load.viewerAge
        }
        applyMembershipOutcome(
            load.outcome,
            for: user.id,
            mergingContentAtRevision: requestedRevision
        )
    }

    private func loadMembershipOutcome(
        for user: AuthUser,
        from backend: any RemoteHomeBackend,
        contextToken: HomeContextToken
    ) async -> HomeMembershipLoad? {
        var viewerAge = AgeStatus.unknown
        do {
            let context = try await backend.loadHomeContext(for: user)
            guard isCurrentHomeContext(contextToken) else { return nil }
            viewerAge = context.viewerAge
            if let state = context.state {
                return HomeMembershipLoad(outcome: .member(state), viewerAge: viewerAge)
            }

            // A non-adult reads the house only through get_minor_home_view.
            if context.isMinorView {
                do {
                    let home = try await backend.loadMinorHome()
                    guard isCurrentHomeContext(contextToken) else { return nil }
                    if home.viewer.state.isMember {
                        return HomeMembershipLoad(outcome: .minor(home), viewerAge: viewerAge)
                    }
                } catch RemoteHomeBackendError.operationUnavailable {
                    guard isCurrentHomeContext(contextToken) else { return nil }
                }
            }

            let request = try await backend.loadPendingJoinRequest()
            guard isCurrentHomeContext(contextToken) else { return nil }
            if let request {
                return HomeMembershipLoad(outcome: .awaitingApproval(request), viewerAge: viewerAge)
            }

            let decision = try await backend.loadFamilyAccessDecision()
            guard isCurrentHomeContext(contextToken) else { return nil }
            return HomeMembershipLoad(outcome: .notAMember(decision), viewerAge: viewerAge)
        } catch is CancellationError {
            return nil
        } catch {
            guard isCurrentHomeContext(contextToken) else { return nil }
            return HomeMembershipLoad(outcome: .unverifiable, viewerAge: viewerAge)
        }
    }

    // Membership decides access; only the content merge may be withheld by a local edit.
    private func applyMembershipOutcome(
        _ outcome: HomeMembershipOutcome,
        for userID: String,
        mergingContentAtRevision requestedRevision: UInt64
    ) {
        let hadAuthorizedHome = homeAccessState == .authorized
        let hasUnmergedLocalEdits = localStateRevision != requestedRevision
        let lostMembershipNotice = Self.lostMembershipNotice(
            forAuthorizedHome: hadAuthorizedHome,
            discardingLocalEdits: hasUnmergedLocalEdits
        )

        switch outcome {
        case .member(let state):
            if homeAccessState == .minorMember {
                minorHome = nil
            }
            homeAccessState = .authorized
            guard !hasUnmergedLocalEdits else { return }
            apply(state)
            cacheActiveHomeLocally()
            cacheAppSnapshotLocally()
        case .minor(let home):
            if hadAuthorizedHome {
                releaseHousehold(discardingQueuedWrites: true)
                clearCachedHome(for: userID)
            }
            enterMinorView(home, for: userID)
        case .awaitingApproval(let request):
            releaseHousehold(discardingQueuedWrites: true)
            clearCachedHome(for: userID)
            pendingJoinRequest = request
            homeAccessState = .pendingApproval
            syncErrorMessage = lostMembershipNotice
        case .notAMember(let decision):
            releaseHousehold(discardingQueuedWrites: true)
            clearCachedHome(for: userID)
            familyAccessDecision = decision
            homeAccessState = decision == nil ? .noHome : .accessDecision
            syncErrorMessage = lostMembershipNotice
        case .unverifiable:
            // The state must change first: releasing the household re-syncs the
            // reminders, and an unverifiable membership must not cancel them.
            homeAccessState = .unavailable
            releaseHousehold(discardingQueuedWrites: false)
            syncErrorMessage = "Não foi possível verificar sua participação nesta casa."
        }
    }

    private func enterMinorView(_ home: MinorHome, for userID: String) {
        stopRealtimeSync()
        minorHome = home
        pendingJoinRequest = nil
        familyAccessDecision = nil
        joinRequests = []
        houseOwnershipOffer = nil
        inviteStatus = nil
        currentPermissionRole = .member
        familyGroup = PreviewData.familyGroup
        resetActivityState()
        homeAccessState = .minorMember
        synchronizeLocalNotifications()
    }

    private func releaseHousehold(discardingQueuedWrites: Bool) {
        if discardingQueuedWrites {
            remoteMutationTask?.cancel()
            remoteMutationTask = nil
            remoteMutationGeneration &+= 1
        }
        stopRealtimeSync()
        pendingJoinRequest = nil
        familyAccessDecision = nil
        minorHome = nil
        currentPermissionRole = .member
        familyGroup = PreviewData.familyGroup
        resetActivityState()
    }

    private static func lostMembershipNotice(
        forAuthorizedHome hadAuthorizedHome: Bool,
        discardingLocalEdits: Bool
    ) -> String? {
        guard hadAuthorizedHome else { return nil }
        return discardingLocalEdits
            ? "Você não faz mais parte desta casa. O que você mudou agora não foi salvo."
            : "Você não faz mais parte desta casa."
    }

    @discardableResult
    func createHome(named rawName: String, owner: AuthUser?) async -> Bool {
        let name = Self.normalizedHomeName(rawName)
        guard !name.isEmpty else { return false }
        let contextToken = currentHomeContextToken
        syncErrorMessage = nil

        if !usesLocalDebugBackend(for: owner ?? activeUser),
           let remoteHomeBackend {
            isSyncingHome = true
            defer { finishSyncingHome(ifCurrent: contextToken) }

            do {
                let state = try await remoteHomeBackend.createHome(named: name, owner: owner)
                guard isCurrentHomeContext(contextToken) else { return false }
                apply(state)
                homeAccessState = .authorized
                persistActiveHome()
                persistActivityLocally()
                startRealtimeSync()
                return true
            } catch {
                guard isCurrentHomeContext(contextToken) else { return false }
                let code = RemoteRPCErrorCode.from(error)
                if code == .ageSignalRequired {
                    ageCheckRequested = true
                }
                syncErrorMessage = code?.userMessage() ?? "Não deu para criar a casa agora. Tente de novo."
                Haptics.error()
                return false
            }
        }

        #if DEBUG
        familyGroup = FamilyGroup(
            name: name,
            inviteCode: Self.secureLocalInviteCode(),
            members: [
                Self.householdMember(for: owner, relationship: "", permissionRole: .owner),
                Self.ninaAssistantMember
            ]
        )
        homeAccessState = .authorized
        currentPermissionRole = .owner
        resetActivityState()
        persistActiveHome()
        persistActivityLocally()
        return true
        #else
        homeAccessState = .unavailable
        syncErrorMessage = "Não dá para criar a casa agora. Tente mais tarde."
        return false
        #endif
    }

    @discardableResult
    func joinHome(with rawInvite: String, member: AuthUser?) async -> Bool {
        guard let inviteCode = Self.normalizedInviteCode(from: rawInvite) else { return false }
        let contextToken = currentHomeContextToken
        syncErrorMessage = nil

        if !usesLocalDebugBackend(for: member ?? activeUser),
           let remoteHomeBackend {
            isSyncingHome = true
            defer { finishSyncingHome(ifCurrent: contextToken) }

            do {
                let outcome = try await remoteHomeBackend.requestHomeAccess(
                    with: inviteCode,
                    member: member
                )
                guard isCurrentHomeContext(contextToken) else { return false }
                switch outcome {
                case .joined(let state):
                    apply(state)
                    pendingJoinRequest = nil
                    homeAccessState = .authorized
                    persistActiveHome()
                    persistActivityLocally()
                    startRealtimeSync()
                case .pending(let request):
                    pendingJoinRequest = request
                    homeAccessState = .pendingApproval
                    currentPermissionRole = .member
                    familyGroup = PreviewData.familyGroup
                    resetActivityState()
                }
                return true
            } catch {
                guard isCurrentHomeContext(contextToken) else { return false }
                syncErrorMessage = error is RemoteHomeBackendError
                    ? "Este convite é inválido, expirou ou a casa está sem vagas."
                    : "Não deu para verificar o convite agora. Tente de novo em instantes."
                Haptics.error()
                return false
            }
        }

        #if DEBUG
        familyGroup = FamilyGroup(
            name: Self.homeName(fromInviteCode: inviteCode),
            inviteCode: inviteCode,
            members: [
                Self.householdMember(for: member, relationship: "Você"),
                Self.ninaAssistantMember
            ]
        )
        homeAccessState = .authorized
        currentPermissionRole = .member
        resetActivityState()
        persistActiveHome()
        persistActivityLocally()
        return true
        #else
        homeAccessState = .unavailable
        syncErrorMessage = "Não dá para entrar na casa agora. Tente mais tarde."
        return false
        #endif
    }

    @discardableResult
    func cancelPendingJoinRequest() async -> Bool {
        guard let request = pendingJoinRequest else { return false }
        let contextToken = currentHomeContextToken
        syncErrorMessage = nil

        if !usesLocalDebugBackend(for: activeUser),
           let remoteHomeBackend {
            isSyncingHome = true
            defer { finishSyncingHome(ifCurrent: contextToken) }

            do {
                try await remoteHomeBackend.cancelJoinRequest(request.id)
                guard isCurrentHomeContext(contextToken) else { return false }
                pendingJoinRequest = nil
                homeAccessState = .noHome
                return true
            } catch {
                guard isCurrentHomeContext(contextToken) else { return false }
                syncErrorMessage = "Não foi possível cancelar o pedido agora."
                Haptics.error()
                return false
            }
        }

        #if DEBUG
        pendingJoinRequest = nil
        homeAccessState = .noHome
        return true
        #else
        return false
        #endif
    }

    @discardableResult
    func acknowledgeFamilyAccessDecision() async -> Bool {
        guard let decision = familyAccessDecision else { return false }
        let contextToken = currentHomeContextToken
        syncErrorMessage = nil

        if !usesLocalDebugBackend(for: activeUser),
           let remoteHomeBackend {
            isSyncingHome = true
            defer { finishSyncingHome(ifCurrent: contextToken) }

            do {
                try await remoteHomeBackend.acknowledgeFamilyAccessDecision(decision.id)
                guard isCurrentHomeContext(contextToken) else { return false }
                familyAccessDecision = nil
                homeAccessState = .noHome
                return true
            } catch {
                guard isCurrentHomeContext(contextToken) else { return false }
                syncErrorMessage = "Não deu para marcar esse aviso como lido agora."
                Haptics.error()
                return false
            }
        }

        #if DEBUG
        familyAccessDecision = nil
        homeAccessState = .noHome
        return true
        #else
        return false
        #endif
    }

    func previewHomeInvite(_ rawInvite: String) async -> FamilyInvitePreview? {
        guard let inviteCode = Self.normalizedInviteCode(from: rawInvite) else { return nil }
        let contextToken = currentHomeContextToken

        if !usesLocalDebugBackend(for: activeUser),
           let remoteHomeBackend {
            do {
                let preview = try await remoteHomeBackend.previewInvite(code: inviteCode)
                guard isCurrentHomeContext(contextToken) else { return nil }
                return preview
            } catch {
                return nil
            }
        }

        #if DEBUG
        return FamilyInvitePreview(
            code: inviteCode,
            familyName: "Casa compartilhada",
            isValid: true
        )
        #else
        return nil
        #endif
    }

    @discardableResult
    func updateFamilyGroup(name: String) async -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, canManageFamily else { return false }
        let contextToken = currentHomeContextToken
        syncErrorMessage = nil

        if !usesLocalDebugBackend(for: activeUser),
           let remoteHomeBackend {
            await waitForPendingRemoteMutations()
            guard isCurrentHomeContext(contextToken) else { return false }
            isSyncingHome = true
            defer { finishSyncingHome(ifCurrent: contextToken) }

            do {
                let state = try await remoteHomeBackend.updateFamilySettings(
                    familyID: familyGroup.id,
                    name: trimmedName
                )
                guard isCurrentHomeContext(contextToken) else { return false }
                apply(state)
                homeAccessState = .authorized
                persistActiveHome()
                return true
            } catch {
                guard isCurrentHomeContext(contextToken) else { return false }
                syncErrorMessage = "Não foi possível salvar os ajustes da casa."
                Haptics.error()
                return false
            }
        }

        #if DEBUG
        familyGroup.name = trimmedName
        persistActiveHome()
        return true
        #else
        homeAccessState = .unavailable
        syncErrorMessage = "Não dá para fazer isso agora. Tente mais tarde."
        return false
        #endif
    }

    func setWeeklyDigestEnabled(_ isEnabled: Bool) {
        guard canManageFamily, familyGroup.weeklyDigestEnabled != isEnabled else { return }
        let contextToken = currentHomeContextToken
        let previousValue = familyGroup.weeklyDigestEnabled
        let familyName = familyGroup.name
        syncErrorMessage = nil
        familyGroup.weeklyDigestEnabled = isEnabled
        persistActiveHome()

        enqueueRemoteMutation(errorMessage: "Não foi possível salvar o resumo semanal.") {
            [weak self] backend,
            familyID,
            _ in
            do {
                let state = try await backend.updateFamilySettings(
                    familyID: familyID,
                    name: familyName,
                    weeklyDigestEnabled: isEnabled
                )
                guard let self, self.isCurrentHomeContext(contextToken) else { return }
                self.apply(state)
                self.persistActiveHome()
                Haptics.success()
            } catch {
                guard let self, self.isCurrentHomeContext(contextToken) else { throw error }
                self.familyGroup.weeklyDigestEnabled = previousValue
                self.persistActiveHome()
                Haptics.error()
                throw error
            }
        }
    }

    @discardableResult
    func rotateFamilyInvite() async -> Bool {
        guard canManageFamily else { return false }
        let contextToken = currentHomeContextToken
        syncErrorMessage = nil

        if !usesLocalDebugBackend(for: activeUser),
           let remoteHomeBackend {
            await waitForPendingRemoteMutations()
            guard isCurrentHomeContext(contextToken) else { return false }
            isSyncingHome = true
            defer { finishSyncingHome(ifCurrent: contextToken) }

            do {
                let state = try await remoteHomeBackend.rotateFamilyInvite(familyID: familyGroup.id)
                guard isCurrentHomeContext(contextToken) else { return false }
                apply(state)
                homeAccessState = .authorized
                persistActiveHome()
                return true
            } catch {
                guard isCurrentHomeContext(contextToken) else { return false }
                syncErrorMessage = "Não foi possível gerar um novo convite."
                Haptics.error()
                return false
            }
        }

        #if DEBUG
        familyGroup.inviteCode = Self.secureLocalInviteCode()
        persistActiveHome()
        return true
        #else
        homeAccessState = .unavailable
        syncErrorMessage = "Não dá para fazer isso agora. Tente mais tarde."
        return false
        #endif
    }

    @discardableResult
    func addFamilyMember(_ member: HouseholdMember) async -> Bool {
        let contextToken = currentHomeContextToken
        syncErrorMessage = nil

        if member.role != .assistant {
            guard canInviteMorePeople else {
                syncErrorMessage = "A casa já atingiu o limite de 8 pessoas."
                return false
            }
        }
        guard canManageFamily, member.identityState == .unclaimed else { return false }

        if !usesLocalDebugBackend(for: activeUser),
           let remoteHomeBackend {
            await waitForPendingRemoteMutations()
            guard isCurrentHomeContext(contextToken) else { return false }
            isSyncingHome = true
            defer { finishSyncingHome(ifCurrent: contextToken) }

            do {
                let state = try await remoteHomeBackend.addUnclaimedMember(member, familyID: familyGroup.id)
                guard isCurrentHomeContext(contextToken) else { return false }
                apply(state)
                homeAccessState = .authorized
                persistActiveHome()
                return true
            } catch {
                guard isCurrentHomeContext(contextToken) else { return false }
                syncErrorMessage = "Não foi possível adicionar essa pessoa à casa."
                Haptics.error()
                return false
            }
        }

        #if DEBUG
        familyGroup.members.append(member)
        persistActiveHome()
        return true
        #else
        homeAccessState = .unavailable
        syncErrorMessage = "Não dá para fazer isso agora. Tente mais tarde."
        return false
        #endif
    }

    @discardableResult
    func updateFamilyMember(_ member: HouseholdMember) async -> Bool {
        guard canEditFamilyMember(member) else { return false }
        let contextToken = currentHomeContextToken
        syncErrorMessage = nil

        if !usesLocalDebugBackend(for: activeUser),
           let remoteHomeBackend {
            await waitForPendingRemoteMutations()
            guard isCurrentHomeContext(contextToken) else { return false }
            isSyncingHome = true
            defer { finishSyncingHome(ifCurrent: contextToken) }

            do {
                let state = try await remoteHomeBackend.updateFamilyMember(member)
                guard isCurrentHomeContext(contextToken) else { return false }
                apply(state)
                homeAccessState = .authorized
                persistActiveHome()
                return true
            } catch {
                guard isCurrentHomeContext(contextToken) else { return false }
                syncErrorMessage = "Não foi possível salvar este perfil."
                Haptics.error()
                return false
            }
        }

        #if DEBUG
        guard let index = familyGroup.members.firstIndex(where: { $0.id == member.id }) else {
            return false
        }
        familyGroup.members[index] = member
        persistActiveHome()
        return true
        #else
        return false
        #endif
    }

    @discardableResult
    func removeFamilyMember(_ member: HouseholdMember) async -> Bool {
        guard canRemoveFamilyMember(member) else { return false }
        let contextToken = currentHomeContextToken
        syncErrorMessage = nil

        if !usesLocalDebugBackend(for: activeUser),
           let remoteHomeBackend {
            await waitForPendingRemoteMutations()
            guard isCurrentHomeContext(contextToken) else { return false }
            isSyncingHome = true
            defer { finishSyncingHome(ifCurrent: contextToken) }

            do {
                let state = try await remoteHomeBackend.removeFamilyMember(member.id)
                guard isCurrentHomeContext(contextToken) else { return false }
                apply(state)
                homeAccessState = .authorized
                persistActiveHome()
                return true
            } catch {
                guard isCurrentHomeContext(contextToken) else { return false }
                syncErrorMessage = "Não foi possível remover esta pessoa da casa."
                Haptics.error()
                return false
            }
        }

        #if DEBUG
        familyGroup.members.removeAll { $0.id == member.id }
        persistActiveHome()
        return true
        #else
        return false
        #endif
    }

    // The owner holds the house and a minor leaves only through a guardian, so only another adult may walk out.
    var canLeaveFamily: Bool {
        hasActiveHome
            && currentPermissionRole != .owner
            && currentFamilyMember?.role == .adult
            && !usesLocalDebugBackend(for: activeUser)
            && remoteHomeBackend != nil
    }

    // The owner holds the house, so leaving it starts with handing it to someone else.
    var ownerMustHandOverBeforeLeaving: Bool {
        hasActiveHome
            && currentPermissionRole == .owner
            && currentFamilyMember?.role == .adult
            && !usesLocalDebugBackend(for: activeUser)
            && remoteHomeBackend != nil
    }

    var hasAdultToHoldTheHouse: Bool {
        familyGroup.members.contains { canOfferHouse(to: $0) }
    }

    // Only the owner offers the house, and only to another adult with an account in it.
    func canOfferHouse(to member: HouseholdMember) -> Bool {
        ownerMustHandOverBeforeLeaving
            && member.role == .adult
            && member.identityState == .claimed
            && member.userID != nil
            && member.userID != activeHomeUserID
    }

    func houseOffer(to member: HouseholdMember) -> HouseOwnershipOffer? {
        guard let offer = liveHouseOffer, offer.memberID == member.id else { return nil }
        return offer
    }

    // The server stops honouring an offer after seven days, so the phone stops showing it then too.
    var liveHouseOffer: HouseOwnershipOffer? {
        guard let offer = houseOwnershipOffer, offer.expiresAt > .now else { return nil }
        return offer
    }

    var houseOfferRecipientName: String? {
        guard let offer = liveHouseOffer else { return nil }
        return familyGroup.members.first { $0.id == offer.memberID }?.name
    }

    // The offer waiting for this person, shown only while its owner still holds the house.
    var houseOfferForMe: HouseOwnershipOffer? {
        guard hasActiveHome,
              let offer = liveHouseOffer,
              let me = currentFamilyMember,
              offer.memberID == me.id,
              me.role == .adult,
              currentPermissionRole != .owner,
              houseOfferOwnerName != nil else { return nil }
        return offer
    }

    var houseOfferOwnerName: String? {
        guard let offer = houseOwnershipOffer else { return nil }
        return familyGroup.members.first {
            $0.userID == offer.offeredBy && $0.permissionRole == .owner
        }?.name
    }

    @discardableResult
    func offerHouse(to member: HouseholdMember) async -> Bool {
        guard canOfferHouse(to: member) else { return false }
        return await changeHouseHolder(
            failure: { RemoteRPCErrorCode.from($0)?.userMessage(name: member.name) ?? "Não deu para passar a casa agora. Tente de novo." }
        ) { backend, _ in
            try await backend.offerFamilyOwnership(to: member.id)
        }
    }

    // The owner withdraws an offer and the person it was made to declines it through the same call.
    @discardableResult
    func withdrawHouseOffer() async -> Bool {
        guard houseOwnershipOffer != nil else { return false }
        return await changeHouseHolder(
            failure: { _ in "Não deu para desfazer agora. Tente de novo." }
        ) { backend, familyID in
            try await backend.cancelFamilyOwnershipOffer(familyID: familyID)
        }
    }

    @discardableResult
    func acceptHouseOffer() async -> Bool {
        guard houseOfferForMe != nil else { return false }
        return await changeHouseHolder(
            failure: { RemoteRPCErrorCode.from($0)?.userMessage() ?? "Não deu para aceitar agora. Tente de novo." }
        ) { backend, familyID in
            try await backend.acceptFamilyOwnershipOffer(familyID: familyID)
        }
    }

    private func changeHouseHolder(
        failure: (Error) -> String,
        _ operation: (any RemoteHomeBackend, UUID) async throws -> RemoteHomeState
    ) async -> Bool {
        guard hasActiveHome, !usesLocalDebugBackend(for: activeUser), let remoteHomeBackend else { return false }
        let contextToken = currentHomeContextToken
        let familyID = familyGroup.id
        syncErrorMessage = nil

        await waitForPendingRemoteMutations()
        guard isCurrentHomeContext(contextToken) else { return false }
        isSyncingHome = true
        defer { finishSyncingHome(ifCurrent: contextToken) }

        do {
            let state = try await operation(remoteHomeBackend, familyID)
            guard isCurrentHomeContext(contextToken) else { return false }
            apply(state)
            homeAccessState = .authorized
            persistActiveHome()
            return true
        } catch {
            guard isCurrentHomeContext(contextToken) else { return false }
            if RemoteRPCErrorCode.from(error) == .familyOwnershipOfferNotFound {
                houseOwnershipOffer = nil
            }
            syncErrorMessage = failure(error)
            Haptics.error()
            return false
        }
    }

    @discardableResult
    func leaveFamily() async -> Bool {
        guard canLeaveFamily, let remoteHomeBackend else { return false }
        let contextToken = currentHomeContextToken
        let familyID = familyGroup.id
        syncErrorMessage = nil

        await waitForPendingRemoteMutations()
        guard isCurrentHomeContext(contextToken) else { return false }
        isSyncingHome = true

        do {
            try await remoteHomeBackend.leaveFamily(familyID: familyID)
        } catch {
            finishSyncingHome(ifCurrent: contextToken)
            guard isCurrentHomeContext(contextToken) else { return false }
            syncErrorMessage = "Não deu para sair da casa agora. Tente de novo."
            Haptics.error()
            return false
        }

        finishSyncingHome(ifCurrent: contextToken)
        guard isCurrentHomeContext(contextToken) else { return false }
        if let activeHomeUserID {
            clearCachedHome(for: activeHomeUserID)
        }
        notificationScheduler.removeDeliveredNotifications()
        await activateHomeContext(for: activeUser)
        return true
    }

    @discardableResult
    func approveJoinRequest(
        _ request: FamilyJoinRequest,
        permissionRole: FamilyPermissionRole = .member
    ) async -> Bool {
        guard canManageFamily else { return false }
        guard canInviteMorePeople else {
            syncErrorMessage = "A casa já atingiu o limite de 8 pessoas."
            return false
        }
        guard permissionRole != .owner,
              permissionRole != .admin || canChangeFamilyPermissions else {
            return false
        }
        let contextToken = currentHomeContextToken
        syncErrorMessage = nil

        if !usesLocalDebugBackend(for: activeUser),
           let remoteHomeBackend {
            isSyncingHome = true
            defer { finishSyncingHome(ifCurrent: contextToken) }

            do {
                let state = try await remoteHomeBackend.approveJoinRequest(
                    request.id,
                    permissionRole: permissionRole
                )
                guard isCurrentHomeContext(contextToken) else { return false }
                apply(state)
                homeAccessState = .authorized
                persistActiveHome()
                return true
            } catch {
                guard isCurrentHomeContext(contextToken) else { return false }
                let code = RemoteRPCErrorCode.from(error)
                syncErrorMessage = code?.userMessage(name: request.requesterName)
                    ?? "Não foi possível aprovar este pedido."
                Haptics.error()
                if code == .joinRequestAgeChanged {
                    isSyncingHome = false
                    await refreshHomeFromRemote(for: activeUser)
                }
                return false
            }
        }

        #if DEBUG
        joinRequests.removeAll { $0.id == request.id }
        return true
        #else
        return false
        #endif
    }

    @discardableResult
    func declineJoinRequest(_ request: FamilyJoinRequest) async -> Bool {
        guard canManageFamily else { return false }
        let contextToken = currentHomeContextToken
        syncErrorMessage = nil

        if !usesLocalDebugBackend(for: activeUser),
           let remoteHomeBackend {
            isSyncingHome = true
            defer { finishSyncingHome(ifCurrent: contextToken) }

            do {
                let state = try await remoteHomeBackend.declineJoinRequest(request.id)
                guard isCurrentHomeContext(contextToken) else { return false }
                apply(state)
                homeAccessState = .authorized
                persistActiveHome()
                return true
            } catch {
                guard isCurrentHomeContext(contextToken) else { return false }
                syncErrorMessage = "Não foi possível recusar este pedido."
                Haptics.error()
                return false
            }
        }

        #if DEBUG
        joinRequests.removeAll { $0.id == request.id }
        return true
        #else
        return false
        #endif
    }

    @discardableResult
    func approveJoinRequest(
        _ request: FamilyJoinRequest,
        asGuardian approval: GuardianApproval
    ) async -> Bool {
        guard canManageFamily, canActForMinors, !request.requesterAge.isAdult else { return false }
        guard canInviteMorePeople else {
            syncErrorMessage = "A casa já atingiu o limite de 8 pessoas."
            return false
        }
        let succeeded = await performHomeMutation(
            name: request.requesterName,
            fallback: "Não foi possível aprovar este pedido."
        ) { backend in
            try await backend.approveJoinRequestAsGuardian(request.id, approval: approval)
        }
        if !succeeded, lastMutationErrorCode == .joinRequestAgeChanged {
            await refreshHomeFromRemote(for: activeUser)
        }
        return succeeded
    }

    @discardableResult
    func addMinorProfile(_ draft: MinorProfileDraft) async -> Bool {
        guard canActForMinors, canInviteMorePeople else { return false }
        let familyID = familyGroup.id
        return await performHomeMutation(
            name: draft.name,
            fallback: "Não foi possível cadastrar este perfil."
        ) { backend in
            try await backend.addMinorProfile(draft, familyID: familyID)
        }
    }

    @discardableResult
    func declareMinorGuardianship(
        for member: HouseholdMember,
        declaration: GuardianDeclaration
    ) async -> Bool {
        guard canActForMinors, member.isMinorProfile else { return false }
        return await performHomeMutation(
            name: member.name,
            fallback: "Não deu para salvar agora."
        ) { backend in
            try await backend.declareMinorGuardianship(member.id, declaration: declaration)
        }
    }

    @discardableResult
    func setMinorHealthConsent(for member: HouseholdMember, granted: Bool) async -> Bool {
        guard member.minorAccess?.isViewerGuardian == true else { return false }
        return await performHomeMutation(
            name: member.name,
            fallback: "Não deu para salvar agora."
        ) { backend in
            try await backend.setMinorHealthConsent(
                member.id,
                granted: granted,
                consentVersion: MinorConsentVersion.current
            )
        }
    }

    @discardableResult
    func updateMinorSupervision(for member: HouseholdMember, update: MinorSupervisionUpdate) async -> Bool {
        guard member.minorAccess?.isViewerGuardian == true else { return false }
        return await performHomeMutation(
            name: member.name,
            fallback: "Não deu para salvar agora."
        ) { backend in
            try await backend.setMinorSupervision(member.id, update: update)
        }
    }

    @discardableResult
    func changeMinorBand(for member: HouseholdMember, to band: MinorBand) async -> Bool {
        guard let supervision = member.minorAccess?.supervision,
              member.minorAccess?.isViewerGuardian == true,
              band != supervision.band else { return false }
        // Only an unclaimed profile may grow older, and only with the consent affirmed again.
        let consentVersion: String? = band > supervision.band ? MinorConsentVersion.current : nil
        if band > supervision.band, member.isClaimed {
            return false
        }
        return await performHomeMutation(
            name: member.name,
            fallback: "Não deu para salvar agora."
        ) { backend in
            try await backend.changeMinorBand(member.id, band: band, consentVersion: consentVersion)
        }
    }

    @discardableResult
    func endMinorGuardianship(for member: HouseholdMember) async -> Bool {
        guard member.minorAccess?.isViewerGuardian == true else { return false }
        return await performHomeMutation(
            name: member.name,
            fallback: "Não deu para salvar agora."
        ) { backend in
            try await backend.endMinorGuardianship(member.id)
        }
    }

    @discardableResult
    func reportNinaReply(_ message: ChatMessage, reason: NinaReplyReportReason) async -> Bool {
        guard message.sender == .nina else { return false }
        let contextToken = currentHomeContextToken
        syncErrorMessage = nil
        guard let activeUser,
              !usesLocalDebugBackend(for: activeUser),
              let remoteHomeBackend else {
            return false
        }
        do {
            try await remoteHomeBackend.reportNinaReply(message.id, reason: reason)
            guard isCurrentHomeContext(contextToken) else { return false }
            Haptics.success()
            return true
        } catch {
            guard isCurrentHomeContext(contextToken) else { return false }
            syncErrorMessage = RemoteRPCErrorCode.from(error)?.userMessage() ?? "Não deu para enviar agora."
            Haptics.error()
            return false
        }
    }

    // Only a sign-in that just passed the welcome screen's footnote may be recorded as accepting the Terms;
    // a restored session never saw the current version, so it waits for the person to tap Aceitar.
    // The footnote outlives a relaunch on this phone until the server records it.
    func noteTermsFootnoteShown(for userID: String, at shownAt: Date = .now) {
        termsFootnote = TermsFootnote(userID: userID, shownAt: shownAt, wasRestored: false)
        hasUnrecordedTermsFootnote = true
        PrivateLocalDataAccess.writeDataBestEffort(
            Data(Self.termsFootnoteDateFormatter.string(from: shownAt).utf8),
            forKey: Self.termsFootnoteKey(for: userID),
            ownerScope: PrivateLocalDataScope.termsFootnote(for: userID),
            store: privateDataStore,
            legacyDefaults: defaults
        )
    }

    var needsTermsAcceptance: Bool {
        viewerAge.isAdult
            && !viewerAge.terms.acceptedCurrent
            && !viewerAge.terms.reachedMajority
            && !isRecordingFootnoteAcceptance
    }

    // A footnote read back after a relaunch covers only Terms dated on or before the São Paulo day it was shown.
    static func termsFootnote(shownAt: Date, covers termsVersion: String) -> Bool {
        guard termsVersion.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else {
            return false
        }
        return termsVersionDayFormatter.string(from: shownAt) >= termsVersion
    }

    private func recordTermsAcceptanceIfNeeded() {
        guard viewerAge.isAdult,
              !viewerAge.terms.acceptedCurrent,
              !viewerAge.terms.reachedMajority,
              let activeUser,
              let footnote = termsFootnote,
              footnote.userID == activeUser.id,
              !usesLocalDebugBackend(for: activeUser),
              let remoteHomeBackend else {
            return
        }
        termsFootnote = nil
        let userID = activeUser.id
        if footnote.wasRestored,
           !Self.termsFootnote(shownAt: footnote.shownAt, covers: viewerAge.terms.currentTermsVersion) {
            removeStoredTermsFootnote(for: userID)
            hasUnrecordedTermsFootnote = false
            return
        }
        isRecordingFootnoteAcceptance = true
        // The acceptance belongs to the account, not to one home context, so a reload that raced it still
        // receives its result instead of showing the Terms gate to someone who just accepted them.
        Task { [weak self] in
            let status = try? await remoteHomeBackend.recordTermsAcceptance()
            guard let self, self.activeHomeUserID == userID else { return }
            self.isRecordingFootnoteAcceptance = false
            guard let status else {
                self.termsFootnote = footnote
                return
            }
            if self.viewerAge.isAdult {
                self.viewerAge.terms = status.terms
            }
            self.removeStoredTermsFootnote(for: userID)
            self.hasUnrecordedTermsFootnote = false
        }
    }

    private func storedTermsFootnote(for userID: String) -> TermsFootnote? {
        guard let stored = PrivateLocalDataAccess.loadString(
            forKey: Self.termsFootnoteKey(for: userID),
            ownerScope: PrivateLocalDataScope.termsFootnote(for: userID),
            store: privateDataStore,
            legacyDefaults: defaults
        ),
              let shownAt = Self.termsFootnoteDateFormatter.date(from: stored) else {
            return nil
        }
        return TermsFootnote(userID: userID, shownAt: shownAt, wasRestored: true)
    }

    private func removeStoredTermsFootnote(for userID: String) {
        PrivateLocalDataAccess.removeAllData(
            forOwnerScope: PrivateLocalDataScope.termsFootnote(for: userID),
            store: privateDataStore
        )
    }

    private static func termsFootnoteKey(for userID: String) -> String {
        "nina.termsFootnote.\(userID)"
    }

    private static let termsFootnoteDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let termsVersionDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "America/Sao_Paulo")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    @discardableResult
    func acceptTermsAsAdult() async -> Bool {
        let contextToken = currentHomeContextToken
        syncErrorMessage = nil
        guard let activeUser,
              !usesLocalDebugBackend(for: activeUser),
              let remoteHomeBackend else {
            viewerAge.terms.reachedMajority = false
            viewerAge.terms.acceptedCurrent = true
            return true
        }
        isSyncingHome = true
        defer { finishSyncingHome(ifCurrent: contextToken) }
        do {
            let status = try await remoteHomeBackend.recordTermsAcceptance()
            guard isCurrentHomeContext(contextToken) else { return false }
            viewerAge = status
            termsFootnote = nil
            removeStoredTermsFootnote(for: activeUser.id)
            hasUnrecordedTermsFootnote = false
            Haptics.success()
            return true
        } catch {
            guard isCurrentHomeContext(contextToken) else { return false }
            syncErrorMessage = RemoteRPCErrorCode.from(error)?.userMessage() ?? "Não deu para salvar agora."
            Haptics.error()
            return false
        }
    }

    // After age-signal records a new status the whole context is read again: the shape may have changed.
    func applyRecordedAge(_ status: AgeStatus, for user: AuthUser?) async {
        guard user?.id == activeHomeUserID else { return }
        viewerAge = status
        await activateHomeContext(for: user)
    }

    func refreshMinorHome() async {
        let contextToken = currentHomeContextToken
        guard homeAccessState == .minorMember,
              let activeUser,
              !usesLocalDebugBackend(for: activeUser),
              let remoteHomeBackend else {
            return
        }
        do {
            let home = try await remoteHomeBackend.loadMinorHome()
            guard isCurrentHomeContext(contextToken) else { return }
            if home.viewer.state.isMember {
                minorHome = home
                synchronizeLocalNotifications()
            } else {
                await refreshHomeFromRemote(for: activeUser)
            }
        } catch {
            guard isCurrentHomeContext(contextToken) else { return }
        }
    }

    var minorTaskItems: [TaskItem] {
        minorHome?.taskItems ?? []
    }

    // A minor's repeating task never lands on tonight: marking it done closes every occurrence through today.
    func markMinorTaskDone(
        _ id: TaskItem.ID,
        now: Date = .now,
        calendar: Calendar = .current
    ) async -> ChildDayMark? {
        guard let task = minorTaskItems.first(where: { $0.id == id }),
              let marked = ChildDay.markedDone(task, now: now, calendar: calendar) else {
            return nil
        }
        let nextDueAt: Date? = task.recurrence == .none ? nil : marked.dueAt
        if let nextDueAt, let dueAt = task.dueAt, nextDueAt <= dueAt {
            return nil
        }
        guard let written = await writeMinorTask(task, markDone: true, nextDueAt: nextDueAt) else {
            return nil
        }
        return ChildDayMark(baseline: task, written: written, markedAt: now)
    }

    @discardableResult
    func reopenMinorTask(_ mark: ChildDayMark) async -> Bool {
        guard let live = minorTaskItems.first(where: { $0.id == mark.written.id }),
              mark.holds(on: live) else { return false }
        let nextDueAt: Date? = live.recurrence == .none ? nil : mark.baseline.dueAt
        return await writeMinorTask(live, markDone: false, nextDueAt: nextDueAt) != nil
    }

    private func writeMinorTask(_ task: TaskItem, markDone: Bool, nextDueAt: Date?) async -> TaskItem? {
        let contextToken = currentHomeContextToken
        syncErrorMessage = nil
        guard homeAccessState == .minorMember,
              let activeUser,
              !usesLocalDebugBackend(for: activeUser),
              let remoteHomeBackend else {
            return nil
        }
        do {
            let home = try await remoteHomeBackend.setMinorTaskDone(
                task.id,
                expectedVersion: task.version,
                markDone: markDone,
                nextDueAt: nextDueAt
            )
            guard isCurrentHomeContext(contextToken) else { return nil }
            minorHome = home
            synchronizeLocalNotifications()
            return home.taskItems.first { $0.id == task.id }
        } catch {
            guard isCurrentHomeContext(contextToken) else { return nil }
            // A version conflict is settled by the house's version, silently, never by a sheet in a child's hands.
            if RemoteRPCErrorCode.from(error) == .taskVersionConflict {
                await refreshMinorHome()
                return nil
            }
            syncErrorMessage = RemoteRPCErrorCode.from(error)?.userMessage() ?? "Não deu para salvar agora."
            Haptics.error()
            return nil
        }
    }

    @discardableResult
    func acknowledgeMinorTerms() async -> Bool {
        let contextToken = currentHomeContextToken
        syncErrorMessage = nil
        guard let kind = minorHome?.viewer.acknowledgementKind,
              let activeUser,
              !usesLocalDebugBackend(for: activeUser),
              let remoteHomeBackend else {
            return false
        }
        isSyncingHome = true
        defer { finishSyncingHome(ifCurrent: contextToken) }
        do {
            let home = try await remoteHomeBackend.acknowledgeMinorTerms(
                kind: kind,
                textVersion: viewerAge.terms.currentTermsVersion
            )
            guard isCurrentHomeContext(contextToken) else { return false }
            minorHome = home
            Haptics.success()
            return true
        } catch {
            guard isCurrentHomeContext(contextToken) else { return false }
            syncErrorMessage = RemoteRPCErrorCode.from(error)?.userMessage() ?? "Não deu para salvar agora."
            Haptics.error()
            return false
        }
    }

    func minorSceneBecameActive(now: Date = .now) {
        guard homeAccessState == .minorMember, minorSessionStartedAt == nil else { return }
        minorSessionStartedAt = now
    }

    // Foreground time is counted on the device and synced when the app leaves the screen; the counter never touches UserDefaults.
    func minorSceneLeftForeground(now: Date = .now) async {
        let contextToken = currentHomeContextToken
        guard homeAccessState == .minorMember,
              let userID = activeHomeUserID,
              let startedAt = minorSessionStartedAt else {
            return
        }
        minorSessionStartedAt = nil
        let today = MinorUsageClock.day(for: now)
        let ledger = loadMinorUsageLedger(for: userID)
            .adding(seconds: Int(now.timeIntervalSince(startedAt)), on: today)
        writeMinorUsageLedger(ledger, for: userID)

        guard let activeUser,
              !usesLocalDebugBackend(for: activeUser),
              let remoteHomeBackend else {
            return
        }
        guard let result = try? await remoteHomeBackend.recordMinorUsage(
            day: ledger.day,
            minutes: ledger.minutes
        ) else { return }
        guard isCurrentHomeContext(contextToken) else { return }
        minorHome?.viewer.usageTodayMinutes = result.usageTodayMinutes
        minorHome?.viewer.supervision.dailyLimitMinutes = result.dailyLimitMinutes
    }

    func minorUsageMinutes(now: Date = .now) -> Int {
        guard let userID = activeHomeUserID else { return minorHome?.viewer.usageTodayMinutes ?? 0 }
        let today = MinorUsageClock.day(for: now)
        let ledger = loadMinorUsageLedger(for: userID)
        let running = minorSessionStartedAt.map { Int(now.timeIntervalSince($0)) } ?? 0
        let local = ledger.day == today ? ledger.adding(seconds: running, on: today).minutes : running / 60
        return max(local, minorHome?.viewer.usageTodayMinutes ?? 0)
    }

    func isMinorOverDailyLimit(now: Date = .now) -> Bool {
        guard let limit = minorHome?.viewer.supervision.dailyLimitMinutes else { return false }
        return minorUsageMinutes(now: now) >= limit
    }

    private func loadMinorUsageLedger(for userID: String) -> MinorUsageLedger {
        guard let data = PrivateLocalDataAccess.loadData(
            forKey: Self.minorUsageKey(for: userID),
            ownerScope: PrivateLocalDataScope.minorUsage(for: userID),
            store: privateDataStore,
            legacyDefaults: defaults
        ),
              let ledger = try? JSONDecoder().decode(MinorUsageLedger.self, from: data) else {
            return MinorUsageLedger(day: MinorUsageClock.day(for: .now), seconds: 0)
        }
        return ledger
    }

    private func writeMinorUsageLedger(_ ledger: MinorUsageLedger, for userID: String) {
        guard let data = try? JSONEncoder().encode(ledger) else { return }
        PrivateLocalDataAccess.writeDataBestEffort(
            data,
            forKey: Self.minorUsageKey(for: userID),
            ownerScope: PrivateLocalDataScope.minorUsage(for: userID),
            store: privateDataStore,
            legacyDefaults: defaults
        )
    }

    private static func minorUsageKey(for userID: String) -> String {
        "nina.minor.usage.\(userID)"
    }

    private func performHomeMutation(
        name: String?,
        fallback: String,
        _ operation: @escaping (any RemoteHomeBackend) async throws -> RemoteHomeState
    ) async -> Bool {
        let contextToken = currentHomeContextToken
        syncErrorMessage = nil
        lastMutationErrorCode = nil
        guard !usesLocalDebugBackend(for: activeUser), let remoteHomeBackend else {
            return false
        }
        await waitForPendingRemoteMutations()
        guard isCurrentHomeContext(contextToken) else { return false }
        isSyncingHome = true
        defer { finishSyncingHome(ifCurrent: contextToken) }

        do {
            let state = try await operation(remoteHomeBackend)
            guard isCurrentHomeContext(contextToken) else { return false }
            apply(state)
            homeAccessState = .authorized
            persistActiveHome()
            return true
        } catch {
            guard isCurrentHomeContext(contextToken) else { return false }
            lastMutationErrorCode = RemoteRPCErrorCode.from(error)
            syncErrorMessage = lastMutationErrorCode?.userMessage(name: name) ?? fallback
            Haptics.error()
            return false
        }
    }

    func sendMessage(
        _ rawText: String,
        attachments requestedAttachments: [NinaAttachmentInput] = []
    ) async {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        let attachments = attachmentGate.permittedAttachments(requestedAttachments)
        guard canSendNinaMessages,
              (!text.isEmpty || !attachments.isEmpty),
              !isNinaResponding else {
            return
        }
        let contextToken = currentHomeContextToken
        let familyID = familyGroup.id

        let userMessage = ChatMessage(
            sender: .user,
            text: text,
            timestamp: .now,
            attachments: attachments.map(\.metadata)
        )
        messages.append(userMessage)
        persistActivityLocally()

        isNinaResponding = true
        defer {
            if isCurrentHomeContext(contextToken) {
                isNinaResponding = false
            }
        }

        let response: NinaEngineResponse

        do {
            let usesLocalEngine = usesLocalDebugBackend(for: activeUser)
            let engine: any NinaEngine = usesLocalEngine
                ? fallbackNinaEngine
                : ninaEngine
            response = try await engine.respond(
                to: text,
                attachments: attachments,
                familyID: familyID,
                messageID: userMessage.id
            )
            guard isCurrentHomeContext(contextToken) else { return }
            ninaConnectionNotice = nil
        } catch let engineError as NinaEngineError where engineError != .unavailable {
            guard isCurrentHomeContext(contextToken) else { return }
            switch engineError {
            case .consentOutdated:
                // The server no longer counts this consent, so the card asks again and the unread message is dropped.
                messages.removeAll { $0.id == userMessage.id }
                restorableDraft = text
                applyAIMemoryConsent(nil)
                aiConsentStatus.lastRevokeReason = "policy_changed"
                aiConsentStatus.isGranted = false
                persistActivityLocally()
                Haptics.error()
                return
            case .ageConfirmationRequired:
                messages.removeAll { $0.id == userMessage.id }
                restorableDraft = text
                viewerAge = viewerAge.withoutAI()
                persistActivityLocally()
                Haptics.error()
                return
            case .aiBlocked:
                messages.removeAll { $0.id == userMessage.id }
                restorableDraft = text
                viewerAge = viewerAge.blockingAI()
                persistActivityLocally()
                Haptics.error()
                return
            case .inputNotSupported:
                // A refused message never stays on the phone in its original words.
                if let index = messages.firstIndex(where: { $0.id == userMessage.id }) {
                    messages[index].text = Self.heldMessageMarker
                    messages[index].attachments = []
                }
            default:
                break
            }
            response = NinaEngineResponse(
                reply: engineError.userMessage,
                suggestion: nil
            )
            ninaConnectionNotice = nil
        } catch {
            guard isCurrentHomeContext(contextToken) else { return }
            let fallbackResponse = try? await fallbackNinaEngine.respond(
                to: text,
                attachments: attachments,
                familyID: familyID,
                messageID: userMessage.id
            )
            guard isCurrentHomeContext(contextToken) else { return }
            response = fallbackResponse ?? NinaEngineResponse(
                    reply: "Não consegui organizar isso agora. Tente de novo em instantes.",
                    suggestion: nil
                )
            ninaConnectionNotice = "Sem conexão. Esta resposta veio do aparelho."
            Haptics.error()
        }
        guard isCurrentHomeContext(contextToken) else { return }

        let gate = NinaProposalGate.current
        let ninaMessage = ChatMessage(
            id: response.assistantMessageID ?? UUID(),
            sender: .nina,
            text: response.reply,
            timestamp: .now,
            suggestion: response.serverPersisted ? nil : response.suggestion,
            proposals: gate.visibleProposals(response.proposals),
            hasWithheldProposals: gate.withholdsProposals(response.proposals)
        )
        messages.append(ninaMessage)
        persistActivityLocally()

        if response.serverPersisted {
            ninaThread = response.threadID.flatMap {
                guard let userID = activeUser?.id,
                      let ownerID = UUID(uuidString: userID) else {
                    return nil
                }
                return NinaThread(
                    id: $0,
                    familyID: familyID,
                    ownerUserID: ownerID
                )
            }
        }
    }

    func applySuggestion(_ suggestion: NinaSuggestion) {
        guard messages.contains(where: { $0.suggestion == suggestion }) else { return }

        switch suggestion.kind {
        case .task, .gift, .document, .redistribution:
            addTask(
                title: suggestion.payloadTitle,
                subtitle: suggestion.payloadDetail,
                owner: suggestion.payloadOwner,
                dueLabel: suggestion.payloadDueLabel,
                dueAt: Self.inferredDueAt(from: suggestion.payloadDueLabel),
                category: suggestion.category,
                createdBy: "Nina"
            )
        case .seed:
            addTask(
                title: suggestion.payloadTitle,
                subtitle: suggestion.payloadDetail,
                owner: suggestion.payloadOwner,
                dueLabel: "Sem data",
                category: suggestion.category,
                kind: .seed,
                createdBy: "Nina"
            )
        case .reminder:
            addTask(
                title: suggestion.payloadTitle,
                subtitle: suggestion.payloadDetail,
                owner: suggestion.payloadOwner,
                dueLabel: suggestion.payloadDueLabel,
                dueAt: Self.inferredDueAt(from: suggestion.payloadDueLabel),
                category: suggestion.category,
                recurrence: .none,
                createdBy: "Nina"
            )
        }

        // A confirmed suggestion stops being confirmable. Leaving the card live
        // let every extra tap create another copy of the same thing.
        for index in messages.indices where messages[index].suggestion == suggestion {
            messages[index].suggestion = nil
        }

        // Nina's voice reaches the server only through nina-chat, so this line stays on the phone.
        let confirmation = ChatMessage(
            sender: .nina,
            text: "Você confirmou. Está na casa agora.",
            timestamp: .now
        )
        messages.append(confirmation)
        persistActivityLocally()
    }

    @discardableResult
    func resolveProposal(
        _ proposal: NinaProposal,
        decision: NinaProposalDecision,
        editedPayload: NinaProposalPayload? = nil,
        memoryVisibility: NinaMemoryVisibility? = nil
    ) async -> Bool {
        guard proposal.state == .pending,
              let activeUser,
              !usesLocalDebugBackend(for: activeUser),
              let remoteHomeBackend,
              hasActiveHome else {
            return false
        }
        let contextToken = currentHomeContextToken

        isSyncingHome = true
        defer { finishSyncingHome(ifCurrent: contextToken) }
        do {
            let resolution = try await remoteHomeBackend.resolveNinaProposal(
                proposal.id,
                decision: decision,
                editedPayload: editedPayload,
                memoryVisibility: memoryVisibility
            )
            guard isCurrentHomeContext(contextToken) else { return false }
            updateProposalState(proposal.id, state: resolution.state)
            persistActivityLocally()
            isSyncingHome = false
            await refreshHomeFromRemote(for: activeUser)
            guard isCurrentHomeContext(contextToken) else { return false }
            Haptics.success()
            return true
        } catch {
            guard isCurrentHomeContext(contextToken) else { return false }
            Haptics.error()
            return false
        }
    }

    func canEditMemory(_ memory: NinaMemory) -> Bool {
        guard let rawUserID = activeUser?.id,
              let userID = UUID(uuidString: rawUserID) else {
            return false
        }
        return memory.ownerUserID == userID
    }

    @discardableResult
    func updateMemory(_ memory: NinaMemory) async -> Bool {
        guard canEditMemory(memory),
              let activeUser,
              !usesLocalDebugBackend(for: activeUser),
              let remoteHomeBackend else {
            return false
        }
        let contextToken = currentHomeContextToken

        do {
            let updated = try await remoteHomeBackend.updateNinaMemory(memory)
            guard isCurrentHomeContext(contextToken) else { return false }
            if let index = ninaMemories.firstIndex(where: { $0.id == updated.id }) {
                ninaMemories[index] = updated
            }
            persistActivityLocally()
            return true
        } catch {
            guard isCurrentHomeContext(contextToken) else { return false }
            syncErrorMessage = "Não foi possível atualizar essa memória."
            return false
        }
    }

    @discardableResult
    func deleteMemory(_ memory: NinaMemory) async -> Bool {
        guard canEditMemory(memory),
              let activeUser,
              !usesLocalDebugBackend(for: activeUser),
              let remoteHomeBackend else {
            return false
        }
        let contextToken = currentHomeContextToken

        do {
            try await remoteHomeBackend.deleteNinaMemory(memory.id)
            guard isCurrentHomeContext(contextToken) else { return false }
            ninaMemories.removeAll { $0.id == memory.id }
            persistActivityLocally()
            return true
        } catch {
            guard isCurrentHomeContext(contextToken) else { return false }
            syncErrorMessage = "Não foi possível apagar essa memória."
            return false
        }
    }

    @discardableResult
    func deleteNinaChatHistory() async -> Bool {
        guard let activeUser,
              !usesLocalDebugBackend(for: activeUser),
              let remoteHomeBackend else {
            messages.removeAll()
            ninaThread = nil
            persistActivityLocally()
            return true
        }
        let contextToken = currentHomeContextToken
        let familyID = familyGroup.id

        do {
            try await remoteHomeBackend.deleteNinaChatHistory(familyID: familyID)
            guard isCurrentHomeContext(contextToken) else { return false }
            messages.removeAll()
            ninaThread = nil
            persistActivityLocally()
            return true
        } catch {
            guard isCurrentHomeContext(contextToken) else { return false }
            syncErrorMessage = "Não foi possível apagar o histórico da Nina."
            return false
        }
    }

    static let heldMessageMarker = "Mensagem não enviada."

    // The transfer abroad is its own consent: without the ticked box there is no grant to send.
    @discardableResult
    func grantAIMemoryConsent(transferConsented: Bool) async -> Bool {
        guard transferConsented else { return false }
        return await recordAIMemoryConsent(granted: true, transferConsented: true)
    }

    @discardableResult
    func revokeAIMemoryConsent() async -> Bool {
        await recordAIMemoryConsent(granted: false, transferConsented: false)
    }

    // The local record is a mirror of the server grant, never the grant itself.
    private func recordAIMemoryConsent(granted: Bool, transferConsented: Bool) async -> Bool {
        let contextToken = currentHomeContextToken
        let previousRecord = aiMemoryConsent
        syncErrorMessage = nil

        let optimisticRecord = granted
            ? AIMemoryConsentRecord(
                acceptedAt: .now,
                policyVersion: PrivacyPolicyVersion.current,
                transferConsented: transferConsented
            )
            : nil
        applyAIMemoryConsent(optimisticRecord)

        if activeUser != nil,
           !usesLocalDebugBackend(for: activeUser),
           let remoteHomeBackend {
            await waitForPendingRemoteMutations()
            guard isCurrentHomeContext(contextToken) else { return false }
            isSyncingHome = true
            defer { finishSyncingHome(ifCurrent: contextToken) }

            do {
                let state = try await remoteHomeBackend.recordNinaAIConsent(
                    granted: granted,
                    policyVersion: PrivacyPolicyVersion.current,
                    transferConsented: transferConsented
                )
                guard isCurrentHomeContext(contextToken) else { return false }
                apply(state)
                homeAccessState = .authorized
                persistActiveHome()
                if hasAIMemoryConsent {
                    hasStaleLocalConsent = false
                }
                return hasAIMemoryConsent == granted
            } catch {
                guard isCurrentHomeContext(contextToken) else { return false }
                applyAIMemoryConsent(previousRecord)
                let code = RemoteRPCErrorCode.from(error)
                switch code {
                case .ageConfirmationRequired:
                    viewerAge = viewerAge.withoutAI()
                case .ninaAIBlocked:
                    viewerAge = viewerAge.blockingAI()
                case .ninaConsentOutdated, .ninaTransferConsentRequired:
                    aiConsentStatus.lastRevokeReason = "policy_changed"
                default:
                    break
                }
                syncErrorMessage = code?.userMessage() ?? (granted
                    ? "Não foi possível registrar seu consentimento. Nada mudou por enquanto."
                    : "Não foi possível revogar seu consentimento. Ele continua ativo nesta casa.")
                Haptics.error()
                return false
            }
        }

        return true
    }

    private func applyAIMemoryConsent(_ record: AIMemoryConsentRecord?) {
        aiMemoryConsent = record
        guard let userID = activeHomeUserID else { return }

        guard let record, let data = try? JSONEncoder().encode(record) else {
            PrivateLocalDataAccess.removeData(
                forKey: Self.aiMemoryConsentKey(for: userID),
                ownerScope: PrivateLocalDataScope.aiConsent(for: userID),
                store: privateDataStore,
                legacyDefaults: defaults
            )
            return
        }

        PrivateLocalDataAccess.writeDataBestEffort(
            data,
            forKey: Self.aiMemoryConsentKey(for: userID),
            ownerScope: PrivateLocalDataScope.aiConsent(for: userID),
            store: privateDataStore,
            legacyDefaults: defaults
        )
    }

    // The file is the server's export of this account's own data, written byte for byte; the phone adds no one else.
    func exportAccountData() async throws -> Data {
        let contextToken = currentHomeContextToken
        guard let activeUser,
              !usesLocalDebugBackend(for: activeUser),
              let remoteHomeBackend else {
            throw RemoteHomeBackendError.operationUnavailable
        }
        let data = try await remoteHomeBackend.exportAccountData()
        guard isCurrentHomeContext(contextToken) else { throw CancellationError() }
        return data
    }

    func exportMinorData(for member: HouseholdMember) async throws -> Data {
        let contextToken = currentHomeContextToken
        guard member.minorAccess?.isViewerGuardian == true,
              let activeUser,
              !usesLocalDebugBackend(for: activeUser),
              let remoteHomeBackend else {
            throw RemoteHomeBackendError.operationUnavailable
        }
        let data = try await remoteHomeBackend.exportMinorData(member.id)
        guard isCurrentHomeContext(contextToken) else { throw CancellationError() }
        return data
    }

    var privacyExportFilename: String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "nina-privacy-export-\(formatter.string(from: .now)).json"
    }

    func clearLocalDataForActiveUser() {
        guard let userID = activeHomeUserID else { return }
        clearLocalData(for: userID)
    }

    // A minor's usage ledger and the last age reading stay, so signing out never resets a limit or the age step.
    // Work still in flight for this account is invalidated first, so nothing it finishes can write the house back.
    func clearHouseholdCopy(for userID: String) {
        if activeHomeUserID == userID {
            homeContextGeneration &+= 1
            remoteMutationTask?.cancel()
            remoteMutationTask = nil
            remoteMutationGeneration &+= 1
            notificationSyncTask?.cancel()
            notificationSyncTask = nil
        }
        notificationScheduler.removeDeliveredNotifications()
        clearCachedHome(for: userID)
        PrivateLocalDataAccess.removeAllData(
            forOwnerScope: PrivateLocalDataScope.aiConsent(for: userID),
            store: privateDataStore
        )
        defaults.removeObject(forKey: Self.aiMemoryConsentKey(for: userID))
    }

    func clearLocalData(for userID: String) {
        let clearsActiveContext = activeHomeUserID == userID
        if clearsActiveContext {
            homeContextGeneration &+= 1
        }

        clearCachedHome(for: userID)
        PrivateLocalDataAccess.removeAllData(
            forOwnerScope: PrivateLocalDataScope.aiConsent(for: userID),
            store: privateDataStore
        )
        PrivateLocalDataAccess.removeAllData(
            forOwnerScope: PrivateLocalDataScope.minorUsage(for: userID),
            store: privateDataStore
        )
        PrivateLocalDataAccess.removeAllData(
            forOwnerScope: PrivateLocalDataScope.ageAssurance(for: userID),
            store: privateDataStore
        )
        removeStoredTermsFootnote(for: userID)
        defaults.removeObject(forKey: Self.aiMemoryConsentKey(for: userID))

        guard clearsActiveContext else { return }

        remoteMutationTask?.cancel()
        remoteMutationTask = nil
        remoteMutationGeneration &+= 1
        stopRealtimeSync()
        notificationSyncTask?.cancel()
        notificationSyncTask = nil
        activeHomeUserID = nil
        activeUser = nil
        homeAccessState = .noHome
        currentPermissionRole = .member
        inviteStatus = nil
        pendingJoinRequest = nil
        familyAccessDecision = nil
        joinRequests = []
        houseOwnershipOffer = nil
        isNinaResponding = false
        ninaConnectionNotice = nil
        taskEditConflict = nil
        queuedTaskEditConflicts = []
        isSyncingHome = false
        syncErrorMessage = nil
        aiMemoryConsent = nil
        aiConsentStatus = .withheld
        hasStaleLocalConsent = false
        viewerAge = .unknown
        minorHome = nil
        minorSessionStartedAt = nil
        familyGroup = PreviewData.familyGroup
        resetActivityState()
    }

    private func updateProposalState(_ proposalID: UUID, state: NinaProposalState) {
        for messageIndex in messages.indices {
            guard let proposalIndex = messages[messageIndex].proposals.firstIndex(
                where: { $0.id == proposalID }
            ) else {
                continue
            }
            messages[messageIndex].proposals[proposalIndex].state = state
            return
        }
    }

    func addTask(
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
        kind: TaskKind = .task,
        createdBy: String = "Manual",
        sectionID: String = TaskSectionDefaults.houseTasksID
    ) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedOwner = owner.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDueLabel = dueLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }

        let task = TaskItem(
            kind: kind,
            title: trimmedTitle,
            subtitle: subtitle.trimmingCharacters(in: .whitespacesAndNewlines),
            owner: trimmedOwner.isEmpty ? "Casa" : trimmedOwner,
            ownerMemberID: Self.assignableMemberID(ownerMemberID, forOwner: trimmedOwner),
            dueLabel: kind == .seed ? "Sem data" : (trimmedDueLabel.isEmpty ? "Sem data" : trimmedDueLabel),
            dueAt: kind == .seed ? nil : dueAt,
            category: category,
            priority: priority,
            recurrence: kind == .seed ? .none : recurrence,
            reminderLead: kind == .seed ? .atTime : reminderLead,
            isDone: false,
            createdBy: createdBy,
            sectionID: sectionID
        )
        tasks.insert(task, at: 0)
        persistActivityLocally()
        synchronizeLocalNotifications()
        enqueueRemoteMutation(errorMessage: "Não foi possível sincronizar a nova tarefa.") {
            backend,
            familyID,
            user in
            try await backend.createTask(task, familyID: familyID, currentUser: user)
        }
    }

    @discardableResult
    func addTaskSection(
        title: String,
        symbolName: String = "list.bullet.rectangle.fill"
    ) -> TaskSection {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSymbolName = symbolName.trimmingCharacters(in: .whitespacesAndNewlines)
        let section = TaskSection(
            id: UUID().uuidString,
            title: trimmedTitle.isEmpty ? "Nova seção" : trimmedTitle,
            symbolName: trimmedSymbolName.isEmpty ? "list.bullet.rectangle.fill" : trimmedSymbolName,
            tone: nextTaskSectionTone
        )

        let sortOrder = taskSections.count
        taskSections.append(section)
        persistActivityLocally()
        enqueueRemoteMutation(errorMessage: "Não foi possível sincronizar a seção.") {
            backend,
            familyID,
            _ in
            try await backend.createTaskSection(section, sortOrder: sortOrder, familyID: familyID)
        }
        return section
    }

    @discardableResult
    func deleteTaskSection(_ sectionID: String) -> Bool {
        guard sectionID != Self.houseTasksSectionID,
              taskSections.contains(where: { $0.id == sectionID }) else {
            return false
        }

        taskSections.removeAll { $0.id == sectionID }
        for index in tasks.indices where tasks[index].sectionID == sectionID {
            tasks[index].sectionID = Self.houseTasksSectionID
            tasks[index].version += 1
        }

        persistActivityLocally()
        synchronizeLocalNotifications()
        enqueueRemoteMutation(errorMessage: "Não foi possível excluir a seção.") {
            backend,
            familyID,
            _ in
            try await backend.deleteTaskSection(sectionID, familyID: familyID)
        }
        return true
    }

    func updateTask(
        id: TaskItem.ID,
        title: String,
        subtitle: String,
        owner: String,
        ownerMemberID: UUID? = nil,
        dueLabel: String,
        dueAt: Date?,
        category: TaskCategory,
        priority: TaskPriority,
        recurrence: TaskRecurrence? = nil,
        reminderLead: TaskReminderLead? = nil,
        kind: TaskKind? = nil,
        expectedVersion: Int? = nil
    ) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedOwner = owner.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDueLabel = dueLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        let currentTask = tasks[index]
        var proposedTask = currentTask
        let proposedKind = kind ?? currentTask.kind
        proposedTask.kind = proposedKind
        proposedTask.title = trimmedTitle
        proposedTask.subtitle = subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        proposedTask.owner = trimmedOwner.isEmpty ? "Casa" : trimmedOwner
        proposedTask.ownerMemberID = Self.assignableMemberID(ownerMemberID, forOwner: trimmedOwner)
        proposedTask.dueLabel = proposedKind == .seed
            ? "Sem data"
            : (trimmedDueLabel.isEmpty ? "Sem data" : trimmedDueLabel)
        proposedTask.dueAt = proposedKind == .seed ? nil : dueAt
        proposedTask.category = category
        proposedTask.priority = priority
        if proposedKind == .seed {
            proposedTask.recurrence = .none
            proposedTask.reminderLead = .atTime
            proposedTask.snoozedUntil = nil
        } else {
            if let recurrence {
                proposedTask.recurrence = recurrence
                proposedTask.snoozedUntil = nil
            }
            if let reminderLead {
                proposedTask.reminderLead = reminderLead
            }
        }

        if let expectedVersion, expectedVersion != currentTask.version {
            presentTaskEditConflict(TaskEditConflict(localTask: proposedTask, remoteTask: currentTask))
            return
        }

        submitTaskUpdate(proposedTask, basedOn: currentTask)
    }

    @discardableResult
    func addTaskCategory(title: String) -> TaskCategory? {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return nil }

        if let existing = availableTaskCategories.first(where: { $0.title.caseInsensitiveCompare(trimmedTitle) == .orderedSame }) {
            return existing
        }

        let baseID = "custom-\(Self.slugified(trimmedTitle))"
        let existingIDs = Set(availableTaskCategories.map(\.id))
        var id = baseID.isEmpty ? "custom-\(UUID().uuidString)" : baseID
        var suffix = 2

        while existingIDs.contains(id) {
            id = "\(baseID)-\(suffix)"
            suffix += 1
        }

        let category = TaskCategory.custom(id: id, title: trimmedTitle, tone: nextCustomCategoryTone)
        customTaskCategories.append(category)
        persistActivityLocally()
        enqueueRemoteMutation(errorMessage: "Não foi possível sincronizar a categoria.") {
            backend,
            familyID,
            _ in
            try await backend.createTaskCategory(category, familyID: familyID)
        }
        return category
    }

    // A reminder's button closes the occurrence it announced, even when an earlier one was missed.
    func toggleTask(_ task: TaskItem, through announced: Date? = nil) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        let currentTask = tasks[index]
        var proposedTask = currentTask

        if !currentTask.isDone, currentTask.recurrence != .none {
            let anchor = max(currentTask.dueAt ?? .now, .now, announced ?? .distantPast).addingTimeInterval(1)
            guard let nextDate = currentTask.scheduledOccurrence(after: anchor) else { return }
            proposedTask.dueAt = nextDate
            proposedTask.dueLabel = Self.taskDueLabel(for: nextDate)
            proposedTask.snoozedUntil = nil
        } else {
            proposedTask.isDone.toggle()
            // Stamped here, not only on the way back from the server: without it
            // nothing local knows when a task closed, so "concluídas hoje" and the
            // day-cleared count stay empty forever on a device that is offline.
            proposedTask.completedAt = proposedTask.isDone ? .now : nil
        }
        submitTaskUpdate(proposedTask, basedOn: currentTask)

        if !currentTask.isDone {
            completionPulse &+= 1
        }
        if proposedTask.isDone, !currentTask.isDone {
            offerUndo(for: proposedTask.id)
        } else if !currentTask.isDone, currentTask.recurrence != .none {
            offerUndo(for: proposedTask.id, rolledFrom: currentTask, to: proposedTask)
        } else {
            clearUndo()
        }
    }

    // Completing is reversible for a moment. Closing something is the one action
    // people take by accident on a list, and an undo is cheaper than a confirm.
    func undoLastCompletion() {
        guard let id = undoableCompletionID,
              let task = tasks.first(where: { $0.id == id }) else { return }
        let roll = undoableRoll
        clearUndo()
        guard let roll, roll.after.id == id else {
            toggleTask(task)
            return
        }
        // A repeating task goes back to the occurrence it left, and only if nobody moved it since.
        guard task.isDone == roll.after.isDone,
              task.dueAt == roll.after.dueAt,
              task.snoozedUntil == roll.after.snoozedUntil else { return }
        var restored = task
        restored.dueAt = roll.before.dueAt
        restored.dueLabel = roll.before.dueLabel
        restored.snoozedUntil = roll.before.snoozedUntil
        submitTaskUpdate(restored, basedOn: task)
    }

    private func offerUndo(for id: TaskItem.ID, rolledFrom before: TaskItem? = nil, to after: TaskItem? = nil) {
        undoExpiryTask?.cancel()
        undoableRoll = before.flatMap { before in after.map { (before: before, after: $0) } }
        undoableCompletionID = id
        undoExpiryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.undoableCompletionID = nil
                self?.undoableRoll = nil
            }
        }
    }

    private func clearUndo() {
        undoExpiryTask?.cancel()
        undoExpiryTask = nil
        undoableCompletionID = nil
        undoableRoll = nil
    }

    func presentChildDay(for child: HouseholdMember, now: Date = .now) {
        guard ChildDay.canShow(child) else { return }
        childDayPresentation = ChildDayPresentation(
            childID: child.id,
            session: ChildDaySession(child: child, tasks: tasks, members: familyGroup.members, now: now)
        )
    }

    func dismissChildDay() {
        childDayPresentation = nil
    }

    // A child's list writes on its own path: no app-wide undo sits under the cover, a child never
    // settles a conflict, and a failed write waits for the adult instead of buzzing in a child's hands.
    func markChildTaskDone(
        _ id: TaskItem.ID,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> ChildDayMark? {
        guard let currentTask = tasks.first(where: { $0.id == id }),
              let markedTask = ChildDay.markedDone(currentTask, now: now, calendar: calendar) else {
            return nil
        }
        submitTaskUpdate(markedTask, basedOn: currentTask, for: .child)
        guard let written = tasks.first(where: { $0.id == id }) else { return nil }
        return ChildDayMark(baseline: currentTask, written: written, markedAt: now)
    }

    @discardableResult
    func reopenChildTask(_ mark: ChildDayMark) -> Bool {
        guard let currentTask = tasks.first(where: { $0.id == mark.written.id }),
              mark.holds(on: currentTask) else { return false }
        submitTaskUpdate(
            ChildDay.reopened(currentTask, restoring: mark.baseline),
            basedOn: currentTask,
            for: .child
        )
        return true
    }

    func snoozeTask(_ id: TaskItem.ID, until date: Date) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        let currentTask = tasks[index]
        var proposedTask = currentTask
        proposedTask.snoozedUntil = date
        submitTaskUpdate(proposedTask, basedOn: currentTask)
    }

    // Several tasks change exactly as each would alone, and a bulk change offers no undo it could not keep.
    func completeTasks(_ ids: Set<TaskItem.ID>) {
        for task in tasks where ids.contains(task.id) && !task.isDone && task.kind == .task {
            toggleTask(task)
        }
        clearUndo()
    }

    func reassignTasks(_ ids: Set<TaskItem.ID>, to member: HouseholdMember?) {
        for task in tasks where ids.contains(task.id) {
            updateTask(
                id: task.id,
                title: task.title,
                subtitle: task.subtitle,
                owner: member?.name ?? HouseholdWorkload.sharedOwnerLabel,
                ownerMemberID: member?.id,
                dueLabel: task.dueLabel,
                dueAt: task.dueAt,
                category: task.category,
                priority: task.priority
            )
        }
    }

    func deleteTasks(_ ids: Set<TaskItem.ID>) {
        for id in ids {
            deleteTask(id)
        }
    }

    func deleteTask(_ id: TaskItem.ID) {
        guard tasks.contains(where: { $0.id == id }) else { return }
        tasks.removeAll { $0.id == id }
        persistActivityLocally()
        synchronizeLocalNotifications()
        enqueueRemoteMutation(errorMessage: "Não foi possível apagar a tarefa.") {
            backend,
            familyID,
            _ in
            try await backend.deleteTask(id, familyID: familyID)
        }
    }

    func refreshNotificationAuthorizationStatus() async {
        notificationAuthorizationStatus = await notificationScheduler.authorizationStatus()
    }

    @discardableResult
    func requestNotificationAuthorization() async -> Bool {
        notificationAuthorizationStatus = await notificationScheduler.requestAuthorization()
        if notificationAuthorizationStatus.canSchedule {
            defaults.set(true, forKey: LocalHomeNotificationScheduler.notificationsEnabledKey)
            synchronizeLocalNotifications()
            return true
        }
        return false
    }

    // Quiet hours keep a reminder's time and take its sound, so the editor says so before saving.
    func reminderRingsSilently(
        owner: String,
        ownerMemberID: UUID?,
        dueAt: Date,
        lead: TaskReminderLead,
        recurrence: TaskRecurrence,
        now: Date = .now
    ) -> Bool {
        guard notificationAuthorizationStatus.canSchedule, homeAccessState != .minorMember else { return false }
        var probe = TaskItem(
            title: "",
            subtitle: "",
            owner: owner,
            dueLabel: "",
            dueAt: dueAt,
            category: .home,
            isDone: false,
            createdBy: ""
        )
        probe.ownerMemberID = ownerMemberID
        probe.recurrence = recurrence
        probe.reminderLead = lead
        guard LocalHomeNotificationScheduler.isForViewer(
            probe,
            viewer: HomeNotificationViewer(member: currentFamilyMember)
        ) else { return false }
        return LocalHomeNotificationScheduler.ringsSilently(probe, now: now, defaults: defaults)
    }

    func synchronizeLocalNotifications() {
        // A membership the server could not confirm is not a lost one: the alerts
        // already on the phone stay until a verified answer replaces them.
        guard homeAccessState != .unavailable else { return }
        let canScheduleForActiveUser = activeHomeUserID != nil && hasActiveHome
        var tasksForNotifications = canScheduleForActiveUser ? tasks : []
        var viewer = canScheduleForActiveUser
            ? HomeNotificationViewer(member: currentFamilyMember)
            : HomeNotificationViewer()
        var familyID = familyGroup.id
        // A minor's phone announces only their own tasks, in the neutral template, inside the guardian's quiet hours.
        if homeAccessState == .minorMember, activeHomeUserID != nil, let minorHome {
            tasksForNotifications = minorHome.taskItems
            viewer = HomeNotificationViewer(
                memberID: minorHome.viewer.memberID,
                name: minorHome.ownerName,
                minorPolicy: MinorNotificationPolicy(settings: minorHome.viewer.supervision)
            )
            familyID = minorHome.family?.id ?? familyID
        }
        let scheduler = notificationScheduler
        let previousTask = notificationSyncTask

        previousTask?.cancel()
        notificationSyncTask = Task {
            await previousTask?.value
            guard !Task.isCancelled else { return }
            await scheduler.synchronize(
                tasks: tasksForNotifications,
                familyID: familyID,
                viewer: viewer
            )
        }
    }

    func keepLocalTaskConflict() {
        guard let conflict = taskEditConflict else { return }
        showNextTaskEditConflict()
        submitTaskUpdate(conflict.localTask, basedOn: conflict.remoteTask)
    }

    func acceptRemoteTaskConflict() {
        showNextTaskEditConflict()
    }

    private func presentTaskEditConflict(_ conflict: TaskEditConflict) {
        if taskEditConflict == nil || taskEditConflict?.id == conflict.id {
            taskEditConflict = conflict
        } else {
            queuedTaskEditConflicts.removeAll { $0.id == conflict.id }
            queuedTaskEditConflicts.append(conflict)
        }
    }

    private func showNextTaskEditConflict() {
        taskEditConflict = queuedTaskEditConflicts.isEmpty ? nil : queuedTaskEditConflicts.removeFirst()
    }

    func addShoppingItem(title: String, amount: String, owner: String, ownerMemberID: UUID? = nil) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedOwner = owner.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }

        let item = ShoppingItem(
            title: trimmedTitle,
            amount: amount.trimmingCharacters(in: .whitespacesAndNewlines),
            owner: trimmedOwner.isEmpty ? "Casa" : trimmedOwner,
            ownerMemberID: Self.assignableMemberID(ownerMemberID, forOwner: trimmedOwner),
            isChecked: false
        )
        shoppingItems.insert(item, at: 0)
        persistActivityLocally()
        enqueueRemoteMutation(errorMessage: "Não foi possível sincronizar o item de compra.") {
            backend,
            familyID,
            user in
            try await backend.createShoppingItem(item, familyID: familyID, currentUser: user)
        }
    }

    func updateShoppingItem(
        id: ShoppingItem.ID,
        title: String,
        amount: String,
        owner: String,
        ownerMemberID: UUID? = nil
    ) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedOwner = owner.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }
        guard let index = shoppingItems.firstIndex(where: { $0.id == id }) else { return }
        shoppingItems[index].title = trimmedTitle
        shoppingItems[index].amount = amount.trimmingCharacters(in: .whitespacesAndNewlines)
        shoppingItems[index].owner = trimmedOwner.isEmpty ? "Casa" : trimmedOwner
        shoppingItems[index].ownerMemberID = Self.assignableMemberID(ownerMemberID, forOwner: trimmedOwner)
        let item = shoppingItems[index]
        persistActivityLocally()
        enqueueRemoteMutation(errorMessage: "Não foi possível sincronizar as alterações da compra.") {
            backend,
            familyID,
            _ in
            try await backend.updateShoppingItem(item, familyID: familyID)
        }
    }

    func toggleShoppingItem(_ item: ShoppingItem) {
        guard let index = shoppingItems.firstIndex(where: { $0.id == item.id }) else { return }
        shoppingItems[index].isChecked.toggle()
        let updatedItem = shoppingItems[index]
        persistActivityLocally()
        enqueueRemoteMutation(errorMessage: "Não foi possível sincronizar o estado da compra.") {
            backend,
            familyID,
            _ in
            try await backend.updateShoppingItem(updatedItem, familyID: familyID)
        }
    }

    func deleteShoppingItem(_ id: ShoppingItem.ID) {
        guard shoppingItems.contains(where: { $0.id == id }) else { return }
        shoppingItems.removeAll { $0.id == id }
        persistActivityLocally()
        enqueueRemoteMutation(errorMessage: "Não foi possível apagar o item da lista.") {
            backend,
            familyID,
            _ in
            try await backend.deleteShoppingItem(id, familyID: familyID)
        }
    }

    @discardableResult
    func clearCheckedShoppingItems() -> Int {
        let checkedIDs = shoppingItems.filter(\.isChecked).map(\.id)
        guard !checkedIDs.isEmpty else { return 0 }

        shoppingItems.removeAll(where: \.isChecked)
        persistActivityLocally()
        for id in checkedIDs {
            enqueueRemoteMutation(errorMessage: "Não foi possível limpar os itens comprados.") {
                backend,
                familyID,
                _ in
                try await backend.deleteShoppingItem(id, familyID: familyID)
            }
        }
        return checkedIDs.count
    }

    private var nextTaskSectionTone: MemberTone {
        let tones: [MemberTone] = [.lavender, .sky, .coral, .amber, .mint]
        return tones[taskSections.count % tones.count]
    }

    private var nextCustomCategoryTone: MemberTone {
        let tones: [MemberTone] = [.lavender, .amber, .sky, .coral, .mint]
        return tones[customTaskCategories.count % tones.count]
    }

    private func persistActiveHome() {
        localStateRevision &+= 1
        cacheActiveHomeLocally()
    }

    private func cacheActiveHomeLocally() {
        guard let activeHomeUserID else { return }
        guard let data = try? JSONEncoder().encode(familyGroup) else { return }
        PrivateLocalDataAccess.writeDataBestEffort(
            data,
            forKey: Self.homeKey(for: activeHomeUserID),
            ownerScope: PrivateLocalDataScope.household(for: activeHomeUserID),
            store: privateDataStore,
            legacyDefaults: defaults
        )
    }

    private func persistActivityLocally() {
        localStateRevision &+= 1
        cacheAppSnapshotLocally()
    }

    func waitForPendingRemoteMutations() async {
        while true {
            let generation = remoteMutationGeneration
            await remoteMutationTask?.value
            guard generation != remoteMutationGeneration else { return }
        }
    }

    private func enqueueRemoteMutation(
        errorMessage: String,
        signalsFailure: Bool = true,
        operation: @escaping (
            _ backend: any RemoteHomeBackend,
            _ familyID: UUID,
            _ user: AuthUser
        ) async throws -> Void
    ) {
        guard let activeUser,
              !usesLocalDebugBackend(for: activeUser),
              let remoteHomeBackend,
              hasActiveHome else {
            return
        }

        let familyID = familyGroup.id
        let userID = activeUser.id
        let contextToken = currentHomeContextToken
        let previousTask = remoteMutationTask
        remoteMutationGeneration &+= 1

        remoteMutationTask = Task { [weak self] in
            await previousTask?.value
            guard !Task.isCancelled else { return }

            do {
                try await operation(remoteHomeBackend, familyID, activeUser)
            } catch is CancellationError {
                return
            } catch {
                guard let self,
                      self.isCurrentHomeContext(contextToken),
                      self.activeHomeUserID == userID else { return }
                self.syncErrorMessage = errorMessage
                // A run of writes that fail together buzzes once, not once per write.
                if signalsFailure, Date().timeIntervalSince(self.lastFailureHapticAt) > 1 {
                    self.lastFailureHapticAt = Date()
                    Haptics.error()
                }
            }
        }
    }

    func dismissSyncError(ifStill message: String) {
        guard syncErrorMessage == message else { return }
        syncErrorMessage = nil
    }

    func reportSyncError(_ message: String) {
        syncErrorMessage = message
        Haptics.error()
    }

    private enum TaskUpdateAudience {
        case adult
        case child
    }

    private func submitTaskUpdate(
        _ proposedTask: TaskItem,
        basedOn baseTask: TaskItem,
        for audience: TaskUpdateAudience = .adult
    ) {
        guard let index = tasks.firstIndex(where: { $0.id == proposedTask.id }) else { return }
        let contextToken = currentHomeContextToken

        var optimisticTask = proposedTask
        optimisticTask.version = baseTask.version + 1
        tasks[index] = optimisticTask
        persistActivityLocally()
        synchronizeLocalNotifications()

        enqueueRemoteMutation(
            errorMessage: "Não foi possível sincronizar as alterações da tarefa.",
            signalsFailure: audience == .adult
        ) {
            [weak self] backend,
            familyID,
            _ in
            let result = try await backend.updateTask(
                optimisticTask,
                expectedVersion: baseTask.version,
                familyID: familyID
            )
            guard let self, self.isCurrentHomeContext(contextToken) else { return }
            self.applyTaskUpdateResult(result, optimisticTask: optimisticTask, for: audience)
        }
    }

    private func applyTaskUpdateResult(
        _ result: TaskUpdateResult,
        optimisticTask: TaskItem,
        for audience: TaskUpdateAudience
    ) {
        guard let index = tasks.firstIndex(where: { $0.id == optimisticTask.id }) else { return }

        switch result {
        case .updated(let serverTask):
            guard tasks[index].version <= serverTask.version else { return }
            tasks[index] = serverTask
        case .conflict(let remoteTask):
            guard tasks[index].version <= optimisticTask.version else { return }
            tasks[index] = remoteTask
            if audience == .adult {
                presentTaskEditConflict(
                    TaskEditConflict(localTask: optimisticTask, remoteTask: remoteTask)
                )
            }
        }

        cacheAppSnapshotLocally()
        synchronizeLocalNotifications()
    }

    private func startRealtimeSync() {
        stopRealtimeSync()

        guard let activeUser,
              !usesLocalDebugBackend(for: activeUser),
              let remoteHomeBackend,
              hasActiveHome else {
            return
        }

        let familyID = familyGroup.id
        let userID = activeUser.id

        realtimeListenerTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self,
                      self.activeHomeUserID == userID,
                      self.familyGroup.id == familyID else {
                    return
                }

                let events = await remoteHomeBackend.realtimeEvents(familyID: familyID)
                for await _ in events {
                    guard !Task.isCancelled else { return }
                    guard self.activeHomeUserID == userID,
                          self.familyGroup.id == familyID else {
                        return
                    }
                    self.scheduleRealtimeRefresh(for: activeUser)
                }

                guard !Task.isCancelled else { return }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func scheduleRealtimeRefresh(for user: AuthUser) {
        realtimeRefreshTask?.cancel()
        realtimeRefreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled, let self else { return }
            await self.waitForPendingRemoteMutations()
            guard !Task.isCancelled else { return }
            await self.refreshHomeFromRemote(for: user)
        }
    }

    private func stopRealtimeSync() {
        realtimeListenerTask?.cancel()
        realtimeListenerTask = nil
        realtimeRefreshTask?.cancel()
        realtimeRefreshTask = nil
    }

    private func cacheAppSnapshotLocally() {
        guard let activeHomeUserID, hasActiveHome else { return }

        let snapshot = Self.snapshotForLocalCache(currentSnapshot)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        PrivateLocalDataAccess.writeDataBestEffort(
            data,
            forKey: Self.appDataKey(for: activeHomeUserID, familyID: familyGroup.id),
            ownerScope: PrivateLocalDataScope.household(for: activeHomeUserID),
            store: privateDataStore,
            legacyDefaults: defaults
        )
    }

    private var currentHomeContextToken: HomeContextToken {
        HomeContextToken(
            userID: activeHomeUserID,
            generation: homeContextGeneration
        )
    }

    private func isCurrentHomeContext(_ token: HomeContextToken) -> Bool {
        token.generation == homeContextGeneration && token.userID == activeHomeUserID
    }

    private func finishSyncingHome(ifCurrent token: HomeContextToken) {
        guard isCurrentHomeContext(token) else { return }
        isSyncingHome = false
    }

    private func usesLocalDebugBackend(for user: AuthUser?) -> Bool {
        #if DEBUG
        return user?.isDebugAccount == true
        #else
        return false
        #endif
    }

    #if DEBUG
    private func activateLocalHomeContext(for user: AuthUser) {
        viewerAge = .localTrustedAdult
        if let savedHome = loadFamilyGroup(for: user.id) {
            familyGroup = savedHome
            homeAccessState = .authorized
            currentPermissionRole = .owner
            loadActivityState(for: user.id)
        } else {
            familyGroup = PreviewData.familyGroup
            homeAccessState = .noHome
            currentPermissionRole = .member
            resetActivityState()
        }
    }
    #endif

    // Photographed boletos and receitas are the most sensitive thing this app holds, so the copy that
    // lands on disk carries only the newest few readings and stays far below the protected store cap.
    nonisolated static let maxLocallyCachedAttachmentImages = 12

    nonisolated static func snapshotForLocalCache(_ snapshot: AppDataSnapshot) -> AppDataSnapshot {
        var bounded = snapshot
        var remaining = maxLocallyCachedAttachmentImages

        for messageIndex in bounded.messages.indices.reversed() {
            for attachmentIndex in bounded.messages[messageIndex].attachments.indices.reversed() {
                guard bounded.messages[messageIndex].attachments[attachmentIndex].thumbnailData != nil else {
                    continue
                }
                guard remaining > 0 else {
                    bounded.messages[messageIndex].attachments[attachmentIndex].thumbnailData = nil
                    continue
                }
                remaining -= 1
            }
        }

        return bounded
    }

    private var currentSnapshot: AppDataSnapshot {
        AppDataSnapshot(
            messages: messages,
            taskSections: taskSections,
            customTaskCategories: customTaskCategories,
            tasks: tasks,
            shoppingItems: shoppingItems,
            insights: insights,
            ninaThread: ninaThread,
            ninaMemories: ninaMemories
        )
    }

    private func clearCachedHome(for userID: String) {
        PrivateLocalDataAccess.removeAllData(
            forOwnerScope: PrivateLocalDataScope.household(for: userID),
            store: privateDataStore
        )
        defaults.removeObject(forKey: Self.homeKey(for: userID))
        let appDataPrefix = Self.appDataKeyPrefix(for: userID)
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(appDataPrefix) {
            defaults.removeObject(forKey: key)
        }
    }

    private func loadActivityState(for userID: String) {
        let key = Self.appDataKey(for: userID, familyID: familyGroup.id)
        guard let data = PrivateLocalDataAccess.loadData(
            forKey: key,
            ownerScope: PrivateLocalDataScope.household(for: userID),
            store: privateDataStore,
            legacyDefaults: defaults
        ),
              let snapshot = try? JSONDecoder().decode(AppDataSnapshot.self, from: data) else {
            resetActivityState()
            return
        }

        apply(snapshot)
    }

    private func loadAIMemoryConsent(for userID: String?) {
        guard let userID else {
            aiMemoryConsent = nil
            return
        }
        let key = Self.aiMemoryConsentKey(for: userID)
        guard let data = PrivateLocalDataAccess.loadData(
            forKey: key,
            ownerScope: PrivateLocalDataScope.aiConsent(for: userID),
            store: privateDataStore,
            legacyDefaults: defaults
        ),
              let record = try? JSONDecoder().decode(AIMemoryConsentRecord.self, from: data) else {
            aiMemoryConsent = nil
            hasStaleLocalConsent = false
            return
        }
        aiMemoryConsent = record
        hasStaleLocalConsent = !record.isCurrent
    }

    private func resetActivityState() {
        householdPremium = .inactive
        apply(.preview)
    }

    // The server keeps no attachment imagery, so a refresh would erase the photo the user just sent
    // unless the device carries its own copy forward; the context token is what keeps that copy from
    // ever reaching another account's conversation.
    private var carriableAttachmentImagery: [ChatMessage.ID: [ChatAttachment]] {
        guard let messagesContext, isCurrentHomeContext(messagesContext) else { return [:] }
        return messages.reduce(into: [:]) { imagery, message in
            guard message.attachments.contains(where: { $0.thumbnailData != nil }) else { return }
            imagery[message.id] = message.attachments
        }
    }

    nonisolated private static func messages(
        _ messages: [ChatMessage],
        carryingImageryFrom imagery: [ChatMessage.ID: [ChatAttachment]]
    ) -> [ChatMessage] {
        guard !imagery.isEmpty else { return messages }

        return messages.map { message in
            guard let held = imagery[message.id],
                  held.count == message.attachments.count else {
                return message
            }

            var merged = message
            for index in merged.attachments.indices where merged.attachments[index].thumbnailData == nil {
                guard held[index].filename == merged.attachments[index].filename else { continue }
                merged.attachments[index].thumbnailData = held[index].thumbnailData
            }
            return merged
        }
    }

    private func apply(_ snapshot: AppDataSnapshot) {
        messages = Self.messages(snapshot.messages, carryingImageryFrom: carriableAttachmentImagery)
        messagesContext = currentHomeContextToken
        taskSections = snapshot.taskSections.isEmpty ? PreviewData.taskSections : snapshot.taskSections
        customTaskCategories = snapshot.customTaskCategories
        tasks = snapshot.tasks
        shoppingItems = snapshot.shoppingItems
        insights = snapshot.insights
        ninaThread = snapshot.ninaThread
        ninaMemories = snapshot.ninaMemories
        synchronizeLocalNotifications()
    }

    private func apply(_ state: RemoteHomeState) {
        familyGroup = state.familyGroup
        currentPermissionRole = state.permissionRole
        inviteStatus = state.inviteStatus
        joinRequests = state.joinRequests
        houseOwnershipOffer = state.ownershipOffer
        pendingJoinRequest = nil
        familyAccessDecision = nil

        if let snapshot = state.snapshot {
            apply(snapshot)
        } else {
            resetActivityState()
        }

        householdPremium = state.householdPremium
        viewerAge = state.viewerAge
        aiConsentStatus = state.aiConsent
        applyAIMemoryConsent(Self.consentRecord(from: state.aiConsent))
    }

    // Only a grant the server counts as current, with its transfer consent, is mirrored on the phone.
    private static func consentRecord(from consent: NinaAIConsent) -> AIMemoryConsentRecord? {
        guard consent.countsAsConsent, let policyVersion = consent.policyVersion else { return nil }
        return AIMemoryConsentRecord(
            acceptedAt: consent.acceptedAt ?? .now,
            policyVersion: policyVersion,
            transferConsented: consent.transferConsented
        )
    }

    private func loadFamilyGroup(for userID: String) -> FamilyGroup? {
        guard let data = PrivateLocalDataAccess.loadData(
            forKey: Self.homeKey(for: userID),
            ownerScope: PrivateLocalDataScope.household(for: userID),
            store: privateDataStore,
            legacyDefaults: defaults
        ) else { return nil }
        return try? JSONDecoder().decode(FamilyGroup.self, from: data)
    }

    private static func homeKey(for userID: String) -> String {
        "nina.home.familyGroup.\(userID)"
    }

    private static func appDataKey(for userID: String, familyID: FamilyGroup.ID) -> String {
        "nina.home.appData.\(userID).\(familyID.uuidString)"
    }

    private static func appDataKeyPrefix(for userID: String) -> String {
        "nina.home.appData.\(userID)."
    }

    private static func aiMemoryConsentKey(for userID: String) -> String {
        "nina.privacy.aiMemoryConsent.\(userID)"
    }

    nonisolated static func normalizedHomeName(_ rawName: String) -> String {
        rawName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated static func secureLocalInviteCode() -> String {
        let token = UUID().uuidString
            .replacingOccurrences(of: "-", with: "")
            .lowercased()
        return "casa-\(token)"
    }

    nonisolated static func normalizedInviteCode(from rawInvite: String) -> String? {
        let trimmedInvite = rawInvite.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInvite.isEmpty else { return nil }

        let candidate: String
        let lowercased = trimmedInvite.lowercased()
        if (lowercased.hasPrefix("http") || lowercased.hasPrefix("www.") || lowercased.contains("://")),
           let url = URL(string: trimmedInvite),
           url.scheme != nil,
           let lastPathComponent = url.pathComponents.filter({ $0 != "/" }).last {
            candidate = lastPathComponent
        } else {
            candidate = trimmedInvite
        }

        let code = slugified(candidate)
        return code.count >= 4 ? code : nil
    }

    nonisolated private static func homeName(fromInviteCode inviteCode: String) -> String {
        if inviteCode.range(of: #"^casa-[0-9a-f]{20,64}$"#, options: .regularExpression) != nil {
            return "Casa compartilhada"
        }

        let words = inviteCode
            .split(separator: "-")
            .filter { !$0.allSatisfy(\.isNumber) }
            .prefix(3)
            .map { String($0).capitalized }

        guard !words.isEmpty else { return "Casa compartilhada" }

        if words.first?.lowercased() == "casa" {
            return words.joined(separator: " ")
        }

        return "Casa \(words.joined(separator: " "))"
    }

    // Casa is the unassigned bucket, so it can never carry a member pointer.
    nonisolated private static func assignableMemberID(_ memberID: UUID?, forOwner owner: String) -> UUID? {
        HouseholdWorkload.isSharedOwner(owner) ? nil : memberID
    }

    nonisolated private static func slugified(_ text: String) -> String {
        let folded = text
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
        let allowed = CharacterSet.alphanumerics
        let replaced = folded.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? String(scalar) : "-"
        }.joined()

        return replaced
            .split(separator: "-")
            .joined(separator: "-")
    }

    // The prompt and the server book a day without a time at this same hour.
    nonisolated static let defaultDueHour = 9

    nonisolated static func inferredDueAt(
        from label: String,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Date? {
        guard let words = Self.dueWords(in: label) else { return nil }
        let components = calendar.dateComponents([.year, .month, .day, .weekday], from: now)
        guard let year = components.year,
              let month = components.month,
              let day = components.day,
              let weekday = components.weekday else {
            return nil
        }
        let today = DueDay(year: year, month: month, day: day)
        let time = words.time ?? DueClockTime(hour: Self.defaultDueHour, minute: 0)

        if words.dates.isEmpty {
            if let todayAt = Self.dueInstant(on: today, at: time, calendar: calendar), todayAt > now {
                return todayAt
            }
            guard let tomorrow = Self.dueDay(today, adding: 1, calendar: calendar) else { return nil }
            return Self.dueInstant(on: tomorrow, at: time, calendar: calendar)
        }

        let resolved = words.dates.map { word in
            Self.resolveDueWord(
                word,
                today: today,
                todayWeekday: weekday,
                time: time,
                timeStated: words.time != nil,
                now: now,
                calendar: calendar
            )
        }
        guard let first = resolved.first, resolved.allSatisfy({ $0 == first }) else { return nil }
        return first
    }

    nonisolated static func reminderDate(
        onSameDayAs date: Date,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Date? {
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        components.hour = Self.defaultDueHour
        components.minute = 0

        guard let defaultDate = calendar.date(from: components) else { return nil }
        if calendar.isDate(defaultDate, inSameDayAs: now), defaultDate <= now {
            return calendar.date(byAdding: .minute, value: 5, to: now)
        }
        return defaultDate
    }

    nonisolated static func taskDueLabel(
        for date: Date,
        relativeTo referenceDate: Date = .now,
        calendar: Calendar = .current
    ) -> String {
        let time = Self.formattedTaskDate(date, format: "HH:mm", calendar: calendar)
        if calendar.isDate(date, inSameDayAs: referenceDate) {
            return "Hoje, \(time)"
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: referenceDate),
           calendar.isDate(date, inSameDayAs: tomorrow) {
            return "Amanhã, \(time)"
        }
        let day = Self.formattedTaskDate(date, format: "dd MMM", calendar: calendar)
        return "\(day), \(time)"
    }

    nonisolated private static func formattedTaskDate(
        _ date: Date,
        format: String,
        calendar: Calendar
    ) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.dateFormat = format
        return formatter.string(from: date)
    }

    nonisolated private static func resolveDueWord(
        _ word: DueDateWord,
        today: DueDay,
        todayWeekday: Int,
        time: DueClockTime,
        timeStated: Bool,
        now: Date,
        calendar: Calendar
    ) -> Date? {
        func instant(_ day: DueDay) -> Date? {
            Self.dueInstant(on: day, at: time, calendar: calendar)
        }
        func pinnedDay(_ day: DueDay) -> Date? {
            guard let pinned = instant(day) else { return nil }
            if pinned > now {
                return pinned
            }
            guard !timeStated, day == today else { return nil }
            return Self.reminderDate(onSameDayAs: now, now: now, calendar: calendar)
        }

        switch word {
        case .pinned(let days):
            guard days <= 366, let day = Self.dueDay(today, adding: days, calendar: calendar) else {
                return nil
            }
            return pinnedDay(day)
        case .dayOfMonth(let dayNumber, let nextMonth):
            guard (1...31).contains(dayNumber) else { return nil }
            for step in (nextMonth ? 1 : 0)..<13 {
                let year = today.year + (today.month - 1 + step) / 12
                let month = (today.month - 1 + step) % 12 + 1
                let fits = dayNumber <= Self.daysInMonth(year: year, month: month, calendar: calendar)
                let day = DueDay(year: year, month: month, day: dayNumber)
                if nextMonth {
                    return fits ? instant(day) : nil
                }
                if fits, let candidate = instant(day), candidate > now {
                    return candidate
                }
            }
            return nil
        case .monthDay(let dayNumber, let month, let year):
            guard (1...12).contains(month), dayNumber >= 1 else { return nil }
            if let year {
                guard dayNumber <= Self.daysInMonth(year: year, month: month, calendar: calendar) else {
                    return nil
                }
                return pinnedDay(DueDay(year: year, month: month, day: dayNumber))
            }
            if month == today.month, dayNumber == today.day {
                return pinnedDay(today)
            }
            for year in today.year..<(today.year + 9)
            where dayNumber <= Self.daysInMonth(year: year, month: month, calendar: calendar) {
                if let candidate = instant(DueDay(year: year, month: month, day: dayNumber)),
                   candidate > now {
                    return candidate
                }
            }
            return nil
        case .weekday(let weekday, let notToday):
            var days = (weekday - todayWeekday + 7) % 7
            let todayIsStillAhead = instant(today).map { $0 > now } ?? false
            if days == 0, notToday || !todayIsStillAhead {
                days = 7
            }
            guard let day = Self.dueDay(today, adding: days, calendar: calendar) else { return nil }
            return instant(day)
        }
    }

    nonisolated private static func dueInstant(
        on day: DueDay,
        at time: DueClockTime,
        calendar: Calendar
    ) -> Date? {
        var components = DateComponents()
        components.year = day.year
        components.month = day.month
        components.day = day.day
        components.hour = time.hour
        components.minute = time.minute
        components.second = 0
        return calendar.date(from: components)
    }

    nonisolated private static func dueDay(_ day: DueDay, adding days: Int, calendar: Calendar) -> DueDay? {
        let noonTime = DueClockTime(hour: 12, minute: 0)
        guard let noon = Self.dueInstant(on: day, at: noonTime, calendar: calendar),
              let shifted = calendar.date(byAdding: .day, value: days, to: noon) else {
            return nil
        }
        let components = calendar.dateComponents([.year, .month, .day], from: shifted)
        guard let year = components.year, let month = components.month, let dayNumber = components.day else {
            return nil
        }
        return DueDay(year: year, month: month, day: dayNumber)
    }

    nonisolated private static func daysInMonth(year: Int, month: Int, calendar: Calendar) -> Int {
        let firstDay = DueDay(year: year, month: month, day: 1)
        let noonTime = DueClockTime(hour: 12, minute: 0)
        guard let noon = Self.dueInstant(on: firstDay, at: noonTime, calendar: calendar),
              let days = calendar.range(of: .day, in: .month, for: noon) else {
            return 0
        }
        return days.count
    }

    nonisolated private static func foldedDueText(_ label: String) -> String {
        label.precomposedStringWithCanonicalMapping
            .lowercased()
            .replacingOccurrences(of: "º", with: "")
            .replacingOccurrences(of: "°", with: "")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_BR"))
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private static func dueWords(in label: String) -> DueWords? {
        guard let durationPattern = Self.dueDurationPattern,
              let alternativePattern = Self.dueAlternativePattern,
              let noonPattern = Self.dueNoonPattern,
              let partOfDayTimePattern = Self.duePartOfDayTimePattern,
              let hourMinutePattern = Self.dueHourMinutePattern,
              let wholeHourPattern = Self.dueWholeHourPattern,
              let bareHourPattern = Self.dueBareHourPattern,
              let afterTomorrowPattern = Self.dueAfterTomorrowPattern,
              let tomorrowPattern = Self.dueTomorrowPattern,
              let todayPattern = Self.dueTodayPattern,
              let daysAheadPattern = Self.dueDaysAheadPattern,
              let numericDatePattern = Self.dueNumericDatePattern,
              let namedMonthPattern = Self.dueNamedMonthPattern,
              let dayOfMonthPattern = Self.dueDayOfMonthPattern,
              let weekdayPattern = Self.dueWeekdayPattern,
              let ordinalWeekdayPattern = Self.dueOrdinalWeekdayPattern,
              let ordinalNounPattern = Self.dueOrdinalNounPattern,
              let weekdayTimePattern = Self.dueWeekdayTimePattern,
              let strayHourPattern = Self.dueStrayHourPattern,
              let periodWordPattern = Self.duePeriodWordPattern,
              let partOfDayPattern = Self.duePartOfDayPattern else {
            return nil
        }

        let folded = Self.foldedDueText(label)
        let foldedText = folded as NSString
        let foldedRange = NSRange(location: 0, length: foldedText.length)
        if durationPattern.firstMatch(in: folded, range: foldedRange) != nil
            || alternativePattern.firstMatch(in: folded, range: foldedRange) != nil {
            return nil
        }

        var text = folded
        var invalid = false
        var times: [DueClockTime] = []
        var dates: [DueDateWord] = []

        func consume(_ pattern: NSRegularExpression, _ read: ([String?]) -> Void) {
            let source = text as NSString
            let matches = pattern.matches(in: text, range: NSRange(location: 0, length: source.length))
            guard !matches.isEmpty else { return }
            let consumed = NSMutableString(string: source)
            for match in matches {
                read((0..<match.numberOfRanges).map { index in
                    let range = match.range(at: index)
                    return range.location == NSNotFound ? nil : source.substring(with: range)
                })
                consumed.replaceCharacters(
                    in: match.range,
                    with: String(repeating: " ", count: match.range.length)
                )
            }
            text = consumed as String
        }
        func number(_ groups: [String?], _ index: Int) -> Int? {
            groups.indices.contains(index) ? groups[index].flatMap { Int($0) } : nil
        }
        func pushTime(_ hour: Int?, _ minute: Int?) {
            if let hour, let minute, (0...23).contains(hour), (0...59).contains(minute) {
                times.append(DueClockTime(hour: hour, minute: minute))
            } else {
                invalid = true
            }
        }

        consume(noonPattern) { groups in pushTime(12, groups[1] == nil ? 0 : 30) }
        consume(numericDatePattern) { groups in
            let marked = groups[1] == "dia" || groups[1] == "no dia"
            let year = number(groups, 4).map { groups[4]?.count == 2 ? $0 + 2000 : $0 }
            // A word that is also an ordinal, a fraction or an article counts as a date only in a date's context.
            guard marked || year != nil || (groups[3]?.count ?? 0) >= 2 else { return }
            dates.append(.monthDay(day: number(groups, 2) ?? 0, month: number(groups, 3) ?? 0, year: year))
        }
        consume(namedMonthPattern) { groups in
            dates.append(.monthDay(
                day: number(groups, 1) ?? 0,
                month: groups[2].flatMap { Self.dueMonthNumbers[$0] } ?? 0,
                year: number(groups, 3)
            ))
        }
        consume(dayOfMonthPattern) { groups in
            dates.append(.dayOfMonth(day: number(groups, 1) ?? 0, nextMonth: groups[2] != nil))
        }
        consume(partOfDayTimePattern) { groups in
            guard let hour = number(groups, 1) else {
                invalid = true
                return
            }
            let minute = number(groups, 2) ?? number(groups, 3) ?? 0
            if groups[4] == "manha" {
                pushTime(hour, minute)
            } else if (1...11).contains(hour) {
                pushTime(hour + 12, minute)
            } else if (13...23).contains(hour) {
                pushTime(hour, minute)
            } else {
                invalid = true
            }
        }
        consume(hourMinutePattern) { groups in pushTime(number(groups, 1), number(groups, 2)) }
        consume(wholeHourPattern) { groups in pushTime(number(groups, 1), 0) }
        consume(bareHourPattern) { groups in
            let hour = number(groups, 1)
            // A bare "às 5" means 17h as often as 5h, so an hour from one to seven is never guessed.
            if let hour, (1...7).contains(hour) {
                invalid = true
            } else {
                pushTime(hour, 0)
            }
        }

        consume(afterTomorrowPattern) { _ in dates.append(.pinned(days: 2)) }
        consume(tomorrowPattern) { _ in dates.append(.pinned(days: 1)) }
        consume(todayPattern) { _ in dates.append(.pinned(days: 0)) }
        consume(daysAheadPattern) { groups in dates.append(.pinned(days: number(groups, 1) ?? Int.max)) }

        var unplacedWeekday = false
        func readWeekday(
            _ match: NSTextCheckingResult,
            weekday: Int?,
            hasFeira: Bool,
            hasQueVem: Bool,
            alwaysPlaced: Bool
        ) {
            let before = foldedText.substring(to: match.range.location)
                .trimmingCharacters(in: .whitespaces)
            let previous = before.split(separator: " ").last.map(String.init) ?? ""
            let after = foldedText.substring(from: NSMaxRange(match.range))
            let afterRange = NSRange(location: 0, length: (after as NSString).length)
            // A word that is also an ordinal, a fraction or an article counts as a date only in a date's context.
            if !hasFeira, ordinalNounPattern.firstMatch(in: after, range: afterRange) != nil {
                return
            }
            let placed = alwaysPlaced || hasFeira || hasQueVem
                || Self.dueWeekdayMarkers.contains(previous)
                || before.isEmpty
                || weekdayTimePattern.firstMatch(in: after, range: afterRange) != nil
            guard placed, let weekday else {
                unplacedWeekday = true
                return
            }
            dates.append(.weekday(weekday, notToday: hasQueVem || previous.hasPrefix("proxim")))
        }
        func captured(_ match: NSTextCheckingResult, _ index: Int) -> Bool {
            match.range(at: index).location != NSNotFound
        }
        for match in weekdayPattern.matches(in: folded, range: foldedRange) {
            let name = foldedText.substring(with: match.range(at: 1))
            readWeekday(
                match,
                weekday: Self.dueWeekdayNumbers[name],
                hasFeira: captured(match, 2),
                hasQueVem: captured(match, 3),
                alwaysPlaced: name == "sabado" || name == "domingo"
            )
        }
        for match in ordinalWeekdayPattern.matches(in: folded, range: foldedRange) {
            readWeekday(
                match,
                weekday: Int(foldedText.substring(with: match.range(at: 1))),
                hasFeira: captured(match, 2) || captured(match, 3),
                hasQueVem: captured(match, 4),
                alwaysPlaced: false
            )
        }

        let remaining = NSRange(location: 0, length: (text as NSString).length)
        func remains(_ pattern: NSRegularExpression) -> Bool {
            pattern.firstMatch(in: text, range: remaining) != nil
        }
        // A date or time word the reader cannot place refuses the whole text; it never falls back to today.
        if invalid || unplacedWeekday || times.count > 1
            || remains(strayHourPattern) || remains(periodWordPattern)
            || (times.isEmpty && remains(partOfDayPattern)) {
            return nil
        }
        guard !dates.isEmpty || !times.isEmpty else { return nil }
        return DueWords(dates: dates, time: times.first)
    }

    nonisolated private static let dueMonthNumbers: [String: Int] = [
        "janeiro": 1, "fevereiro": 2, "marco": 3, "abril": 4, "maio": 5, "junho": 6,
        "julho": 7, "agosto": 8, "setembro": 9, "outubro": 10, "novembro": 11, "dezembro": 12,
        "jan": 1, "fev": 2, "mar": 3, "abr": 4, "mai": 5, "jun": 6,
        "jul": 7, "ago": 8, "set": 9, "out": 10, "nov": 11, "dez": 12
    ]

    nonisolated private static let dueWeekdayNumbers: [String: Int] = [
        "domingo": 1, "segunda": 2, "terca": 3, "quarta": 4, "quinta": 5, "sexta": 6, "sabado": 7
    ]

    nonisolated private static let dueWeekdayMarkers: Set<String> = [
        "na", "no", "nesta", "neste", "nessa", "nesse", "esta", "este", "essa", "esse",
        "desta", "deste", "dessa", "desse", "de", "pra", "para", "proxima", "proximo",
        "ate", "toda", "todo"
    ]

    nonisolated private static let dueDurationPattern = try? NSRegularExpression(
        pattern: #"\b(?:a cada|cada|daqui(?: a)?|em|por|durante|ha|faz|dentro de|umas?|uns)\s+\d{1,3}\s*(?:h|hs|horas?|min|minutos?)\b|\bde\s+\d{1,3}\s+horas?\b|\b\d{1,2}\s*/\s*\d{1,2}\s*h\b|\b\d{1,3}\s*(?:h|hs|horas?)\s+(?:antes|depois|seguidas|por dia)\b"#
    )
    nonisolated private static let dueAlternativePattern = try? NSRegularExpression(
        pattern: #"\bdia \d{1,2} (?:ou|e|a|ate) \d{1,2}(?!\d)|\b\d{1,2}(?:h\d{0,2})? ?(?:ou|e|a|ate) (?:as )?\d{1,2} ?(?:h|horas?)\b|\bentre (?:as |os dias |o dia |dia )?\d{1,2}(?!\d)|\bdas \d{1,2}(?:h\d{0,2})? (?:as|a|ate) \d{1,2}(?!\d)|\b\d{1,2}h \d{2}\b"#
    )
    nonisolated private static let dueNoonPattern = try? NSRegularExpression(
        pattern: #"\bmeio[- ]?dia( e meia)?\b"#
    )
    nonisolated private static let duePartOfDayTimePattern = try? NSRegularExpression(
        pattern: #"\b(\d{1,2})(?:h(\d{2})?|:(\d{2}))?(?:min)?\s*(?:horas?\s*)?d[ae] (manha|tarde|noite)\b"#
    )
    nonisolated private static let dueHourMinutePattern = try? NSRegularExpression(
        pattern: #"\b(\d{1,2})(?:h|:)(\d{2})(?:h|min)?\b"#
    )
    nonisolated private static let dueWholeHourPattern = try? NSRegularExpression(
        pattern: #"\b(\d{1,2}) ?(?:hs?|horas?)\b"#
    )
    nonisolated private static let dueBareHourPattern = try? NSRegularExpression(
        pattern: #"\bas (\d{1,2})\b(?=\s*(?:$|[,.;!?)]|(?:de |da )?(?:hoje|amanha|depois|dia|na|no|nesta|neste|nessa|nesse|esta|este|proxim[ao]|segunda|terca|quarta|quinta|sexta|sabado|domingo)\b))"#
    )
    nonisolated private static let dueAfterTomorrowPattern = try? NSRegularExpression(
        pattern: #"\bdepois de amanha\b"#
    )
    nonisolated private static let dueTomorrowPattern = try? NSRegularExpression(
        pattern: #"\bamanha\b"#
    )
    nonisolated private static let dueTodayPattern = try? NSRegularExpression(
        pattern: #"\bhoje\b"#
    )
    nonisolated private static let dueDaysAheadPattern = try? NSRegularExpression(
        pattern: #"\b(?:daqui (?:a )?|em )(\d{1,3}) dias?\b"#
    )
    nonisolated private static let dueNumericDatePattern = try? NSRegularExpression(
        pattern: #"\b(?:(dia|em|ate|para|no dia) )?(\d{1,2})o?/(\d{1,2})(?:/(\d{4}|\d{2}))?\b"#
    )
    nonisolated private static let dueNamedMonthPattern = try? NSRegularExpression(
        pattern: #"\b(?:dia )?(\d{1,2})o? (?:de )?(janeiro|fevereiro|marco|abril|maio|junho|julho|agosto|setembro|outubro|novembro|dezembro|jan|fev|mar|abr|mai|jun|jul|ago|set|out|nov|dez)\b\.?(?: de (\d{4}))?"#
    )
    nonisolated private static let dueDayOfMonthPattern = try? NSRegularExpression(
        pattern: #"\bdia (\d{1,2})o?\b( do (?:mes que vem|proximo mes))?"#
    )
    nonisolated private static let dueWeekdayPattern = try? NSRegularExpression(
        pattern: #"\b(domingo|segunda|terca|quarta|quinta|sexta|sabado)(-feira| feira)?( que vem)?\b"#
    )
    nonisolated private static let dueOrdinalWeekdayPattern = try? NSRegularExpression(
        pattern: #"\b([2-6])(?:ª([ -]?feira)?|a([ -]?feira))( que vem)?(?=$|[\s,.;!?)])"#
    )
    nonisolated private static let dueOrdinalNounPattern = try? NSRegularExpression(
        pattern: #"^ (?:via|vez|serie|ano|parcela|parte|dose|opcao|etapa|fase|prestacao|mensalidade|semana|turma|chamada|colocad[ao]|lugar|edicao|chance|mao)\b"#
    )
    nonisolated private static let dueWeekdayTimePattern = try? NSRegularExpression(
        pattern: #"^,? (?:as \d{1,2}|\d{1,2} ?(?:hs?\b|h\d|:|horas?\b|da ))"#
    )
    nonisolated private static let dueStrayHourPattern = try? NSRegularExpression(
        pattern: #"\bas \d{1,2}\b"#
    )
    nonisolated private static let duePeriodWordPattern = try? NSRegularExpression(
        pattern: #"\b(?:ontem|anteontem|semana|mes|quinzena|feriado|seg|qua|qui|sex|sab|dom)\b"#
    )
    nonisolated private static let duePartOfDayPattern = try? NSRegularExpression(
        pattern: #"\b(?:tarde|noite|madrugada)\b"#
    )

    private static func householdMember(
        for user: AuthUser?,
        relationship: String,
        permissionRole: FamilyPermissionRole = .member
    ) -> HouseholdMember {
        let rawDisplayName = user?.displayName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        return HouseholdMember(
            userID: user?.id,
            name: rawDisplayName.isEmpty ? "Você" : rawDisplayName,
            relationship: relationship,
            role: .adult,
            permissionRole: permissionRole,
            tone: .sky,
            taskCount: 0,
            memoryNote: "Participante principal desta casa."
        )
    }

    private static var ninaAssistantMember: HouseholdMember {
        PreviewData.familyGroup.members.first { $0.role == .assistant } ?? HouseholdMember(
            name: "Nina",
            relationship: "IA da casa",
            role: .assistant,
            tone: .mint,
            taskCount: 0,
            memoryNote: "Aprende a dinâmica familiar e transforma lembranças soltas em organização."
        )
    }
}

private struct DueDay: Equatable {
    var year: Int
    var month: Int
    var day: Int
}

private struct DueClockTime {
    var hour: Int
    var minute: Int
}

private enum DueDateWord {
    case pinned(days: Int)
    case monthDay(day: Int, month: Int, year: Int?)
    case dayOfMonth(day: Int, nextMonth: Bool)
    case weekday(Int, notToday: Bool)
}

private struct DueWords {
    var dates: [DueDateWord]
    var time: DueClockTime?
}

enum PreviewData {
    static let mirnaID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    static let heitorID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    static let childID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
    static let thorID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
    static let ninaID = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!

    static let familyGroup = FamilyGroup(
        name: "Casa Castello",
        inviteCode: "casa-47a9f2d0b3c1e8a4d6f2",
        members: [
            HouseholdMember(
                id: heitorID,
                name: "Heitor",
                relationship: "Marido",
                role: .adult,
                tone: .sky,
                taskCount: 8,
                memoryNote: "Costuma cuidar das contas e compras de última hora."
            ),
            HouseholdMember(
                id: mirnaID,
                name: "Mirna",
                relationship: "Esposa",
                role: .adult,
                tone: .coral,
                taskCount: 82,
                memoryNote: "Centraliza escola, saúde, refeições e lembretes da casa."
            ),
            HouseholdMember(
                id: childID,
                name: "Filho",
                relationship: "Criança",
                role: .child,
                tone: .amber,
                taskCount: 4,
                memoryNote: ""
            ),
            HouseholdMember(
                id: thorID,
                name: "Thor",
                relationship: "Pet",
                role: .pet,
                tone: .lavender,
                taskCount: 3,
                memoryNote: ""
            ),
            HouseholdMember(
                id: ninaID,
                name: "Nina",
                relationship: "IA da casa",
                role: .assistant,
                tone: .mint,
                taskCount: 0,
                memoryNote: "Aprende a dinâmica familiar e transforma lembranças soltas em organização."
            )
        ]
    )

    static let messages: [ChatMessage] = [
        ChatMessage(
            sender: .nina,
            text: "Me conta o que está pesando.",
            timestamp: .now
        )
    ]

    static let taskSections: [TaskSection] = [
        TaskSection(
            id: TaskSectionDefaults.houseTasksID,
            title: "Tarefas da casa",
            symbolName: "checklist",
            tone: .mint
        )
    ]

    static let customTaskCategories: [TaskCategory] = []

    static let tasks: [TaskItem] = [
        TaskItem(
            title: "Separar uniforme da escola",
            subtitle: "Deixar mochila e garrafa prontas antes de dormir.",
            owner: "Mirna",
            dueLabel: "Hoje, noite",
            category: .school,
            priority: .high,
            isDone: false,
            createdBy: "Nina"
        ),
        TaskItem(
            title: "Pagar conta de energia",
            subtitle: "Vencimento salvo a partir do boleto.",
            owner: "Heitor",
            dueLabel: "Amanhã",
            category: .bills,
            priority: .urgent,
            isDone: false,
            createdBy: "Manual"
        ),
        TaskItem(
            title: "Planejar almoço de quarta",
            subtitle: "Usar o que já tem na geladeira.",
            owner: "Casa",
            dueLabel: "Quarta",
            category: .food,
            priority: .normal,
            isDone: true,
            createdBy: "Nina"
        ),
        TaskItem(
            kind: .seed,
            title: "Organizar as fotos da família",
            subtitle: "Separar os melhores momentos do último ano.",
            owner: "Casa",
            dueLabel: "Sem data",
            category: .home,
            isDone: false,
            createdBy: "Nina"
        ),
        TaskItem(
            title: "Levar comprovante escolar",
            subtitle: "Documento precisa ir na mochila.",
            owner: "Casa",
            dueLabel: "Hoje, 18:00",
            dueAt: Calendar.current.date(byAdding: .hour, value: 2, to: .now),
            category: .school,
            isDone: false,
            createdBy: "Nina"
        ),
        TaskItem(
            title: "Comprar gás",
            subtitle: "Estimativa: acaba em 10 dias.",
            owner: "Casa",
            dueLabel: "Daqui 8 dias",
            dueAt: Calendar.current.date(byAdding: .day, value: 8, to: .now),
            category: .home,
            priority: .high,
            isDone: false,
            createdBy: "Nina"
        ),
        TaskItem(
            title: "Remédio do filho",
            subtitle: "Rotina médica simulada.",
            owner: "Casa",
            dueLabel: "21:00",
            dueAt: Calendar.current.date(byAdding: .hour, value: 4, to: .now),
            category: .health,
            recurrence: .daily,
            isDone: false,
            createdBy: "Nina"
        )
    ]

    static let shoppingItems: [ShoppingItem] = [
        ShoppingItem(title: "Gás", amount: "1 botijão", owner: "Heitor", isChecked: false),
        ShoppingItem(title: "Ração do Thor", amount: "3 kg", owner: "Casa", isChecked: false),
        ShoppingItem(title: "Frutas para lancheira", amount: "5 dias", owner: "Mirna", isChecked: true)
    ]

    // Demo insights never assert a metric about the household: the live workload card is the only
    // surface allowed to put a number on who is carrying what.
    static let insights: [HouseholdInsight] = [
        HouseholdInsight(
            title: "Resumo da semana",
            message: "Toda semana a Nina reúne o que ficou pendente, o que foi concluído e onde a casa está pesando mais.",
            metric: "Semanal",
            symbolName: "calendar.badge.clock",
            tone: .lavender
        )
    ]
}
