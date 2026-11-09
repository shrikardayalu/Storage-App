import Foundation

public enum FileChangeError: LocalizedError, Equatable {
    /// iOS no longer lets the app into the picked folder. Picking it again fixes this.
    case noAccess
    /// The fresh check right before deleting failed; nothing was deleted.
    case unsafe(FileSafetyCheck)
    /// What's in the folder isn't what the person reviewed.
    case changed(String)
    /// The deletion ran, but the folder afterwards wasn't what was expected.
    case verificationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .noAccess:
            "SimpleShrink can't open that folder any more. Pick it again. Nothing was deleted."
        case .unsafe(let check):
            "\(check.problem ?? "The safety check failed.") Scan again. Nothing was deleted."
        case .changed(let detail):
            "\(detail) Scan again. Nothing was deleted."
        case .verificationFailed(let detail):
            detail
        }
    }
}

/// Reads and deletes files, only inside the one folder the person picked in
/// Files. Every call takes that folder and refuses anything outside it.
public protocol FolderFilesService: Sendable {
    /// Every regular file in the folder and its subfolders, with a content hash
    /// for files that share a size. Read-only.
    func scan(_ folder: URL) async throws -> FolderScan
    /// Re-reads the folder, checks each approved file is still there and
    /// unchanged (and each kept copy too), deletes them for good, then confirms
    /// that exactly those files are gone. If one file fails the check, nothing is deleted.
    func delete(_ approved: [FileItem], keeping keepers: [FileItem], in folder: URL) async throws -> FileDeletionReceipt
}

/// An in-memory folder, for tests and previews. Follows the same rules as the real one.
public actor MockFolderFiles: FolderFilesService {
    public private(set) var files: [FileItem]
    /// Files elsewhere on the phone. Nothing may touch them.
    public private(set) var outsideFiles: [FileItem]
    public private(set) var deleteCount = 0
    public var canOpen = true

    public init(files: [FileItem], outsideFiles: [FileItem] = []) {
        self.files = files
        self.outsideFiles = outsideFiles
    }

    public func setCanOpen(_ value: Bool) {
        canOpen = value
    }

    /// Changes a file behind the app's back, like another app saving over it.
    public func replace(_ file: FileItem) {
        files.removeAll { $0.id == file.id }
        files.append(file)
    }

    public func scan(_ folder: URL) async throws -> FolderScan {
        guard canOpen else { throw FileChangeError.noAccess }
        return FolderScan(folderName: folder.lastPathComponent, files: files)
    }

    public func delete(_ approved: [FileItem], keeping keepers: [FileItem], in folder: URL) async throws -> FileDeletionReceipt {
        guard canOpen else { throw FileChangeError.noAccess }
        let current = Dictionary(uniqueKeysWithValues: files.map { ($0.id, $0.fingerprint) })
        let check = FileSafetyCheck.evaluate(approved: approved, keepers: keepers, current: current)
        guard check.isSafe else { throw FileChangeError.unsafe(check) }

        let before = Set(files.map(\.id))
        let ids = Set(approved.map(\.id))
        files.removeAll { ids.contains($0.id) }
        deleteCount += 1
        return FileDeletionReceipt.audit(approved: approved, before: before, after: Set(files.map(\.id)))
    }
}
