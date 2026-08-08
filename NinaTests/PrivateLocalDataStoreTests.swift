import Foundation
import XCTest
@testable import Nina

final class PrivateLocalDataStoreTests: XCTestCase {
    func testProtectedStoreUsesOpaqueProtectedBackupExcludedFiles() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("private", isDirectory: true)
        let store = ProtectedLocalDataStore(directoryURL: directory)
        let key = "nina.profile.metadata.sensitive-user-id"
        let scope = PrivateLocalDataScope.profile(for: "sensitive-user-id")
        let expected = Data("private household content".utf8)

        try store.set(expected, forKey: key, ownerScope: scope)

        XCTAssertEqual(try store.data(forKey: key, ownerScope: scope), expected)
        let files = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        let file = try XCTUnwrap(files.first(where: { $0.pathExtension == "data" }))
        XCTAssertEqual(files.filter { $0.pathExtension == "data" }.count, 1)
        XCTAssertFalse(file.lastPathComponent.contains("sensitive-user-id"))
        XCTAssertFalse(file.lastPathComponent.contains("profile"))

        try assertExpectedFileProtection(at: file)
        XCTAssertEqual(
            try file.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup,
            true
        )
        XCTAssertEqual(
            try directory.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup,
            true
        )
    }

    func testOwnerScopeRemovalDoesNotCrossProfilesOrHouseholds() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ProtectedLocalDataStore(directoryURL: root.appendingPathComponent("private"))
        let userAHome = PrivateLocalDataScope.household(for: "user-a")
        let userAProfile = PrivateLocalDataScope.profile(for: "user-a")
        let userBHome = PrivateLocalDataScope.household(for: "user-b")

        try store.set(Data("home-a".utf8), forKey: "payload", ownerScope: userAHome)
        try store.set(Data("profile-a".utf8), forKey: "payload", ownerScope: userAProfile)
        try store.set(Data("home-b".utf8), forKey: "payload", ownerScope: userBHome)

        try store.removeAllData(forOwnerScope: userAHome)

        XCTAssertNil(try store.data(forKey: "payload", ownerScope: userAHome))
        XCTAssertEqual(
            try store.data(forKey: "payload", ownerScope: userAProfile),
            Data("profile-a".utf8)
        )
        XCTAssertEqual(
            try store.data(forKey: "payload", ownerScope: userBHome),
            Data("home-b".utf8)
        )
    }

    func testProtectedStoreRejectsOversizedEntriesWithoutWriting() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("private")
        let store = ProtectedLocalDataStore(
            directoryURL: directory,
            maximumEntryBytes: 8
        )

        XCTAssertThrowsError(
            try store.set(Data(repeating: 1, count: 9), forKey: "large", ownerScope: "test")
        ) { error in
            XCTAssertEqual(
                error as? PrivateLocalDataStoreError,
                .entryTooLarge(maximumBytes: 8)
            )
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

    func testLegacyMigrationRemovesDefaultsOnlyAfterProtectedWriteSucceeds() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let suiteName = "PrivateLocalDataStoreTests.\(#function).\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = ProtectedLocalDataStore(directoryURL: root.appendingPathComponent("private"))
        let key = "nina.profile.metadata.legacy-user"
        let scope = PrivateLocalDataScope.profile(for: "legacy-user")
        let legacyData = Data("legacy".utf8)
        defaults.set(legacyData, forKey: key)

        let migrated = PrivateLocalDataAccess.loadData(
            forKey: key,
            ownerScope: scope,
            store: store,
            legacyDefaults: defaults
        )

        XCTAssertEqual(migrated, legacyData)
        XCTAssertNil(defaults.data(forKey: key))
        XCTAssertEqual(try store.data(forKey: key, ownerScope: scope), legacyData)

        defaults.set(legacyData, forKey: "failed")
        XCTAssertEqual(
            PrivateLocalDataAccess.loadData(
                forKey: "failed",
                ownerScope: scope,
                store: FailingPrivateLocalDataStore(),
                legacyDefaults: defaults
            ),
            legacyData
        )
        XCTAssertEqual(defaults.data(forKey: "failed"), legacyData)
    }

    @MainActor
    func testProfileMetadataAndPhotoMigrateAndClearTogether() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let suiteName = "PrivateLocalDataStoreTests.\(#function).\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let privateStore = ProtectedLocalDataStore(directoryURL: root.appendingPathComponent("private"))
        let user = AuthUser(
            id: UUID().uuidString,
            displayName: "Private User",
            email: "private@example.com",
            provider: .apple
        )
        var expectedProfile = UserProfile.default(for: user)
        expectedProfile.phone = "+55 11 99999-0000"
        expectedProfile.avatar = expectedProfile.avatar.asPhoto(for: user.id)
        let photoData = Data([0xFF, 0xD8, 0xFF, 0xD9])
        let profileKey = "nina.profile.metadata.\(user.id)"
        let photoKey = "nina.profile.photo.\(user.id)"
        defaults.set(try JSONEncoder().encode(expectedProfile), forKey: profileKey)
        defaults.set(photoData, forKey: photoKey)
        let profileStore = ProfileStore(
            defaults: defaults,
            privateDataStore: privateStore,
            remoteProfileBackend: nil
        )

        let restoredProfile = profileStore.profile(for: user)
        XCTAssertEqual(restoredProfile, expectedProfile)
        XCTAssertEqual(profileStore.photoData(for: restoredProfile), photoData)
        XCTAssertNil(defaults.data(forKey: profileKey))
        XCTAssertNil(defaults.data(forKey: photoKey))

        profileStore.clearLocalData(for: user.id)

        let scope = PrivateLocalDataScope.profile(for: user.id)
        XCTAssertNil(try privateStore.data(forKey: profileKey, ownerScope: scope))
        XCTAssertNil(try privateStore.data(forKey: photoKey, ownerScope: scope))
        XCTAssertNil(profileStore.profiles[user.id])
    }

    @MainActor
    func testProfileCleanupInvalidatesInFlightRemoteRefresh() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let suiteName = "PrivateLocalDataStoreTests.\(#function).\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let privateStore = ProtectedLocalDataStore(directoryURL: root.appendingPathComponent("private"))
        let user = AuthUser(
            id: UUID().uuidString,
            displayName: "Deleted User",
            email: "deleted@example.com",
            provider: .apple
        )
        var staleProfile = UserProfile.default(for: user)
        staleProfile.phone = "+55 11 98888-0000"
        let backend = ControlledProfileBackend()
        let profileStore = ProfileStore(
            defaults: defaults,
            privateDataStore: privateStore,
            remoteProfileBackend: backend
        )

        let refreshTask = Task {
            await profileStore.refreshProfile(for: user)
        }
        await backend.waitUntilLoadStarted()

        profileStore.clearLocalData(for: user.id)
        await backend.completeLoad(with: staleProfile)
        await refreshTask.value

        let profileKey = "nina.profile.metadata.\(user.id)"
        XCTAssertNil(profileStore.profiles[user.id])
        XCTAssertNil(
            try privateStore.data(
                forKey: profileKey,
                ownerScope: PrivateLocalDataScope.profile(for: user.id)
            )
        )
        XCTAssertNil(defaults.data(forKey: profileKey))
    }

    func testPrivacyExportReplacesStaleFileAndRemovesItExplicitly() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("exports")
        let first = try PrivacyExportFileStore.write(
            Data("first".utf8),
            filename: "nina-privacy-export-20260803-120000.json",
            directoryURL: directory
        )
        let second = try PrivacyExportFileStore.write(
            Data("second".utf8),
            filename: "nina-privacy-export-20260803-120001.json",
            directoryURL: directory
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: first.path))
        XCTAssertEqual(try Data(contentsOf: second), Data("second".utf8))
        XCTAssertEqual(
            try second.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup,
            true
        )
        try assertExpectedFileProtection(at: second)

        PrivacyExportFileStore.remove(second)
        XCTAssertFalse(FileManager.default.fileExists(atPath: second.path))
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "nina-private-data-tests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    private func assertExpectedFileProtection(at fileURL: URL) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let protection = attributes[.protectionKey]

        #if targetEnvironment(simulator)
        // CoreSimulator accepts protection writes but may not expose the metadata.
        if let protection {
            XCTAssertTrue(
                String(describing: protection).contains(
                    FileProtectionType.completeUntilFirstUserAuthentication.rawValue
                )
            )
        }
        #else
        let protection = try XCTUnwrap(protection)
        XCTAssertTrue(
            String(describing: protection).contains(
                FileProtectionType.completeUntilFirstUserAuthentication.rawValue
            )
        )
        #endif
    }
}

private final class FailingPrivateLocalDataStore: PrivateLocalDataStoring {
    private struct StorageFailure: Error {}

    func data(forKey key: String, ownerScope: String?) throws -> Data? {
        nil
    }

    func set(_ data: Data, forKey key: String, ownerScope: String?) throws {
        throw StorageFailure()
    }

    func removeData(forKey key: String, ownerScope: String?) throws {}

    func removeAllData(forOwnerScope ownerScope: String) throws {}
}

private actor ControlledProfileBackend: RemoteProfileBackend {
    private enum TestError: Error {
        case unexpectedPhotoLoad
    }

    private var loadStarted = false
    private var loadStartedContinuation: CheckedContinuation<Void, Never>?
    private var loadContinuation: CheckedContinuation<UserProfile?, Error>?

    func waitUntilLoadStarted() async {
        if loadStarted { return }
        await withCheckedContinuation { continuation in
            loadStartedContinuation = continuation
        }
    }

    func completeLoad(with profile: UserProfile?) {
        loadContinuation?.resume(returning: profile)
        loadContinuation = nil
    }

    func loadProfile(for user: AuthUser) async throws -> UserProfile? {
        loadStarted = true
        loadStartedContinuation?.resume()
        loadStartedContinuation = nil
        return try await withCheckedThrowingContinuation { continuation in
            loadContinuation = continuation
        }
    }

    func saveProfile(_ profile: UserProfile, user: AuthUser?) async throws {}

    func loadPhotoData(for userID: String) async throws -> Data {
        throw TestError.unexpectedPhotoLoad
    }

    func savePhotoData(_ data: Data, for userID: String) async throws {}
    func deletePhoto(for userID: String) async throws {}
}
