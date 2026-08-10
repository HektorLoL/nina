import Foundation
import Observation

enum PrivacyPolicyVersion {
    static let current = "2026-06-16"
}

struct AIMemoryConsentRecord: Codable, Hashable {
    var acceptedAt: Date
    var policyVersion: String
}

struct PrivacyExportPackage: Codable {
    var exportedAt: Date
    var policyVersion: String
    var user: AuthUser?
    var profile: UserProfile?
    var profilePhotoData: Data?
    var familyGroup: FamilyGroup
    var aiMemoryConsent: AIMemoryConsentRecord?
    var data: AppDataSnapshot
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
    case pendingApproval
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

@MainActor
@Observable
final class AppStore {
    static let maxFamilyPeople = 8
    static let houseTasksSectionID = TaskSectionDefaults.houseTasksID

    var familyGroup: FamilyGroup
    var homeAccessState: HomeAccessState = .loading
    var currentPermissionRole: FamilyPermissionRole = .member
    var inviteStatus: FamilyInviteStatus?
    var pendingJoinRequest: FamilyJoinRequest?
    var joinRequests: [FamilyJoinRequest] = []
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
    var pendingPriorityTaskIDs: Set<TaskItem.ID> = []
    var isNinaResponding = false
    var ninaConnectionNotice: String?
    var taskEditConflict: TaskEditConflict?
    var aiMemoryConsent: AIMemoryConsentRecord?
    var notificationAuthorizationStatus: HomeNotificationAuthorizationStatus = .notDetermined

    @ObservationIgnored private let ninaEngine: any NinaEngine
    @ObservationIgnored private let fallbackNinaEngine = MockNinaEngine()
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let privateDataStore: any PrivateLocalDataStoring
    @ObservationIgnored private let remoteHomeBackend: (any RemoteHomeBackend)?
    @ObservationIgnored private let notificationScheduler: any HomeNotificationScheduling
    @ObservationIgnored private var activeHomeUserID: String?
    @ObservationIgnored private var activeUser: AuthUser?
    @ObservationIgnored private var homeContextGeneration: UInt64 = 0
    @ObservationIgnored private var localStateRevision: UInt64 = 0
    @ObservationIgnored private var remoteMutationGeneration: UInt64 = 0
    @ObservationIgnored private var remoteMutationTask: Task<Void, Never>?
    @ObservationIgnored private var realtimeListenerTask: Task<Void, Never>?
    @ObservationIgnored private var realtimeRefreshTask: Task<Void, Never>?
    @ObservationIgnored private var notificationSyncTask: Task<Void, Never>?

    var isSyncingHome = false
    var syncErrorMessage: String?

    var hasActiveHome: Bool {
        homeAccessState == .authorized
    }

    var canManageFamily: Bool {
        currentPermissionRole.canManageFamily
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

    var canUseNinaAI: Bool {
        if isUsingLocalNina {
            return true
        }
        guard let activeUser else {
            return remoteHomeBackend == nil
        }
        return familyGroup.members.contains {
            $0.userID == activeUser.id && $0.role == .adult
        }
    }

    var requiresAIMemoryConsent: Bool {
        canUseNinaAI
            && !isUsingLocalNina
            && activeUser != nil
            && remoteHomeBackend != nil
    }

    var hasAIMemoryConsent: Bool {
        aiMemoryConsent != nil
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
        "\(familyPeopleCount) pessoas + Nina"
    }

    func canEditFamilyMember(_ member: HouseholdMember) -> Bool {
        guard member.role != .assistant else { return false }
        if member.userID == activeHomeUserID {
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
        homeContextGeneration &+= 1
        remoteMutationTask?.cancel()
        remoteMutationTask = nil
        remoteMutationGeneration = 0
        stopRealtimeSync()
        activeHomeUserID = user?.id
        activeUser = user
        let contextToken = currentHomeContextToken
        loadAIMemoryConsent(for: user?.id)
        pendingPriorityTaskIDs = []
        taskEditConflict = nil
        syncErrorMessage = nil
        inviteStatus = nil
        pendingJoinRequest = nil
        joinRequests = []
        householdPremium = .inactive

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

            do {
                let state = try await remoteHomeBackend.loadHome(for: user)
                guard isCurrentHomeContext(contextToken) else { return }

                if let state {
                    apply(state)
                    homeAccessState = .authorized
                    cacheActiveHomeLocally()
                    cacheAppSnapshotLocally()
                    startRealtimeSync()
                    return
                }

                let request = try await remoteHomeBackend.loadPendingJoinRequest()
                guard isCurrentHomeContext(contextToken) else { return }

                if let request {
                    pendingJoinRequest = request
                    homeAccessState = .pendingApproval
                    currentPermissionRole = .member
                    familyGroup = PreviewData.familyGroup
                    resetActivityState()
                    return
                }

                homeAccessState = .noHome
                currentPermissionRole = .member
                familyGroup = PreviewData.familyGroup
                resetActivityState()
                return
            } catch is CancellationError {
                return
            } catch {
                guard isCurrentHomeContext(contextToken) else { return }
                homeAccessState = .unavailable
                currentPermissionRole = .member
                familyGroup = PreviewData.familyGroup
                resetActivityState()
                syncErrorMessage = "Não foi possível verificar sua participação nesta casa."
                return
            }
        }

        #if DEBUG
        activateLocalHomeContext(for: user)
        #else
        homeAccessState = .unavailable
        syncErrorMessage = "O backend da Nina não está configurado."
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
        let requestedUserID = user.id
        let requestedRevision = localStateRevision
        isSyncingHome = true
        syncErrorMessage = nil
        defer { finishSyncingHome(ifCurrent: contextToken) }

        do {
            let state = try await remoteHomeBackend.loadHome(for: user)

            guard isCurrentHomeContext(contextToken),
                  activeHomeUserID == requestedUserID,
                  localStateRevision == requestedRevision else {
                return
            }

            guard let state else {
                let request = try await remoteHomeBackend.loadPendingJoinRequest()
                guard isCurrentHomeContext(contextToken),
                      localStateRevision == requestedRevision else {
                    return
                }

                if let request {
                    pendingJoinRequest = request
                    homeAccessState = .pendingApproval
                    currentPermissionRole = .member
                    familyGroup = PreviewData.familyGroup
                    resetActivityState()
                    return
                }

                clearCachedHome(for: requestedUserID)
                homeAccessState = .noHome
                currentPermissionRole = .member
                familyGroup = PreviewData.familyGroup
                resetActivityState()
                return
            }

            apply(state)
            homeAccessState = .authorized
            cacheActiveHomeLocally()
            cacheAppSnapshotLocally()
        } catch is CancellationError {
            return
        } catch {
            guard isCurrentHomeContext(contextToken),
                  activeHomeUserID == requestedUserID else { return }
            guard localStateRevision == requestedRevision else {
                syncErrorMessage = "Não foi possível atualizar a casa. Suas alterações locais foram mantidas."
                return
            }
            homeAccessState = .unavailable
            currentPermissionRole = .member
            familyGroup = PreviewData.familyGroup
            resetActivityState()
            syncErrorMessage = "Não foi possível verificar sua participação nesta casa."
        }
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
                syncErrorMessage = "Não consegui criar a casa no Supabase agora."
                Haptics.error()
                return false
            }
        }

        #if DEBUG
        familyGroup = FamilyGroup(
            name: name,
            inviteCode: Self.secureLocalInviteCode(),
            members: [
                Self.householdMember(for: owner, relationship: "Criador", permissionRole: .owner),
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
        syncErrorMessage = "O Supabase não está configurado para criar uma casa."
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
                syncErrorMessage = "Este convite é inválido, expirou ou a casa está sem vagas."
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
        syncErrorMessage = "O Supabase não está configurado para entrar em uma casa."
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
        syncErrorMessage = "O backend da Nina não está configurado."
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
        syncErrorMessage = "O backend da Nina não está configurado."
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
        syncErrorMessage = "O backend da Nina não está configurado."
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
                syncErrorMessage = "Não foi possível aprovar este pedido."
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

    func sendMessage(
        _ rawText: String,
        attachments: [NinaAttachmentInput] = []
    ) async {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
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
        var shouldPersistLegacyTurn = false

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
            shouldPersistLegacyTurn = !response.serverPersisted
            ninaConnectionNotice = nil
        } catch let engineError as NinaEngineError where engineError != .unavailable {
            guard isCurrentHomeContext(contextToken) else { return }
            response = NinaEngineResponse(
                reply: engineError.userMessage,
                suggestion: nil
            )
            ninaConnectionNotice = nil
            shouldPersistLegacyTurn = false
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
                    reply: "Anotei. Tente novamente em instantes para eu organizar isso com você.",
                    suggestion: nil
                )
            ninaConnectionNotice = "A Nina online está indisponível. A resposta abaixo usou o modo local."
            shouldPersistLegacyTurn = false
        }
        guard isCurrentHomeContext(contextToken) else { return }

        let ninaMessage = ChatMessage(
            id: response.assistantMessageID ?? UUID(),
            sender: .nina,
            text: response.reply,
            timestamp: .now,
            suggestion: response.suggestion,
            proposals: NinaAIConfiguration.isV2Enabled ? response.proposals : []
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
        } else if shouldPersistLegacyTurn {
            enqueueRemoteMutation(errorMessage: "Não foi possível sincronizar a conversa com a Nina.") {
                backend,
                familyID,
                user in
                try await backend.createChatMessage(userMessage, familyID: familyID, currentUser: user)
                try await backend.createChatMessage(ninaMessage, familyID: familyID, currentUser: user)
            }
        }
    }

    func applySuggestion(_ suggestion: NinaSuggestion) {
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

        let confirmation = ChatMessage(
            sender: .nina,
            text: "Pronto. Deixei isso organizado na casa.",
            timestamp: .now
        )
        messages.append(confirmation)
        persistActivityLocally()
        enqueueRemoteMutation(errorMessage: "Não foi possível sincronizar a confirmação da Nina.") {
            backend,
            familyID,
            user in
            try await backend.createChatMessage(confirmation, familyID: familyID, currentUser: user)
        }
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
            ninaConnectionNotice = "Não foi possível confirmar essa ação agora."
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

    @discardableResult
    func grantAIMemoryConsent() async -> Bool {
        await recordAIMemoryConsent(granted: true)
    }

    @discardableResult
    func revokeAIMemoryConsent() async -> Bool {
        await recordAIMemoryConsent(granted: false)
    }

    // The local record is a mirror of the server grant, never the grant itself.
    private func recordAIMemoryConsent(granted: Bool) async -> Bool {
        let contextToken = currentHomeContextToken
        let previousRecord = aiMemoryConsent
        syncErrorMessage = nil

        let optimisticRecord = granted
            ? AIMemoryConsentRecord(
                acceptedAt: .now,
                policyVersion: PrivacyPolicyVersion.current
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
                    policyVersion: PrivacyPolicyVersion.current
                )
                guard isCurrentHomeContext(contextToken) else { return false }
                apply(state)
                homeAccessState = .authorized
                persistActiveHome()
                return hasAIMemoryConsent == granted
            } catch {
                guard isCurrentHomeContext(contextToken) else { return false }
                applyAIMemoryConsent(previousRecord)
                syncErrorMessage = granted
                    ? "Não foi possível registrar seu consentimento. Nada mudou por enquanto."
                    : "Não foi possível revogar seu consentimento. Ele continua ativo nesta casa."
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

    func makePrivacyExportData(
        profile: UserProfile? = nil,
        profilePhotoData: Data? = nil
    ) throws -> Data {
        let package = PrivacyExportPackage(
            exportedAt: .now,
            policyVersion: PrivacyPolicyVersion.current,
            user: activeUser,
            profile: profile,
            profilePhotoData: profilePhotoData,
            familyGroup: familyGroup,
            aiMemoryConsent: aiMemoryConsent,
            data: currentSnapshot
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(package)
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
        joinRequests = []
        pendingPriorityTaskIDs = []
        isNinaResponding = false
        ninaConnectionNotice = nil
        taskEditConflict = nil
        isSyncingHome = false
        syncErrorMessage = nil
        aiMemoryConsent = nil
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
            proposedTask.snoozedUntil = nil
        } else if let recurrence {
            proposedTask.recurrence = recurrence
            proposedTask.snoozedUntil = nil
        }

        if let expectedVersion, expectedVersion != currentTask.version {
            taskEditConflict = TaskEditConflict(
                localTask: proposedTask,
                remoteTask: currentTask
            )
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

    func toggleTask(_ task: TaskItem) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        let currentTask = tasks[index]
        var proposedTask = currentTask

        if !currentTask.isDone, currentTask.recurrence != .none {
            let anchor = max(currentTask.dueAt ?? .now, .now).addingTimeInterval(1)
            guard let nextDate = currentTask.scheduledOccurrence(after: anchor) else { return }
            proposedTask.dueAt = nextDate
            proposedTask.dueLabel = Self.taskDueLabel(for: nextDate)
            proposedTask.snoozedUntil = nil
        } else {
            proposedTask.isDone.toggle()
        }
        submitTaskUpdate(proposedTask, basedOn: currentTask)
    }

    func snoozeTask(_ id: TaskItem.ID, until date: Date) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        let currentTask = tasks[index]
        var proposedTask = currentTask
        proposedTask.snoozedUntil = date
        submitTaskUpdate(proposedTask, basedOn: currentTask)
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

    func synchronizeLocalNotifications() {
        let canScheduleForActiveUser = activeHomeUserID != nil && hasActiveHome
        let tasksForNotifications = canScheduleForActiveUser ? tasks : []
        let viewer = canScheduleForActiveUser
            ? HomeNotificationViewer(member: currentFamilyMember)
            : HomeNotificationViewer()
        let familyID = familyGroup.id
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
        taskEditConflict = nil
        submitTaskUpdate(conflict.localTask, basedOn: conflict.remoteTask)
    }

    func acceptRemoteTaskConflict() {
        taskEditConflict = nil
    }

    func markPriorityTaskPending(_ id: TaskItem.ID) {
        var pendingIDs = pendingPriorityTaskIDs
        pendingIDs.insert(id)
        pendingPriorityTaskIDs = pendingIDs
    }

    func clearPriorityTaskPending(_ id: TaskItem.ID) {
        var pendingIDs = pendingPriorityTaskIDs
        pendingIDs.remove(id)
        pendingPriorityTaskIDs = pendingIDs
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
            }
        }
    }

    private func submitTaskUpdate(_ proposedTask: TaskItem, basedOn baseTask: TaskItem) {
        guard let index = tasks.firstIndex(where: { $0.id == proposedTask.id }) else { return }
        let contextToken = currentHomeContextToken

        var optimisticTask = proposedTask
        optimisticTask.version = baseTask.version + 1
        tasks[index] = optimisticTask
        persistActivityLocally()
        synchronizeLocalNotifications()

        enqueueRemoteMutation(errorMessage: "Não foi possível sincronizar as alterações da tarefa.") {
            [weak self] backend,
            familyID,
            _ in
            let result = try await backend.updateTask(
                optimisticTask,
                expectedVersion: baseTask.version,
                familyID: familyID
            )
            guard let self, self.isCurrentHomeContext(contextToken) else { return }
            self.applyTaskUpdateResult(result, optimisticTask: optimisticTask)
        }
    }

    private func applyTaskUpdateResult(
        _ result: TaskUpdateResult,
        optimisticTask: TaskItem
    ) {
        guard let index = tasks.firstIndex(where: { $0.id == optimisticTask.id }) else { return }

        switch result {
        case .updated(let serverTask):
            guard tasks[index].version <= serverTask.version else { return }
            tasks[index] = serverTask
        case .conflict(let remoteTask):
            guard tasks[index].version <= optimisticTask.version else { return }
            tasks[index] = remoteTask
            taskEditConflict = TaskEditConflict(
                localTask: optimisticTask,
                remoteTask: remoteTask
            )
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

        let snapshot = currentSnapshot
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
            return
        }
        aiMemoryConsent = record
    }

    private func resetActivityState() {
        householdPremium = .inactive
        apply(.preview)
    }

    private func apply(_ snapshot: AppDataSnapshot) {
        messages = snapshot.messages
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
        pendingJoinRequest = nil

        if let snapshot = state.snapshot {
            apply(snapshot)
        } else {
            resetActivityState()
        }

        householdPremium = state.householdPremium
        applyAIMemoryConsent(Self.consentRecord(from: state.aiConsent))
    }

    private static func consentRecord(from consent: NinaAIConsent) -> AIMemoryConsentRecord? {
        guard consent.isGranted else { return nil }
        return AIMemoryConsentRecord(
            acceptedAt: consent.acceptedAt ?? .now,
            policyVersion: consent.policyVersion ?? PrivacyPolicyVersion.current
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

    nonisolated static func inferredDueAt(from label: String, now: Date = .now) -> Date? {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let normalized = trimmed
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
        let calendar = Calendar.current

        if let explicitTime = Self.timeFormatter.date(from: normalized) {
            let timeComponents = calendar.dateComponents([.hour, .minute], from: explicitTime)
            var dateComponents = calendar.dateComponents([.year, .month, .day], from: now)
            dateComponents.hour = timeComponents.hour
            dateComponents.minute = timeComponents.minute
            guard var date = calendar.date(from: dateComponents) else { return nil }
            if date <= now {
                date = calendar.date(byAdding: .day, value: 1, to: date) ?? date
            }
            return date
        }

        if let offset = Self.dayOffset(from: normalized),
           let date = calendar.date(byAdding: .day, value: offset, to: now) {
            return reminderDate(onSameDayAs: date, now: now)
        }

        if normalized.contains("amanha"),
           let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) {
            return reminderDate(onSameDayAs: tomorrow, now: now)
        }

        if normalized.contains("hoje") {
            return reminderDate(onSameDayAs: now, now: now)
        }

        if let absoluteDate = Self.shortDateFormatter.date(from: normalized) {
            return reminderDate(onSameDayAs: absoluteDate, now: now)
        }

        return nil
    }

    nonisolated static func reminderDate(onSameDayAs date: Date, now: Date = .now) -> Date? {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        components.hour = 9
        components.minute = 0

        guard let defaultDate = Calendar.current.date(from: components) else { return nil }
        if Calendar.current.isDate(defaultDate, inSameDayAs: now), defaultDate <= now {
            return Calendar.current.date(byAdding: .minute, value: 5, to: now)
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

    nonisolated private static func dayOffset(from label: String) -> Int? {
        guard let range = label.range(of: #"daqui\s+(\d+)\s+dias?"#, options: .regularExpression) else {
            return nil
        }

        let match = String(label[range])
        guard let numberRange = match.range(of: #"\d+"#, options: .regularExpression) else {
            return nil
        }
        return Int(match[numberRange])
    }

    nonisolated private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    nonisolated private static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.dateFormat = "dd/MM/yyyy"
        return formatter
    }()

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
                memoryNote: "Tem rotina de escola, mochila e atividades da semana."
            ),
            HouseholdMember(
                id: thorID,
                name: "Thor",
                relationship: "Pet",
                role: .pet,
                tone: .lavender,
                taskCount: 3,
                memoryNote: "Veterinário e ração precisam entrar na rotina."
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
            text: "Oi, eu sou a Nina. Pode escrever como você falaria com alguém da casa. Eu transformo isso em tarefa, lembrete ou memória.",
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
