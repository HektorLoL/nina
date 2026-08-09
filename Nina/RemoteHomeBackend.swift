import Foundation

struct RemoteHomeState {
    var familyGroup: FamilyGroup
    var permissionRole: FamilyPermissionRole
    var snapshot: AppDataSnapshot?
    var inviteStatus: FamilyInviteStatus? = nil
    var joinRequests: [FamilyJoinRequest] = []
    var householdPremium: HouseholdPremium = .inactive
    var aiConsent: NinaAIConsent = .withheld
}

struct FamilyInvitePreview: Hashable {
    var code: String
    var familyName: String?
    var isValid: Bool
    var expiresAt: Date? = nil
    var usesRemaining: Int? = nil
}

enum FamilyJoinOutcome {
    case joined(RemoteHomeState)
    case pending(FamilyJoinRequest)
}

enum HomeRealtimeEvent: Sendable {
    case familyMembers
    case taskSections
    case tasks
    case shoppingItems
    case chatMessages
}

enum TaskUpdateResult {
    case updated(TaskItem)
    case conflict(current: TaskItem)
}

enum PostgresDateOnlyCodec {
    static func string(from date: Date?, timeZone: TimeZone = .current) -> String? {
        guard let date else { return nil }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month, .day], from: date)

        guard let year = components.year,
              let month = components.month,
              let day = components.day else {
            return nil
        }

        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    static func date(from value: String?, timeZone: TimeZone = .current) -> Date? {
        guard let value else { return nil }
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else {
            return nil
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = timeZone
        components.year = year
        components.month = month
        components.day = day

        guard let date = calendar.date(from: components) else { return nil }
        let resolved = calendar.dateComponents([.year, .month, .day], from: date)
        guard resolved.year == year,
              resolved.month == month,
              resolved.day == day else {
            return nil
        }
        return date
    }
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
    func requestHomeAccess(with inviteCode: String, member: AuthUser?) async throws -> FamilyJoinOutcome
    func loadPendingJoinRequest() async throws -> FamilyJoinRequest?
    func previewInvite(code: String) async throws -> FamilyInvitePreview
    func updateFamilySettings(familyID: UUID, name: String) async throws -> RemoteHomeState
    func updateFamilySettings(
        familyID: UUID,
        name: String,
        weeklyDigestEnabled: Bool
    ) async throws -> RemoteHomeState
    func rotateFamilyInvite(familyID: UUID) async throws -> RemoteHomeState
    func addUnclaimedMember(_ member: HouseholdMember, familyID: UUID) async throws -> RemoteHomeState
    func updateFamilyMember(_ member: HouseholdMember) async throws -> RemoteHomeState
    func removeFamilyMember(_ memberID: UUID) async throws -> RemoteHomeState
    func approveJoinRequest(_ requestID: UUID, permissionRole: FamilyPermissionRole) async throws -> RemoteHomeState
    func declineJoinRequest(_ requestID: UUID) async throws -> RemoteHomeState
    func cancelJoinRequest(_ requestID: UUID) async throws
    func createTaskSection(_ section: TaskSection, sortOrder: Int, familyID: UUID) async throws
    func deleteTaskSection(_ sectionID: String, familyID: UUID) async throws
    func createTaskCategory(_ category: TaskCategory, familyID: UUID) async throws
    func createTask(_ task: TaskItem, familyID: UUID, currentUser: AuthUser) async throws
    func updateTask(_ task: TaskItem, familyID: UUID) async throws
    func updateTask(
        _ task: TaskItem,
        expectedVersion: Int,
        familyID: UUID
    ) async throws -> TaskUpdateResult
    func deleteTask(_ taskID: UUID, familyID: UUID) async throws
    func createShoppingItem(_ item: ShoppingItem, familyID: UUID, currentUser: AuthUser) async throws
    func updateShoppingItem(_ item: ShoppingItem, familyID: UUID) async throws
    func deleteShoppingItem(_ itemID: UUID, familyID: UUID) async throws
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
    func recordNinaAIConsent(granted: Bool, policyVersion: String) async throws -> RemoteHomeState
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
    func requestHomeAccess(with inviteCode: String, member: AuthUser?) async throws -> FamilyJoinOutcome {
        .joined(try await joinHome(with: inviteCode, member: member))
    }

    func loadPendingJoinRequest() async throws -> FamilyJoinRequest? {
        nil
    }

    func previewInvite(code: String) async throws -> FamilyInvitePreview {
        throw RemoteHomeBackendError.operationUnavailable
    }

    func updateFamilySettings(
        familyID: UUID,
        name: String,
        weeklyDigestEnabled: Bool
    ) async throws -> RemoteHomeState {
        throw RemoteHomeBackendError.operationUnavailable
    }

    func rotateFamilyInvite(familyID: UUID) async throws -> RemoteHomeState {
        throw RemoteHomeBackendError.operationUnavailable
    }

    func removeFamilyMember(_ memberID: UUID) async throws -> RemoteHomeState {
        throw RemoteHomeBackendError.operationUnavailable
    }

    func approveJoinRequest(
        _ requestID: UUID,
        permissionRole: FamilyPermissionRole
    ) async throws -> RemoteHomeState {
        throw RemoteHomeBackendError.operationUnavailable
    }

    func declineJoinRequest(_ requestID: UUID) async throws -> RemoteHomeState {
        throw RemoteHomeBackendError.operationUnavailable
    }

    func cancelJoinRequest(_ requestID: UUID) async throws {
        throw RemoteHomeBackendError.operationUnavailable
    }

    func deleteTaskSection(_ sectionID: String, familyID: UUID) async throws {
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

    func deleteTask(_ taskID: UUID, familyID: UUID) async throws {
        throw RemoteHomeBackendError.operationUnavailable
    }

    func deleteShoppingItem(_ itemID: UUID, familyID: UUID) async throws {
        throw RemoteHomeBackendError.operationUnavailable
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

    func recordNinaAIConsent(granted: Bool, policyVersion: String) async throws -> RemoteHomeState {
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
        switch try await requestHomeAccess(with: inviteCode, member: member) {
        case .joined(let state):
            return state
        case .pending:
            throw RemoteHomeBackendError.operationUnavailable
        }
    }

    func requestHomeAccess(
        with inviteCode: String,
        member: AuthUser?
    ) async throws -> FamilyJoinOutcome {
        guard let normalizedInvite = AppStore.normalizedInviteCode(from: inviteCode) else {
            throw RemoteHomeBackendError.invalidInviteCode
        }

        let outcome: FamilyJoinOutcomeRow = try await perform(operation: "request_family_join") {
            try await client
                .rpc(
                    "request_family_join",
                    params: JoinFamilyByInviteParams(inviteCode: normalizedInvite)
                )
                .execute()
                .value
        }

        switch outcome.status {
        case "member":
            guard let context = outcome.homeContext,
                  let state = try await loadRemoteState(from: context) else {
                throw RemoteHomeBackendError.familyNotFound
            }
            return .joined(state)
        case "pending":
            guard let request = outcome.request?.domainRequest else {
                throw RemoteHomeBackendError.operationUnavailable
            }
            return .pending(request)
        default:
            throw RemoteHomeBackendError.operationUnavailable
        }
    }

    func loadPendingJoinRequest() async throws -> FamilyJoinRequest? {
        let request: FamilyJoinRequestRow? = try await perform(
            operation: "get_pending_family_join_request"
        ) {
            try await client
                .rpc("get_pending_family_join_request")
                .execute()
                .value
        }

        return request?.domainRequest
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
            isValid: preview.valid,
            expiresAt: preview.expiresAt,
            usesRemaining: preview.usesRemaining
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

    func updateFamilySettings(
        familyID: UUID,
        name: String,
        weeklyDigestEnabled: Bool
    ) async throws -> RemoteHomeState {
        let context: HomeContextRow = try await perform(operation: "update_family_settings") {
            try await client
                .rpc(
                    "update_family_settings",
                    params: UpdateFamilyDigestSettingsParams(
                        targetFamilyID: familyID,
                        familyName: name,
                        weeklyDigestEnabled: weeklyDigestEnabled
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
                        memoryNote: member.memoryNote,
                        birthDate: PostgresDateOnlyCodec.string(from: member.birthDate),
                        petSpecies: member.petSpecies,
                        petBreed: member.petBreed
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
                        permissionRole: member.permissionRole.rawValue,
                        tone: member.tone.rawValue,
                        memoryNote: member.memoryNote,
                        birthDate: PostgresDateOnlyCodec.string(from: member.birthDate),
                        petSpecies: member.petSpecies,
                        petBreed: member.petBreed
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

    func removeFamilyMember(_ memberID: UUID) async throws -> RemoteHomeState {
        let context: HomeContextRow = try await perform(operation: "remove_family_member") {
            try await client
                .rpc(
                    "remove_family_member",
                    params: MemberIDParams(targetMemberID: memberID)
                )
                .execute()
                .value
        }

        guard let state = try await loadRemoteState(from: context) else {
            throw RemoteHomeBackendError.familyNotFound
        }
        return state
    }

    func approveJoinRequest(
        _ requestID: UUID,
        permissionRole: FamilyPermissionRole
    ) async throws -> RemoteHomeState {
        let context: HomeContextRow = try await perform(operation: "approve_family_join_request") {
            try await client
                .rpc(
                    "approve_family_join_request",
                    params: ApproveJoinRequestParams(
                        targetRequestID: requestID,
                        grantedPermissionRole: permissionRole.rawValue
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

    func declineJoinRequest(_ requestID: UUID) async throws -> RemoteHomeState {
        let context: HomeContextRow = try await perform(operation: "decline_family_join_request") {
            try await client
                .rpc(
                    "decline_family_join_request",
                    params: JoinRequestIDParams(targetRequestID: requestID)
                )
                .execute()
                .value
        }

        guard let state = try await loadRemoteState(from: context) else {
            throw RemoteHomeBackendError.familyNotFound
        }
        return state
    }

    func cancelJoinRequest(_ requestID: UUID) async throws {
        try await perform(operation: "cancel_family_join_request") {
            _ = try await client
                .rpc(
                    "cancel_family_join_request",
                    params: JoinRequestIDParams(targetRequestID: requestID)
                )
                .execute()
            return ()
        }
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

    func deleteTaskSection(_ sectionID: String, familyID: UUID) async throws {
        try await perform(operation: "delete_task_section") {
            _ = try await client
                .rpc(
                    "delete_task_section",
                    params: DeleteTaskSectionParams(
                        familyID: familyID,
                        sectionID: sectionID
                    )
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

    func deleteTask(_ taskID: UUID, familyID: UUID) async throws {
        try await perform(operation: "tasks.delete") {
            _ = try await client
                .from("tasks")
                .delete()
                .eq("id", value: taskID)
                .eq("family_id", value: familyID)
                .execute()
            return ()
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

    func deleteShoppingItem(_ itemID: UUID, familyID: UUID) async throws {
        try await perform(operation: "shopping_items.delete") {
            _ = try await client
                .from("shopping_items")
                .delete()
                .eq("id", value: itemID)
                .eq("family_id", value: familyID)
                .execute()
            return ()
        }
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

    func recordNinaAIConsent(granted: Bool, policyVersion: String) async throws -> RemoteHomeState {
        let context: HomeContextRow = try await perform(operation: "record_nina_ai_consent") {
            try await client
                .rpc(
                    "record_nina_ai_consent",
                    params: RecordNinaAIConsentParams(
                        policyVersion: policyVersion,
                        granted: granted
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

    func realtimeEvents(familyID: UUID) async -> AsyncStream<HomeRealtimeEvent> {
        let channel = client.channel("home-\(familyID.uuidString)")
        let filter = RealtimePostgresFilter.eq("family_id", value: familyID)
        let taskChanges = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "tasks",
            filter: filter
        )
        let familyMemberChanges = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "family_members",
            filter: filter
        )
        let taskSectionChanges = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "task_sections",
            filter: filter
        )
        let shoppingChanges = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "shopping_items",
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
                        for await _ in familyMemberChanges {
                            continuation.yield(.familyMembers)
                        }
                    }
                    group.addTask {
                        for await _ in taskSectionChanges {
                            continuation.yield(.taskSections)
                        }
                    }
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
        async let ninaState = loadNinaState(familyID: familyID)
        async let insightRows = loadInsights(familyID: familyID)

        return try await AppDataSnapshot(
            messages: ninaState.messages.map(\.domainMessage),
            taskSections: sectionRows.map(\.domainSection),
            customTaskCategories: categoryRows.map(\.domainCategory),
            tasks: taskRows.map(\.domainTask),
            shoppingItems: shoppingRows.map(\.domainItem),
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
                .select("id,title,amount,owner_label,owner_member_id,is_checked")
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
        "id,task_kind,section_id,title,subtitle,owner_label,owner_member_id,due_label,due_at,category_id,category_snapshot,priority,recurrence_rule,snoozed_until,is_done,created_by_label,version"
}

private struct HomeContextRow: Decodable {
    var family: FamilyRow?
    var members: [FamilyMemberRow]
    var permissionRole: String?
    var membershipVerified: Bool
    var activeInvite: FamilyInviteStatusRow?
    var pendingJoinRequests: [FamilyJoinRequestRow]
    var premium: HouseholdPremium
    var aiConsent: NinaAIConsent

    private enum CodingKeys: String, CodingKey {
        case family
        case members
        case permissionRole = "permission_role"
        case membershipVerified = "membership_verified"
        case activeInvite = "active_invite"
        case pendingJoinRequests = "pending_join_requests"
        case premium
        case aiConsent = "ai_consent"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        family = try container.decodeIfPresent(FamilyRow.self, forKey: .family)
        members = try container.decodeIfPresent([FamilyMemberRow].self, forKey: .members) ?? []
        permissionRole = try container.decodeIfPresent(String.self, forKey: .permissionRole)
        membershipVerified = try container.decodeIfPresent(Bool.self, forKey: .membershipVerified) ?? false
        activeInvite = try container.decodeIfPresent(FamilyInviteStatusRow.self, forKey: .activeInvite)
        pendingJoinRequests = try container.decodeIfPresent(
            [FamilyJoinRequestRow].self,
            forKey: .pendingJoinRequests
        ) ?? []
        premium = try container.decodeIfPresent(HouseholdPremium.self, forKey: .premium) ?? .inactive
        aiConsent = try container.decodeIfPresent(NinaAIConsent.self, forKey: .aiConsent) ?? .withheld
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
            snapshot: nil,
            inviteStatus: activeInvite?.domainStatus,
            joinRequests: pendingJoinRequests.map(\.domainRequest),
            householdPremium: premium,
            aiConsent: aiConsent
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
    var weeklyDigestEnabled: Bool

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case inviteCode = "invite_code"
        case createdBy = "created_by"
        case weeklyDigestEnabled = "weekly_digest_enabled"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        inviteCode = try container.decodeIfPresent(String.self, forKey: .inviteCode) ?? ""
        createdBy = try container.decode(UUID.self, forKey: .createdBy)
        weeklyDigestEnabled = try container.decodeIfPresent(Bool.self, forKey: .weeklyDigestEnabled) ?? true
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
                .map(\.domainMember),
            weeklyDigestEnabled: weeklyDigestEnabled
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
    var birthDate: String?
    var petSpecies: String
    var petBreed: String
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
        case birthDate = "birth_date"
        case petSpecies = "pet_species"
        case petBreed = "pet_breed"
        case createdAt = "created_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        familyID = try container.decode(UUID.self, forKey: .familyID)
        userID = try container.decodeIfPresent(UUID.self, forKey: .userID)
        name = try container.decode(String.self, forKey: .name)
        relationship = try container.decodeIfPresent(String.self, forKey: .relationship) ?? ""
        householdRole = try container.decodeIfPresent(String.self, forKey: .householdRole) ?? "adult"
        permissionRole = try container.decodeIfPresent(String.self, forKey: .permissionRole) ?? "member"
        identityState = try container.decodeIfPresent(String.self, forKey: .identityState)
            ?? (userID == nil ? "unclaimed" : "claimed")
        tone = try container.decodeIfPresent(String.self, forKey: .tone) ?? "mint"
        taskCount = try container.decodeIfPresent(Int.self, forKey: .taskCount) ?? 0
        memoryNote = try container.decodeIfPresent(String.self, forKey: .memoryNote) ?? ""
        birthDate = try container.decodeIfPresent(String.self, forKey: .birthDate)
        petSpecies = try container.decodeIfPresent(String.self, forKey: .petSpecies) ?? ""
        petBreed = try container.decodeIfPresent(String.self, forKey: .petBreed) ?? ""
        createdAt = try container.decode(Date.self, forKey: .createdAt)
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
            memoryNote: memoryNote,
            birthDate: PostgresDateOnlyCodec.date(from: birthDate),
            petSpecies: petSpecies,
            petBreed: petBreed
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

private struct UpdateFamilyDigestSettingsParams: Encodable {
    var targetFamilyID: UUID
    var familyName: String
    var weeklyDigestEnabled: Bool

    private enum CodingKeys: String, CodingKey {
        case targetFamilyID = "target_family_id"
        case familyName = "family_name"
        case weeklyDigestEnabled = "weekly_digest_enabled"
    }
}

private struct FamilyIDParams: Encodable {
    var targetFamilyID: UUID

    private enum CodingKeys: String, CodingKey {
        case targetFamilyID = "target_family_id"
    }
}

private struct RecordNinaAIConsentParams: Encodable {
    var policyVersion: String
    var granted: Bool

    private enum CodingKeys: String, CodingKey {
        case policyVersion = "policy_version"
        case granted
    }
}

private struct DeleteTaskSectionParams: Encodable {
    var familyID: UUID
    var sectionID: String

    private enum CodingKeys: String, CodingKey {
        case familyID = "target_family_id"
        case sectionID = "target_section_id"
    }
}

private struct AddFamilyMemberParams: Encodable {
    var targetFamilyID: UUID
    var memberName: String
    var relationship: String
    var householdRole: String
    var tone: String
    var memoryNote: String
    var birthDate: String?
    var petSpecies: String
    var petBreed: String

    private enum CodingKeys: String, CodingKey {
        case targetFamilyID = "target_family_id"
        case memberName = "member_name"
        case relationship
        case householdRole = "household_role"
        case tone
        case memoryNote = "memory_note"
        case birthDate = "birth_date"
        case petSpecies = "pet_species"
        case petBreed = "pet_breed"
    }
}

private struct UpdateFamilyMemberParams: Encodable {
    var targetMemberID: UUID
    var memberName: String
    var relationship: String
    var householdRole: String
    var permissionRole: String
    var tone: String
    var memoryNote: String
    var birthDate: String?
    var petSpecies: String
    var petBreed: String

    private enum CodingKeys: String, CodingKey {
        case targetMemberID = "target_member_id"
        case memberName = "member_name"
        case relationship
        case householdRole = "household_role"
        case permissionRole = "permission_role"
        case tone
        case memoryNote = "memory_note"
        case birthDate = "birth_date"
        case petSpecies = "pet_species"
        case petBreed = "pet_breed"
    }
}

private struct MemberIDParams: Encodable {
    var targetMemberID: UUID

    private enum CodingKeys: String, CodingKey {
        case targetMemberID = "target_member_id"
    }
}

private struct JoinRequestIDParams: Encodable {
    var targetRequestID: UUID

    private enum CodingKeys: String, CodingKey {
        case targetRequestID = "target_request_id"
    }
}

private struct ApproveJoinRequestParams: Encodable {
    var targetRequestID: UUID
    var grantedPermissionRole: String

    private enum CodingKeys: String, CodingKey {
        case targetRequestID = "target_request_id"
        case grantedPermissionRole = "granted_permission_role"
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
    var taskKind: String
    var sectionID: String
    var title: String
    var subtitle: String
    var ownerLabel: String
    var ownerMemberID: UUID?
    var dueLabel: String
    var dueAt: Date?
    var categoryID: String
    var categorySnapshot: TaskCategory
    var priority: String
    var recurrenceRule: String
    var snoozedUntil: Date?
    var isDone: Bool
    var createdBy: UUID?
    var createdByLabel: String

    private enum CodingKeys: String, CodingKey {
        case id
        case familyID = "family_id"
        case taskKind = "task_kind"
        case sectionID = "section_id"
        case title
        case subtitle
        case ownerLabel = "owner_label"
        case ownerMemberID = "owner_member_id"
        case dueLabel = "due_label"
        case dueAt = "due_at"
        case categoryID = "category_id"
        case categorySnapshot = "category_snapshot"
        case priority
        case recurrenceRule = "recurrence_rule"
        case snoozedUntil = "snoozed_until"
        case isDone = "is_done"
        case createdBy = "created_by"
        case createdByLabel = "created_by_label"
    }

    init(task: TaskItem, familyID: UUID, currentUserID: UUID?) {
        id = task.id
        self.familyID = familyID
        taskKind = task.kind.rawValue
        sectionID = task.sectionID
        title = task.title
        subtitle = task.subtitle
        ownerLabel = task.owner
        ownerMemberID = task.ownerMemberID
        dueLabel = task.dueLabel
        dueAt = task.dueAt
        categoryID = task.category.id
        categorySnapshot = task.category
        priority = task.priority.rawValue
        recurrenceRule = task.recurrence.rawValue
        snoozedUntil = task.snoozedUntil
        isDone = task.isDone
        createdBy = currentUserID
        createdByLabel = task.createdBy
    }
}

private struct TaskUpdateRow: Encodable {
    var taskKind: String
    var sectionID: String
    var title: String
    var subtitle: String
    var ownerLabel: String
    var ownerMemberID: UUID?
    var dueLabel: String
    var dueAt: Date?
    var categoryID: String
    var categorySnapshot: TaskCategory
    var priority: String
    var recurrenceRule: String
    var snoozedUntil: Date?
    var isDone: Bool
    var createdByLabel: String

    private enum CodingKeys: String, CodingKey {
        case taskKind = "task_kind"
        case sectionID = "section_id"
        case title
        case subtitle
        case ownerLabel = "owner_label"
        case ownerMemberID = "owner_member_id"
        case dueLabel = "due_label"
        case dueAt = "due_at"
        case categoryID = "category_id"
        case categorySnapshot = "category_snapshot"
        case priority
        case recurrenceRule = "recurrence_rule"
        case snoozedUntil = "snoozed_until"
        case isDone = "is_done"
        case createdByLabel = "created_by_label"
    }

    init(task: TaskItem) {
        taskKind = task.kind.rawValue
        sectionID = task.sectionID
        title = task.title
        subtitle = task.subtitle
        ownerLabel = task.owner
        ownerMemberID = task.ownerMemberID
        dueLabel = task.dueLabel
        dueAt = task.dueAt
        categoryID = task.category.id
        categorySnapshot = task.category
        priority = task.priority.rawValue
        recurrenceRule = task.recurrence.rawValue
        snoozedUntil = task.snoozedUntil
        isDone = task.isDone
        createdByLabel = task.createdBy
    }

    // An omitted owner_member_id would leave the previous person assigned, so unassigning travels
    // as an explicit null rather than the synthesized encodeIfPresent.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(taskKind, forKey: .taskKind)
        try container.encode(sectionID, forKey: .sectionID)
        try container.encode(title, forKey: .title)
        try container.encode(subtitle, forKey: .subtitle)
        try container.encode(ownerLabel, forKey: .ownerLabel)
        try container.encode(ownerMemberID, forKey: .ownerMemberID)
        try container.encodeIfPresent(dueAt, forKey: .dueAt)
        try container.encode(dueLabel, forKey: .dueLabel)
        try container.encode(categoryID, forKey: .categoryID)
        try container.encode(categorySnapshot, forKey: .categorySnapshot)
        try container.encode(priority, forKey: .priority)
        try container.encode(recurrenceRule, forKey: .recurrenceRule)
        try container.encodeIfPresent(snoozedUntil, forKey: .snoozedUntil)
        try container.encode(isDone, forKey: .isDone)
        try container.encode(createdByLabel, forKey: .createdByLabel)
    }
}

private struct ShoppingItemInsertRow: Encodable {
    var id: UUID
    var familyID: UUID
    var title: String
    var amount: String
    var ownerLabel: String
    var ownerMemberID: UUID?
    var isChecked: Bool
    var createdBy: UUID?

    private enum CodingKeys: String, CodingKey {
        case id
        case familyID = "family_id"
        case title
        case amount
        case ownerLabel = "owner_label"
        case ownerMemberID = "owner_member_id"
        case isChecked = "is_checked"
        case createdBy = "created_by"
    }

    init(item: ShoppingItem, familyID: UUID, currentUserID: UUID?) {
        id = item.id
        self.familyID = familyID
        title = item.title
        amount = item.amount
        ownerLabel = item.owner
        ownerMemberID = item.ownerMemberID
        isChecked = item.isChecked
        createdBy = currentUserID
    }
}

private struct ShoppingItemUpdateRow: Encodable {
    var title: String
    var amount: String
    var ownerLabel: String
    var ownerMemberID: UUID?
    var isChecked: Bool

    private enum CodingKeys: String, CodingKey {
        case title
        case amount
        case ownerLabel = "owner_label"
        case ownerMemberID = "owner_member_id"
        case isChecked = "is_checked"
    }

    init(item: ShoppingItem) {
        title = item.title
        amount = item.amount
        ownerLabel = item.owner
        ownerMemberID = item.ownerMemberID
        isChecked = item.isChecked
    }

    // An omitted owner_member_id would leave the previous person assigned, so unassigning travels
    // as an explicit null rather than the synthesized encodeIfPresent.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(title, forKey: .title)
        try container.encode(amount, forKey: .amount)
        try container.encode(ownerLabel, forKey: .ownerLabel)
        try container.encode(ownerMemberID, forKey: .ownerMemberID)
        try container.encode(isChecked, forKey: .isChecked)
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
    var taskKind: String
    var sectionID: String
    var title: String
    var subtitle: String
    var ownerLabel: String
    var ownerMemberID: UUID?
    var dueLabel: String
    var dueAt: Date?
    var categoryID: String
    var categorySnapshot: TaskCategory
    var priority: String
    var recurrenceRule: String
    var snoozedUntil: Date?
    var isDone: Bool
    var createdByLabel: String
    var version: Int

    private enum CodingKeys: String, CodingKey {
        case id
        case taskKind = "task_kind"
        case sectionID = "section_id"
        case title
        case subtitle
        case ownerLabel = "owner_label"
        case ownerMemberID = "owner_member_id"
        case dueLabel = "due_label"
        case dueAt = "due_at"
        case categoryID = "category_id"
        case categorySnapshot = "category_snapshot"
        case priority
        case recurrenceRule = "recurrence_rule"
        case snoozedUntil = "snoozed_until"
        case isDone = "is_done"
        case createdByLabel = "created_by_label"
        case version
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        taskKind = try container.decodeIfPresent(String.self, forKey: .taskKind) ?? TaskKind.task.rawValue
        sectionID = try container.decodeIfPresent(String.self, forKey: .sectionID)
            ?? TaskSectionDefaults.houseTasksID
        title = try container.decode(String.self, forKey: .title)
        subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle) ?? ""
        ownerLabel = try container.decodeIfPresent(String.self, forKey: .ownerLabel) ?? "Casa"
        ownerMemberID = try container.decodeIfPresent(UUID.self, forKey: .ownerMemberID) ?? nil
        dueLabel = try container.decodeIfPresent(String.self, forKey: .dueLabel) ?? "Sem data"
        dueAt = try container.decodeIfPresent(Date.self, forKey: .dueAt)
        let decodedCategoryID = try container.decodeIfPresent(String.self, forKey: .categoryID)
            ?? TaskCategory.home.id
        categoryID = decodedCategoryID
        categorySnapshot = (try? container.decode(TaskCategory.self, forKey: .categorySnapshot))
            ?? TaskCategory.allCases.first(where: { $0.id == decodedCategoryID })
            ?? .custom(id: decodedCategoryID, title: decodedCategoryID.capitalized, tone: .lavender)
        priority = try container.decodeIfPresent(String.self, forKey: .priority) ?? TaskPriority.normal.rawValue
        recurrenceRule = try container.decodeIfPresent(String.self, forKey: .recurrenceRule) ?? TaskRecurrence.none.rawValue
        snoozedUntil = try container.decodeIfPresent(Date.self, forKey: .snoozedUntil)
        isDone = try container.decodeIfPresent(Bool.self, forKey: .isDone) ?? false
        createdByLabel = try container.decodeIfPresent(String.self, forKey: .createdByLabel) ?? "Manual"
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
    }

    var domainTask: TaskItem {
        TaskItem(
            id: id,
            kind: TaskKind(rawValue: taskKind) ?? .task,
            title: title,
            subtitle: subtitle,
            owner: ownerLabel,
            ownerMemberID: ownerMemberID,
            dueLabel: dueLabel,
            dueAt: dueAt,
            category: categorySnapshot,
            priority: TaskPriority(rawValue: priority) ?? .normal,
            recurrence: TaskRecurrence(rawValue: recurrenceRule) ?? .none,
            snoozedUntil: snoozedUntil,
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
    var ownerMemberID: UUID?
    var isChecked: Bool

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case amount
        case ownerLabel = "owner_label"
        case ownerMemberID = "owner_member_id"
        case isChecked = "is_checked"
    }

    var domainItem: ShoppingItem {
        ShoppingItem(
            id: id,
            title: title,
            amount: amount,
            owner: ownerLabel,
            ownerMemberID: ownerMemberID,
            isChecked: isChecked
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
    var expiresAt: Date?
    var usesRemaining: Int?

    private enum CodingKeys: String, CodingKey {
        case valid
        case familyName = "family_name"
        case expiresAt = "expires_at"
        case usesRemaining = "uses_remaining"
    }
}

private struct FamilyInviteStatusRow: Decodable {
    var code: String
    var status: String
    var expiresAt: Date
    var maxUses: Int
    var uses: Int
    var usesRemaining: Int

    private enum CodingKeys: String, CodingKey {
        case code
        case status
        case expiresAt = "expires_at"
        case maxUses = "max_uses"
        case uses
        case usesRemaining = "uses_remaining"
    }

    var domainStatus: FamilyInviteStatus? {
        guard let status = FamilyInviteLifecycleStatus(rawValue: status) else { return nil }
        return FamilyInviteStatus(
            code: code,
            status: status,
            expiresAt: expiresAt,
            maxUses: maxUses,
            uses: uses,
            usesRemaining: usesRemaining
        )
    }
}

private struct FamilyJoinRequestRow: Decodable {
    var id: UUID
    var familyID: UUID
    var familyName: String
    var requesterUserID: UUID
    var requesterName: String
    var status: String
    var createdAt: Date
    var reviewedAt: Date?

    private enum CodingKeys: String, CodingKey {
        case id
        case familyID = "family_id"
        case familyName = "family_name"
        case requesterUserID = "requester_user_id"
        case requesterName = "requester_name"
        case status
        case createdAt = "created_at"
        case reviewedAt = "reviewed_at"
    }

    var domainRequest: FamilyJoinRequest {
        FamilyJoinRequest(
            id: id,
            familyID: familyID,
            familyName: familyName,
            requesterUserID: requesterUserID,
            requesterName: requesterName,
            status: FamilyJoinRequestStatus(rawValue: status) ?? .pending,
            createdAt: createdAt,
            reviewedAt: reviewedAt
        )
    }
}

private struct FamilyJoinOutcomeRow: Decodable {
    var status: String
    var homeContext: HomeContextRow?
    var request: FamilyJoinRequestRow?

    private enum CodingKeys: String, CodingKey {
        case status
        case homeContext = "home_context"
        case request
    }
}

private struct CreateFamilyParams: Encodable {
    var familyName: String

    private enum CodingKeys: String, CodingKey {
        case familyName = "family_name"
    }
}
#endif
