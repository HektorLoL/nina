import Foundation
import MetricKit
import OSLog

final class OperationalDiagnostics: NSObject, MXMetricManagerSubscriber {
    static let shared = OperationalDiagnostics()

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.heitor.nina",
        category: "OperationalDiagnostics"
    )
    private let archiveQueue = DispatchQueue(
        label: "com.heitor.nina.operational-diagnostics",
        qos: .utility
    )
    private let stateLock = NSLock()
    private var isStarted = false

    private let maximumArchiveCount = 12
    private let maximumArchiveBytes = 8 * 1_024 * 1_024

    private override init() {
        super.init()
    }

    func start() {
        stateLock.lock()
        defer { stateLock.unlock() }

        guard !isStarted else { return }
        isStarted = true
        MXMetricManager.shared.add(self)
        logger.info("operational_diagnostics event=started")
    }

    func didReceive(_ payloads: [MXMetricPayload]) {
        archive(
            payloads.map { $0.jsonRepresentation() },
            kind: "metrics"
        )
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        archive(
            payloads.map { $0.jsonRepresentation() },
            kind: "diagnostics"
        )
    }

    private func archive(_ payloads: [Data], kind: String) {
        guard !payloads.isEmpty else { return }

        archiveQueue.async { [weak self] in
            guard let self else { return }

            do {
                let directory = try self.diagnosticsDirectory()
                for payload in payloads {
                    let timestamp = Int64(Date().timeIntervalSince1970 * 1_000)
                    let filename = String(
                        format: "%013lld-%@-%@.json",
                        timestamp,
                        kind,
                        UUID().uuidString.lowercased()
                    )
                    let fileURL = directory.appendingPathComponent(filename, isDirectory: false)
                    try payload.write(to: fileURL, options: [.atomic])
                    try FileManager.default.setAttributes(
                        [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                        ofItemAtPath: fileURL.path
                    )

                    var values = URLResourceValues()
                    values.isExcludedFromBackup = true
                    var mutableFileURL = fileURL
                    try mutableFileURL.setResourceValues(values)
                }

                try self.enforceArchiveLimits(in: directory)
                self.logger.info(
                    "operational_diagnostics event=archived kind=\(kind, privacy: .public) count=\(payloads.count, privacy: .public)"
                )
            } catch {
                self.logger.error(
                    "operational_diagnostics event=archive_failed kind=\(kind, privacy: .public) error=\(String(describing: error), privacy: .private)"
                )
            }
        }
    }

    private func diagnosticsDirectory() throws -> URL {
        let baseDirectory = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = baseDirectory.appendingPathComponent(
            "OperationalDiagnostics",
            isDirectory: true
        )

        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableDirectory = directory
        try mutableDirectory.setResourceValues(values)
        return directory
    }

    private func enforceArchiveLimits(in directory: URL) throws {
        let keys: Set<URLResourceKey> = [
            .fileSizeKey,
            .isRegularFileKey
        ]
        var archives = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        )
        .compactMap { url -> DiagnosticArchive? in
            guard let values = try? url.resourceValues(forKeys: keys),
                  values.isRegularFile == true else {
                return nil
            }
            return DiagnosticArchive(
                url: url,
                sortKey: url.lastPathComponent,
                byteCount: values.fileSize ?? 0
            )
        }
        .sorted { $0.sortKey < $1.sortKey }

        var totalBytes = archives.reduce(0) { $0 + $1.byteCount }
        while archives.count > maximumArchiveCount || totalBytes > maximumArchiveBytes {
            let archive = archives.removeFirst()
            try FileManager.default.removeItem(at: archive.url)
            totalBytes = max(totalBytes - archive.byteCount, 0)
        }
    }
}

private struct DiagnosticArchive {
    var url: URL
    var sortKey: String
    var byteCount: Int
}
