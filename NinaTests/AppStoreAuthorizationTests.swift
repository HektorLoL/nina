import XCTest
@testable import Nina
#if canImport(UIKit)
import UIKit
#endif

final class AppStoreAuthorizationTests: XCTestCase {
    @MainActor
    func testFailedMembershipVerificationBlocksCachedHomeAccess() async {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)

        let user = AuthUser(
            id: UUID().uuidString,
            displayName: "Owner",
            email: "owner@example.com",
            provider: .apple
        )
        let cachedFamily = FamilyGroup(
            name: "Cached Home",
            inviteCode: "cached-home",
            members: []
        )
        defaults.set(
            try! JSONEncoder().encode(cachedFamily),
            forKey: "nina.home.familyGroup.\(user.id)"
        )

        let store = AppStore(
            defaults: defaults,
            remoteHomeBackend: FailingHomeBackend(),
            ninaEngine: MockNinaEngine()
        )

        await store.activateHomeContext(for: user)

        XCTAssertEqual(store.homeAccessState, .unavailable)
        XCTAssertFalse(store.hasActiveHome)
        XCTAssertNotEqual(store.familyGroup.name, "Cached Home")
    }

    #if DEBUG
    @MainActor
    func testDebugAccountUsesLocalHomeWhenRemoteBackendExists() async {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)

        let user = DebugAuthAccount.testOne.user
        let cachedFamily = FamilyGroup(
            name: "Debug Home",
            inviteCode: "debug-home",
            members: []
        )
        defaults.set(
            try! JSONEncoder().encode(cachedFamily),
            forKey: "nina.home.familyGroup.\(user.id)"
        )

        let store = AppStore(
            defaults: defaults,
            remoteHomeBackend: FailingHomeBackend(),
            ninaEngine: MockNinaEngine()
        )

        await store.activateHomeContext(for: user)

        XCTAssertEqual(store.homeAccessState, .authorized)
        XCTAssertEqual(store.familyGroup.name, "Debug Home")
    }
    #endif

    @MainActor
    func testCreateHomeUsesRemoteBackendAndPersistsReturnedState() async throws {
        let suiteName = "AppStoreAuthorizationTests.\(#function).\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let user = makeUser()
        let task = TaskItem(
            title: "Prepare dinner",
            subtitle: "Family recipe",
            owner: "Owner",
            dueLabel: "Tonight",
            category: .food,
            isDone: false,
            createdBy: user.displayName
        )
        let expectedState = makeRemoteState(
            familyName: "Casa Aurora",
            inviteCode: "casa-47a9f2d0b3c1e8a4d6f2a9c5e7b1d304",
            tasks: [task]
        )
        let backend = HomeLifecycleBackend(createState: expectedState)
        let store = AppStore(
            defaults: defaults,
            remoteHomeBackend: backend,
            ninaEngine: MockNinaEngine()
        )
        await store.activateHomeContext(for: user)

        let created = await store.createHome(named: "  Casa Aurora  ", owner: user)
        let createRequest = await backend.createRequest()

        XCTAssertTrue(created)
        XCTAssertEqual(
            createRequest,
            HomeLifecycleBackend.CreateRequest(name: "Casa Aurora", ownerID: user.id)
        )
        XCTAssertEqual(store.homeAccessState, .authorized)
        XCTAssertEqual(store.currentPermissionRole, .owner)
        XCTAssertEqual(store.familyGroup, expectedState.familyGroup)
        XCTAssertEqual(store.tasks, [task])

        let familyData = try XCTUnwrap(
            defaults.data(forKey: "nina.home.familyGroup.\(user.id)")
        )
        XCTAssertEqual(try JSONDecoder().decode(FamilyGroup.self, from: familyData), expectedState.familyGroup)

        let snapshotData = try XCTUnwrap(
            defaults.data(
                forKey: "nina.home.appData.\(user.id).\(expectedState.familyGroup.id.uuidString)"
            )
        )
        let cachedSnapshot = try JSONDecoder().decode(AppDataSnapshot.self, from: snapshotData)
        XCTAssertEqual(cachedSnapshot.tasks, [task])
    }

    @MainActor
    func testJoinHomeNormalizesInviteAndAppliesMemberState() async {
        let user = makeUser()
        let inviteCode = "casa-47a9f2d0b3c1e8a4d6f2a9c5e7b1d304"
        let expectedState = makeRemoteState(
            familyName: "Shared Home",
            inviteCode: inviteCode,
            permissionRole: .member
        )
        let backend = HomeLifecycleBackend(joinState: expectedState)
        let store = AppStore(remoteHomeBackend: backend, ninaEngine: MockNinaEngine())
        await store.activateHomeContext(for: user)

        let joined = await store.joinHome(
            with: "  https://ninai.app/invite/\(inviteCode.uppercased())?source=share  ",
            member: user
        )
        let joinRequest = await backend.joinRequest()

        XCTAssertTrue(joined)
        XCTAssertEqual(
            joinRequest,
            HomeLifecycleBackend.JoinRequest(inviteCode: inviteCode, memberID: user.id)
        )
        XCTAssertEqual(store.homeAccessState, .authorized)
        XCTAssertEqual(store.currentPermissionRole, .member)
        XCTAssertEqual(store.familyGroup, expectedState.familyGroup)
    }

    @MainActor
    func testCreateAndJoinFailuresKeepHomeUnauthorized() async {
        let user = makeUser()
        let backend = HomeLifecycleBackend(failCreate: true, failJoin: true)
        let store = AppStore(remoteHomeBackend: backend, ninaEngine: MockNinaEngine())
        await store.activateHomeContext(for: user)

        let created = await store.createHome(named: "Casa", owner: user)
        XCTAssertFalse(created)
        XCTAssertEqual(store.homeAccessState, .noHome)
        XCTAssertEqual(store.syncErrorMessage, "Não consegui criar a casa no Supabase agora.")

        let joined = await store.joinHome(with: "casa-valid-invite", member: user)
        XCTAssertFalse(joined)
        XCTAssertEqual(store.homeAccessState, .noHome)
        XCTAssertEqual(store.syncErrorMessage, "Não encontrei esse convite no Supabase.")
    }

    func testAppDataSnapshotRoundTripsEveryCollection() throws {
        let snapshot = AppDataSnapshot.preview

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(AppDataSnapshot.self, from: data)

        XCTAssertEqual(decoded.messages, snapshot.messages)
        XCTAssertEqual(decoded.taskSections, snapshot.taskSections)
        XCTAssertEqual(decoded.customTaskCategories, snapshot.customTaskCategories)
        XCTAssertEqual(decoded.tasks, snapshot.tasks)
        XCTAssertEqual(decoded.shoppingItems, snapshot.shoppingItems)
        XCTAssertEqual(decoded.reminders, snapshot.reminders)
        XCTAssertEqual(decoded.insights, snapshot.insights)
    }

    func testAppDataSnapshotDecodesMissingCollectionsAsEmpty() throws {
        let snapshot = try JSONDecoder().decode(AppDataSnapshot.self, from: Data("{}".utf8))

        XCTAssertTrue(snapshot.messages.isEmpty)
        XCTAssertTrue(snapshot.taskSections.isEmpty)
        XCTAssertTrue(snapshot.customTaskCategories.isEmpty)
        XCTAssertTrue(snapshot.tasks.isEmpty)
        XCTAssertTrue(snapshot.shoppingItems.isEmpty)
        XCTAssertTrue(snapshot.reminders.isEmpty)
        XCTAssertTrue(snapshot.insights.isEmpty)
    }

    @MainActor
    func testTaskMutationsUseTargetedRowsInOrder() async {
        let user = makeUser()
        let backend = RecordingHomeBackend(state: makeRemoteState())
        let store = AppStore(remoteHomeBackend: backend, ninaEngine: MockNinaEngine())
        await store.activateHomeContext(for: user)

        store.addTask(
            title: "Buy milk",
            subtitle: "",
            owner: "Home",
            dueLabel: "Today",
            category: .food
        )
        let task = store.tasks[0]
        store.toggleTask(task)
        await store.waitForPendingRemoteMutations()
        let mutations = await backend.recordedMutations()

        XCTAssertEqual(
            mutations,
            [.createTask(task.id), .updateTask(task.id)]
        )
    }

    @MainActor
    func testShoppingMutationsUseTargetedRowsInOrder() async {
        let user = makeUser()
        let backend = RecordingHomeBackend(state: makeRemoteState())
        let store = AppStore(remoteHomeBackend: backend, ninaEngine: MockNinaEngine())
        await store.activateHomeContext(for: user)

        store.addShoppingItem(title: "Coffee", amount: "1", owner: "Home")
        let item = store.shoppingItems[0]
        store.updateShoppingItem(id: item.id, title: "Coffee beans", amount: "2", owner: "Home")
        store.toggleShoppingItem(item)
        await store.waitForPendingRemoteMutations()
        let mutations = await backend.recordedMutations()

        XCTAssertEqual(
            mutations,
            [.createShoppingItem(item.id), .updateShoppingItem(item.id), .updateShoppingItem(item.id)]
        )
    }

    @MainActor
    func testSectionAndCategoryMutationsAreIndependentRows() async {
        let user = makeUser()
        let backend = RecordingHomeBackend(state: makeRemoteState())
        let store = AppStore(remoteHomeBackend: backend, ninaEngine: MockNinaEngine())
        await store.activateHomeContext(for: user)

        let section = store.addTaskSection(title: "Weekend")
        let category = store.addTaskCategory(title: "Garden")
        await store.waitForPendingRemoteMutations()
        let mutations = await backend.recordedMutations()

        XCTAssertEqual(
            mutations,
            [.createTaskSection(section.id), .createTaskCategory(category!.id)]
        )
    }

    @MainActor
    func testLocalTaskEditDuringRefreshRejectsStaleRemoteState() async {
        let user = makeUser()
        let taskID = UUID()
        let initialState = makeRemoteState(
            tasks: [
                TaskItem(
                    id: taskID,
                    title: "Remote original",
                    subtitle: "",
                    owner: "Home",
                    dueLabel: "Today",
                    category: .home,
                    isDone: false,
                    createdBy: "Manual"
                )
            ]
        )
        let backend = ControlledRefreshHomeBackend(initialState: initialState)
        let store = AppStore(remoteHomeBackend: backend, ninaEngine: MockNinaEngine())
        await store.activateHomeContext(for: user)

        let refreshTask = Task {
            await store.refreshHomeFromRemote(for: user)
        }
        await backend.waitUntilRefreshStarted()

        store.updateTask(
            id: taskID,
            title: "Local edit",
            subtitle: "",
            owner: "Home",
            dueLabel: "Tomorrow",
            dueAt: nil,
            category: .home,
            priority: .high
        )
        await backend.completeRefresh(with: initialState)
        await refreshTask.value
        await store.waitForPendingRemoteMutations()

        XCTAssertEqual(store.tasks.first?.title, "Local edit")
        XCTAssertEqual(store.tasks.first?.dueLabel, "Tomorrow")
        XCTAssertEqual(store.tasks.first?.priority, .high)
    }

    @MainActor
    func testLocalShoppingEditSurvivesFailedRefresh() async {
        let user = makeUser()
        let itemID = UUID()
        let initialState = makeRemoteState(
            shoppingItems: [
                ShoppingItem(
                    id: itemID,
                    title: "Remote original",
                    amount: "1",
                    owner: "Home",
                    isChecked: false
                )
            ]
        )
        let backend = ControlledRefreshHomeBackend(initialState: initialState)
        let store = AppStore(remoteHomeBackend: backend, ninaEngine: MockNinaEngine())
        await store.activateHomeContext(for: user)

        let refreshTask = Task {
            await store.refreshHomeFromRemote(for: user)
        }
        await backend.waitUntilRefreshStarted()

        store.updateShoppingItem(
            id: itemID,
            title: "Local coffee",
            amount: "2",
            owner: "Owner"
        )
        await backend.failRefresh()
        await refreshTask.value
        await store.waitForPendingRemoteMutations()

        XCTAssertEqual(store.homeAccessState, .authorized)
        XCTAssertEqual(store.shoppingItems.first?.title, "Local coffee")
        XCTAssertEqual(store.shoppingItems.first?.amount, "2")
        XCTAssertEqual(store.shoppingItems.first?.owner, "Owner")
        XCTAssertNotNil(store.syncErrorMessage)
    }

    @MainActor
    func testRemoteRefreshAppliesWhenNoLocalEditOccurs() async {
        let user = makeUser()
        let taskID = UUID()
        let initialState = makeRemoteState(
            tasks: [
                TaskItem(
                    id: taskID,
                    title: "Initial",
                    subtitle: "",
                    owner: "Home",
                    dueLabel: "Today",
                    category: .home,
                    isDone: false,
                    createdBy: "Manual"
                )
            ]
        )
        let refreshedState = makeRemoteState(
            tasks: [
                TaskItem(
                    id: taskID,
                    title: "Updated remotely",
                    subtitle: "",
                    owner: "Home",
                    dueLabel: "Tomorrow",
                    category: .home,
                    priority: .high,
                    isDone: false,
                    createdBy: "Manual"
                )
            ]
        )
        let backend = ControlledRefreshHomeBackend(initialState: initialState)
        let store = AppStore(remoteHomeBackend: backend, ninaEngine: MockNinaEngine())
        await store.activateHomeContext(for: user)

        let refreshTask = Task {
            await store.refreshHomeFromRemote(for: user)
        }
        await backend.waitUntilRefreshStarted()
        await backend.completeRefresh(with: refreshedState)
        await refreshTask.value

        XCTAssertEqual(store.tasks.first?.title, "Updated remotely")
        XCTAssertEqual(store.tasks.first?.dueLabel, "Tomorrow")
        XCTAssertEqual(store.tasks.first?.priority, .high)
    }

    @MainActor
    func testRealtimeEventReloadsSharedActivity() async {
        let user = makeUser()
        let taskID = UUID()
        let initialState = makeRemoteState(
            tasks: [
                TaskItem(
                    id: taskID,
                    title: "Initial",
                    subtitle: "",
                    owner: "Home",
                    dueLabel: "Today",
                    category: .home,
                    isDone: false,
                    createdBy: "Manual"
                )
            ]
        )
        let backend = RecordingHomeBackend(state: initialState)
        let store = AppStore(remoteHomeBackend: backend, ninaEngine: MockNinaEngine())
        await store.activateHomeContext(for: user)
        await backend.waitUntilRealtimeSubscribed()

        await backend.publishRealtimeState(
            makeRemoteState(
                tasks: [
                    TaskItem(
                        id: taskID,
                        title: "Changed by family",
                        subtitle: "",
                        owner: "Home",
                        dueLabel: "Tomorrow",
                        category: .home,
                        priority: .high,
                        isDone: false,
                        createdBy: "Manual",
                        version: 2
                    )
                ]
            ),
            event: .tasks
        )

        for _ in 0..<40 where store.tasks.first?.title != "Changed by family" {
            try? await Task.sleep(for: .milliseconds(50))
        }

        XCTAssertEqual(store.tasks.first?.title, "Changed by family")
        XCTAssertEqual(store.tasks.first?.version, 2)
    }

    @MainActor
    func testConcurrentTaskEditShowsConflictAndKeepsRemoteVersion() async {
        let user = makeUser()
        let taskID = UUID()
        let initialTask = TaskItem(
            id: taskID,
            title: "Original",
            subtitle: "",
            owner: "Home",
            dueLabel: "Today",
            category: .home,
            isDone: false,
            createdBy: "Manual",
            version: 1
        )
        let remoteTask = TaskItem(
            id: taskID,
            title: "Changed by family",
            subtitle: "",
            owner: "Home",
            dueLabel: "Tomorrow",
            category: .home,
            priority: .high,
            isDone: false,
            createdBy: "Manual",
            version: 2
        )
        let backend = RecordingHomeBackend(
            state: makeRemoteState(tasks: [initialTask]),
            conflictingTask: remoteTask
        )
        let store = AppStore(remoteHomeBackend: backend, ninaEngine: MockNinaEngine())
        await store.activateHomeContext(for: user)

        store.updateTask(
            id: taskID,
            title: "My edit",
            subtitle: "",
            owner: "Home",
            dueLabel: "Next week",
            dueAt: nil,
            category: .home,
            priority: .urgent,
            expectedVersion: 1
        )
        await store.waitForPendingRemoteMutations()

        XCTAssertEqual(store.tasks.first, remoteTask)
        XCTAssertEqual(store.taskEditConflict?.localTask.title, "My edit")
        XCTAssertEqual(store.taskEditConflict?.remoteTask, remoteTask)
    }

    @MainActor
    func testStaleEditorVersionShowsConflictWithoutWriting() async {
        let user = makeUser()
        let taskID = UUID()
        let remoteTask = TaskItem(
            id: taskID,
            title: "Already changed",
            subtitle: "",
            owner: "Home",
            dueLabel: "Tomorrow",
            category: .home,
            isDone: false,
            createdBy: "Manual",
            version: 2
        )
        let backend = RecordingHomeBackend(state: makeRemoteState(tasks: [remoteTask]))
        let store = AppStore(remoteHomeBackend: backend, ninaEngine: MockNinaEngine())
        await store.activateHomeContext(for: user)

        store.updateTask(
            id: taskID,
            title: "Stale form edit",
            subtitle: "",
            owner: "Home",
            dueLabel: "Next week",
            dueAt: nil,
            category: .home,
            priority: .high,
            expectedVersion: 1
        )
        await store.waitForPendingRemoteMutations()
        let mutations = await backend.recordedMutations()

        XCTAssertEqual(store.tasks.first, remoteTask)
        XCTAssertNotNil(store.taskEditConflict)
        XCTAssertTrue(mutations.isEmpty)
    }

    @MainActor
    func testAttachmentOnlyMessageIsAcceptedAndStoredInConversation() async {
        let store = AppStore(remoteHomeBackend: nil, ninaEngine: MockNinaEngine())
        let initialMessageCount = store.messages.count
        let metadata = ChatAttachment(
            kind: .document,
            filename: "conta.pdf",
            mimeType: "application/pdf",
            byteCount: 4
        )

        await store.sendMessage(
            "",
            attachments: [NinaAttachmentInput(metadata: metadata, data: Data("test".utf8))]
        )

        XCTAssertEqual(store.messages.count, initialMessageCount + 2)
        XCTAssertEqual(store.messages[initialMessageCount].sender, .user)
        XCTAssertEqual(store.messages[initialMessageCount].text, "")
        XCTAssertEqual(store.messages[initialMessageCount].attachments, [metadata])
        XCTAssertEqual(store.messages[initialMessageCount + 1].sender, .nina)
    }

    func testChatMessageDecodesLegacyPayloadWithoutAttachments() throws {
        let payload = """
        {
          "id": "00000000-0000-0000-0000-000000000001",
          "sender": "user",
          "text": "Oi",
          "timestamp": 0
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let message = try decoder.decode(ChatMessage.self, from: payload)

        XCTAssertTrue(message.attachments.isEmpty)
        XCTAssertTrue(message.proposals.isEmpty)
    }

    func testNinaV2ResponseDecodesMultipleProposals() throws {
        let payload = """
        {
          "version": 2,
          "run_id": "70000000-0000-0000-0000-000000000001",
          "thread_id": "70000000-0000-0000-0000-000000000002",
          "reply": "Preparei duas propostas.",
          "assistant_message_id": "70000000-0000-0000-0000-000000000003",
          "proposals": [
            {
              "id": "70000000-0000-0000-0000-000000000004",
              "kind": "task",
              "state": "pending",
              "title": "Separar documentos",
              "detail": "Amanhã",
              "action_title": "Criar tarefa",
              "payload": {
                "title": "Separar documentos",
                "detail": "",
                "owner": "Casa",
                "due_label": "Amanhã",
                "due_at": "2026-06-16T09:00:00-03:00",
                "category": "home",
                "symbol_name": "doc.fill",
                "amount": "",
                "visibility": null,
                "confidence": null,
                "deduplication_key": "documents-2026-06-16"
              },
              "allowed_memory_visibilities": []
            },
            {
              "id": "70000000-0000-0000-0000-000000000005",
              "kind": "memory",
              "state": "pending",
              "title": "Preferência de lembrete",
              "detail": "Avisar antes",
              "action_title": "Guardar",
              "payload": {
                "title": "Antecedência",
                "detail": "Prefere aviso três dias antes",
                "owner": "Casa",
                "due_label": "Sem data",
                "due_at": null,
                "category": "home",
                "symbol_name": "brain.head.profile",
                "amount": "",
                "visibility": "private",
                "confidence": 0.9,
                "deduplication_key": "reminder-lead-time"
              },
              "allowed_memory_visibilities": ["private", "shared"]
            }
          ],
          "suggestion": null
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(NinaFunctionResponse.self, from: payload)
            .domainResponse

        XCTAssertEqual(response.version, 2)
        XCTAssertTrue(response.serverPersisted)
        XCTAssertEqual(response.proposals.map(\.kind), [.task, .memory])
        XCTAssertEqual(
            response.proposals.last?.allowedMemoryVisibilities,
            [.privateMemory, .shared]
        )
        XCTAssertEqual(
            response.proposals.first?.payload.dueAt,
            "2026-06-16T09:00:00-03:00"
        )
    }

    func testTaskAndReminderDueDatesRoundTrip() throws {
        let dueAt = Date(timeIntervalSince1970: 1_781_600_400)
        let task = TaskItem(
            title: "Pay bill",
            subtitle: "",
            owner: "Casa",
            dueLabel: "Tomorrow",
            dueAt: dueAt,
            category: .bills,
            isDone: false,
            createdBy: "Nina"
        )
        let reminder = ReminderItem(
            title: "Appointment",
            detail: "",
            dateLabel: "Tomorrow",
            dueAt: dueAt,
            symbolName: "calendar",
            tone: .amber
        )

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        XCTAssertEqual(
            try decoder.decode(TaskItem.self, from: encoder.encode(task)).dueAt,
            dueAt
        )
        XCTAssertEqual(
            try decoder.decode(ReminderItem.self, from: encoder.encode(reminder)).dueAt,
            dueAt
        )
    }

    @MainActor
    func testTaskWithDueDateRequestsLocalNotificationSync() async throws {
        let user = makeUser()
        let scheduler = RecordingNotificationScheduler()
        let store = AppStore(
            remoteHomeBackend: RecordingHomeBackend(state: makeRemoteState(tasks: [])),
            ninaEngine: MockNinaEngine(),
            notificationScheduler: scheduler
        )
        await store.activateHomeContext(for: user)

        let dueAt = Date(timeIntervalSinceNow: 3_600)
        store.addTask(
            title: "Pay school fee",
            subtitle: "",
            owner: "Casa",
            dueLabel: "Hoje",
            dueAt: dueAt,
            category: .bills
        )
        let taskID = try XCTUnwrap(store.tasks.first?.id)

        var didSyncTask = false
        for _ in 0..<40 {
            let records = await scheduler.records()
            didSyncTask = records.contains { record in
                record.tasks.contains { task in
                    task.id == taskID && task.dueAt == dueAt && !task.isDone
                }
            }
            if didSyncTask { break }
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertTrue(didSyncTask)
    }

    func testNinaRateLimitAndBudgetErrorsHaveExplicitMessages() {
        XCTAssertEqual(NinaEngineError(code: "rate_limited"), .rateLimited)
        XCTAssertEqual(
            NinaEngineError(code: "monthly_budget_reached"),
            .monthlyBudgetReached
        )
        XCTAssertTrue(NinaEngineError.rateLimited.userMessage.contains("limite"))
        XCTAssertTrue(NinaEngineError.monthlyBudgetReached.userMessage.contains("mensal"))
    }

    @MainActor
    func testOnlineNinaChatRequiresAIMemoryConsent() async {
        let user = makeUser()
        let adultMember = HouseholdMember(
            userID: user.id,
            name: user.displayName,
            relationship: "Você",
            role: .adult,
            tone: .mint,
            taskCount: 0,
            memoryNote: ""
        )
        let backend = RecordingHomeBackend(
            state: makeRemoteState(members: [adultMember])
        )
        let store = AppStore(
            remoteHomeBackend: backend,
            ninaEngine: PersistedNinaEngine(assistantMessageID: UUID())
        )
        await store.activateHomeContext(for: user)
        let initialCount = store.messages.count

        XCTAssertTrue(store.requiresAIMemoryConsent)
        XCTAssertFalse(store.hasAIMemoryConsent)
        XCTAssertFalse(store.canSendNinaMessages)

        await store.sendMessage("Antes do consentimento")
        XCTAssertEqual(store.messages.count, initialCount)

        store.grantAIMemoryConsent()
        XCTAssertTrue(store.hasAIMemoryConsent)
        XCTAssertTrue(store.canSendNinaMessages)

        await store.sendMessage("Depois do consentimento")
        XCTAssertEqual(store.messages.count, initialCount + 2)
    }

    @MainActor
    func testPrivacyExportIncludesConsentAndSnapshot() async throws {
        let suiteName = "AppStoreAuthorizationTests.\(#function).\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let user = makeUser()
        let task = TaskItem(
            title: "Enviar autorização escolar",
            subtitle: "Documento assinado",
            owner: user.displayName,
            dueLabel: "Sexta",
            category: .school,
            isDone: false,
            createdBy: "Nina"
        )
        let adultMember = HouseholdMember(
            userID: user.id,
            name: user.displayName,
            relationship: "Você",
            role: .adult,
            tone: .mint,
            taskCount: 1,
            memoryNote: ""
        )
        let store = AppStore(
            defaults: defaults,
            remoteHomeBackend: RecordingHomeBackend(
                state: makeRemoteState(tasks: [task], members: [adultMember])
            ),
            ninaEngine: MockNinaEngine()
        )
        await store.activateHomeContext(for: user)
        store.grantAIMemoryConsent()

        let data = try store.makePrivacyExportData()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let export = try decoder.decode(PrivacyExportPackage.self, from: data)

        XCTAssertEqual(export.policyVersion, PrivacyPolicyVersion.current)
        XCTAssertEqual(export.user?.id, user.id)
        XCTAssertEqual(export.familyGroup.name, "Test Home")
        XCTAssertEqual(export.aiMemoryConsent?.policyVersion, PrivacyPolicyVersion.current)
        XCTAssertEqual(export.data.tasks, [task])
    }

    @MainActor
    func testServerPersistedV2TurnSkipsLegacyChatMutations() async {
        let user = makeUser()
        let adultMember = HouseholdMember(
            userID: user.id,
            name: user.displayName,
            relationship: "Você",
            role: .adult,
            tone: .mint,
            taskCount: 0,
            memoryNote: ""
        )
        let backend = RecordingHomeBackend(
            state: makeRemoteState(members: [adultMember])
        )
        let assistantID = UUID()
        let store = AppStore(
            remoteHomeBackend: backend,
            ninaEngine: PersistedNinaEngine(assistantMessageID: assistantID)
        )
        await store.activateHomeContext(for: user)
        store.grantAIMemoryConsent()

        await store.sendMessage("Organize a conta")
        await store.waitForPendingRemoteMutations()

        let mutations = await backend.recordedMutations()
        XCTAssertFalse(mutations.contains { mutation in
            if case .createChatMessage = mutation { return true }
            return false
        })
        XCTAssertEqual(store.messages.last?.id, assistantID)
    }

    @MainActor
    func testChildHouseholdMemberCannotSendNinaMessages() async {
        let user = makeUser()
        let childMember = HouseholdMember(
            userID: user.id,
            name: user.displayName,
            relationship: "Filho",
            role: .child,
            tone: .amber,
            taskCount: 0,
            memoryNote: ""
        )
        let backend = RecordingHomeBackend(
            state: makeRemoteState(members: [childMember])
        )
        let store = AppStore(
            remoteHomeBackend: backend,
            ninaEngine: PersistedNinaEngine(assistantMessageID: UUID())
        )
        await store.activateHomeContext(for: user)
        let initialCount = store.messages.count

        await store.sendMessage("Tente enviar")

        XCTAssertFalse(store.canUseNinaAI)
        XCTAssertEqual(store.messages.count, initialCount)
    }

    @MainActor
    func testProposalConfirmationAndRejectionUseAtomicBackendRPC() async {
        let user = makeUser()
        let backend = RecordingHomeBackend(state: makeRemoteState())
        let store = AppStore(remoteHomeBackend: backend, ninaEngine: MockNinaEngine())
        await store.activateHomeContext(for: user)
        let accepted = makeProposal(kind: .task)
        let rejected = makeProposal(kind: .reminder)
        store.messages = [
            ChatMessage(
                sender: .nina,
                text: "Confirme",
                timestamp: .now,
                proposals: [accepted, rejected]
            )
        ]

        let didAccept = await store.resolveProposal(accepted, decision: .accept)
        store.messages = [
            ChatMessage(
                sender: .nina,
                text: "Confirme",
                timestamp: .now,
                proposals: [rejected]
            )
        ]
        let didReject = await store.resolveProposal(rejected, decision: .reject)

        let mutations = await backend.recordedMutations()
        XCTAssertTrue(didAccept)
        XCTAssertTrue(didReject)
        XCTAssertTrue(mutations.contains(.resolveNinaProposal(accepted.id, .accept)))
        XCTAssertTrue(mutations.contains(.resolveNinaProposal(rejected.id, .reject)))
    }

    @MainActor
    func testDeletePrivateHistoryUsesBackendAndClearsLocalThread() async {
        let user = makeUser()
        let backend = RecordingHomeBackend(state: makeRemoteState())
        let store = AppStore(remoteHomeBackend: backend, ninaEngine: MockNinaEngine())
        await store.activateHomeContext(for: user)
        store.messages = [
            ChatMessage(sender: .user, text: "Privado", timestamp: .now)
        ]
        store.ninaThread = NinaThread(
            id: UUID(),
            familyID: store.familyGroup.id,
            ownerUserID: try! XCTUnwrap(UUID(uuidString: user.id))
        )

        let didDelete = await store.deleteNinaChatHistory()
        let mutations = await backend.recordedMutations()

        XCTAssertTrue(didDelete)
        XCTAssertTrue(store.messages.isEmpty)
        XCTAssertNil(store.ninaThread)
        XCTAssertTrue(mutations.contains(.deleteNinaChatHistory(store.familyGroup.id)))
    }

    #if canImport(UIKit)
    func testProfilePhotoPolicyReducesDimensionsAndFileSize() throws {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let image = UIGraphicsImageRenderer(
            size: CGSize(width: 1_600, height: 1_200),
            format: format
        ).image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1_600, height: 1_200))

            for offset in stride(from: 0, through: 1_600, by: 12) {
                UIColor(
                    red: CGFloat(offset % 255) / 255,
                    green: CGFloat((offset * 3) % 255) / 255,
                    blue: CGFloat((offset * 7) % 255) / 255,
                    alpha: 1
                ).setStroke()
                context.cgContext.move(to: CGPoint(x: offset, y: 0))
                context.cgContext.addLine(to: CGPoint(x: 1_600 - offset, y: 1_200))
                context.cgContext.strokePath()
            }
        }
        let sourceData = try XCTUnwrap(image.pngData())

        let preparedData = try ProfilePhotoPolicy.prepareForStorage(sourceData)
        let preparedImage = try XCTUnwrap(UIImage(data: preparedData))
        let width = try XCTUnwrap(preparedImage.cgImage?.width)
        let height = try XCTUnwrap(preparedImage.cgImage?.height)

        XCTAssertLessThanOrEqual(preparedData.count, ProfilePhotoPolicy.maxBytes)
        XCTAssertLessThanOrEqual(max(width, height), ProfilePhotoPolicy.maxPixelDimension)
        XCTAssertEqual(Array(preparedData.prefix(2)), [0xFF, 0xD8])
    }

    func testProfilePhotoPolicyRejectsUnreadableData() {
        XCTAssertThrowsError(
            try ProfilePhotoPolicy.prepareForStorage(Data("not an image".utf8))
        ) { error in
            guard case ProfilePhotoError.unreadable = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }
    #endif

    @MainActor
    func testBackendDiagnosticsRecordsSuccessfulRequest() async throws {
        let diagnostics = BackendDiagnosticsStore(environment: .mock)

        let value = try await BackendRequestLogger.perform(
            component: "tests",
            operation: "success",
            diagnostics: diagnostics
        ) {
            42
        }

        XCTAssertEqual(value, 42)
        XCTAssertEqual(diagnostics.activeRequestCount, 0)
        XCTAssertEqual(diagnostics.lastOperation, "tests.success")
        XCTAssertNotNil(diagnostics.lastSyncAt)
        XCTAssertNil(diagnostics.lastError)
    }

    @MainActor
    func testBackendDiagnosticsRecordsFailedRequest() async {
        let diagnostics = BackendDiagnosticsStore(environment: .mock)

        do {
            _ = try await BackendRequestLogger.perform(
                component: "tests",
                operation: "failure",
                diagnostics: diagnostics
            ) {
                throw DiagnosticsTestError.expected
            }
            XCTFail("Expected the backend request to throw.")
        } catch DiagnosticsTestError.expected {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(diagnostics.activeRequestCount, 0)
        XCTAssertEqual(diagnostics.lastOperation, "tests.failure")
        XCTAssertNil(diagnostics.lastSyncAt)
        XCTAssertNotNil(diagnostics.lastErrorAt)
        XCTAssertTrue(diagnostics.lastError?.contains("tests.failure") == true)
    }

    private func makeUser() -> AuthUser {
        AuthUser(
            id: UUID().uuidString,
            displayName: "Owner",
            email: "owner@example.com",
            provider: .apple
        )
    }

    private func makeProposal(kind: NinaProposalKind) -> NinaProposal {
        NinaProposal(
            kind: kind,
            title: "Proposal",
            detail: "Detail",
            actionTitle: "Confirm",
            payload: NinaProposalPayload(title: "Payload", detail: "Detail")
        )
    }

    private func makeRemoteState(
        familyName: String = "Test Home",
        inviteCode: String = "test-home",
        permissionRole: FamilyPermissionRole = .owner,
        tasks: [TaskItem] = [],
        shoppingItems: [ShoppingItem] = [],
        members: [HouseholdMember] = []
    ) -> RemoteHomeState {
        RemoteHomeState(
            familyGroup: FamilyGroup(name: familyName, inviteCode: inviteCode, members: members),
            permissionRole: permissionRole,
            snapshot: AppDataSnapshot(
                messages: [],
                taskSections: PreviewData.taskSections,
                tasks: tasks,
                shoppingItems: shoppingItems,
                reminders: [],
                insights: []
            )
        )
    }
}

private struct PersistedNinaEngine: NinaEngine {
    var assistantMessageID: UUID

    func respond(
        to text: String,
        attachments: [NinaAttachmentInput],
        familyID: UUID,
        messageID: UUID
    ) async throws -> NinaEngineResponse {
        NinaEngineResponse(
            reply: "Preparei uma proposta.",
            suggestion: nil,
            version: 2,
            runID: UUID(),
            threadID: UUID(),
            assistantMessageID: assistantMessageID,
            proposals: [],
            serverPersisted: true
        )
    }
}

private enum DiagnosticsTestError: Error {
    case expected
}

private actor HomeLifecycleBackend: RemoteHomeBackend {
    struct CreateRequest: Equatable {
        var name: String
        var ownerID: String?
    }

    struct JoinRequest: Equatable {
        var inviteCode: String
        var memberID: String?
    }

    enum LifecycleError: Error {
        case expected
    }

    private let createState: RemoteHomeState?
    private let joinState: RemoteHomeState?
    private let failCreate: Bool
    private let failJoin: Bool
    private var recordedCreateRequest: CreateRequest?
    private var recordedJoinRequest: JoinRequest?

    init(
        createState: RemoteHomeState? = nil,
        joinState: RemoteHomeState? = nil,
        failCreate: Bool = false,
        failJoin: Bool = false
    ) {
        self.createState = createState
        self.joinState = joinState
        self.failCreate = failCreate
        self.failJoin = failJoin
    }

    func createRequest() -> CreateRequest? {
        recordedCreateRequest
    }

    func joinRequest() -> JoinRequest? {
        recordedJoinRequest
    }

    func loadHome(for user: AuthUser) async throws -> RemoteHomeState? {
        nil
    }

    func createHome(named name: String, owner: AuthUser?) async throws -> RemoteHomeState {
        recordedCreateRequest = CreateRequest(name: name, ownerID: owner?.id)
        guard !failCreate, let createState else { throw LifecycleError.expected }
        return createState
    }

    func joinHome(with inviteCode: String, member: AuthUser?) async throws -> RemoteHomeState {
        recordedJoinRequest = JoinRequest(inviteCode: inviteCode, memberID: member?.id)
        guard !failJoin, let joinState else { throw LifecycleError.expected }
        return joinState
    }

    func updateFamilySettings(
        familyID: UUID,
        name: String
    ) async throws -> RemoteHomeState {
        guard let state = createState ?? joinState else { throw LifecycleError.expected }
        return state
    }

    func addUnclaimedMember(_ member: HouseholdMember, familyID: UUID) async throws -> RemoteHomeState {
        guard let state = createState ?? joinState else { throw LifecycleError.expected }
        return state
    }

    func updateFamilyMember(_ member: HouseholdMember) async throws -> RemoteHomeState {
        guard let state = createState ?? joinState else { throw LifecycleError.expected }
        return state
    }

    func createTaskSection(_ section: TaskSection, sortOrder: Int, familyID: UUID) async throws {}
    func createTaskCategory(_ category: TaskCategory, familyID: UUID) async throws {}
    func createTask(_ task: TaskItem, familyID: UUID, currentUser: AuthUser) async throws {}
    func updateTask(_ task: TaskItem, familyID: UUID) async throws {}
    func createShoppingItem(_ item: ShoppingItem, familyID: UUID, currentUser: AuthUser) async throws {}
    func updateShoppingItem(_ item: ShoppingItem, familyID: UUID) async throws {}
    func createReminder(_ reminder: ReminderItem, familyID: UUID, currentUser: AuthUser) async throws {}
    func createChatMessage(_ message: ChatMessage, familyID: UUID, currentUser: AuthUser) async throws {}
}

private struct FailingHomeBackend: RemoteHomeBackend {
    struct VerificationError: Error {}

    func loadHome(for user: AuthUser) async throws -> RemoteHomeState? {
        throw VerificationError()
    }

    func createHome(named name: String, owner: AuthUser?) async throws -> RemoteHomeState {
        throw VerificationError()
    }

    func joinHome(with inviteCode: String, member: AuthUser?) async throws -> RemoteHomeState {
        throw VerificationError()
    }

    func updateFamilySettings(
        familyID: UUID,
        name: String
    ) async throws -> RemoteHomeState {
        throw VerificationError()
    }

    func addUnclaimedMember(_ member: HouseholdMember, familyID: UUID) async throws -> RemoteHomeState {
        throw VerificationError()
    }

    func updateFamilyMember(_ member: HouseholdMember) async throws -> RemoteHomeState {
        throw VerificationError()
    }

    func createTaskSection(_ section: TaskSection, sortOrder: Int, familyID: UUID) async throws {}
    func createTaskCategory(_ category: TaskCategory, familyID: UUID) async throws {}
    func createTask(_ task: TaskItem, familyID: UUID, currentUser: AuthUser) async throws {}
    func updateTask(_ task: TaskItem, familyID: UUID) async throws {}
    func createShoppingItem(_ item: ShoppingItem, familyID: UUID, currentUser: AuthUser) async throws {}
    func updateShoppingItem(_ item: ShoppingItem, familyID: UUID) async throws {}
    func createReminder(_ reminder: ReminderItem, familyID: UUID, currentUser: AuthUser) async throws {}
    func createChatMessage(_ message: ChatMessage, familyID: UUID, currentUser: AuthUser) async throws {}
}

private enum RecordedHomeMutation: Equatable {
    case createTaskSection(String)
    case createTaskCategory(String)
    case createTask(UUID)
    case updateTask(UUID)
    case createShoppingItem(UUID)
    case updateShoppingItem(UUID)
    case createReminder(UUID)
    case createChatMessage(UUID)
    case resolveNinaProposal(UUID, NinaProposalDecision)
    case deleteNinaChatHistory(UUID)
}

private struct NotificationSyncRecord {
    var tasks: [TaskItem]
    var reminders: [ReminderItem]
    var familyID: UUID
}

private actor RecordingNotificationScheduler: HomeNotificationScheduling {
    private var syncRecords: [NotificationSyncRecord] = []

    func synchronize(tasks: [TaskItem], reminders: [ReminderItem], familyID: UUID) async {
        syncRecords.append(
            NotificationSyncRecord(
                tasks: tasks,
                reminders: reminders,
                familyID: familyID
            )
        )
    }

    func records() -> [NotificationSyncRecord] {
        syncRecords
    }
}

private actor RecordingHomeBackend: RemoteHomeBackend {
    private var state: RemoteHomeState
    private let conflictingTask: TaskItem?
    private var mutations: [RecordedHomeMutation] = []
    private var realtimeContinuation: AsyncStream<HomeRealtimeEvent>.Continuation?
    private var realtimeSubscribed = false
    private var realtimeSubscribedContinuation: CheckedContinuation<Void, Never>?

    init(state: RemoteHomeState, conflictingTask: TaskItem? = nil) {
        self.state = state
        self.conflictingTask = conflictingTask
    }

    func recordedMutations() -> [RecordedHomeMutation] {
        mutations
    }

    func waitUntilRealtimeSubscribed() async {
        if realtimeSubscribed { return }
        await withCheckedContinuation { continuation in
            realtimeSubscribedContinuation = continuation
        }
    }

    func publishRealtimeState(_ state: RemoteHomeState, event: HomeRealtimeEvent) {
        self.state = state
        realtimeContinuation?.yield(event)
    }

    func loadHome(for user: AuthUser) async throws -> RemoteHomeState? {
        state
    }

    func createHome(named name: String, owner: AuthUser?) async throws -> RemoteHomeState {
        state
    }

    func joinHome(with inviteCode: String, member: AuthUser?) async throws -> RemoteHomeState {
        state
    }

    func updateFamilySettings(
        familyID: UUID,
        name: String
    ) async throws -> RemoteHomeState {
        state
    }

    func addUnclaimedMember(_ member: HouseholdMember, familyID: UUID) async throws -> RemoteHomeState {
        state
    }

    func updateFamilyMember(_ member: HouseholdMember) async throws -> RemoteHomeState {
        state
    }

    func createTaskSection(_ section: TaskSection, sortOrder: Int, familyID: UUID) async throws {
        mutations.append(.createTaskSection(section.id))
    }

    func createTaskCategory(_ category: TaskCategory, familyID: UUID) async throws {
        mutations.append(.createTaskCategory(category.id))
    }

    func createTask(_ task: TaskItem, familyID: UUID, currentUser: AuthUser) async throws {
        mutations.append(.createTask(task.id))
    }

    func updateTask(_ task: TaskItem, familyID: UUID) async throws {
        mutations.append(.updateTask(task.id))
    }

    func updateTask(
        _ task: TaskItem,
        expectedVersion: Int,
        familyID: UUID
    ) async throws -> TaskUpdateResult {
        mutations.append(.updateTask(task.id))
        if let conflictingTask {
            return .conflict(current: conflictingTask)
        }
        return .updated(task)
    }

    func createShoppingItem(_ item: ShoppingItem, familyID: UUID, currentUser: AuthUser) async throws {
        mutations.append(.createShoppingItem(item.id))
    }

    func updateShoppingItem(_ item: ShoppingItem, familyID: UUID) async throws {
        mutations.append(.updateShoppingItem(item.id))
    }

    func createReminder(_ reminder: ReminderItem, familyID: UUID, currentUser: AuthUser) async throws {
        mutations.append(.createReminder(reminder.id))
    }

    func createChatMessage(_ message: ChatMessage, familyID: UUID, currentUser: AuthUser) async throws {
        mutations.append(.createChatMessage(message.id))
    }

    func resolveNinaProposal(
        _ proposalID: UUID,
        decision: NinaProposalDecision,
        editedPayload: NinaProposalPayload?,
        memoryVisibility: NinaMemoryVisibility?
    ) async throws -> NinaProposalResolution {
        mutations.append(.resolveNinaProposal(proposalID, decision))
        return NinaProposalResolution(
            id: proposalID,
            state: decision == .accept ? .accepted : .rejected
        )
    }

    func deleteNinaChatHistory(familyID: UUID) async throws {
        mutations.append(.deleteNinaChatHistory(familyID))
    }

    func realtimeEvents(familyID: UUID) async -> AsyncStream<HomeRealtimeEvent> {
        AsyncStream { continuation in
            realtimeContinuation = continuation
            realtimeSubscribed = true
            realtimeSubscribedContinuation?.resume()
            realtimeSubscribedContinuation = nil
        }
    }
}

private actor ControlledRefreshHomeBackend: RemoteHomeBackend {
    struct RefreshFailure: Error {}

    private let initialState: RemoteHomeState
    private var loadCount = 0
    private var refreshStarted = false
    private var refreshStartedContinuation: CheckedContinuation<Void, Never>?
    private var refreshContinuation: CheckedContinuation<RemoteHomeState?, Error>?

    init(initialState: RemoteHomeState) {
        self.initialState = initialState
    }

    func waitUntilRefreshStarted() async {
        if refreshStarted { return }
        await withCheckedContinuation { continuation in
            refreshStartedContinuation = continuation
        }
    }

    func completeRefresh(with state: RemoteHomeState) {
        refreshContinuation?.resume(returning: state)
        refreshContinuation = nil
    }

    func failRefresh() {
        refreshContinuation?.resume(throwing: RefreshFailure())
        refreshContinuation = nil
    }

    func loadHome(for user: AuthUser) async throws -> RemoteHomeState? {
        loadCount += 1
        guard loadCount > 1 else { return initialState }

        refreshStarted = true
        refreshStartedContinuation?.resume()
        refreshStartedContinuation = nil

        return try await withCheckedThrowingContinuation { continuation in
            refreshContinuation = continuation
        }
    }

    func createHome(named name: String, owner: AuthUser?) async throws -> RemoteHomeState {
        initialState
    }

    func joinHome(with inviteCode: String, member: AuthUser?) async throws -> RemoteHomeState {
        initialState
    }

    func updateFamilySettings(
        familyID: UUID,
        name: String
    ) async throws -> RemoteHomeState {
        initialState
    }

    func addUnclaimedMember(_ member: HouseholdMember, familyID: UUID) async throws -> RemoteHomeState {
        initialState
    }

    func updateFamilyMember(_ member: HouseholdMember) async throws -> RemoteHomeState {
        initialState
    }

    func createTaskSection(_ section: TaskSection, sortOrder: Int, familyID: UUID) async throws {}
    func createTaskCategory(_ category: TaskCategory, familyID: UUID) async throws {}
    func createTask(_ task: TaskItem, familyID: UUID, currentUser: AuthUser) async throws {}
    func updateTask(_ task: TaskItem, familyID: UUID) async throws {}
    func createShoppingItem(_ item: ShoppingItem, familyID: UUID, currentUser: AuthUser) async throws {}
    func updateShoppingItem(_ item: ShoppingItem, familyID: UUID) async throws {}
    func createReminder(_ reminder: ReminderItem, familyID: UUID, currentUser: AuthUser) async throws {}
    func createChatMessage(_ message: ChatMessage, familyID: UUID, currentUser: AuthUser) async throws {}
}
