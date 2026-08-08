import CryptoKit
import Foundation
import OSLog

protocol PrivateLocalDataStoring: AnyObject {
    func data(forKey key: String, ownerScope: String?) throws -> Data?
    func set(_ data: Data, forKey key: String, ownerScope: String?) throws
    func removeData(forKey key: String, ownerScope: String?) throws
    func removeAllData(forOwnerScope ownerScope: String) throws
}

enum PrivateLocalDataScope {
    static func household(for userID: String) -> String {
        "household:\(userID)"
    }

    static func profile(for userID: String) -> String {
        "profile:\(userID)"
    }

    static func aiConsent(for userID: String) -> String {
        "ai-consent:\(userID)"
    }

    static let pendingInvite = "pending-invite"
}

enum PrivateLocalDataStoreError: Error, Equatable {
    case emptyIdentifier
    case entryTooLarge(maximumBytes: Int)
    case unsafeStorageItem
}

final class ProtectedLocalDataStore: PrivateLocalDataStoring {
    static let shared = ProtectedLocalDataStore()
    static let defaultMaximumEntryBytes = 32 * 1_024 * 1_024

    private let fileManager: FileManager
    private let directoryOverride: URL?
    private let maximumEntryBytes: Int
    private let lock = NSLock()

    init(
        directoryURL: URL? = nil,
        maximumEntryBytes: Int = ProtectedLocalDataStore.defaultMaximumEntryBytes,
        fileManager: FileManager = .default
    ) {
        self.directoryOverride = directoryURL
        self.maximumEntryBytes = max(maximumEntryBytes, 1)
        self.fileManager = fileManager
    }

    func data(forKey key: String, ownerScope: String?) throws -> Data? {
        try synchronized {
            let directory = try preparedDirectory()
            let fileURL = try entryURL(forKey: key, ownerScope: ownerScope, in: directory)
            guard fileManager.fileExists(atPath: fileURL.path) else { return nil }

            let values = try ProtectedFileSystem.regularFileValues(
                at: fileURL,
                fileManager: fileManager
            )
            if let fileSize = values.fileSize, fileSize > maximumEntryBytes {
                throw PrivateLocalDataStoreError.entryTooLarge(maximumBytes: maximumEntryBytes)
            }

            let data = try Data(contentsOf: fileURL)
            guard data.count <= maximumEntryBytes else {
                throw PrivateLocalDataStoreError.entryTooLarge(maximumBytes: maximumEntryBytes)
            }
            return data
        }
    }

    func set(_ data: Data, forKey key: String, ownerScope: String?) throws {
        guard data.count <= maximumEntryBytes else {
            throw PrivateLocalDataStoreError.entryTooLarge(maximumBytes: maximumEntryBytes)
        }

        try synchronized {
            let directory = try preparedDirectory()
            let fileURL = try entryURL(forKey: key, ownerScope: ownerScope, in: directory)
            if fileManager.fileExists(atPath: fileURL.path) {
                _ = try ProtectedFileSystem.regularFileValues(
                    at: fileURL,
                    fileManager: fileManager
                )
            }

            try data.write(to: fileURL, options: [.atomic])
            do {
                try ProtectedFileSystem.protectAndExcludeFromBackup(
                    fileURL,
                    fileManager: fileManager
                )
            } catch {
                try? fileManager.removeItem(at: fileURL)
                throw error
            }
        }
    }

    func removeData(forKey key: String, ownerScope: String?) throws {
        try synchronized {
            let directory = try preparedDirectory()
            let fileURL = try entryURL(forKey: key, ownerScope: ownerScope, in: directory)
            guard fileManager.fileExists(atPath: fileURL.path) else { return }
            try fileManager.removeItem(at: fileURL)
        }
    }

    func removeAllData(forOwnerScope ownerScope: String) throws {
        guard !ownerScope.isEmpty else {
            throw PrivateLocalDataStoreError.emptyIdentifier
        }

        try synchronized {
            let directory = try preparedDirectory()
            let prefix = "entry-v1-\(Self.digest("scope:\(ownerScope)"))-"
            let entries = try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )

            for entry in entries where
                entry.lastPathComponent.hasPrefix(prefix) && entry.pathExtension == "data" {
                try fileManager.removeItem(at: entry)
            }
        }
    }

    private func synchronized<T>(_ operation: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try operation()
    }

    private func preparedDirectory() throws -> URL {
        let directory: URL
        if let directoryOverride {
            directory = directoryOverride
        } else {
            let applicationSupport = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            directory = applicationSupport.appendingPathComponent(
                "PrivateLocalData-v1",
                isDirectory: true
            )
        }

        try ProtectedFileSystem.prepareDirectory(directory, fileManager: fileManager)
        return directory
    }

    private func entryURL(forKey key: String, ownerScope: String?, in directory: URL) throws -> URL {
        guard !key.isEmpty else {
            throw PrivateLocalDataStoreError.emptyIdentifier
        }

        let scope = ownerScope ?? "global"
        let scopeDigest = Self.digest("scope:\(scope)")
        let keyDigest = Self.digest("key:\(scope):\(key)")
        return directory.appendingPathComponent(
            "entry-v1-\(scopeDigest)-\(keyDigest).data",
            isDirectory: false
        )
    }

    private static func digest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

enum PrivateLocalDataAccess {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.heitor.nina",
        category: "PrivateLocalData"
    )

    static func loadData(
        forKey key: String,
        ownerScope: String?,
        store: any PrivateLocalDataStoring,
        legacyDefaults: UserDefaults
    ) -> Data? {
        do {
            if let data = try store.data(forKey: key, ownerScope: ownerScope) {
                return data
            }
        } catch {
            logger.error("private_local_data event=read_failed")
        }

        guard let legacyData = legacyDefaults.data(forKey: key) else { return nil }
        do {
            try store.set(legacyData, forKey: key, ownerScope: ownerScope)
            legacyDefaults.removeObject(forKey: key)
            logger.info("private_local_data event=legacy_data_migrated")
        } catch {
            logger.error("private_local_data event=legacy_data_migration_failed")
        }
        return legacyData
    }

    static func loadString(
        forKey key: String,
        ownerScope: String?,
        store: any PrivateLocalDataStoring,
        legacyDefaults: UserDefaults
    ) -> String? {
        do {
            if let data = try store.data(forKey: key, ownerScope: ownerScope) {
                return String(data: data, encoding: .utf8)
            }
        } catch {
            logger.error("private_local_data event=read_failed")
        }

        guard let legacyValue = legacyDefaults.string(forKey: key) else { return nil }
        do {
            try store.set(Data(legacyValue.utf8), forKey: key, ownerScope: ownerScope)
            legacyDefaults.removeObject(forKey: key)
            logger.info("private_local_data event=legacy_string_migrated")
        } catch {
            logger.error("private_local_data event=legacy_string_migration_failed")
        }
        return legacyValue
    }

    static func writeData(
        _ data: Data,
        forKey key: String,
        ownerScope: String?,
        store: any PrivateLocalDataStoring,
        legacyDefaults: UserDefaults
    ) throws {
        try store.set(data, forKey: key, ownerScope: ownerScope)
        legacyDefaults.removeObject(forKey: key)
    }

    static func writeString(
        _ value: String,
        forKey key: String,
        ownerScope: String?,
        store: any PrivateLocalDataStoring,
        legacyDefaults: UserDefaults
    ) throws {
        try writeData(
            Data(value.utf8),
            forKey: key,
            ownerScope: ownerScope,
            store: store,
            legacyDefaults: legacyDefaults
        )
    }

    @discardableResult
    static func writeDataBestEffort(
        _ data: Data,
        forKey key: String,
        ownerScope: String?,
        store: any PrivateLocalDataStoring,
        legacyDefaults: UserDefaults
    ) -> Bool {
        do {
            try writeData(
                data,
                forKey: key,
                ownerScope: ownerScope,
                store: store,
                legacyDefaults: legacyDefaults
            )
            return true
        } catch {
            logger.error("private_local_data event=write_failed")
            return false
        }
    }

    @discardableResult
    static func writeStringBestEffort(
        _ value: String,
        forKey key: String,
        ownerScope: String?,
        store: any PrivateLocalDataStoring,
        legacyDefaults: UserDefaults
    ) -> Bool {
        writeDataBestEffort(
            Data(value.utf8),
            forKey: key,
            ownerScope: ownerScope,
            store: store,
            legacyDefaults: legacyDefaults
        )
    }

    static func removeData(
        forKey key: String,
        ownerScope: String?,
        store: any PrivateLocalDataStoring,
        legacyDefaults: UserDefaults
    ) {
        do {
            try store.removeData(forKey: key, ownerScope: ownerScope)
        } catch {
            logger.error("private_local_data event=remove_failed")
        }
        legacyDefaults.removeObject(forKey: key)
    }

    static func removeAllData(
        forOwnerScope ownerScope: String,
        store: any PrivateLocalDataStoring
    ) {
        do {
            try store.removeAllData(forOwnerScope: ownerScope)
        } catch {
            logger.error("private_local_data event=owner_remove_failed")
        }
    }
}

enum PrivacyExportFileStore {
    static let maximumExportBytes = 64 * 1_024 * 1_024
    private static let filenamePrefix = "nina-privacy-export-"
    private static let directoryName = "NinaPrivacyExports-v1"

    static func write(
        _ data: Data,
        filename: String,
        directoryURL: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> URL {
        guard data.count <= maximumExportBytes else {
            throw PrivateLocalDataStoreError.entryTooLarge(maximumBytes: maximumExportBytes)
        }
        guard isValidExportFilename(filename) else {
            throw PrivateLocalDataStoreError.emptyIdentifier
        }

        let directory = directoryURL ?? defaultDirectory(fileManager: fileManager)
        try ProtectedFileSystem.prepareDirectory(directory, fileManager: fileManager)
        try removeAll(in: directory, fileManager: fileManager)

        let fileURL = directory.appendingPathComponent(filename, isDirectory: false)
        try data.write(to: fileURL, options: [.atomic])
        do {
            try ProtectedFileSystem.protectAndExcludeFromBackup(
                fileURL,
                fileManager: fileManager
            )
        } catch {
            try? fileManager.removeItem(at: fileURL)
            throw error
        }
        return fileURL
    }

    static func remove(_ fileURL: URL, fileManager: FileManager = .default) {
        guard isValidExportFilename(fileURL.lastPathComponent) else { return }
        try? fileManager.removeItem(at: fileURL)
    }

    static func removeAll(
        directoryURL: URL? = nil,
        fileManager: FileManager = .default
    ) throws {
        let directory = directoryURL ?? defaultDirectory(fileManager: fileManager)
        guard fileManager.fileExists(atPath: directory.path) else { return }
        try ProtectedFileSystem.prepareDirectory(directory, fileManager: fileManager)
        try removeAll(in: directory, fileManager: fileManager)
    }

    private static func removeAll(in directory: URL, fileManager: FileManager) throws {
        let files = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        for file in files where isValidExportFilename(file.lastPathComponent) {
            try fileManager.removeItem(at: file)
        }
    }

    private static func defaultDirectory(fileManager: FileManager) -> URL {
        fileManager.temporaryDirectory.appendingPathComponent(directoryName, isDirectory: true)
    }

    private static func isValidExportFilename(_ filename: String) -> Bool {
        filename.hasPrefix(filenamePrefix) &&
            filename.hasSuffix(".json") &&
            !filename.contains("/") &&
            !filename.contains(":")
    }
}

private enum ProtectedFileSystem {
    static func prepareDirectory(_ directory: URL, fileManager: FileManager) throws {
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory) {
            let values = try directory.resourceValues(forKeys: [
                .isDirectoryKey,
                .isSymbolicLinkKey
            ])
            guard isDirectory.boolValue,
                  values.isDirectory == true,
                  values.isSymbolicLink != true else {
                throw PrivateLocalDataStoreError.unsafeStorageItem
            }
        } else {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [
                    .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication
                ]
            )
        }

        try protectAndExcludeFromBackup(directory, fileManager: fileManager)
    }

    static func regularFileValues(
        at fileURL: URL,
        fileManager: FileManager
    ) throws -> URLResourceValues {
        let values = try fileURL.resourceValues(forKeys: [
            .fileSizeKey,
            .isRegularFileKey,
            .isSymbolicLinkKey
        ])
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw PrivateLocalDataStoreError.unsafeStorageItem
        }
        return values
    }

    static func protectAndExcludeFromBackup(
        _ url: URL,
        fileManager: FileManager
    ) throws {
        try fileManager.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path
        )

        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = url
        try mutableURL.setResourceValues(values)
    }
}
