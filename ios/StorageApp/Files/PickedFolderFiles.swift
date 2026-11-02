import CryptoKit
import Foundation
import StorageCore

/// The only code in the app that reads or deletes the person's own files, and
/// it can only reach the one folder they picked in Files (Build Plan step 8).
/// `Tools/check-no-device-access.sh` enforces that files are removed nowhere
/// else, and that this file checks `PickedFolder.contains` before removing.
///
/// Every deletion re-reads the folder first and refuses unless each approved
/// file is still there, inside the folder, a regular file, and unchanged since
/// the review, and each kept copy of a duplicate is too. Afterwards the folder
/// is read again to confirm exactly the approved files are gone.
struct PickedFolderFiles: FolderFilesService {
    func scan(_ folder: URL) async throws -> FolderScan {
        try await Task.detached(priority: .userInitiated) {
            try Self.withAccess(to: folder) { root in
                let entries = try Self.list(root)
                // Only files that share a size can be duplicates, so only those are read.
                let sizes = Dictionary(grouping: entries.values, by: \.bytes).filter { $0.key > 0 && $0.value.count > 1 }
                let toHash = Set(sizes.values.joined().map(\.path))
                let files = entries.values.map { entry in
                    FileItem(
                        path: entry.path,
                        bytes: entry.bytes,
                        modified: entry.modified,
                        lastOpened: entry.opened,
                        contentHash: toHash.contains(entry.path) ? Self.hash(entry.url) : nil
                    )
                }
                return FolderScan(folderName: folder.lastPathComponent, files: files)
            }
        }.value
    }

    func delete(_ approved: [FileItem], keeping keepers: [FileItem], in folder: URL) async throws -> FileDeletionReceipt {
        try await Task.detached(priority: .userInitiated) {
            try Self.withAccess(to: folder) { root in
                let before = try Self.list(root)
                let check = FileSafetyCheck.evaluate(
                    approved: approved,
                    keepers: keepers,
                    current: before.mapValues { FileFingerprint(bytes: $0.bytes, modified: $0.modified) }
                )
                guard check.isSafe else { throw FileChangeError.unsafe(check) }
                // Every target is confirmed inside the folder before the first one is removed.
                let targets = try approved.map { file -> URL in
                    guard let entry = before[file.id], PickedFolder.contains(root: root, candidate: entry.url) else {
                        throw FileChangeError.changed("A file is outside the folder you picked.")
                    }
                    return entry.url
                }

                var failure: Error?
                for url in targets {
                    do {
                        try Self.remove(url, inside: root)
                    } catch {
                        failure = error
                        break
                    }
                }

                let after = try Self.list(root)
                let receipt = FileDeletionReceipt.audit(approved: approved, before: Set(before.keys), after: Set(after.keys))
                guard failure == nil, receipt.isExact else {
                    let reason = failure.map { " \($0.localizedDescription)" } ?? ""
                    throw FileChangeError.verificationFailed(
                        "Deleted \(receipt.deleted.count) of \(approved.count) files, then stopped.\(reason) Scan again to see what's there."
                    )
                }
                return receipt
            }
        }.value
    }

    // MARK: - Inside the folder

    private struct Entry: Sendable {
        let url: URL
        let path: String
        let bytes: Int64
        let modified: Date
        let opened: Date?
    }

    /// Opens the picked folder for the length of `work`. iOS grants access only
    /// to the folder the person picked, and to nothing else.
    private static func withAccess<T>(to folder: URL, _ work: (URL) throws -> T) throws -> T {
        let granted = folder.startAccessingSecurityScopedResource()
        defer { if granted { folder.stopAccessingSecurityScopedResource() } }
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isFolder), isFolder.boolValue,
              FileManager.default.isReadableFile(atPath: folder.path) else {
            throw FileChangeError.noAccess
        }
        return try work(folder.resolvingSymlinksInPath().standardizedFileURL)
    }

    /// Every regular file in `root` and its subfolders, by path inside `root`.
    /// Hidden files, symbolic links, folders and package contents are skipped.
    private static func list(_ root: URL) throws -> [String: Entry] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey, .contentAccessDateKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { throw FileChangeError.noAccess }

        var entries: [String: Entry] = [:]
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true, values.isSymbolicLink != true else { continue }
            let resolved = url.resolvingSymlinksInPath().standardizedFileURL
            guard let path = PickedFolder.relativePath(of: resolved, in: root) else { continue }
            entries[path] = Entry(
                url: resolved,
                path: path,
                bytes: Int64(values.fileSize ?? 0),
                modified: values.contentModificationDate ?? .distantPast,
                opened: values.contentAccessDate
            )
        }
        return entries
    }

    /// Removes one file, coordinated with Files and iCloud. Refuses anything outside `root`.
    private static func remove(_ url: URL, inside root: URL) throws {
        guard PickedFolder.contains(root: root, candidate: url) else {
            throw FileChangeError.changed("A file is outside the folder you picked.")
        }
        var coordinationError: NSError?
        var removeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forDeleting, error: &coordinationError) { target in
            let target = target.resolvingSymlinksInPath().standardizedFileURL
            guard PickedFolder.contains(root: root, candidate: target) else {
                removeError = FileChangeError.changed("A file is outside the folder you picked.")
                return
            }
            do {
                try FileManager.default.removeItem(at: target)
            } catch {
                removeError = error
            }
        }
        if let error = coordinationError ?? removeError { throw error }
    }

    /// SHA-256 of the contents, read in chunks; nil if it can't be read.
    private static func hash(_ url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        do {
            while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
                hasher.update(data: chunk)
            }
        } catch {
            return nil
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
