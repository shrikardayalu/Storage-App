import Foundation
import StorageCore

/// Reads real free space from the volume that holds the app's home directory,
/// the same figures iOS uses for Settings → General → iPhone Storage. Read-only,
/// and needs no permission.
struct VolumeStorageService: DeviceStorageService {
    enum ReadError: LocalizedError {
        case missingValues

        var errorDescription: String? { "The iPhone didn't report its storage." }
    }

    var volumeURL = URL(fileURLWithPath: NSHomeDirectory())

    func currentSnapshot() async throws -> StorageSnapshot {
        let values = try volumeURL.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
        ])
        guard let total = values.volumeTotalCapacity, let available = values.volumeAvailableCapacity else {
            throw ReadError.missingValues
        }
        return StorageSnapshot(
            date: Date(),
            totalBytes: Int64(total),
            availableBytes: Int64(available),
            // Can be missing on some volumes; fall back to plain free space (purgeable 0).
            availableForImportantUsageBytes: values.volumeAvailableCapacityForImportantUsage ?? Int64(available)
        )
    }
}

/// Saves storage readings as JSON in Application Support. A missing or
/// unreadable file starts a fresh history instead of failing.
struct StorageHistoryStore: Sendable {
    /// Nil keeps history in memory only (tests and previews).
    let fileURL: URL?

    static let inMemory = StorageHistoryStore(fileURL: nil)

    static var applicationSupport: StorageHistoryStore {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        return StorageHistoryStore(fileURL: directory?.appendingPathComponent("storage-history.json"))
    }

    func load() -> StorageHistory {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return StorageHistory() }
        return (try? Self.decoder.decode(StorageHistory.self, from: data)) ?? StorageHistory()
    }

    func save(_ history: StorageHistory) throws {
        guard let fileURL else { return }
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.encoder.encode(history).write(to: fileURL, options: .atomic)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
