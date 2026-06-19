import Foundation

struct RemoteHomeState {
    var familyGroup: FamilyGroup
    var permissionRole: FamilyPermissionRole
    var snapshot: AppDataSnapshot?
}

struct FamilyInvitePreview: Hashable {
    var code: String
    var familyName: String?
    var isValid: Bool
}

enum HomeRealtimeEvent: Sendable {
    case tasks
    case shoppingItems
    case reminders
    case chatMessages
}

enum TaskUpdateResult {
    case updated(TaskItem)
    case conflict(current: TaskItem)
}

enum NinaProposalDecision: String, Equatable {
    case accept
    case reject
}

struct NinaProposalResolution: Decodable {
    var id: UUID
    var state: NinaProposalState
}

protocol RemoteHomeBackend {
    func loadHome(for user: AuthUser) async throws -> RemoteHomeState?
    func createHome(named name: String, owner: AuthUser?) async throws -> RemoteHomeState
    func joinHome(with inviteCode: String, member: AuthUser?) async throws -> RemoteHomeState
    func previewInvite(code: String) async throws -> FamilyInvitePreview
    func updateFamilySettings(familyID: UUID, name: String) async throws -> RemoteHomeState
    func rotateFamilyInvite(familyID: UUID) async throws -> RemoteHomeState
    func addUnclaimedMember(_ member: HouseholdMember, familyID: UUID) async throws -> RemoteHomeState
    func updateFamilyMember(_ member: HouseholdMember) async throws -> RemoteHomeState
    func createTaskSection(_ section: TaskSection, sortOrder: Int, familyID: UUID) async throws
    func createTaskCategory(_ category: TaskCategory, familyID: UUID) async throws
    func createTask(_ task: TaskItem, familyID: UUID, currentUser: AuthUser) async throws
    func updateTask(_ task: TaskItem, familyID: UUID) async throws
    func updateTask(
        _ task: TaskItem,
        expectedVersion: Int,
        familyID: UUID
    ) async throws -> TaskUpdateResult
    func createShoppingItem(_ item: ShoppingItem, familyID: UUID, currentUser: AuthUser) async throws
    func updateShoppingItem(_ item: ShoppingItem, familyID: UUID) async throws
    func createReminder(_ reminder: ReminderItem, familyID: UUID, currentUser: AuthUser) async throws
    func createChatMessage(_ message: ChatMessage, familyID: UUID, currentUser: AuthUser) async throws
    func resolveNinaProposal(
        _ proposalID: UUID,
        decision: NinaProposalDecision,
        editedPayload: NinaProposalPayload?,
        memoryVisibility: NinaMemoryVisibility?
    ) async throws -> NinaProposalResolution
    func updateNinaMemory(_ memory: NinaMemory) async throws -> NinaMemory
    func deleteNinaMemory(_ memoryID: UUID) async throws
    func deleteNinaChatHistory(familyID: UUID) async throws
    func realtimeEvents(familyID: UUID) async -> AsyncStream<HomeRealtimeEvent>
}

enum RemoteHomeBackendError: Error {
    case missingAuthenticatedUser
    case invalidAuthenticatedUserID
    case invalidInviteCode
    case familyNotFound
    case operationUnavailable
}

extension RemoteHomeBackend {
    func previewInvite(code: String) async throws -> FamilyInvitePreview {
        throw RemoteHomeBackendError.operationUnavailable
    }

    func rotateFamilyInvite(familyID: UUID) async throws -> RemoteHomeState {
        throw RemoteHomeBackendError.operationUnavailable
    }

    func updateTask(
        _ task: TaskItem,
        expectedVersion: Int,
        familyID: UUID
    ) async throws -> TaskUpdateResult {
        try await updateTask(task, familyID: familyID)
        return .updated(task)
    }

    func resolveNinaProposal(
        _ proposalID: UUID,
        decision: NinaProposalDecision,
        editedPayload: NinaProposalPayload?,
        memoryVisibility: NinaMemoryVisibility?
    ) async throws -> NinaProposalResolution {
        throw RemoteHomeBackendError.operationUnavailable
    }

    func updateNinaMemory(_ memory: NinaMemory) async throws -> NinaMemory {
        throw RemoteHomeBackendError.operationUnavailable
    }

    func deleteNinaMemory(_ memoryID: UUID) async throws {
        throw RemoteHomeBackendError.operationUnavailable
    }

    func deleteNinaChatHistory(familyID: UUID) async throws {
        throw RemoteHomeBackendError.operationUnavailable
    }

    func realtimeEvents(familyID: UUID) async -> AsyncStream<HomeRealtimeEvent> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }
}

#if canImport(Supabase)
import Supabase

struct SupabaseRemoteHomeBackend: RemoteHomeBackend {
    var client: SupabaseClient
    var diagnostics: BackendDiagnosticsStore? = nil

    func loadHome(for user: AuthUser) async throws -> RemoteHomeState? {
        let context: HomeContextRow = try await perform(
            operation: "get_current_home_context"
        ) {
            try await client
                .rpc("get_current_home_context")
                .execute()
                .value
        }

        return try await loadRemoteState(from: context)
    }

    func createHome(named name: String, owner: AuthUser?) async throws -> RemoteHomeState {
        guard let owner else { throw RemoteHomeBackendError.missingAuthenticatedUser }
        guard UUID(uuidString: owner.id) != nil else {
            throw RemoteHomeBackendError.invalidAuthenticatedUserID
        }

        let context: HomeContextRow = try await perform(operation: "create_family") {
            try await client
                .rpc(
                    "create_family",
                    params: CreateFamilyParams(familyName: name)
                )
                .execute()
                .value
        }

        guard let state = try await loadRemoteState(from: context) else {
            throw RemoteHomeBackendError.familyNotFound
        }
        return state
    }

    func joinHome(with inviteCode: String, member: AuthUser?) async throws -> RemoteHomeState {
        guard let normalizedInvite = AppStore.normalizedInviteCode(from: inviteCode) else {
            throw RemoteHomeBackendError.invalidInviteCode
        }

        let context: HomeContextRow = try await perform(operation: "join_family_by_invite") {
            try await client
                .rpc(
                    "join_family_by_invite",
                    params: JoinFamilyByInviteParams(inviteCode: normalizedInvite)
                )
                .execute()
                .value
        }

        guard let state = try await loadRemoteState(from: context) else {
            throw RemoteHomeBackendError.familyNotFound
        }
        return state
    }

    func previewInvite(code: String) async throws -> FamilyInvitePreview {
        guard let normalizedInvite = AppStore.normalizedInviteCode(from: code) else {
            throw RemoteHomeBackendError.invalidInviteCode
        }

        let preview: InvitePreviewRow = try await perform(operation: "get_family_invite_preview") {
            try await client
                .rpc(
                    "get_family_invite_preview",
                    params: JoinFamilyByInviteParams(inviteCode: normalizedInvite)
                )
                .execute()
                .value
        }

        return FamilyInvitePreview(
            code: normalizedInvite,
            familyName: preview.familyName,
            isValid: preview.valid
        )
    }

    func updateFamilySettings(
        familyID: UUID,
        name: String
    ) async throws -> RemoteHomeState {
        let context: HomeContextRow = try await perform(operation: "update_family_settings") {
            try await client
                .rpc(
                    "update_family_settings",
                    params: UpdateFamilySettingsParams(
                        targetFamilyID: familyID,
                        familyName: name
                    )
                )
                .execute()
                .value
        }

        guard let state = try await loadRemoteState(from: context) else {
            throw RemoteHomeBackendError.familyNotFound
        }
        return state
    }

    func rotateFamilyInvite(familyID: UUID) async throws -> RemoteHomeState {
        let context: HomeContextRow = try await perform(operation: "rotate_family_invite_code") {
            try await client
                .rpc(
                    "rotate_family_invite_code",
                    params: FamilyIDParams(targetFamilyID: familyID)
                )
                .execute()
                .value
        }

        guard let state = try await loadRemoteState(from: context) else {
            throw RemoteHomeBackendError.familyNotFound
        }
        return state
    }

    func addUnclaimedMember(_ member: HouseholdMember, familyID: UUID) async throws -> RemoteHomeState {
        let context: HomeContextRow = try await perform(operation: "add_unclaimed_family_member") {
            try await client
                .rpc(
                    "add_unclaimed_family_member",
                    params: AddFamilyMemberParams(
                        targetFamilyID: familyID,
                        memberName: member.name,
                        relationship: member.relationship,
                        householdRole: member.role.rawValue,
                        tone: member.tone.rawValue,
                        memoryNote: member.memoryNote
                    )
                )
                .execute()
                .value
        }

        guard let state = try await loadRemoteState(from: context) else {
            throw RemoteHomeBackendError.familyNotFound
        }
        return state
    }

    func updateFamilyMember(_ member: HouseholdMember) async throws -> RemoteHomeState {
        let context: HomeContextRow = try await perform(operation: "update_family_member") {
            try await client
                .rpc(
                    "update_family_member",
                    params: UpdateFamilyMemberParams(
                        targetMemberID: member.id,
                        memberName: member.name,
                        relationship: member.relationship,
                        householdRole: member.role.rawValue,
                        tone: member.tone.rawValue,
                        memoryNote: member.memoryNote
                    )
                )
                .execute()
                .value
        }

        guard let state = try await loadRemoteState(from: context) else {
            throw RemoteHomeBackendError.familyNotFound
        }
        return state
    }

    func createTaskSection(_ section: TaskSection, sortOrder: Int, familyID: UUID) async throws {
        try await perform(operation: "task_sections.upsert") {
            _ = try await client
                .from("task_sections")
                .upsert(
                    TaskSectionUpsertRow(section: section, familyID: familyID, sortOrder: sortOrder),
                    onConflict: "family_id,id"
                )
                .execute()
            return ()
        }
    }

    func createTaskCategory(_ category: TaskCategory, familyID: UUID) async throws {
        try await perform(operation: "task_categories.upsert") {
            _ = try await client
                .from("task_categories")
                .upsert(
                    TaskCategoryUpsertRow(category: category, familyID: familyID),
                    onConflict: "family_id,id"
                )
                .execute()
            return ()
        }
    }

    func createTask(_ task: TaskItem, familyID: UUID, currentUser: AuthUser) async throws {
        try await perform(operation: "tasks.insert") {
            _ = try await client
                .from("tasks")
                .insert(
                    TaskInsertRow(
                        task: task,
                        familyID: familyID,
                        currentUserID: UUID(uuidString: currentUser.id)
                    )
                )
                .execute()
            return ()
        }
    }

    func updateTask(_ task: TaskItem, familyID: UUID) async throws {
        _ = try await updateTask(
            task,
            expectedVersion: max(task.version - 1, 1),
            familyID: familyID
        )
    }

    func updateTask(
        _ task: TaskItem,
        expectedVersion: Int,
        familyID: UUID
    ) async throws -> TaskUpdateResult {
        try await perform(operation: "tasks.update") {
            let updatedRows: [TaskRow] = try await client
                .from("tasks")
                .update(TaskUpdateRow(task: task))
                .eq("id", value: task.id)
                .eq("family_id", value: familyID)
                .eq("version", value: expectedVersion)
                .select(Self.taskColumns)
                .execute()
                .value

            if let updatedTask = updatedRows.first?.domainTask {
                return .updated(updatedTask)
            }

            let currentRows: [TaskRow] = try await client
                .from("tasks")
                .select(Self.taskColumns)
                .eq("id", value: task.id)
                .eq("family_id", value: familyID)
                .limit(1)
                .execute()
                .value

            guard let currentTask = currentRows.first?.domainTask else {
                throw RemoteHomeBackendError.familyNotFound
            }
            return .conflict(current: currentTask)
        }
    }

    func createShoppingItem(_ item: ShoppingItem, familyID: UUID, currentUser: AuthUser) async throws {
        try await perform(operation: "shopping_items.insert") {
            _ = try await client
                .from("shopping_items")
                .insert(
                    ShoppingItemInsertRow(
                        item: item,
                        familyID: familyID,
                        currentUserID: UUID(uuidString: currentUser.id)
                    )
                )
                .execute()
            return ()
        }
    }

    func updateShoppingItem(_ item: ShoppingItem, familyID: UUID) async throws {
        try await perform(operation: "shopping_items.update") {
            _ = try await client
                .from("shopping_items")
                .update(ShoppingItemUpdateRow(item: item))
                .eq("id", value: item.id)
                .eq("family_id", value: familyID)
                .execute()
            return ()
        }
    }

    func createReminder(_ reminder: ReminderItem, familyID: UUID, currentUser: AuthUser) async throws {
        try await perform(operation: "reminders.insert") {
            _ = try await client
                .from("reminders")
                .insert(
                    ReminderInsertRow(
                        reminder: reminder,
                        familyID: familyID,
                        currentUserID: UUID(uuidString: currentUser.id)
                    )
                )
                .execute()
            return ()
        }

        // TODO(PRODUCTION_APNS): Shared family reminders need server-triggered
        // APNs push notifications so every member's device is notified even
        // when Nina is closed. This is intentionally deferred until production
        // because the Push Notifications capability requires paid Apple
        // Developer Program enrollment, and the current unpaid/free developer
        // setup cannot enable APNs; local notifications cover simple on-device
        // reminders for now.
    }

    func createChatMessage(_ message: ChatMessage, familyID: UUID, currentUser: AuthUser) async throws {
        try await perform(operation: "chat_messages.insert") {
            _ = try await client
                .from("chat_messages")
                .insert(
                    ChatMessageInsertRow(
                        message: message,
                        familyID: familyID,
                        currentUserID: UUID(uuidString: currentUser.id)
                    )
                )
                .execute()
            return ()
        }
    }

    func resolveNinaProposal(
        _ proposalID: UUID,
        decision: NinaProposalDecision,
        editedPayload: NinaProposalPayload?,
        memoryVisibility: NinaMemoryVisibility?
    ) async throws -> NinaProposalResolution {
        try await perform(operation: "resolve_nina_proposal") {
            try await client
                .rpc(
                    "resolve_nina_proposal",
                    params: ResolveNinaProposalParams(
                        proposalID: proposalID,
                        decision: decision.rawValue,
                        editedPayload: editedPayload,
                        memoryVisibility: memoryVisibility?.rawValue
                    )
                )
                .execute()
                .value
        }
    }

    func updateNinaMemory(_ memory: NinaMemory) async throws -> NinaMemory {
        try await perform(operation: "update_nina_memory") {
            try await client
                .rpc(
                    "update_nina_memory",
                    params: UpdateNinaMemoryParams(memory: memory)
                )
                .execute()
                .value
        }
    }

    func deleteNinaMemory(_ memoryID: UUID) async throws {
        try await perform(operation: "delete_nina_memory") {
            _ = try await client
                .rpc(
                    "delete_nina_memory",
                    params: DeleteNinaMemoryParams(memoryID: memoryID)
                )
                .execute()
            return ()
        }
    }

    func deleteNinaChatHistory(familyID: UUID) async throws {
        try await perform(operation: "delete_current_nina_chat_history") {
            _ = try await client
                .rpc(
                    "delete_current_nina_chat_history",
                    params: DeleteNinaChatHistoryParams(familyID: familyID)
                )
                .execute()
            return ()
        }
    }

    func realtimeEvents(familyID: UUID) async -> AsyncStream<HomeRealtimeEvent> {
        let channel = client.channel("home-\(familyID.uuidString)")
        let filter = RealtimePostgresFilter.eq("family_id", value: familyID)
        let taskChanges = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "tasks",
            filter: filter
        )
        let shoppingChanges = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "shopping_items",
            filter: filter
        )
        let reminderChanges = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "reminders",
            filter: filter
        )
        let chatChanges = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "chat_messages",
            filter: filter
        )

        return AsyncStream { continuation in
            let observationTask = Task {
                do {
                    try await perform(operation: "realtime.subscribe") {
                        try await channel.subscribeWithError()
                    }
                } catch is CancellationError {
                    continuation.finish()
                    await client.removeChannel(channel)
                    return
                } catch {
                    continuation.finish()
                    await client.removeChannel(channel)
                    return
                }

                await withTaskGroup(of: Void.self) { group in
                    group.addTask {
                        for await _ in taskChanges {
                            continuation.yield(.tasks)
                        }
                    }
                    group.addTask {
                        for await _ in shoppingChanges {
                            continuation.yield(.shoppingItems)
                        }
                    }
                    group.addTask {
                        for await _ in reminderChanges {
                            continuation.yield(.reminders)
                        }
                    }
                    group.addTask {
                        for await _ in chatChanges {
                            continuation.yield(.chatMessages)
                        }
                    }
                    await group.waitForAll()
                }

                continuation.finish()
                await client.removeChannel(channel)
            }

            continuation.onTermination = { _ in
                observationTask.cancel()
            }
        }
    }

    private func loadRemoteState(from context: HomeContextRow) async throws -> RemoteHomeState? {
        guard var state = context.remoteState else { return nil }
        state.snapshot = try await loadNormalizedSnapshot(familyID: state.familyGroup.id)
        return state
    }

    private func loadNormalizedSnapshot(familyID: UUID) async throws -> AppDataSnapshot {
        async let sectionRows = loadTaskSections(familyID: familyID)
        async let categoryRows = loadTaskCategories(familyID: familyID)
        async let taskRows = loadTasks(familyID: familyID)
        async let shoppingRows = loadShoppingItems(familyID: familyID)
        async let reminderRows = loadReminders(familyID: familyID)
        async let ninaState = loadNinaState(familyID: familyID)
        async let insightRows = loadInsights(familyID: familyID)

        return try await AppDataSnapshot(
            messages: ninaState.messages.map(\.domainMessage),
            taskSections: sectionRows.map(\.domainSection),
            customTaskCategories: categoryRows.map(\.domainCategory),
            tasks: taskRows.map(\.domainTask),
            shoppingItems: shoppingRows.map(\.domainItem),
            reminders: reminderRows.map(\.domainReminder),
            insights: insightRows.map(\.domainInsight),
            ninaThread: ninaState.thread,
            ninaMemories: ninaState.memories
        )
    }

    private func loadTaskSections(familyID: UUID) async throws -> [TaskSectionRow] {
        try await perform(operation: "task_sections.select") {
            try await client
                .from("task_sections")
                .select("id,title,symbol_name,tone,sort_order")
                .eq("family_id", value: familyID)
                .order("sort_order")
                .execute()
                .value
        }
    }

    private func loadTaskCategories(familyID: UUID) async throws -> [TaskCategoryRow] {
        try await perform(operation: "task_categories.select") {
            try await client
                .from("task_categories")
                .select("id,title,symbol_name,tone")
                .eq("family_id", value: familyID)
                .order("created_at")
                .execute()
                .value
        }
    }

    private func loadTasks(familyID: UUID) async throws -> [TaskRow] {
        try await perform(operation: "tasks.select") {
            try await client
                .from("tasks")
                .select(Self.taskColumns)
                .eq("family_id", value: familyID)
                .order("created_at", ascending: false)
                .execute()
                .value
        }
    }

    private func loadShoppingItems(familyID: UUID) async throws -> [ShoppingItemRow] {
        try await perform(operation: "shopping_items.select") {
            try await client
                .from("shopping_items")
                .select("id,title,amount,owner_label,is_checked")
                .eq("family_id", value: familyID)
                .order("created_at", ascending: false)
                .execute()
                .value
        }
    }

    private func loadReminders(familyID: UUID) async throws -> [ReminderRow] {
        try await perform(operation: "reminders.select") {
            try await client
                .from("reminders")
                .select("id,title,detail,date_label,due_at,symbol_name,tone")
                .eq("family_id", value: familyID)
                .order("created_at", ascending: false)
                .execute()
                .value
        }
    }

    private func loadNinaState(familyID: UUID) async throws -> NinaStateRow {
        try await perform(operation: "get_current_nina_state") {
            try await client
                .rpc(
                    "get_current_nina_state",
                    params: GetCurrentNinaStateParams(familyID: familyID)
                )
                .execute()
                .value
        }
    }

    private func loadInsights(familyID: UUID) async throws -> [HouseholdInsightRow] {
        try await perform(operation: "household_insights.select") {
            try await client
                .from("household_insights")
                .select("id,title,message,metric,symbol_name,tone")
                .eq("family_id", value: familyID)
                .order("created_at", ascending: false)
                .execute()
                .value
        }
    }

    private func perform<Value>(
        operation: String,
        request: () async throws -> Value
    ) async throws -> Value {
        try await BackendRequestLogger.perform(
            component: "home",
            operation: operation,
            diagnostics: diagnostics,
            request: request
        )
    }

    private static let taskColumns =
        "id,section_id,title,subtitle,owner_label,due_label,due_at,category_id,category_snapshot,priority,is_done,created_by_label,version"
}

private struct HomeContextRow: Decodable {
    var family: FamilyRow?
    var members: [FamilyMemberRow]
    var permissionRole: String?
    var membershipVerified: Bool

    private enum CodingKeys: String, CodingKey {
        case family
        case members
        case permissionRole = "permission_role"
        case membershipVerified = "membership_verified"
    }

    var remoteState: RemoteHomeState? {
        guard membershipVerified,
              let family,
              let permissionRole = permissionRole.flatMap(FamilyPermissionRole.init(rawValue:)) else {
            return nil
        }

        return RemoteHomeState(
            familyGroup: family.domainFamilyGroup(members: members),
            permissionRole: permissionRole,
            snapshot: nil
        )
    }
}

private struct GetCurrentNinaStateParams: Encodable {
    var familyID: UUID

    private enum CodingKeys: String, CodingKey {
        case familyID = "target_family_id"
    }
}

private struct ResolveNinaProposalParams: Encodable {
    var proposalID: UUID
    var decision: String
    var editedPayload: NinaProposalPayload?
    var memoryVisibility: String?

    private enum CodingKeys: String, CodingKey {
        case proposalID = "target_proposal_id"
        case decision
        case editedPayload = "edited_payload"
        case memoryVisibility = "memory_visibility"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(proposalID, forKey: .proposalID)
        try container.encode(decision, forKey: .decision)
        if let editedPayload {
            try container.encode(editedPayload, forKey: .editedPayload)
        } else {
            try container.encode([String: String](), forKey: .editedPayload)
        }
        try container.encodeIfPresent(memoryVisibility, forKey: .memoryVisibility)
    }
}

private struct UpdateNinaMemoryParams: Encodable {
    var memoryID: UUID
    var title: String
    var body: String
    var visibility: String

    private enum CodingKeys: String, CodingKey {
        case memoryID = "target_memory_id"
        case title = "memory_title"
        case body = "memory_body"
        case visibility = "memory_visibility"
    }

    init(memory: NinaMemory) {
        memoryID = memory.id
        title = memory.title
        body = memory.body
        visibility = memory.visibility.rawValue
    }
}

private struct DeleteNinaMemoryParams: Encodable {
    var memoryID: UUID

    private enum CodingKeys: String, CodingKey {
        case memoryID = "target_memory_id"
    }
}

private struct DeleteNinaChatHistoryParams: Encodable {
    var familyID: UUID

    private enum CodingKeys: String, CodingKey {
        case familyID = "target_family_id"
    }
}

private struct FamilyRow: Codable {
    var id: UUID
    var name: String
    var inviteCode: String
    var createdBy: UUID

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case inviteCode = "invite_code"
        case createdBy = "created_by"
    }

    func domainFamilyGroup(members: [FamilyMemberRow]) -> FamilyGroup {
        FamilyGroup(
            id: id,
            name: name,
            inviteCode: inviteCode,
            members: members
                .sorted { lhs, rhs in
                    if lhs.householdRole == "assistant" { return false }
                    if rhs.householdRole == "assistant" { return true }
                    return lhs.createdAt < rhs.createdAt
                }
                .map(\.domainMember)
        )
    }
}

private struct FamilyMemberRow: Decodable {
    var id: UUID
    var familyID: UUID
    var userID: UUID?
    var name: String
    var relationship: String
    var householdRole: String
    var permissionRole: String
    var identityState: String
    var tone: String
    var taskCount: Int
    var memoryNote: String
    var createdAt: Date

    private enum CodingKeys: String, CodingKey {
        case id
        case familyID = "family_id"
        case userID = "user_id"
        case name
        case relationship
        case householdRole = "household_role"
        case permissionRole = "permission_role"
        case identityState = "identity_state"
        case tone
        case taskCount = "task_count"
        case memoryNote = "memory_note"
        case createdAt = "created_at"
    }

    var domainMember: HouseholdMember {
        HouseholdMember(
            id: id,
            userID: userID?.uuidString,
            name: name,
            relationship: relationship,
            role: HouseholdRole(rawValue: householdRole) ?? .adult,
            permissionRole: FamilyPermissionRole(rawValue: permissionRole) ?? .member,
            identityState: MemberIdentityState(rawValue: identityState) ?? (userID == nil ? .unclaimed : .claimed),
            tone: MemberTone(rawValue: tone) ?? .mint,
            taskCount: taskCount,
            memoryNote: memoryNote
        )
    }
}

private struct UpdateFamilySettingsParams: Encodable {
    var targetFamilyID: UUID
    var familyName: String

    private enum CodingKeys: String, CodingKey {
        case targetFamilyID = "target_family_id"
        case familyName = "family_name"
    }
}

private struct FamilyIDParams: Encodable {
    var targetFamilyID: UUID

    private enum CodingKeys: String, CodingKey {
        case targetFamilyID = "target_family_id"
    }
}

private struct AddFamilyMemberParams: Encodable {
    var targetFamilyID: UUID
    var memberName: String
    var relationship: String
    var householdRole: String
    var tone: String
    var memoryNote: String

    private enum CodingKeys: String, CodingKey {
        case targetFamilyID = "target_family_id"
        case memberName = "member_name"
        case relationship
        case householdRole = "household_role"
        case tone
        case memoryNote = "memory_note"
    }
}

private struct UpdateFamilyMemberParams: Encodable {
    var targetMemberID: UUID
    var memberName: String
    var relationship: String
    var householdRole: String
    var tone: String
    var memoryNote: String

    private enum CodingKeys: String, CodingKey {
        case targetMemberID = "target_member_id"
        case memberName = "member_name"
        case relationship
        case householdRole = "household_role"
        case tone
        case memoryNote = "memory_note"
    }
}

private struct TaskSectionUpsertRow: Encodable {
    var familyID: UUID
    var id: String
    var title: String
    var symbolName: String
    var tone: String
    var sortOrder: Int

    private enum CodingKeys: String, CodingKey {
        case familyID = "family_id"
        case id
        case title
        case symbolName = "symbol_name"
        case tone
        case sortOrder = "sort_order"
    }

    init(section: TaskSection, familyID: UUID, sortOrder: Int) {
        self.familyID = familyID
        id = section.id
        title = section.title
        symbolName = section.symbolName
        tone = section.tone.rawValue
        self.sortOrder = sortOrder
    }
}

private struct TaskCategoryUpsertRow: Encodable {
    var familyID: UUID
    var id: String
    var title: String
    var symbolName: String
    var tone: String
    var isCustom: Bool

    private enum CodingKeys: String, CodingKey {
        case familyID = "family_id"
        case id
        case title
        case symbolName = "symbol_name"
        case tone
        case isCustom = "is_custom"
    }

    init(category: TaskCategory, familyID: UUID) {
        self.familyID = familyID
        id = category.id
        title = category.title
        symbolName = category.symbolName
        tone = category.tone.rawValue
        isCustom = true
    }
}

private struct TaskInsertRow: Encodable {
    var id: UUID
    var familyID: UUID
    var sectionID: String
    var title: String
    var subtitle: String
    var ownerLabel: String
    var dueLabel: String
    var dueAt: Date?
    var categoryID: String
    var categorySnapshot: TaskCategory
    var priority: String
    var isDone: Bool
    var createdBy: UUID?
    var createdByLabel: String

    private enum CodingKeys: String, CodingKey {
        case id
        case familyID = "family_id"
        case sectionID = "section_id"
        case title
        case subtitle
        case ownerLabel = "owner_label"
        case dueLabel = "due_label"
        case dueAt = "due_at"
        case categoryID = "category_id"
        case categorySnapshot = "category_snapshot"
        case priority
        case isDone = "is_done"
        case createdBy = "created_by"
        case createdByLabel = "created_by_label"
    }

    init(task: TaskItem, familyID: UUID, currentUserID: UUID?) {
        id = task.id
        self.familyID = familyID
        sectionID = task.sectionID
        title = task.title
        subtitle = task.subtitle
        ownerLabel = task.owner
        dueLabel = task.dueLabel
        dueAt = task.dueAt
        categoryID = task.category.id
        categorySnapshot = task.category
        priority = task.priority.rawValue
        isDone = task.isDone
        createdBy = currentUserID
        createdByLabel = task.createdBy
    }
}

private struct TaskUpdateRow: Encodable {
    var sectionID: String
    var title: String
    var subtitle: String
    var ownerLabel: String
    var dueLabel: String
    var dueAt: Date?
    var categoryID: String
    var categorySnapshot: TaskCategory
    var priority: String
    var isDone: Bool
    var createdByLabel: String

    private enum CodingKeys: String, CodingKey {
        case sectionID = "section_id"
        case title
        case subtitle
        case ownerLabel = "owner_label"
        case dueLabel = "due_label"
        case dueAt = "due_at"
        case categoryID = "category_id"
        case categorySnapshot = "category_snapshot"
        case priority
        case isDone = "is_done"
        case createdByLabel = "created_by_label"
    }

    init(task: TaskItem) {
        sectionID = task.sectionID
        title = task.title
        subtitle = task.subtitle
        ownerLabel = task.owner
        dueLabel = task.dueLabel
        dueAt = task.dueAt
        categoryID = task.category.id
        categorySnapshot = task.category
        priority = task.priority.rawValue
        isDone = task.isDone
        createdByLabel = task.createdBy
    }
}

private struct ShoppingItemInsertRow: Encodable {
    var id: UUID
    var familyID: UUID
    var title: String
    var amount: String
    var ownerLabel: String
    var isChecked: Bool
    var createdBy: UUID?

    private enum CodingKeys: String, CodingKey {
        case id
        case familyID = "family_id"
        case title
        case amount
        case ownerLabel = "owner_label"
        case isChecked = "is_checked"
        case createdBy = "created_by"
    }

    init(item: ShoppingItem, familyID: UUID, currentUserID: UUID?) {
        id = item.id
        self.familyID = familyID
        title = item.title
        amount = item.amount
        ownerLabel = item.owner
        isChecked = item.isChecked
        createdBy = currentUserID
    }
}

private struct ShoppingItemUpdateRow: Encodable {
    var title: String
    var amount: String
    var ownerLabel: String
    var isChecked: Bool

    private enum CodingKeys: String, CodingKey {
        case title
        case amount
        case ownerLabel = "owner_label"
        case isChecked = "is_checked"
    }

    init(item: ShoppingItem) {
        title = item.title
        amount = item.amount
        ownerLabel = item.owner
        isChecked = item.isChecked
    }
}

private struct ReminderInsertRow: Encodable {
    var id: UUID
    var familyID: UUID
    var title: String
    var detail: String
    var dateLabel: String
    var dueAt: Date?
    var symbolName: String
    var tone: String
    var createdBy: UUID?

    private enum CodingKeys: String, CodingKey {
        case id
        case familyID = "family_id"
        case title
        case detail
        case dateLabel = "date_label"
        case dueAt = "due_at"
        case symbolName = "symbol_name"
        case tone
        case createdBy = "created_by"
    }

    init(reminder: ReminderItem, familyID: UUID, currentUserID: UUID?) {
        id = reminder.id
        self.familyID = familyID
        title = reminder.title
        detail = reminder.detail
        dateLabel = reminder.dateLabel
        dueAt = reminder.dueAt
        symbolName = reminder.symbolName
        tone = reminder.tone.rawValue
        createdBy = currentUserID
    }
}

private struct ChatMessageInsertRow: Encodable {
    var id: UUID
    var familyID: UUID
    var sender: String
    var text: String
    var suggestion: NinaSuggestion?
    var attachments: [ChatAttachment]
    var createdBy: UUID?
    var createdAt: Date

    private enum CodingKeys: String, CodingKey {
        case id
        case familyID = "family_id"
        case sender
        case text
        case suggestion
        case attachments
        case createdBy = "created_by"
        case createdAt = "created_at"
    }

    init(message: ChatMessage, familyID: UUID, currentUserID: UUID?) {
        id = message.id
        self.familyID = familyID
        sender = message.sender.rawValue
        text = message.text
        suggestion = message.suggestion
        attachments = message.attachments
        createdBy = message.sender == .user ? currentUserID : nil
        createdAt = message.timestamp
    }
}

private struct TaskSectionRow: Decodable {
    var id: String
    var title: String
    var symbolName: String
    var tone: String

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case symbolName = "symbol_name"
        case tone
    }

    var domainSection: TaskSection {
        TaskSection(
            id: id,
            title: title,
            symbolName: symbolName,
            tone: MemberTone(rawValue: tone) ?? .mint
        )
    }
}

private struct TaskCategoryRow: Decodable {
    var id: String
    var title: String
    var symbolName: String
    var tone: String

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case symbolName = "symbol_name"
        case tone
    }

    var domainCategory: TaskCategory {
        TaskCategory(
            id: id,
            title: title,
            symbolName: symbolName,
            tone: MemberTone(rawValue: tone) ?? .lavender
        )
    }
}

private struct TaskRow: Decodable {
    var id: UUID
    var sectionID: String
    var title: String
    var subtitle: String
    var ownerLabel: String
    var dueLabel: String
    var dueAt: Date?
    var categoryID: String
    var categorySnapshot: TaskCategory
    var priority: String
    var isDone: Bool
    var createdByLabel: String
    var version: Int

    private enum CodingKeys: String, CodingKey {
        case id
        case sectionID = "section_id"
        case title
        case subtitle
        case ownerLabel = "owner_label"
        case dueLabel = "due_label"
        case dueAt = "due_at"
        case categoryID = "category_id"
        case categorySnapshot = "category_snapshot"
        case priority
        case isDone = "is_done"
        case createdByLabel = "created_by_label"
        case version
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        sectionID = try container.decodeIfPresent(String.self, forKey: .sectionID)
            ?? TaskSectionDefaults.houseTasksID
        title = try container.decode(String.self, forKey: .title)
        subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle) ?? ""
        ownerLabel = try container.decodeIfPresent(String.self, forKey: .ownerLabel) ?? "Casa"
        dueLabel = try container.decodeIfPresent(String.self, forKey: .dueLabel) ?? "Sem data"
        dueAt = try container.decodeIfPresent(Date.self, forKey: .dueAt)
        let decodedCategoryID = try container.decodeIfPresent(String.self, forKey: .categoryID)
            ?? TaskCategory.home.id
        categoryID = decodedCategoryID
        categorySnapshot = (try? container.decode(TaskCategory.self, forKey: .categorySnapshot))
            ?? TaskCategory.allCases.first(where: { $0.id == decodedCategoryID })
            ?? .custom(id: decodedCategoryID, title: decodedCategoryID.capitalized, tone: .lavender)
        priority = try container.decodeIfPresent(String.self, forKey: .priority) ?? TaskPriority.normal.rawValue
        isDone = try container.decodeIfPresent(Bool.self, forKey: .isDone) ?? false
        createdByLabel = try container.decodeIfPresent(String.self, forKey: .createdByLabel) ?? "Manual"
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
    }

    var domainTask: TaskItem {
        TaskItem(
            id: id,
            title: title,
            subtitle: subtitle,
            owner: ownerLabel,
            dueLabel: dueLabel,
            dueAt: dueAt,
            category: categorySnapshot,
            priority: TaskPriority(rawValue: priority) ?? .normal,
            isDone: isDone,
            createdBy: createdByLabel,
            sectionID: sectionID,
            version: version
        )
    }
}

private struct ShoppingItemRow: Decodable {
    var id: UUID
    var title: String
    var amount: String
    var ownerLabel: String
    var isChecked: Bool

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case amount
        case ownerLabel = "owner_label"
        case isChecked = "is_checked"
    }

    var domainItem: ShoppingItem {
        ShoppingItem(
            id: id,
            title: title,
            amount: amount,
            owner: ownerLabel,
            isChecked: isChecked
        )
    }
}

private struct ReminderRow: Decodable {
    var id: UUID
    var title: String
    var detail: String
    var dateLabel: String
    var dueAt: Date?
    var symbolName: String
    var tone: String

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case detail
        case dateLabel = "date_label"
        case dueAt = "due_at"
        case symbolName = "symbol_name"
        case tone
    }

    var domainReminder: ReminderItem {
        ReminderItem(
            id: id,
            title: title,
            detail: detail,
            dateLabel: dateLabel,
            dueAt: dueAt,
            symbolName: symbolName,
            tone: MemberTone(rawValue: tone) ?? .mint
        )
    }
}

private struct NinaStateRow: Decodable {
    var thread: NinaThread?
    var messages: [NinaStateMessageRow]
    var memories: [NinaMemory]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        thread = try container.decodeIfPresent(NinaThread.self, forKey: .thread)
        messages = try container.decodeIfPresent([NinaStateMessageRow].self, forKey: .messages) ?? []
        memories = try container.decodeIfPresent([NinaMemory].self, forKey: .memories) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case thread
        case messages
        case memories
    }
}

private struct NinaStateMessageRow: Decodable {
    var id: UUID
    var sender: String
    var text: String
    var suggestion: NinaSuggestion?
    var attachments: [ChatAttachment]
    var createdAt: Date
    var proposals: [NinaProposal]

    private enum CodingKeys: String, CodingKey {
        case id
        case sender
        case text
        case suggestion
        case attachments
        case createdAt = "created_at"
        case proposals
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        sender = try container.decode(String.self, forKey: .sender)
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        suggestion = try container.decodeIfPresent(NinaSuggestion.self, forKey: .suggestion)
        attachments = try container.decodeIfPresent([ChatAttachment].self, forKey: .attachments) ?? []
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        proposals = try container.decodeIfPresent([NinaProposal].self, forKey: .proposals) ?? []
    }

    var domainMessage: ChatMessage {
        ChatMessage(
            id: id,
            sender: MessageSender(rawValue: sender) ?? .user,
            text: text,
            timestamp: createdAt,
            suggestion: suggestion,
            proposals: NinaAIConfiguration.isV2Enabled ? proposals : [],
            attachments: attachments
        )
    }
}

private struct HouseholdInsightRow: Decodable {
    var id: UUID
    var title: String
    var message: String
    var metric: String
    var symbolName: String
    var tone: String

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case message
        case metric
        case symbolName = "symbol_name"
        case tone
    }

    var domainInsight: HouseholdInsight {
        HouseholdInsight(
            id: id,
            title: title,
            message: message,
            metric: metric,
            symbolName: symbolName,
            tone: MemberTone(rawValue: tone) ?? .mint
        )
    }
}

private struct JoinFamilyByInviteParams: Encodable {
    var inviteCode: String

    private enum CodingKeys: String, CodingKey {
        case inviteCode = "invite_code"
    }
}

private struct InvitePreviewRow: Decodable {
    var valid: Bool
    var familyName: String?

    private enum CodingKeys: String, CodingKey {
        case valid
        case familyName = "family_name"
    }
}

private struct CreateFamilyParams: Encodable {
    var familyName: String

    private enum CodingKeys: String, CodingKey {
        case familyName = "family_name"
    }
}
#endif
