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
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "nina-app-store-tests-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let privateDataStore = ProtectedLocalDataStore(directoryURL: directory)

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
            privateDataStore: privateDataStore,
            remoteHomeBackend: FailingHomeBackend(),
            ninaEngine: MockNinaEngine()
        )

        await store.activateHomeContext(for: user)

        XCTAssertEqual(store.homeAccessState, .authorized)
        XCTAssertEqual(store.familyGroup.name, "Debug Home")
        XCTAssertNil(defaults.data(forKey: "nina.home.familyGroup.\(user.id)"))
    }
    #endif

    @MainActor
    func testCreateHomeUsesRemoteBackendAndPersistsReturnedState() async throws {
        let suiteName = "AppStoreAuthorizationTests.\(#function).\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "nina-app-store-tests-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let privateDataStore = ProtectedLocalDataStore(directoryURL: directory)

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
            privateDataStore: privateDataStore,
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
            privateDataStore.data(
                forKey: "nina.home.familyGroup.\(user.id)",
                ownerScope: PrivateLocalDataScope.household(for: user.id)
            )
        )
        XCTAssertEqual(try JSONDecoder().decode(FamilyGroup.self, from: familyData), expectedState.familyGroup)
        XCTAssertNil(defaults.data(forKey: "nina.home.familyGroup.\(user.id)"))

        let snapshotData = try XCTUnwrap(
            privateDataStore.data(
                forKey: "nina.home.appData.\(user.id).\(expectedState.familyGroup.id.uuidString)",
                ownerScope: PrivateLocalDataScope.household(for: user.id)
            )
        )
        let cachedSnapshot = try JSONDecoder().decode(AppDataSnapshot.self, from: snapshotData)
        XCTAssertEqual(cachedSnapshot.tasks, [task])
        XCTAssertNil(
            defaults.data(
                forKey: "nina.home.appData.\(user.id).\(expectedState.familyGroup.id.uuidString)"
            )
        )
    }

    @MainActor
    func testExplicitUserCleanupWorksAfterActiveContextIsGone() async throws {
        let suiteName = "AppStoreAuthorizationTests.\(#function).\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "nina-app-store-tests-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let privateDataStore = ProtectedLocalDataStore(directoryURL: directory)
        let user = makeUser()
        let familyID = UUID()
        let homeKey = "nina.home.familyGroup.\(user.id)"
        let snapshotKey = "nina.home.appData.\(user.id).\(familyID.uuidString)"
        let consentKey = "nina.privacy.aiMemoryConsent.\(user.id)"
        let householdScope = PrivateLocalDataScope.household(for: user.id)
        let consentScope = PrivateLocalDataScope.aiConsent(for: user.id)
        try privateDataStore.set(Data("home".utf8), forKey: homeKey, ownerScope: householdScope)
        try privateDataStore.set(Data("snapshot".utf8), forKey: snapshotKey, ownerScope: householdScope)
        try privateDataStore.set(Data("consent".utf8), forKey: consentKey, ownerScope: consentScope)
        try privateDataStore.set(
            Data("profile".utf8),
            forKey: "profile",
            ownerScope: PrivateLocalDataScope.profile(for: user.id)
        )
        defaults.set(Data("legacy".utf8), forKey: homeKey)
        defaults.set(Data("legacy".utf8), forKey: snapshotKey)
        let store = AppStore(
            defaults: defaults,
            privateDataStore: privateDataStore,
            remoteHomeBackend: nil,
            ninaEngine: MockNinaEngine(),
            notificationScheduler: NoopHomeNotificationScheduler()
        )
        await store.activateHomeContext(for: nil)

        store.clearLocalData(for: user.id)

        XCTAssertNil(try privateDataStore.data(forKey: homeKey, ownerScope: householdScope))
        XCTAssertNil(try privateDataStore.data(forKey: snapshotKey, ownerScope: householdScope))
        XCTAssertNil(try privateDataStore.data(forKey: consentKey, ownerScope: consentScope))
        XCTAssertNotNil(
            try privateDataStore.data(
                forKey: "profile",
                ownerScope: PrivateLocalDataScope.profile(for: user.id)
            )
        )
        XCTAssertNil(defaults.data(forKey: homeKey))
        XCTAssertNil(defaults.data(forKey: snapshotKey))
    }

    @MainActor
    func testAccountCleanupInvalidatesInFlightHomeActivation() async throws {
        let suiteName = "AppStoreAuthorizationTests.\(#function).\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "nina-app-store-tests-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let privateDataStore = ProtectedLocalDataStore(directoryURL: directory)
        let user = makeUser()
        let staleState = makeRemoteState(familyName: "Stale Home")
        let backend = ControlledRefreshHomeBackend(
            initialState: staleState,
            controlsInitialLoad: true
        )
        let store = AppStore(
            defaults: defaults,
            privateDataStore: privateDataStore,
            remoteHomeBackend: backend,
            ninaEngine: MockNinaEngine(),
            notificationScheduler: NoopHomeNotificationScheduler()
        )

        let activationTask = Task {
            await store.activateHomeContext(for: user)
        }
        await backend.waitUntilRefreshStarted()

        store.clearLocalData(for: user.id)
        await backend.completeRefresh(with: staleState)
        await activationTask.value

        XCTAssertEqual(store.homeAccessState, .noHome)
        XCTAssertFalse(store.hasActiveHome)
        XCTAssertNotEqual(store.familyGroup.name, staleState.familyGroup.name)
        XCTAssertNil(
            try privateDataStore.data(
                forKey: "nina.home.familyGroup.\(user.id)",
                ownerScope: PrivateLocalDataScope.household(for: user.id)
            )
        )
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
    func testJoinRequestMovesHomeAccessIntoPendingApproval() async {
        let user = makeUser()
        let request = FamilyJoinRequest(
            id: UUID(),
            familyID: UUID(),
            familyName: "Casa compartilhada",
            requesterUserID: UUID(uuidString: user.id)!,
            requesterName: user.displayName,
            status: .pending,
            createdAt: .now,
            reviewedAt: nil
        )
        let backend = HomeLifecycleBackend(pendingRequest: request)
        let store = AppStore(remoteHomeBackend: backend, ninaEngine: MockNinaEngine())
        await store.activateHomeContext(for: user)

        let requested = await store.joinHome(with: "casa-valid-invite", member: user)

        XCTAssertTrue(requested)
        XCTAssertEqual(store.homeAccessState, .pendingApproval)
        XCTAssertEqual(store.pendingJoinRequest, request)
        XCTAssertFalse(store.hasActiveHome)
    }

    @MainActor
    func testFullHomeRejectsJoinApprovalBeforeCallingBackend() async {
        let user = makeUser()
        let members = (0..<AppStore.maxFamilyPeople).map { index in
            HouseholdMember(
                name: "Pessoa \(index + 1)",
                relationship: "Família",
                role: index == 0 ? .adult : .child,
                tone: .mint,
                taskCount: 0,
                memoryNote: ""
            )
        }
        let state = makeRemoteState(permissionRole: .owner, members: members)
        let store = AppStore(
            remoteHomeBackend: RecordingHomeBackend(state: state),
            ninaEngine: MockNinaEngine()
        )
        await store.activateHomeContext(for: user)

        let request = FamilyJoinRequest(
            id: UUID(),
            familyID: state.familyGroup.id,
            familyName: state.familyGroup.name,
            requesterUserID: UUID(),
            requesterName: "Nova pessoa",
            status: .pending,
            createdAt: .now,
            reviewedAt: nil
        )

        let approved = await store.approveJoinRequest(request)

        XCTAssertFalse(approved)
        XCTAssertFalse(store.canInviteMorePeople)
        XCTAssertEqual(store.syncErrorMessage, "A casa já atingiu o limite de 8 pessoas.")
    }

    @MainActor
    func testADeclinedRequesterSeesTheDecisionInsteadOfTheCreateAHomeScreen() async {
        let user = makeUser()
        let decision = makeAccessDecision(outcome: .declined)
        let backend = AccessDecisionBackend(decision: decision)
        let store = AppStore(remoteHomeBackend: backend, ninaEngine: MockNinaEngine())

        await store.activateHomeContext(for: user)

        XCTAssertEqual(store.homeAccessState, .accessDecision)
        XCTAssertEqual(store.familyAccessDecision, decision)
        XCTAssertFalse(store.hasActiveHome)
    }

    @MainActor
    func testAnAcknowledgedDecisionIsNotShownAgainOnTheNextRefresh() async {
        let user = makeUser()
        let decision = makeAccessDecision(outcome: .declined)
        let backend = AccessDecisionBackend(decision: decision)
        let store = AppStore(remoteHomeBackend: backend, ninaEngine: MockNinaEngine())
        await store.activateHomeContext(for: user)

        let acknowledged = await store.acknowledgeFamilyAccessDecision()

        XCTAssertTrue(acknowledged)
        let acknowledgements = await backend.acknowledgedDecisionIDs()
        XCTAssertEqual(acknowledgements, [decision.id])
        XCTAssertNil(store.familyAccessDecision)
        XCTAssertEqual(store.homeAccessState, .noHome)

        await store.refreshHomeFromRemote(for: user)

        XCTAssertNil(store.familyAccessDecision)
        XCTAssertEqual(store.homeAccessState, .noHome)
    }

    @MainActor
    func testAPersonWhoNeverAskedToJoinStillSeesTheCreateAHomeScreen() async {
        let user = makeUser()
        let backend = AccessDecisionBackend()
        let store = AppStore(remoteHomeBackend: backend, ninaEngine: MockNinaEngine())

        await store.activateHomeContext(for: user)

        XCTAssertEqual(store.homeAccessState, .noHome)
        XCTAssertNil(store.familyAccessDecision)
    }

    @MainActor
    func testARemovedMemberIsNeverToldWhoRemovedThem() async throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let serverPayload = """
        {"id":"3F1A0000-0000-4000-8000-00000000DEC1","family_name":"Casa Castello",
         "outcome":"removed","decided_at":"2026-08-09T12:00:00Z",
         "reviewed_by":"9C2B0000-0000-4000-8000-00000000BEEF","reviewer_name":"Mirna"}
        """
        let decoded = try decoder.decode(FamilyAccessDecision.self, from: Data(serverPayload.utf8))
        let backend = AccessDecisionBackend(decision: decoded)
        let store = AppStore(remoteHomeBackend: backend, ninaEngine: MockNinaEngine())

        await store.activateHomeContext(for: makeUser())

        let shown = try XCTUnwrap(store.familyAccessDecision)
        XCTAssertEqual(store.homeAccessState, .accessDecision)
        XCTAssertEqual(shown.outcome, .removed)
        XCTAssertEqual(shown.familyName, "Casa Castello")
        XCTAssertEqual(
            Mirror(reflecting: shown).children.compactMap(\.label).sorted(),
            ["decidedAt", "familyName", "id", "outcome"]
        )
    }

    @MainActor
    func testAPendingRequestReachesTheCasaTabBadgeWithoutOpeningTheTab() async {
        let user = makeUser()
        let initialState = makeRemoteState(permissionRole: .owner)
        let backend = RecordingHomeBackend(state: initialState)
        let store = AppStore(remoteHomeBackend: backend, ninaEngine: MockNinaEngine())
        await store.activateHomeContext(for: user)
        await backend.waitUntilRealtimeSubscribed()

        XCTAssertEqual(store.pendingJoinRequestCount, 0)

        var stateWithRequest = initialState
        stateWithRequest.joinRequests = [
            FamilyJoinRequest(
                id: UUID(),
                familyID: initialState.familyGroup.id,
                familyName: initialState.familyGroup.name,
                requesterUserID: UUID(),
                requesterName: "Nova pessoa",
                status: .pending,
                createdAt: .now,
                reviewedAt: nil
            )
        ]
        await backend.publishRealtimeState(stateWithRequest, event: .family)

        for _ in 0..<40 where store.pendingJoinRequestCount == 0 {
            try? await Task.sleep(for: .milliseconds(50))
        }

        XCTAssertEqual(store.pendingJoinRequestCount, 1)
    }

    @MainActor
    func testAPlainMemberNeverSeesThePendingRequestBadge() async {
        let user = makeUser()
        var state = makeRemoteState(permissionRole: .member)
        state.joinRequests = [
            FamilyJoinRequest(
                id: UUID(),
                familyID: state.familyGroup.id,
                familyName: state.familyGroup.name,
                requesterUserID: UUID(),
                requesterName: "Nova pessoa",
                status: .pending,
                createdAt: .now,
                reviewedAt: nil
            )
        ]
        let store = AppStore(
            remoteHomeBackend: RecordingHomeBackend(state: state),
            ninaEngine: MockNinaEngine()
        )

        await store.activateHomeContext(for: user)

        XCTAssertEqual(store.joinRequests.count, 1)
        XCTAssertEqual(store.pendingJoinRequestCount, 0)
    }

    func testPostgresDateOnlyCodecRoundTripsWithoutTimezoneShift() throws {
        let timeZone = try XCTUnwrap(TimeZone(identifier: "America/Argentina/Salta"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let birthDate = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2018, month: 4, day: 12))
        )

        let encoded = PostgresDateOnlyCodec.string(from: birthDate, timeZone: timeZone)
        let decoded = try XCTUnwrap(
            PostgresDateOnlyCodec.date(from: encoded, timeZone: timeZone)
        )

        XCTAssertEqual(encoded, "2018-04-12")
        XCTAssertEqual(
            calendar.dateComponents([.year, .month, .day], from: decoded),
            DateComponents(year: 2018, month: 4, day: 12)
        )
        XCTAssertNil(PostgresDateOnlyCodec.date(from: "2018-02-30", timeZone: timeZone))
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
        XCTAssertEqual(
            store.syncErrorMessage,
            "Este convite é inválido, expirou ou a casa está sem vagas."
        )
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
        XCTAssertEqual(decoded.insights, snapshot.insights)
    }

    func testAppDataSnapshotDecodesMissingCollectionsAsEmpty() throws {
        let snapshot = try JSONDecoder().decode(AppDataSnapshot.self, from: Data("{}".utf8))

        XCTAssertTrue(snapshot.messages.isEmpty)
        XCTAssertTrue(snapshot.taskSections.isEmpty)
        XCTAssertTrue(snapshot.customTaskCategories.isEmpty)
        XCTAssertTrue(snapshot.tasks.isEmpty)
        XCTAssertTrue(snapshot.shoppingItems.isEmpty)
        XCTAssertTrue(snapshot.insights.isEmpty)
    }

    func testLegacyReminderCacheDecodesIntoUnifiedTasks() throws {
        let data = Data(
            """
            {
              "tasks": [],
              "reminders": [
                {
                  "id": "73000000-0000-0000-0000-000000000001",
                  "title": "Levar documento",
                  "detail": "Colocar na mochila",
                  "dateLabel": "Hoje, 18:00",
                  "recurrence": "weekly",
                  "symbolName": "backpack.fill",
                  "tone": "amber"
                }
              ]
            }
            """.utf8
        )

        let snapshot = try JSONDecoder().decode(AppDataSnapshot.self, from: data)
        let task = try XCTUnwrap(snapshot.tasks.first)

        XCTAssertEqual(snapshot.tasks.count, 1)
        XCTAssertEqual(task.title, "Levar documento")
        XCTAssertEqual(task.subtitle, "Colocar na mochila")
        XCTAssertEqual(task.recurrence, .weekly)
        XCTAssertEqual(task.category.title, "Casa")
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
    func testAssigningWorkToAMemberStoresTheMemberIDBesideTheDisplayName() async {
        let user = makeUser()
        let backend = RecordingHomeBackend(state: makeRemoteState())
        let store = AppStore(remoteHomeBackend: backend, ninaEngine: MockNinaEngine())
        await store.activateHomeContext(for: user)
        let memberID = UUID()

        store.addTask(
            title: "Buy milk",
            subtitle: "",
            owner: "Mirna",
            ownerMemberID: memberID,
            dueLabel: "Today",
            category: .food
        )
        store.addShoppingItem(title: "Coffee", amount: "1", owner: "Mirna", ownerMemberID: memberID)

        XCTAssertEqual(store.tasks[0].owner, "Mirna")
        XCTAssertEqual(store.tasks[0].ownerMemberID, memberID)
        XCTAssertEqual(store.shoppingItems[0].ownerMemberID, memberID)
    }

    @MainActor
    func testHandingWorkBackToCasaClearsTheMemberPointer() async {
        let user = makeUser()
        let backend = RecordingHomeBackend(state: makeRemoteState())
        let store = AppStore(remoteHomeBackend: backend, ninaEngine: MockNinaEngine())
        await store.activateHomeContext(for: user)
        let memberID = UUID()

        store.addTask(
            title: "Buy milk",
            subtitle: "",
            owner: "Mirna",
            ownerMemberID: memberID,
            dueLabel: "Today",
            category: .food
        )
        let task = store.tasks[0]
        store.updateTask(
            id: task.id,
            title: task.title,
            subtitle: task.subtitle,
            owner: "Casa",
            ownerMemberID: memberID,
            dueLabel: task.dueLabel,
            dueAt: task.dueAt,
            category: task.category,
            priority: task.priority
        )

        store.addShoppingItem(title: "Coffee", amount: "1", owner: "Casa", ownerMemberID: memberID)

        XCTAssertEqual(store.tasks[0].owner, "Casa")
        XCTAssertNil(store.tasks[0].ownerMemberID)
        XCTAssertNil(store.shoppingItems[0].ownerMemberID)
    }

    @MainActor
    func testSectionAndCategoryMutationsAreIndependentRows() async {
        let user = makeUser()
        let backend = RecordingHomeBackend(state: makeRemoteState())
        let store = AppStore(remoteHomeBackend: backend, ninaEngine: MockNinaEngine())
        await store.activateHomeContext(for: user)

        let section = store.addTaskSection(title: "Weekend", symbolName: "sun.max.fill")
        let category = store.addTaskCategory(title: "Garden")
        await store.waitForPendingRemoteMutations()
        let mutations = await backend.recordedMutations()

        XCTAssertEqual(section.symbolName, "sun.max.fill")
        XCTAssertEqual(
            mutations,
            [.createTaskSection(section.id), .createTaskCategory(category!.id)]
        )
    }

    @MainActor
    func testDeletingCustomSectionMovesTasksAndDeletesSectionRemotely() async throws {
        let user = makeUser()
        let customSection = TaskSection(
            id: "weekend",
            title: "Weekend",
            symbolName: "sun.max.fill",
            tone: .amber
        )
        let task = TaskItem(
            title: "Plan lunch",
            subtitle: "",
            owner: "Home",
            dueLabel: "Saturday",
            category: .food,
            isDone: false,
            createdBy: "Manual",
            sectionID: customSection.id
        )
        let backend = RecordingHomeBackend(
            state: makeRemoteState(
                taskSections: PreviewData.taskSections + [customSection],
                tasks: [task]
            )
        )
        let store = AppStore(remoteHomeBackend: backend, ninaEngine: MockNinaEngine())
        await store.activateHomeContext(for: user)

        XCTAssertTrue(store.deleteTaskSection(customSection.id))
        await store.waitForPendingRemoteMutations()
        let mutations = await backend.recordedMutations()

        XCTAssertFalse(store.taskSections.contains(where: { $0.id == customSection.id }))
        XCTAssertEqual(store.tasks.first?.sectionID, AppStore.houseTasksSectionID)
        XCTAssertEqual(
            mutations,
            [RecordedHomeMutation.deleteTaskSection(customSection.id)]
        )
    }

    @MainActor
    func testDefaultTaskSectionCannotBeDeleted() async {
        let backend = RecordingHomeBackend(state: makeRemoteState())
        let store = AppStore(remoteHomeBackend: backend, ninaEngine: MockNinaEngine())
        await store.activateHomeContext(for: makeUser())

        XCTAssertFalse(store.deleteTaskSection(AppStore.houseTasksSectionID))
        XCTAssertTrue(store.taskSections.contains(where: { $0.id == AppStore.houseTasksSectionID }))
        let mutations = await backend.recordedMutations()
        XCTAssertTrue(mutations.isEmpty)
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
    func testAnUnverifiableMembershipEndsHomeAccessEvenWithALocalEditPending() async {
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

        XCTAssertEqual(store.homeAccessState, .unavailable)
        XCTAssertFalse(store.hasActiveHome)
        XCTAssertNotEqual(store.familyGroup.name, initialState.familyGroup.name)
        XCTAssertFalse(store.shoppingItems.contains { $0.id == itemID })
        XCTAssertEqual(
            store.syncErrorMessage,
            "Não foi possível verificar sua participação nesta casa."
        )
    }

    @MainActor
    func testARemovedMemberLosesTheHouseEvenWhileStillEditingIt() async throws {
        let suiteName = "AppStoreAuthorizationTests.\(#function).\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "nina-app-store-tests-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let privateDataStore = ProtectedLocalDataStore(directoryURL: directory)
        let user = makeUser()
        let taskID = UUID()
        let initialState = makeRemoteState(
            familyName: "Casa Aurora",
            tasks: [
                TaskItem(
                    id: taskID,
                    title: "Pagar o boleto",
                    subtitle: "",
                    owner: "Casa",
                    dueLabel: "Hoje",
                    category: .bills,
                    isDone: false,
                    createdBy: "Manual"
                )
            ]
        )
        let backend = ControlledRefreshHomeBackend(initialState: initialState)
        let store = AppStore(
            defaults: defaults,
            privateDataStore: privateDataStore,
            remoteHomeBackend: backend,
            ninaEngine: MockNinaEngine(),
            notificationScheduler: NoopHomeNotificationScheduler()
        )
        await store.activateHomeContext(for: user)
        let householdScope = PrivateLocalDataScope.household(for: user.id)
        let homeKey = "nina.home.familyGroup.\(user.id)"
        XCTAssertNotNil(try privateDataStore.data(forKey: homeKey, ownerScope: householdScope))

        let refreshTask = Task {
            await store.refreshHomeFromRemote(for: user)
        }
        await backend.waitUntilRefreshStarted()

        store.toggleTask(try XCTUnwrap(store.tasks.first(where: { $0.id == taskID })))
        await backend.completeRefreshWithoutHome()
        await refreshTask.value
        await store.waitForPendingRemoteMutations()

        XCTAssertEqual(store.homeAccessState, .noHome)
        XCTAssertFalse(store.hasActiveHome)
        XCTAssertNotEqual(store.familyGroup.name, "Casa Aurora")
        XCTAssertFalse(store.tasks.contains { $0.id == taskID })
        XCTAssertEqual(
            store.syncErrorMessage,
            "Você não faz mais parte desta casa. O que você mudou agora não foi salvo."
        )
        XCTAssertNil(try privateDataStore.data(forKey: homeKey, ownerScope: householdScope))
    }

    @MainActor
    func testADeclinedRemovalReachesTheMemberWhoKeptEditingDuringTheRefresh() async {
        let user = makeUser()
        let decision = makeAccessDecision(outcome: .removed)
        let initialState = makeRemoteState(familyName: "Casa Aurora")
        let backend = ControlledRefreshHomeBackend(
            initialState: initialState,
            accessDecision: decision
        )
        let store = AppStore(remoteHomeBackend: backend, ninaEngine: MockNinaEngine())
        await store.activateHomeContext(for: user)

        let refreshTask = Task {
            await store.refreshHomeFromRemote(for: user)
        }
        await backend.waitUntilRefreshStarted()

        store.addShoppingItem(title: "Café", amount: "1", owner: "Casa")
        await backend.completeRefreshWithoutHome()
        await refreshTask.value
        await store.waitForPendingRemoteMutations()

        XCTAssertEqual(store.homeAccessState, .accessDecision)
        XCTAssertEqual(store.familyAccessDecision, decision)
        XCTAssertFalse(store.hasActiveHome)
        XCTAssertFalse(store.shoppingItems.contains { $0.title == "Café" })
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
    func testAnArchivedTaskNeverComesBackOnTheNextRefresh() async {
        let user = makeUser()
        let openTaskID = UUID()
        let archivedTaskID = UUID()
        let initialState = makeRemoteState(
            tasks: [
                TaskItem(
                    id: openTaskID,
                    title: "Pagar o boleto",
                    subtitle: "",
                    owner: "Casa",
                    dueLabel: "Hoje",
                    category: .home,
                    isDone: false,
                    createdBy: "Manual"
                ),
                TaskItem(
                    id: archivedTaskID,
                    title: "Trocar o filtro",
                    subtitle: "",
                    owner: "Casa",
                    dueLabel: "Sem data",
                    category: .home,
                    isDone: true,
                    completedAt: Date(timeIntervalSinceNow: -40 * 24 * 60 * 60),
                    createdBy: "Manual"
                )
            ]
        )
        let refreshedState = makeRemoteState(
            tasks: [
                TaskItem(
                    id: openTaskID,
                    title: "Pagar o boleto",
                    subtitle: "",
                    owner: "Casa",
                    dueLabel: "Hoje",
                    category: .home,
                    isDone: false,
                    createdBy: "Manual"
                )
            ]
        )
        let backend = ControlledRefreshHomeBackend(initialState: initialState)
        let store = AppStore(remoteHomeBackend: backend, ninaEngine: MockNinaEngine())
        await store.activateHomeContext(for: user)

        XCTAssertEqual(store.tasks.count, 2)

        let refreshTask = Task {
            await store.refreshHomeFromRemote(for: user)
        }
        await backend.waitUntilRefreshStarted()
        await backend.completeRefresh(with: refreshedState)
        await refreshTask.value

        XCTAssertEqual(store.tasks.map(\.id), [openTaskID])
        XCTAssertTrue(store.completedTasks.isEmpty)
        XCTAssertTrue(store.completedTasks(in: TaskSectionDefaults.houseTasksID).isEmpty)
    }

    @MainActor
    func testTheOldestVisibleCompletionSitsAtTheBottomOfTheCompletedList() async {
        let user = makeUser()
        let oldestID = UUID()
        let newestID = UUID()
        let justCompletedID = UUID()
        let state = makeRemoteState(
            tasks: [
                completedTask(
                    id: oldestID,
                    title: "Levar o cachorro ao veterinário",
                    completedAt: Date(timeIntervalSinceNow: -28 * 24 * 60 * 60)
                ),
                completedTask(
                    id: justCompletedID,
                    title: "Comprar o gás",
                    completedAt: nil
                ),
                completedTask(
                    id: newestID,
                    title: "Pagar a escola",
                    completedAt: Date(timeIntervalSinceNow: -2 * 24 * 60 * 60)
                )
            ]
        )
        let backend = ControlledRefreshHomeBackend(initialState: state)
        let store = AppStore(remoteHomeBackend: backend, ninaEngine: MockNinaEngine())
        await store.activateHomeContext(for: user)

        let completed = store.completedTasks(in: TaskSectionDefaults.houseTasksID)

        XCTAssertEqual(completed.map(\.id), [justCompletedID, newestID, oldestID])
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
        XCTAssertFalse(message.hasWithheldProposals)
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

    func testTaskSchedulingFieldsRoundTrip() throws {
        let dueAt = Date(timeIntervalSince1970: 1_781_600_400)
        let task = TaskItem(
            title: "Pay bill",
            subtitle: "",
            owner: "Casa",
            dueLabel: "Tomorrow",
            dueAt: dueAt,
            category: .bills,
            recurrence: .weekly,
            snoozedUntil: dueAt.addingTimeInterval(900),
            isDone: false,
            createdBy: "Nina"
        )

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let decodedTask = try decoder.decode(TaskItem.self, from: encoder.encode(task))

        XCTAssertEqual(decodedTask.dueAt, dueAt)
        XCTAssertEqual(decodedTask.recurrence, .weekly)
        XCTAssertEqual(decodedTask.snoozedUntil, dueAt.addingTimeInterval(900))
    }

    func testRecurringTaskKeepsCurrentOccurrenceUntilCompletionAndCanBecomeOverdue() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Sao_Paulo"))
        let baseDate = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 6, day: 18, hour: 9, minute: 30))
        )
        let referenceDate = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 6, day: 18, hour: 10))
        )

        let recurring = TaskItem(
            title: "Medicine",
            subtitle: "",
            owner: "Casa",
            dueLabel: "09:30",
            dueAt: baseDate,
            category: .health,
            recurrence: .daily,
            isDone: false,
            createdBy: "Nina"
        )
        let oneShot = TaskItem(
            title: "Document",
            subtitle: "",
            owner: "Casa",
            dueLabel: "15 Jun",
            dueAt: baseDate,
            category: .school,
            isDone: false,
            createdBy: "Nina"
        )

        let nextDate = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 6, day: 19, hour: 9, minute: 30))
        )
        XCTAssertEqual(
            recurring.displayDate(relativeTo: referenceDate, calendar: calendar),
            baseDate
        )
        XCTAssertTrue(recurring.isDue(on: referenceDate, calendar: calendar))
        XCTAssertTrue(recurring.isOverdue(relativeTo: referenceDate))
        XCTAssertTrue(oneShot.isOverdue(relativeTo: referenceDate))
        XCTAssertEqual(
            recurring.scheduledOccurrence(after: referenceDate, calendar: calendar),
            nextDate
        )
    }

    func testTaskDueDayUsesTheProvidedCalendarAndSnoozeOverridesOriginalDate() throws {
        var saoPaulo = Calendar(identifier: .gregorian)
        saoPaulo.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Sao_Paulo"))
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))

        let dueAt = try XCTUnwrap(
            saoPaulo.date(from: DateComponents(year: 2026, month: 6, day: 21, hour: 23, minute: 30))
        )
        let sunday = try XCTUnwrap(
            saoPaulo.date(from: DateComponents(year: 2026, month: 6, day: 21, hour: 12))
        )
        let monday = try XCTUnwrap(
            saoPaulo.date(from: DateComponents(year: 2026, month: 6, day: 22, hour: 12))
        )
        var task = TaskItem(
            title: "Late task",
            subtitle: "",
            owner: "Casa",
            dueLabel: "Hoje",
            dueAt: dueAt,
            category: .home,
            isDone: false,
            createdBy: "Manual"
        )

        XCTAssertTrue(task.isDue(on: sunday, calendar: saoPaulo))
        XCTAssertFalse(task.isDue(on: sunday, calendar: utc))
        XCTAssertEqual(
            AppStore.taskDueLabel(
                for: dueAt,
                relativeTo: sunday,
                calendar: saoPaulo
            ),
            "Hoje, 23:30"
        )
        XCTAssertFalse(
            AppStore.taskDueLabel(
                for: dueAt,
                relativeTo: monday,
                calendar: saoPaulo
            ).contains("Hoje")
        )

        task.snoozedUntil = monday
        XCTAssertFalse(task.isDue(on: sunday, calendar: saoPaulo))
        XCTAssertTrue(task.isDue(on: monday, calendar: saoPaulo))
        XCTAssertEqual(task.displayDate(relativeTo: sunday, calendar: saoPaulo), monday)
    }

    func testDailyRecurrencePreservesLocalWallClockAcrossDaylightSavingTime() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let dueAt = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 3, day: 7, hour: 9))
        )
        let referenceDate = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 3, day: 7, hour: 10))
        )
        let task = TaskItem(
            title: "Daily task",
            subtitle: "",
            owner: "Casa",
            dueLabel: "09:00",
            dueAt: dueAt,
            category: .home,
            recurrence: .daily,
            isDone: false,
            createdBy: "Manual"
        )

        let nextDate = try XCTUnwrap(
            task.scheduledOccurrence(after: referenceDate, calendar: calendar)
        )
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: nextDate)

        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 3)
        XCTAssertEqual(components.day, 8)
        XCTAssertEqual(components.hour, 9)
        XCTAssertEqual(components.minute, 0)
    }

    @MainActor
    func testCompletingRecurringTaskAdvancesItInsteadOfClosingIt() async throws {
        let dueAt = Date(timeIntervalSinceNow: 3_600)
        let task = TaskItem(
            title: "Medicine",
            subtitle: "",
            owner: "Casa",
            dueLabel: "Hoje",
            dueAt: dueAt,
            category: .health,
            recurrence: .daily,
            isDone: false,
            createdBy: "Manual"
        )
        let store = AppStore(
            remoteHomeBackend: RecordingHomeBackend(state: makeRemoteState(tasks: [task])),
            ninaEngine: MockNinaEngine(),
            notificationScheduler: RecordingNotificationScheduler()
        )
        await store.activateHomeContext(for: makeUser())

        store.toggleTask(task)

        let updated = try XCTUnwrap(store.tasks.first(where: { $0.id == task.id }))
        XCTAssertFalse(updated.isDone)
        XCTAssertEqual(updated.recurrence, .daily)
        XCTAssertGreaterThan(updated.dueAt ?? .distantPast, dueAt)
    }

    @MainActor
    func testUnifiedTaskCreateUpdateSnoozeAndDeletePersistRemotely() async throws {
        let user = makeUser()
        let backend = RecordingHomeBackend(state: makeRemoteState(tasks: []))
        let store = AppStore(
            remoteHomeBackend: backend,
            ninaEngine: MockNinaEngine(),
            notificationScheduler: RecordingNotificationScheduler()
        )
        await store.activateHomeContext(for: user)

        let dueAt = Date(timeIntervalSinceNow: 3_600)
        store.addTask(
            title: "School document",
            subtitle: "Put it in the backpack",
            owner: "Casa",
            dueLabel: "Hoje",
            dueAt: dueAt,
            category: .school,
            recurrence: .weekly
        )
        let taskID = try XCTUnwrap(store.tasks.first?.id)

        store.updateTask(
            id: taskID,
            title: "Updated document",
            subtitle: "",
            owner: "Casa",
            dueLabel: "Amanhã",
            dueAt: dueAt.addingTimeInterval(3_600),
            category: .school,
            priority: .high,
            recurrence: .monthly
        )
        store.snoozeTask(taskID, until: dueAt.addingTimeInterval(7_200))
        store.deleteTask(taskID)

        var mutations: [RecordedHomeMutation] = []
        for _ in 0..<80 {
            mutations = await backend.recordedMutations()
            if mutations.count >= 4 { break }
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertEqual(
            mutations,
            [
                .createTask(taskID),
                .updateTask(taskID),
                .updateTask(taskID),
                .deleteTask(taskID)
            ]
        )
        XCTAssertFalse(store.tasks.contains(where: { $0.id == taskID }))
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

    @MainActor
    func testLatestNotificationSnapshotWinsWhenAnEarlierSyncIsSlower() async throws {
        let user = makeUser()
        let scheduler = DelayedNotificationScheduler()
        let store = AppStore(
            remoteHomeBackend: RecordingHomeBackend(state: makeRemoteState(tasks: [])),
            ninaEngine: MockNinaEngine(),
            notificationScheduler: scheduler
        )
        await store.activateHomeContext(for: user)

        store.addTask(
            title: "Temporary reminder",
            subtitle: "",
            owner: "Casa",
            dueLabel: "Hoje",
            dueAt: Date(timeIntervalSinceNow: 3_600),
            category: .home
        )
        let taskID = try XCTUnwrap(store.tasks.first?.id)
        await scheduler.waitForNonemptySyncToStart()
        store.deleteTask(taskID)

        var records: [NotificationSyncRecord] = []
        for _ in 0..<80 {
            records = await scheduler.records()
            if records.contains(where: { !$0.tasks.isEmpty }),
               records.last?.tasks.isEmpty == true {
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertGreaterThanOrEqual(records.count, 2)
        XCTAssertTrue(records.contains(where: { !$0.tasks.isEmpty }))
        XCTAssertTrue(try XCTUnwrap(records.last).tasks.isEmpty)
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

        await store.grantAIMemoryConsent()
        XCTAssertTrue(store.hasAIMemoryConsent)
        XCTAssertTrue(store.canSendNinaMessages)

        await store.sendMessage("Depois do consentimento")
        XCTAssertEqual(store.messages.count, initialCount + 2)
    }

    func testTheServerCodeForAMissingAIConsentGetsItsOwnEngineError() {
        XCTAssertEqual(NinaEngineError(code: "ai_consent_required"), .aiConsentRequired)
        XCTAssertNotEqual(NinaEngineError(code: "ai_consent_required"), .unavailable)
        XCTAssertTrue(NinaEngineError.aiConsentRequired.userMessage.contains("consentimento"))
        XCTAssertFalse(NinaEngineError.aiConsentRequired.userMessage.contains("!"))
    }

    func testTheConsentBlockDecodesTheShapeGetCurrentHomeContextReturns() throws {
        let json = """
        {"is_granted":true,"policy_version":"2026-06-16","accepted_at":"2026-08-01T12:00:00Z"}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let consent = try decoder.decode(NinaAIConsent.self, from: Data(json.utf8))

        XCTAssertTrue(consent.isGranted)
        XCTAssertEqual(consent.policyVersion, "2026-06-16")
        XCTAssertEqual(consent.acceptedAt?.timeIntervalSince1970, 1_785_585_600)
    }

    func testAConsentBlockThatTheServerOmitsEntirelyReadsAsWithheld() throws {
        let consent = try JSONDecoder().decode(NinaAIConsent.self, from: Data("{}".utf8))

        XCTAssertFalse(consent.isGranted)
        XCTAssertNil(consent.policyVersion)
        XCTAssertNil(consent.acceptedAt)
    }

    @MainActor
    func testGrantingConsentReachesTheServerInsteadOfStayingOnTheDevice() async {
        let user = makeUser()
        let backend = RecordingHomeBackend(state: makeRemoteState())
        let store = AppStore(remoteHomeBackend: backend, ninaEngine: MockNinaEngine())
        await store.activateHomeContext(for: user)
        XCTAssertFalse(store.hasAIMemoryConsent)

        let didGrant = await store.grantAIMemoryConsent()
        let mutations = await backend.recordedMutations()

        XCTAssertTrue(didGrant)
        XCTAssertTrue(mutations.contains(.recordNinaAIConsent(true)))
        XCTAssertTrue(store.hasAIMemoryConsent)
        XCTAssertEqual(store.aiMemoryConsent?.policyVersion, PrivacyPolicyVersion.current)
        XCTAssertNil(store.syncErrorMessage)
    }

    @MainActor
    func testRevokingConsentReachesTheServerInsteadOfStayingOnTheDevice() async {
        let user = makeUser()
        let backend = RecordingHomeBackend(
            state: makeRemoteState(
                aiConsent: NinaAIConsent(
                    isGranted: true,
                    policyVersion: PrivacyPolicyVersion.current,
                    acceptedAt: Date(timeIntervalSince1970: 1_785_585_600)
                )
            )
        )
        let store = AppStore(remoteHomeBackend: backend, ninaEngine: MockNinaEngine())
        await store.activateHomeContext(for: user)
        XCTAssertTrue(store.hasAIMemoryConsent)

        let didRevoke = await store.revokeAIMemoryConsent()
        let mutations = await backend.recordedMutations()

        XCTAssertTrue(didRevoke)
        XCTAssertTrue(mutations.contains(.recordNinaAIConsent(false)))
        XCTAssertFalse(store.hasAIMemoryConsent)
        XCTAssertNil(store.syncErrorMessage)
    }

    @MainActor
    func testAFailedRevokeLeavesTheConsentThatIsStillLiveOnTheServer() async {
        let user = makeUser()
        let backend = RecordingHomeBackend(
            state: makeRemoteState(
                aiConsent: NinaAIConsent(
                    isGranted: true,
                    policyVersion: PrivacyPolicyVersion.current,
                    acceptedAt: Date(timeIntervalSince1970: 1_785_585_600)
                )
            )
        )
        let store = AppStore(remoteHomeBackend: backend, ninaEngine: MockNinaEngine())
        await store.activateHomeContext(for: user)
        await backend.setConsentWriteFails(true)

        let didRevoke = await store.revokeAIMemoryConsent()

        XCTAssertFalse(didRevoke)
        XCTAssertTrue(store.hasAIMemoryConsent)
        XCTAssertEqual(
            store.syncErrorMessage,
            "Não foi possível revogar seu consentimento. Ele continua ativo nesta casa."
        )
    }

    @MainActor
    func testAFailedGrantNeverUnlocksTheConversationTheServerStillRefuses() async {
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
        let store = AppStore(remoteHomeBackend: backend, ninaEngine: MockNinaEngine())
        await store.activateHomeContext(for: user)
        await backend.setConsentWriteFails(true)

        let didGrant = await store.grantAIMemoryConsent()

        XCTAssertFalse(didGrant)
        XCTAssertFalse(store.hasAIMemoryConsent)
        XCTAssertFalse(store.canSendNinaMessages)
        XCTAssertEqual(
            store.syncErrorMessage,
            "Não foi possível registrar seu consentimento. Nada mudou por enquanto."
        )
    }

    @MainActor
    func testTheHomeContextIsTheSourceOfTruthForConsentAfterARefresh() async {
        let user = makeUser()
        let backend = RecordingHomeBackend(
            state: makeRemoteState(
                aiConsent: NinaAIConsent(
                    isGranted: true,
                    policyVersion: PrivacyPolicyVersion.current,
                    acceptedAt: Date(timeIntervalSince1970: 1_785_585_600)
                )
            )
        )
        let store = AppStore(remoteHomeBackend: backend, ninaEngine: MockNinaEngine())

        await store.activateHomeContext(for: user)
        XCTAssertTrue(store.hasAIMemoryConsent)

        await backend.setAIConsent(.withheld)
        await store.refreshHomeFromRemote(for: user)

        XCTAssertFalse(store.hasAIMemoryConsent)
        let mutations = await backend.recordedMutations()
        XCTAssertFalse(mutations.contains(.recordNinaAIConsent(false)))
    }

    @MainActor
    func testPrivacyExportIncludesConsentAndSnapshot() async throws {
        let suiteName = "AppStoreAuthorizationTests.\(#function).\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "nina-app-store-tests-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let privateDataStore = ProtectedLocalDataStore(directoryURL: directory)

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
            privateDataStore: privateDataStore,
            remoteHomeBackend: RecordingHomeBackend(
                state: makeRemoteState(tasks: [task], members: [adultMember])
            ),
            ninaEngine: MockNinaEngine()
        )
        await store.activateHomeContext(for: user)
        await store.grantAIMemoryConsent()

        var profile = UserProfile.default(for: user)
        profile.phone = "+55 11 99999-0000"
        let profilePhotoData = Data([0xFF, 0xD8, 0xFF, 0xD9])
        let data = try store.makePrivacyExportData(
            profile: profile,
            profilePhotoData: profilePhotoData
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let export = try decoder.decode(PrivacyExportPackage.self, from: data)

        XCTAssertEqual(export.policyVersion, PrivacyPolicyVersion.current)
        XCTAssertEqual(export.user?.id, user.id)
        XCTAssertEqual(export.profile, profile)
        XCTAssertEqual(export.profilePhotoData, profilePhotoData)
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
        await store.grantAIMemoryConsent()

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
    func testAServerRecordedTurnDropsTheLegacySuggestionSoOnlyItsProposalConfirms() async {
        let store = await makeStoreForServerRecordedTurn()

        await store.sendMessage("Marque o veterinário do Thor")

        XCTAssertNil(store.messages.last?.suggestion)
    }

    @MainActor
    func testTheLegacyPathCreatesNothingForATurnTheServerAlreadyRecordedAProposalFor() async {
        let store = await makeStoreForServerRecordedTurn()
        await store.sendMessage("Marque o veterinário do Thor")
        let tasksAfterTurn = store.tasks
        let messagesAfterTurn = store.messages

        store.applySuggestion(Self.legacySuggestion)

        XCTAssertEqual(store.tasks, tasksAfterTurn)
        XCTAssertEqual(store.messages, messagesAfterTurn)
    }

    @MainActor
    func testALocalNinaTurnKeepsTheSuggestionItAloneHasNoProposalFor() async throws {
        let store = AppStore(remoteHomeBackend: nil, ninaEngine: MockNinaEngine())
        await store.sendMessage("Marcar veterinário do Thor")
        let suggestion = try XCTUnwrap(store.messages.last?.suggestion)
        let taskCountAfterTurn = store.tasks.count

        store.applySuggestion(suggestion)

        XCTAssertEqual(store.tasks.count, taskCountAfterTurn + 1)
    }

    @MainActor
    func testConfirmingASuggestionTwiceCreatesOneThingAndNotTwo() async throws {
        let store = AppStore(remoteHomeBackend: nil, ninaEngine: MockNinaEngine())
        await store.sendMessage("Marcar veterinário do Thor")
        let suggestion = try XCTUnwrap(store.messages.last?.suggestion)
        let taskCountAfterTurn = store.tasks.count

        store.applySuggestion(suggestion)
        store.applySuggestion(suggestion)

        // The card stayed live after being confirmed, so every extra tap made
        // another copy of the same thing.
        XCTAssertEqual(store.tasks.count, taskCountAfterTurn + 1)
        XCTAssertFalse(store.messages.contains { $0.suggestion == suggestion })
    }

    func testProposalsAreDiscardedWhileTheAIFlagIsOff() {
        let pending = makeProposal(kind: .task)

        XCTAssertTrue(NinaProposalGate(isV2Enabled: false).visibleProposals([pending]).isEmpty)
        XCTAssertEqual(NinaProposalGate(isV2Enabled: true).visibleProposals([pending]), [pending])
    }

    func testATurnWhosePendingProposalsWereDiscardedSaysSoInsteadOfLookingEmpty() {
        let pending = makeProposal(kind: .task)
        var resolved = makeProposal(kind: .task)
        resolved.state = .accepted

        XCTAssertTrue(NinaProposalGate(isV2Enabled: false).withholdsProposals([pending]))
        XCTAssertFalse(NinaProposalGate(isV2Enabled: false).withholdsProposals([resolved]))
        XCTAssertFalse(NinaProposalGate(isV2Enabled: false).withholdsProposals([]))
        XCTAssertFalse(NinaProposalGate(isV2Enabled: true).withholdsProposals([pending]))
    }

    func testACachedTurnRemembersThatItsProposalsWereWithheld() throws {
        let message = ChatMessage(
            sender: .nina,
            text: "Preparei uma proposta.",
            timestamp: Date(timeIntervalSince1970: 1_785_639_600),
            hasWithheldProposals: true
        )

        let encoded = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ChatMessage.self, from: encoded)

        XCTAssertTrue(decoded.hasWithheldProposals)
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
    func testConfirmingAProposalCreatesTheWordingTheCardShowedAndNotNinasFraming() async {
        let user = makeUser()
        let backend = RecordingHomeBackend(state: makeRemoteState())
        let store = AppStore(remoteHomeBackend: backend, ninaEngine: MockNinaEngine())
        await store.activateHomeContext(for: user)
        let proposal = NinaProposal(
            kind: .task,
            title: "Anotei o boleto da luz",
            detail: "Chegou hoje no seu nome",
            actionTitle: "Criar tarefa",
            payload: NinaProposalPayload(
                title: "Pagar o boleto da Enel",
                detail: "Vence sexta",
                owner: "Heitor",
                dueLabel: "sexta, 09:00",
                dueAt: "2026-08-14T12:00:00Z"
            )
        )
        store.messages = [
            ChatMessage(sender: .nina, text: "Confirme", timestamp: .now, proposals: [proposal])
        ]

        let shown = proposal.confirmationPayload
        let didAccept = await store.resolveProposal(
            proposal,
            decision: .accept,
            editedPayload: shown
        )
        let confirmed = await backend.confirmedPayload(for: proposal.id)

        XCTAssertTrue(didAccept)
        XCTAssertEqual(shown.title, "Pagar o boleto da Enel")
        XCTAssertEqual(confirmed?.title, shown.title)
        XCTAssertEqual(confirmed?.detail, shown.detail)
        XCTAssertNotEqual(confirmed?.title, proposal.title)
    }

    @MainActor
    func testAProposalCachedByAnOlderBuildWithoutABasisStillConfirms() async throws {
        let user = makeUser()
        let backend = RecordingHomeBackend(state: makeRemoteState())
        let store = AppStore(remoteHomeBackend: backend, ninaEngine: MockNinaEngine())
        await store.activateHomeContext(for: user)
        let cached = """
        {"id":"7A2C0000-0000-4000-8000-00000000000A","kind":"task","state":"pending",
         "title":"Anotei o boleto da luz","detail":"Chegou hoje","action_title":"Criar tarefa",
         "payload":{"title":"Pagar o boleto da Enel","detail":"Vence sexta","owner":"Heitor",
         "due_label":"sexta, 09:00","due_at":"2026-08-14T12:00:00Z","category":"bills"}}
        """
        let proposal = try JSONDecoder().decode(NinaProposal.self, from: Data(cached.utf8))
        store.messages = [
            ChatMessage(sender: .nina, text: "Confirme", timestamp: .now, proposals: [proposal])
        ]

        let shown = proposal.confirmationPayload
        let didAccept = await store.resolveProposal(
            proposal,
            decision: .accept,
            editedPayload: shown
        )
        let confirmed = await backend.confirmedPayload(for: proposal.id)

        XCTAssertTrue(didAccept)
        XCTAssertTrue(shown.rationale.isEmpty)
        XCTAssertNil(shown.source)
        XCTAssertEqual(confirmed?.title, "Pagar o boleto da Enel")
        XCTAssertEqual(confirmed?.owner, "Heitor")
        XCTAssertEqual(confirmed?.dueLabel, "sexta, 09:00")
        XCTAssertTrue(confirmed?.rationale.isEmpty ?? false)
        XCTAssertNil(confirmed?.source)
    }

    @MainActor
    func testConfirmingAProposalCarriesTheBasisItWasShownWith() async {
        let user = makeUser()
        let backend = RecordingHomeBackend(state: makeRemoteState())
        let store = AppStore(remoteHomeBackend: backend, ninaEngine: MockNinaEngine())
        await store.activateHomeContext(for: user)
        let proposal = NinaProposal(
            kind: .task,
            title: "Anotei o boleto da luz",
            detail: "Chegou hoje",
            actionTitle: "Criar tarefa",
            payload: NinaProposalPayload(
                title: "Pagar o boleto da Enel",
                detail: "Vence sexta",
                owner: "Heitor",
                dueLabel: "sexta, 09:00",
                dueAt: "2026-08-14T12:00:00Z",
                rationale: "Vencimento que li na foto",
                source: .attachment,
                confidence: 0.42
            )
        )

        let shown = proposal.confirmationPayload
        _ = await store.resolveProposal(proposal, decision: .accept, editedPayload: shown)
        let confirmed = await backend.confirmedPayload(for: proposal.id)

        XCTAssertEqual(confirmed?.source, .attachment)
        XCTAssertEqual(confirmed?.rationale, "Vencimento que li na foto")
        XCTAssertFalse(confirmed?.title.contains("42") ?? true)
        XCTAssertFalse(confirmed?.detail.contains("42") ?? true)
        XCTAssertFalse(confirmed?.rationale.contains("42") ?? true)
    }

    @MainActor
    func testAProposalWithoutPayloadWordingConfirmsTheHeadlineTheCardShowed() async {
        let user = makeUser()
        let backend = RecordingHomeBackend(state: makeRemoteState())
        let store = AppStore(remoteHomeBackend: backend, ninaEngine: MockNinaEngine())
        await store.activateHomeContext(for: user)
        let proposal = NinaProposal(
            kind: .task,
            title: "Levar o Thor ao veterinário",
            detail: "A vacina anual venceu",
            actionTitle: "Criar tarefa",
            payload: NinaProposalPayload(title: "   ", detail: "")
        )

        let shown = proposal.confirmationPayload
        _ = await store.resolveProposal(proposal, decision: .accept, editedPayload: shown)
        let confirmed = await backend.confirmedPayload(for: proposal.id)

        XCTAssertEqual(shown.title, "Levar o Thor ao veterinário")
        XCTAssertEqual(shown.detail, "A vacina anual venceu")
        XCTAssertEqual(confirmed?.title, shown.title)
        XCTAssertEqual(confirmed?.detail, shown.detail)
    }

    @MainActor
    func testAProposalWithoutADateConfirmsUndatedWithTheHouseCarryingIt() async {
        let user = makeUser()
        let backend = RecordingHomeBackend(state: makeRemoteState())
        let store = AppStore(remoteHomeBackend: backend, ninaEngine: MockNinaEngine())
        await store.activateHomeContext(for: user)
        let proposal = NinaProposal(
            kind: .task,
            title: "Trocar a lâmpada da varanda",
            detail: "Sem pressa",
            actionTitle: "Criar tarefa",
            payload: NinaProposalPayload(
                title: "Trocar a lâmpada da varanda",
                detail: "Sem pressa",
                owner: "  ",
                dueLabel: "",
                dueAt: nil
            )
        )

        let shown = proposal.confirmationPayload
        _ = await store.resolveProposal(proposal, decision: .accept, editedPayload: shown)
        let confirmed = await backend.confirmedPayload(for: proposal.id)

        XCTAssertEqual(shown.owner, "Casa")
        XCTAssertEqual(shown.dueLabel, "Sem data")
        XCTAssertNil(shown.dueAt)
        XCTAssertEqual(confirmed?.owner, "Casa")
        XCTAssertEqual(confirmed?.dueLabel, "Sem data")
        XCTAssertNil(confirmed?.dueAt)
    }

    @MainActor
    func testConfirmingASeedProposalCarriesNoDateEvenWhenNinaProposedOne() async {
        let user = makeUser()
        let backend = RecordingHomeBackend(state: makeRemoteState())
        let store = AppStore(remoteHomeBackend: backend, ninaEngine: MockNinaEngine())
        await store.activateHomeContext(for: user)
        let proposal = NinaProposal(
            kind: .seed,
            title: "Guardar como semente",
            detail: "Ainda não há uma data clara",
            actionTitle: "Guardar semente",
            payload: NinaProposalPayload(
                title: "Organizar as fotos da família",
                detail: "Separar os melhores momentos do último ano",
                owner: "Casa",
                dueLabel: "sexta, 09:00",
                dueAt: "2026-08-14T12:00:00Z"
            )
        )

        let shown = proposal.confirmationPayload
        let didAccept = await store.resolveProposal(
            proposal,
            decision: .accept,
            editedPayload: shown
        )
        let confirmed = await backend.confirmedPayload(for: proposal.id)

        XCTAssertTrue(didAccept)
        XCTAssertEqual(shown.dueLabel, "Sem data")
        XCTAssertNil(shown.dueAt)
        XCTAssertEqual(confirmed?.title, "Organizar as fotos da família")
        XCTAssertEqual(confirmed?.dueLabel, "Sem data")
        XCTAssertNil(confirmed?.dueAt)
    }

    @MainActor
    func testTheSeedWordingTheProposalCardShowsIsTheSeedTheHouseStores() async throws {
        let user = makeUser()
        let store = AppStore(
            remoteHomeBackend: RecordingHomeBackend(state: makeRemoteState(tasks: [])),
            ninaEngine: MockNinaEngine(),
            notificationScheduler: RecordingNotificationScheduler()
        )
        await store.activateHomeContext(for: user)
        let proposal = NinaProposal(
            kind: .seed,
            title: "Guardar como semente",
            detail: "",
            actionTitle: "Guardar semente",
            payload: NinaProposalPayload(
                title: "Planejar a viagem de fim de ano",
                detail: "Sem pressa para escolher a data",
                dueLabel: "dezembro",
                dueAt: "2026-12-01T12:00:00Z"
            )
        )

        let shown = proposal.confirmationPayload
        store.addTask(
            title: shown.title,
            subtitle: shown.detail,
            owner: shown.owner,
            dueLabel: shown.dueLabel,
            category: shown.category,
            kind: .seed,
            createdBy: "Nina"
        )

        let stored = try XCTUnwrap(store.tasks.first(where: { $0.title == shown.title }))
        XCTAssertEqual(stored.kind, .seed)
        XCTAssertEqual(stored.kind.title, "Semente")
        XCTAssertEqual(stored.kind.symbolName, "leaf.fill")
        XCTAssertEqual(shown.dueLabel, stored.dueLabel)
        XCTAssertNil(shown.dueAt)
        XCTAssertNil(stored.dueAt)
        XCTAssertEqual(store.openSeeds, [stored])
    }

    @MainActor
    func testCorrectingAProposalConfirmsTheCorrectedOwnerQuantityAndDate() async {
        let user = makeUser()
        let backend = RecordingHomeBackend(state: makeRemoteState())
        let store = AppStore(remoteHomeBackend: backend, ninaEngine: MockNinaEngine())
        await store.activateHomeContext(for: user)
        let now = Date(timeIntervalSince1970: 1_786_000_000)
        let proposal = NinaProposal(
            kind: .shopping,
            title: "Arroz na lista",
            detail: "Acabou ontem",
            actionTitle: "Adicionar à lista",
            payload: NinaProposalPayload(
                title: "Arroz",
                detail: "Acabou ontem",
                owner: "Heitor",
                dueLabel: "amanhã",
                dueAt: "2026-08-11T12:00:00Z",
                amount: "1 pacote"
            )
        )

        let shown = proposal.confirmationPayload(
            title: "Arroz integral",
            detail: proposal.payload.detail,
            owner: "Mirna",
            dueLabel: "hoje",
            amount: "2 pacotes",
            now: now
        )
        _ = await store.resolveProposal(proposal, decision: .accept, editedPayload: shown)
        let confirmed = await backend.confirmedPayload(for: proposal.id)
        let expectedDueAt = AppStore.inferredDueAt(from: "hoje", now: now)
            .map(ISO8601DateFormatter().string(from:))

        XCTAssertEqual(confirmed?.title, "Arroz integral")
        XCTAssertEqual(confirmed?.owner, "Mirna")
        XCTAssertEqual(confirmed?.amount, "2 pacotes")
        XCTAssertEqual(confirmed?.dueLabel, "hoje")
        XCTAssertEqual(confirmed?.dueAt, expectedDueAt)
    }

    @MainActor
    func testConfirmingAMemoryCarriesOnlyTheVisibilityTheUserTapped() async {
        let user = makeUser()
        let backend = RecordingHomeBackend(state: makeRemoteState())
        let store = AppStore(remoteHomeBackend: backend, ninaEngine: MockNinaEngine())
        await store.activateHomeContext(for: user)
        let proposal = NinaProposal(
            kind: .memory,
            title: "Guardar uma preferência",
            detail: "Mirna prefere mercado de manhã",
            actionTitle: "Guardar",
            payload: NinaProposalPayload(
                title: "Compras de manhã",
                detail: "Mirna prefere ir ao mercado antes das 10h"
            ),
            allowedMemoryVisibilities: [.privateMemory, .shared]
        )

        let shown = proposal.confirmationPayload
        _ = await store.resolveProposal(
            proposal,
            decision: .accept,
            editedPayload: shown,
            memoryVisibility: .privateMemory
        )
        let confirmed = await backend.confirmedPayload(for: proposal.id)
        let visibility = await backend.confirmedMemoryVisibility(for: proposal.id)

        XCTAssertNil(shown.visibility)
        XCTAssertNil(confirmed?.visibility)
        XCTAssertEqual(visibility, .privateMemory)
        XCTAssertEqual(confirmed?.title, "Compras de manhã")
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

    func testTheRetainedThumbnailStaysReadableEnoughToCheckADocument() throws {
        let source = try XCTUnwrap(Self.densePhotograph(side: 2_400))

        let readable = try XCTUnwrap(ChatAttachmentLimits.retainedThumbnailData(for: source))
        let decoded = try XCTUnwrap(UIImage(data: readable))
        let longestSide = max(
            try XCTUnwrap(decoded.cgImage?.width),
            try XCTUnwrap(decoded.cgImage?.height)
        )

        XCTAssertLessThanOrEqual(readable.count, ChatAttachmentLimits.maxThumbnailBytes)
        XCTAssertGreaterThan(longestSide, 320)
        XCTAssertEqual(Array(readable.prefix(2)), [0xFF, 0xD8])
    }

    func testAnImageThatResistsCompressionNeverLandsOnDiskAboveTheCeiling() throws {
        let source = try XCTUnwrap(Self.densePhotograph(side: 900))

        let unbounded = try XCTUnwrap(source.jpegData(compressionQuality: 0.7))
        let retained = ChatAttachmentLimits.retainedThumbnailData(for: source)

        XCTAssertGreaterThan(unbounded.count, ChatAttachmentLimits.maxThumbnailBytes)
        XCTAssertLessThanOrEqual(retained?.count ?? 0, ChatAttachmentLimits.maxThumbnailBytes)
    }

    private static func densePhotograph(side: Int) -> UIImage? {
        let bytesPerRow = side * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * side)
        var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
        for index in pixels.indices {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            pixels[index] = UInt8(truncatingIfNeeded: seed >> 33)
        }

        let cgImage = pixels.withUnsafeMutableBytes { buffer -> CGImage? in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: side,
                height: side,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            ) else { return nil }
            return context.makeImage()
        }

        return cgImage.map(UIImage.init(cgImage:))
    }
    #endif

    @MainActor
    func testARefreshNoLongerLosesThePhotoTheUserJustSentToNina() async throws {
        let user = makeUser()
        let backend = RecordingHomeBackend(
            state: makeRemoteState(members: [adultMember(for: user)])
        )
        let store = AppStore(
            remoteHomeBackend: backend,
            ninaEngine: PersistedNinaEngine(assistantMessageID: UUID())
        )
        await store.activateHomeContext(for: user)
        await store.grantAIMemoryConsent()

        let thumbnail = Data("thumbnail-do-boleto".utf8)
        await store.sendMessage(
            "Segue o boleto da Enel",
            attachments: [
                NinaAttachmentInput(
                    metadata: ChatAttachment(
                        kind: .image,
                        filename: "foto-1.jpg",
                        mimeType: "image/jpeg",
                        byteCount: 412_000,
                        thumbnailData: thumbnail
                    ),
                    data: Data("boleto".utf8)
                )
            ]
        )
        let sentMessage = try XCTUnwrap(store.messages.last { $0.sender == .user })
        XCTAssertEqual(sentMessage.attachments.first?.thumbnailData, thumbnail)

        await backend.setHomeState(
            makeRemoteState(
                members: [adultMember(for: user)],
                messages: [
                    ChatMessage(
                        id: sentMessage.id,
                        sender: .user,
                        text: "Segue o boleto da Enel",
                        timestamp: sentMessage.timestamp,
                        attachments: [Self.serverAttachment(filename: "foto-1.jpg")]
                    )
                ]
            )
        )
        await store.refreshHomeFromRemote(for: user)

        let refreshed = try XCTUnwrap(store.messages.first { $0.id == sentMessage.id })
        XCTAssertEqual(refreshed.attachments.first?.thumbnailData, thumbnail)
        XCTAssertEqual(refreshed.attachments.first?.byteCount, 412_000)
    }

    @MainActor
    func testAnAccountSwitchNeverCarriesHouseholdImageryIntoTheNextConversation() async throws {
        let firstUser = makeUser()
        let secondUser = makeUser()
        let backend = RecordingHomeBackend(
            state: makeRemoteState(members: [adultMember(for: firstUser)])
        )
        let store = AppStore(
            remoteHomeBackend: backend,
            ninaEngine: PersistedNinaEngine(assistantMessageID: UUID())
        )
        await store.activateHomeContext(for: firstUser)
        await store.grantAIMemoryConsent()

        await store.sendMessage(
            "Segue a receita do Pedro",
            attachments: [
                NinaAttachmentInput(
                    metadata: ChatAttachment(
                        kind: .image,
                        filename: "foto-1.jpg",
                        mimeType: "image/jpeg",
                        byteCount: 240_000,
                        thumbnailData: Data("thumbnail-da-receita".utf8)
                    ),
                    data: Data("receita".utf8)
                )
            ]
        )
        let sentMessage = try XCTUnwrap(store.messages.last { $0.sender == .user })

        await backend.setHomeState(
            makeRemoteState(
                members: [adultMember(for: secondUser)],
                messages: [
                    ChatMessage(
                        id: sentMessage.id,
                        sender: .user,
                        text: "Segue a receita do Pedro",
                        timestamp: sentMessage.timestamp,
                        attachments: [Self.serverAttachment(filename: "foto-1.jpg")]
                    )
                ]
            )
        )
        await store.activateHomeContext(for: secondUser)

        let carried = try XCTUnwrap(store.messages.first { $0.id == sentMessage.id })
        XCTAssertNil(carried.attachments.first?.thumbnailData)
        XCTAssertTrue(store.messages.allSatisfy { message in
            message.attachments.allSatisfy { $0.thumbnailData == nil }
        })
    }

    @MainActor
    func testSigningOutDropsTheHouseholdImageryTheDeviceWasHolding() async throws {
        let user = makeUser()
        let backend = RecordingHomeBackend(
            state: makeRemoteState(members: [adultMember(for: user)])
        )
        let store = AppStore(
            remoteHomeBackend: backend,
            ninaEngine: PersistedNinaEngine(assistantMessageID: UUID())
        )
        await store.activateHomeContext(for: user)
        await store.grantAIMemoryConsent()

        await store.sendMessage(
            "Segue o comunicado da escola",
            attachments: [
                NinaAttachmentInput(
                    metadata: ChatAttachment(
                        kind: .image,
                        filename: "foto-1.jpg",
                        mimeType: "image/jpeg",
                        byteCount: 180_000,
                        thumbnailData: Data("thumbnail-do-comunicado".utf8)
                    ),
                    data: Data("comunicado".utf8)
                )
            ]
        )
        let sentMessage = try XCTUnwrap(store.messages.last { $0.sender == .user })

        await store.activateHomeContext(for: nil)
        XCTAssertTrue(store.messages.allSatisfy(\.attachments.isEmpty))

        await backend.setHomeState(
            makeRemoteState(
                members: [adultMember(for: user)],
                messages: [
                    ChatMessage(
                        id: sentMessage.id,
                        sender: .user,
                        text: "Segue o comunicado da escola",
                        timestamp: sentMessage.timestamp,
                        attachments: [Self.serverAttachment(filename: "foto-1.jpg")]
                    )
                ]
            )
        )
        await store.activateHomeContext(for: user)

        let restored = try XCTUnwrap(store.messages.first { $0.id == sentMessage.id })
        XCTAssertNil(restored.attachments.first?.thumbnailData)
    }

    func testTheHouseholdSnapshotOnDiskCarriesOnlyTheNewestDocumentImagery() {
        let imageCount = AppStore.maxLocallyCachedAttachmentImages + 5
        let messages = (0..<imageCount).map { index in
            ChatMessage(
                sender: .user,
                text: "Anexo \(index)",
                timestamp: Date(timeIntervalSince1970: 1_785_000_000 + Double(index)),
                attachments: [
                    ChatAttachment(
                        kind: .image,
                        filename: "foto-\(index).jpg",
                        mimeType: "image/jpeg",
                        byteCount: 300_000,
                        thumbnailData: Data("thumbnail-\(index)".utf8)
                    )
                ]
            )
        }
        let snapshot = AppDataSnapshot(
            messages: messages,
            taskSections: [],
            tasks: [],
            shoppingItems: [],
            insights: []
        )

        let bounded = AppStore.snapshotForLocalCache(snapshot)
        let kept = bounded.messages.filter { message in
            message.attachments.contains { $0.thumbnailData != nil }
        }

        XCTAssertEqual(kept.count, AppStore.maxLocallyCachedAttachmentImages)
        XCTAssertEqual(kept.map(\.text), messages.suffix(AppStore.maxLocallyCachedAttachmentImages).map(\.text))
        XCTAssertEqual(bounded.messages.count, messages.count)
        XCTAssertTrue(bounded.messages.allSatisfy { !$0.attachments.isEmpty })
    }

    private static func serverAttachment(filename: String) -> ChatAttachment {
        ChatAttachment(
            kind: .image,
            filename: filename,
            mimeType: "image/jpeg",
            byteCount: 412_000
        )
    }

    private func adultMember(for user: AuthUser) -> HouseholdMember {
        HouseholdMember(
            userID: user.id,
            name: user.displayName,
            relationship: "Você",
            role: .adult,
            tone: .mint,
            taskCount: 0,
            memoryNote: ""
        )
    }

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

    func testLegacyTaskDecodingDefaultsToRegularTaskKind() throws {
        let data = Data(
            """
            {
              "title": "Legacy task",
              "category": "home",
              "isDone": false,
              "createdBy": "Manual"
            }
            """.utf8
        )

        let task = try JSONDecoder().decode(TaskItem.self, from: data)

        XCTAssertEqual(task.kind, .task)
    }

    @MainActor
    func testSeedCreationStaysUnscheduledUntilPlanted() async throws {
        let user = makeUser()
        let store = AppStore(
            remoteHomeBackend: RecordingHomeBackend(state: makeRemoteState(tasks: [])),
            ninaEngine: MockNinaEngine(),
            notificationScheduler: RecordingNotificationScheduler()
        )
        await store.activateHomeContext(for: user)

        store.addTask(
            title: "Organize family photos",
            subtitle: "Someday",
            owner: "Casa",
            dueLabel: "Tomorrow",
            dueAt: Date(timeIntervalSinceNow: 3_600),
            category: .home,
            recurrence: .weekly,
            kind: .seed
        )

        let seed = try XCTUnwrap(store.tasks.first)
        XCTAssertEqual(seed.kind, .seed)
        XCTAssertEqual(seed.dueLabel, "Sem data")
        XCTAssertNil(seed.dueAt)
        XCTAssertEqual(seed.recurrence, .none)
        XCTAssertEqual(store.openSeeds, [seed])
    }

    @MainActor
    func testPlantingSeedTurnsItIntoScheduledTask() async throws {
        let user = makeUser()
        let seed = TaskItem(
            kind: .seed,
            title: "Plan family trip",
            subtitle: "",
            owner: "Casa",
            dueLabel: "Sem data",
            category: .home,
            isDone: false,
            createdBy: "Manual"
        )
        let store = AppStore(
            remoteHomeBackend: RecordingHomeBackend(state: makeRemoteState(tasks: [seed])),
            ninaEngine: MockNinaEngine(),
            notificationScheduler: RecordingNotificationScheduler()
        )
        await store.activateHomeContext(for: user)
        let dueAt = Date(timeIntervalSinceNow: 7_200)

        store.updateTask(
            id: seed.id,
            title: seed.title,
            subtitle: seed.subtitle,
            owner: seed.owner,
            dueLabel: "Hoje",
            dueAt: dueAt,
            category: seed.category,
            priority: seed.priority,
            recurrence: TaskRecurrence.none,
            kind: .task
        )

        let planted = try XCTUnwrap(store.tasks.first(where: { $0.id == seed.id }))
        XCTAssertEqual(planted.kind, .task)
        XCTAssertEqual(planted.dueAt, dueAt)
        XCTAssertTrue(store.openSeeds.isEmpty)
    }

    private func makeUser() -> AuthUser {
        AuthUser(
            id: UUID().uuidString,
            displayName: "Owner",
            email: "owner@example.com",
            provider: .apple
        )
    }

    private static let legacySuggestion = NinaSuggestion(
        title: "Veterinário do Thor",
        detail: "Marcar consulta e verificar carteira de vacinas.",
        actionTitle: "Criar tarefa",
        kind: .task,
        payloadTitle: "Marcar veterinário para o Thor",
        payloadDetail: "Conferir horários e carteira de vacinas.",
        payloadOwner: "Heitor",
        payloadDueLabel: "Esta semana",
        category: .pet,
        symbolName: "pawprint.fill"
    )

    @MainActor
    private func makeStoreForServerRecordedTurn() async -> AppStore {
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
            ninaEngine: PersistedNinaEngine(
                assistantMessageID: UUID(),
                suggestion: Self.legacySuggestion,
                proposals: [makeProposal(kind: .task)]
            )
        )
        await store.activateHomeContext(for: user)
        await store.grantAIMemoryConsent()
        return store
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

    private func completedTask(id: UUID, title: String, completedAt: Date?) -> TaskItem {
        TaskItem(
            id: id,
            title: title,
            subtitle: "",
            owner: "Casa",
            dueLabel: "Sem data",
            category: .home,
            isDone: true,
            completedAt: completedAt,
            createdBy: "Manual"
        )
    }

    private func makeAccessDecision(outcome: FamilyAccessOutcome) -> FamilyAccessDecision {
        FamilyAccessDecision(
            id: UUID(),
            familyName: "Casa Castello",
            outcome: outcome,
            decidedAt: Date(timeIntervalSince1970: 1_785_639_600)
        )
    }

    private func makeRemoteState(
        familyName: String = "Test Home",
        inviteCode: String = "test-home",
        permissionRole: FamilyPermissionRole = .owner,
        taskSections: [TaskSection] = PreviewData.taskSections,
        tasks: [TaskItem] = [],
        shoppingItems: [ShoppingItem] = [],
        members: [HouseholdMember] = [],
        messages: [ChatMessage] = [],
        aiConsent: NinaAIConsent = .withheld
    ) -> RemoteHomeState {
        RemoteHomeState(
            familyGroup: FamilyGroup(name: familyName, inviteCode: inviteCode, members: members),
            permissionRole: permissionRole,
            snapshot: AppDataSnapshot(
                messages: messages,
                taskSections: taskSections,
                tasks: tasks,
                shoppingItems: shoppingItems,
                insights: []
            ),
            aiConsent: aiConsent
        )
    }
}

private struct PersistedNinaEngine: NinaEngine {
    var assistantMessageID: UUID
    var suggestion: NinaSuggestion?
    var proposals: [NinaProposal] = []

    func respond(
        to text: String,
        attachments: [NinaAttachmentInput],
        familyID: UUID,
        messageID: UUID
    ) async throws -> NinaEngineResponse {
        NinaEngineResponse(
            reply: "Preparei uma proposta.",
            suggestion: suggestion,
            version: 2,
            runID: UUID(),
            threadID: UUID(),
            assistantMessageID: assistantMessageID,
            proposals: proposals,
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
    private let pendingRequest: FamilyJoinRequest?
    private var recordedCreateRequest: CreateRequest?
    private var recordedJoinRequest: JoinRequest?
    private var didSubmitJoinRequest = false

    init(
        createState: RemoteHomeState? = nil,
        joinState: RemoteHomeState? = nil,
        pendingRequest: FamilyJoinRequest? = nil,
        failCreate: Bool = false,
        failJoin: Bool = false
    ) {
        self.createState = createState
        self.joinState = joinState
        self.pendingRequest = pendingRequest
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

    func requestHomeAccess(
        with inviteCode: String,
        member: AuthUser?
    ) async throws -> FamilyJoinOutcome {
        recordedJoinRequest = JoinRequest(inviteCode: inviteCode, memberID: member?.id)
        guard !failJoin else { throw LifecycleError.expected }
        didSubmitJoinRequest = true
        if let pendingRequest {
            return .pending(pendingRequest)
        }
        guard let joinState else { throw LifecycleError.expected }
        return .joined(joinState)
    }

    func loadPendingJoinRequest() async throws -> FamilyJoinRequest? {
        didSubmitJoinRequest ? pendingRequest : nil
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
    func createChatMessage(_ message: ChatMessage, familyID: UUID, currentUser: AuthUser) async throws {}
}

private actor AccessDecisionBackend: RemoteHomeBackend {
    enum DecisionError: Error {
        case expected
    }

    private var decision: FamilyAccessDecision?
    private var acknowledgements: [UUID] = []

    init(decision: FamilyAccessDecision? = nil) {
        self.decision = decision
    }

    func acknowledgedDecisionIDs() -> [UUID] {
        acknowledgements
    }

    func loadHome(for user: AuthUser) async throws -> RemoteHomeState? {
        nil
    }

    func loadFamilyAccessDecision() async throws -> FamilyAccessDecision? {
        decision
    }

    func acknowledgeFamilyAccessDecision(_ decisionID: UUID) async throws {
        acknowledgements.append(decisionID)
        if decision?.id == decisionID {
            decision = nil
        }
    }

    func createHome(named name: String, owner: AuthUser?) async throws -> RemoteHomeState {
        throw DecisionError.expected
    }

    func joinHome(with inviteCode: String, member: AuthUser?) async throws -> RemoteHomeState {
        throw DecisionError.expected
    }

    func updateFamilySettings(
        familyID: UUID,
        name: String
    ) async throws -> RemoteHomeState {
        throw DecisionError.expected
    }

    func addUnclaimedMember(_ member: HouseholdMember, familyID: UUID) async throws -> RemoteHomeState {
        throw DecisionError.expected
    }

    func updateFamilyMember(_ member: HouseholdMember) async throws -> RemoteHomeState {
        throw DecisionError.expected
    }

    func createTaskSection(_ section: TaskSection, sortOrder: Int, familyID: UUID) async throws {}
    func createTaskCategory(_ category: TaskCategory, familyID: UUID) async throws {}
    func createTask(_ task: TaskItem, familyID: UUID, currentUser: AuthUser) async throws {}
    func updateTask(_ task: TaskItem, familyID: UUID) async throws {}
    func createShoppingItem(_ item: ShoppingItem, familyID: UUID, currentUser: AuthUser) async throws {}
    func updateShoppingItem(_ item: ShoppingItem, familyID: UUID) async throws {}
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
    func createChatMessage(_ message: ChatMessage, familyID: UUID, currentUser: AuthUser) async throws {}
}

private enum RecordedHomeMutation: Equatable {
    case createTaskSection(String)
    case deleteTaskSection(String)
    case createTaskCategory(String)
    case createTask(UUID)
    case updateTask(UUID)
    case deleteTask(UUID)
    case createShoppingItem(UUID)
    case updateShoppingItem(UUID)
    case createChatMessage(UUID)
    case resolveNinaProposal(UUID, NinaProposalDecision)
    case deleteNinaChatHistory(UUID)
    case recordNinaAIConsent(Bool)
}

private struct NotificationSyncRecord {
    var tasks: [TaskItem]
    var familyID: UUID
}

private actor RecordingNotificationScheduler: HomeNotificationScheduling {
    private var syncRecords: [NotificationSyncRecord] = []

    func synchronize(tasks: [TaskItem], familyID: UUID, viewer: HomeNotificationViewer) async {
        syncRecords.append(
            NotificationSyncRecord(
                tasks: tasks,
                familyID: familyID
            )
        )
    }

    func records() -> [NotificationSyncRecord] {
        syncRecords
    }
}

private actor DelayedNotificationScheduler: HomeNotificationScheduling {
    private var syncRecords: [NotificationSyncRecord] = []
    private var didStartNonemptySync = false
    private var nonemptySyncWaiters: [CheckedContinuation<Void, Never>] = []

    func synchronize(tasks: [TaskItem], familyID: UUID, viewer: HomeNotificationViewer) async {
        if tasks.isEmpty {
            try? await Task.sleep(for: .milliseconds(5))
        } else {
            didStartNonemptySync = true
            nonemptySyncWaiters.forEach { $0.resume() }
            nonemptySyncWaiters.removeAll()
            try? await Task.sleep(for: .milliseconds(100))
        }
        syncRecords.append(NotificationSyncRecord(tasks: tasks, familyID: familyID))
    }

    func waitForNonemptySyncToStart() async {
        guard !didStartNonemptySync else { return }
        await withCheckedContinuation { continuation in
            nonemptySyncWaiters.append(continuation)
        }
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
    private var consentWriteFails = false
    private var confirmedProposalPayloads: [UUID: NinaProposalPayload] = [:]
    private var confirmedMemoryVisibilities: [UUID: NinaMemoryVisibility] = [:]

    init(state: RemoteHomeState, conflictingTask: TaskItem? = nil) {
        self.state = state
        self.conflictingTask = conflictingTask
    }

    func recordedMutations() -> [RecordedHomeMutation] {
        mutations
    }

    func confirmedPayload(for proposalID: UUID) -> NinaProposalPayload? {
        confirmedProposalPayloads[proposalID]
    }

    func confirmedMemoryVisibility(for proposalID: UUID) -> NinaMemoryVisibility? {
        confirmedMemoryVisibilities[proposalID]
    }

    func setConsentWriteFails(_ shouldFail: Bool) {
        consentWriteFails = shouldFail
    }

    func setAIConsent(_ consent: NinaAIConsent) {
        state.aiConsent = consent
    }

    func setHomeState(_ state: RemoteHomeState) {
        self.state = state
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

    func deleteTaskSection(_ sectionID: String, familyID: UUID) async throws {
        mutations.append(.deleteTaskSection(sectionID))
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

    func deleteTask(_ taskID: UUID, familyID: UUID) async throws {
        mutations.append(.deleteTask(taskID))
    }

    func createShoppingItem(_ item: ShoppingItem, familyID: UUID, currentUser: AuthUser) async throws {
        mutations.append(.createShoppingItem(item.id))
    }

    func updateShoppingItem(_ item: ShoppingItem, familyID: UUID) async throws {
        mutations.append(.updateShoppingItem(item.id))
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
        confirmedProposalPayloads[proposalID] = editedPayload
        confirmedMemoryVisibilities[proposalID] = memoryVisibility
        return NinaProposalResolution(
            id: proposalID,
            state: decision == .accept ? .accepted : .rejected
        )
    }

    func deleteNinaChatHistory(familyID: UUID) async throws {
        mutations.append(.deleteNinaChatHistory(familyID))
    }

    func recordNinaAIConsent(granted: Bool, policyVersion: String) async throws -> RemoteHomeState {
        mutations.append(.recordNinaAIConsent(granted))
        if consentWriteFails {
            throw DiagnosticsTestError.expected
        }
        state.aiConsent = NinaAIConsent(
            isGranted: granted,
            policyVersion: granted ? policyVersion : nil,
            acceptedAt: granted ? Date(timeIntervalSince1970: 1_785_639_600) : nil
        )
        return state
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
    private let controlsInitialLoad: Bool
    private let accessDecision: FamilyAccessDecision?
    private var loadCount = 0
    private var refreshStarted = false
    private var refreshStartedContinuation: CheckedContinuation<Void, Never>?
    private var refreshContinuation: CheckedContinuation<RemoteHomeState?, Error>?

    init(
        initialState: RemoteHomeState,
        controlsInitialLoad: Bool = false,
        accessDecision: FamilyAccessDecision? = nil
    ) {
        self.initialState = initialState
        self.controlsInitialLoad = controlsInitialLoad
        self.accessDecision = accessDecision
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

    func completeRefreshWithoutHome() {
        refreshContinuation?.resume(returning: nil)
        refreshContinuation = nil
    }

    func failRefresh() {
        refreshContinuation?.resume(throwing: RefreshFailure())
        refreshContinuation = nil
    }

    func loadFamilyAccessDecision() async throws -> FamilyAccessDecision? {
        accessDecision
    }

    func loadHome(for user: AuthUser) async throws -> RemoteHomeState? {
        loadCount += 1
        if !controlsInitialLoad, loadCount == 1 {
            return initialState
        }

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
    func createChatMessage(_ message: ChatMessage, familyID: UUID, currentUser: AuthUser) async throws {}
}
