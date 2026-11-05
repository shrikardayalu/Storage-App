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

/// Saves one value as JSON in Application Support. A missing or unreadable
/// file gives the fallback instead of failing.
struct JSONFileStore<Value: Codable>: Sendable {
    /// Nil keeps the value in memory only (tests and previews).
    let fileURL: URL?

    static var inMemory: Self { Self(fileURL: nil) }

    static func inApplicationSupport(_ filename: String) -> Self {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        return Self(fileURL: directory?.appendingPathComponent(filename))
    }

    func load(or fallback: @autoclosure () -> Value) -> Value {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return fallback() }
        return (try? JSONCoders.decoder.decode(Value.self, from: data)) ?? fallback()
    }

    func save(_ value: Value) throws {
        guard let fileURL else { return }
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONCoders.encoder.encode(value).write(to: fileURL, options: .atomic)
    }
}

/// Storage readings, oldest first.
typealias StorageHistoryStore = JSONFileStore<StorageHistory>

extension JSONFileStore where Value == StorageHistory {
    static var applicationSupport: Self { .inApplicationSupport("storage-history.json") }

    func load() -> StorageHistory { load(or: StorageHistory()) }
}

/// What each action gave back, for the results screen (Build Plan step 11).
typealias FreedLedgerStore = JSONFileStore<FreedLedger>

extension JSONFileStore where Value == FreedLedger {
    static var applicationSupport: Self { .inApplicationSupport("freed-ledger.json") }

    func load() -> FreedLedger { load(or: FreedLedger()) }
}

/// The restart coach's baseline and last result (Build Plan step 9).
typealias RestartCoachStore = JSONFileStore<RestartCoachState>

extension JSONFileStore where Value == RestartCoachState {
    static var applicationSupport: Self { .inApplicationSupport("restart-coach.json") }

    func load() -> RestartCoachState { load(or: RestartCoachState()) }
}

/// Time since the phone started. `CLOCK_MONOTONIC` keeps counting while the
/// phone sleeps, so a long sleep never looks like a restart. Used only to
/// tell whether the phone restarted since the person tapped the restart
/// guide (privacy manifest reason 35F9.1).
enum SystemUptime {
    static func sinceStart() -> TimeInterval {
        TimeInterval(clock_gettime_nsec_np(CLOCK_MONOTONIC)) / 1_000_000_000
    }
}

private enum JSONCoders {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
