import Foundation

/// One file inside the folder the person picked in Files (Build Plan step 8).
public struct FileItem: Identifiable, Hashable, Sendable {
    /// The path inside the picked folder, such as "Downloads/clip.mov". Unique within one scan.
    public let id: String
    public let bytes: Int64
    public let modified: Date
    /// When the file was last opened, if the system knows.
    public let lastOpened: Date?
    /// A hash of the contents, filled in only for files that share their size with another file.
    public let contentHash: String?

    public init(path: String, bytes: Int64, modified: Date, lastOpened: Date? = nil, contentHash: String? = nil) {
        self.id = path
        self.bytes = bytes
        self.modified = modified
        self.lastOpened = lastOpened
        self.contentHash = contentHash
    }

    public var name: String { (id as NSString).lastPathComponent }

    /// The subfolder it's in, or nil at the top of the picked folder.
    public var subfolder: String? {
        let parent = (id as NSString).deletingLastPathComponent
        return parent.isEmpty ? nil : parent
    }

    /// Opened or changed, whichever was later.
    public var lastUsed: Date { max(modified, lastOpened ?? modified) }

    public var kind: FileKind { FileKind(extension: (id as NSString).pathExtension) }

    /// What a deletion must still find, unchanged, right before it removes the file.
    public var fingerprint: FileFingerprint { FileFingerprint(bytes: bytes, modified: modified) }
}

/// Size and modification date: if either moved since the review, the file changed.
public struct FileFingerprint: Hashable, Sendable {
    public let bytes: Int64
    public let modified: Date

    public init(bytes: Int64, modified: Date) {
        self.bytes = bytes
        self.modified = modified
    }

    public static func == (a: FileFingerprint, b: FileFingerprint) -> Bool {
        // File systems store dates with different precision; allow for rounding.
        a.bytes == b.bytes && abs(a.modified.timeIntervalSince(b.modified)) < 0.001
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(bytes)
    }
}

/// A rough type, for the icon and wording.
public enum FileKind: String, Hashable, Sendable {
    case video, archive, document, image, audio, other

    public init(extension ext: String) {
        switch ext.lowercased() {
        case "mov", "mp4", "m4v", "avi", "mkv", "webm": self = .video
        case "zip", "rar", "7z", "gz", "tar", "tgz", "dmg", "ipa", "pkg": self = .archive
        case "pdf", "doc", "docx", "pages", "key", "ppt", "pptx", "xls", "xlsx", "numbers", "txt", "rtf", "epub": self = .document
        case "jpg", "jpeg", "heic", "png", "gif", "tiff", "dng", "raw": self = .image
        case "mp3", "m4a", "wav", "aac", "flac", "aiff": self = .audio
        default: self = .other
        }
    }
}

/// A read of the picked folder: every regular file in it and its subfolders.
public struct FolderScan: Hashable, Sendable {
    public let folderName: String
    public let files: [FileItem]

    public init(folderName: String, files: [FileItem]) {
        self.folderName = folderName
        self.files = files.sorted { ($0.bytes, $1.id) > ($1.bytes, $0.id) }
    }

    public var totalBytes: Int64 { files.reduce(0) { $0 + $1.bytes } }

    public subscript(id: FileItem.ID) -> FileItem? { files.first { $0.id == id } }
}

/// Identical files, best copy first. The first is kept unless the person picks another.
public struct FileDuplicateGroup: Identifiable, Hashable, Sendable {
    public let files: [FileItem]

    public var id: String { files.map(\.id).sorted().joined(separator: "|") }
    public var suggestedKeeper: FileItem.ID { files[0].id }

    public init(files: [FileItem]) {
        self.files = files.sorted(by: FileCleanup.isBetterCopy)
    }

    public func savedBytes(keeping keeper: FileItem.ID) -> Int64 {
        files.filter { $0.id != keeper }.reduce(0) { $0 + $1.bytes }
    }
}

/// Where the files finder draws its lines.
public struct FileRules: Hashable, Sendable {
    /// Files at least this big are listed as large.
    public var largeBytes: Int64
    /// Files not opened or changed for this long are listed as old.
    public var oldAge: TimeInterval

    public init(largeBytes: Int64 = 10_000_000, oldAge: TimeInterval = 180 * 86_400) {
        self.largeBytes = largeBytes
        self.oldAge = oldAge
    }

    public static let standard = FileRules()
}

/// What the files finder suggests for the picked folder. Each file shows up in
/// one list only: duplicates first, then large, then old.
public struct FileReport: Hashable, Sendable {
    public let duplicates: [FileDuplicateGroup]
    public let large: [FileItem]
    public let old: [FileItem]

    public init(duplicates: [FileDuplicateGroup], large: [FileItem], old: [FileItem]) {
        self.duplicates = duplicates
        self.large = large
        self.old = old
    }

    public var isEmpty: Bool { duplicates.isEmpty && large.isEmpty && old.isEmpty }

    /// Refuses a deletion that would take every copy of a duplicate, or a picked keeper.
    public func validate(remove: Set<FileItem.ID>, keepers: Set<FileItem.ID>) throws {
        guard remove.isDisjoint(with: keepers) else {
            throw FileChangeError.changed("A file you chose to keep was also marked for deletion.")
        }
        for group in duplicates {
            let ids = Set(group.files.map(\.id))
            if ids.isSubset(of: remove) {
                throw FileChangeError.changed("Every copy of a duplicate file was marked for deletion.")
            }
            if !ids.isDisjoint(with: remove), ids.isDisjoint(with: keepers) {
                throw FileChangeError.changed("A duplicate file has no copy picked to keep.")
            }
        }
    }
}

public enum FileCleanup {
    public static func report(for scan: FolderScan, now: Date, rules: FileRules = .standard) -> FileReport {
        let hashed = scan.files.filter { $0.contentHash != nil && $0.bytes > 0 }
        let duplicates = Dictionary(grouping: hashed) { "\($0.bytes)-\($0.contentHash!)" }
            .values
            .filter { $0.count > 1 }
            .map(FileDuplicateGroup.init)
            .sorted { ($0.savedBytes(keeping: $0.suggestedKeeper), $1.id) > ($1.savedBytes(keeping: $1.suggestedKeeper), $0.id) }
        let inGroups = Set(duplicates.flatMap(\.files).map(\.id))

        let rest = scan.files.filter { !inGroups.contains($0.id) }
        let large = rest.filter { $0.bytes >= rules.largeBytes }
        let largeIDs = Set(large.map(\.id))
        let old = rest
            .filter { !largeIDs.contains($0.id) && now.timeIntervalSince($0.lastUsed) > rules.oldAge }
            .sorted { ($0.bytes, $1.id) > ($1.bytes, $0.id) }
        return FileReport(duplicates: duplicates, large: large, old: old)
    }

    /// The copy to keep: a name that doesn't look like a copy, then the older
    /// one, then the one higher up in the folder, then by name.
    static func isBetterCopy(_ a: FileItem, _ b: FileItem) -> Bool {
        let ca = looksLikeCopy(a.name)
        let cb = looksLikeCopy(b.name)
        if ca != cb { return !ca }
        if abs(a.modified.timeIntervalSince(b.modified)) >= 1 { return a.modified < b.modified }
        let da = a.id.split(separator: "/").count
        let db = b.id.split(separator: "/").count
        if da != db { return da < db }
        return a.id < b.id
    }

    /// "Report copy.pdf", "Report (1).pdf", "Report 2.pdf", "Report-1.pdf".
    static func looksLikeCopy(_ name: String) -> Bool {
        let stem = (name as NSString).deletingPathExtension.lowercased()
        return stem.hasSuffix(" copy")
            || stem.contains(" copy ")
            || stem.wholeMatch(of: #/.*(\(\d+\)| \d+|-\d+)/#) != nil
    }
}

/// Keeps the app inside the folder the person picked.
public enum PickedFolder {
    /// True only when `candidate` is strictly inside `root`. Both should already
    /// have symlinks resolved; ".." segments are rejected outright.
    public static func contains(root: URL, candidate: URL) -> Bool {
        let rootParts = root.standardizedFileURL.pathComponents
        let parts = candidate.standardizedFileURL.pathComponents
        guard !candidate.pathComponents.contains(".."), parts.count > rootParts.count else { return false }
        return Array(parts.prefix(rootParts.count)) == rootParts
    }

    /// The file's path inside `root`, used as its ID; nil if it isn't inside.
    public static func relativePath(of candidate: URL, in root: URL) -> String? {
        guard contains(root: root, candidate: candidate) else { return nil }
        let rootCount = root.standardizedFileURL.pathComponents.count
        return candidate.standardizedFileURL.pathComponents.dropFirst(rootCount).joined(separator: "/")
    }
}

/// The result of checking approved files against the folder as it is right
/// before deleting. Deletion goes ahead only when `isSafe`.
public struct FileSafetyCheck: Hashable, Sendable {
    public let approved: Set<FileItem.ID>
    /// Approved files that aren't in the folder any more.
    public let missing: Set<FileItem.ID>
    /// Approved files whose size or date changed since the review.
    public let changed: Set<FileItem.ID>
    /// Copies chosen to keep that are gone or changed, so deleting the others could lose the file.
    public let keepersMissing: Set<FileItem.ID>

    public init(approved: Set<FileItem.ID>, missing: Set<FileItem.ID>, changed: Set<FileItem.ID>, keepersMissing: Set<FileItem.ID>) {
        self.approved = approved
        self.missing = missing
        self.changed = changed
        self.keepersMissing = keepersMissing
    }

    /// - Parameters:
    ///   - approved: the files as the review showed them.
    ///   - keepers: the copies kept in each duplicate group being cleaned.
    ///   - current: the folder read fresh, path → fingerprint.
    public static func evaluate(
        approved: [FileItem],
        keepers: [FileItem],
        current: [FileItem.ID: FileFingerprint]
    ) -> FileSafetyCheck {
        FileSafetyCheck(
            approved: Set(approved.map(\.id)),
            missing: Set(approved.filter { current[$0.id] == nil }.map(\.id)),
            changed: Set(approved.filter { file in current[file.id].map { $0 != file.fingerprint } ?? false }.map(\.id)),
            keepersMissing: Set(keepers.filter { current[$0.id] != $0.fingerprint }.map(\.id))
        )
    }

    public var isSafe: Bool {
        !approved.isEmpty && missing.isEmpty && changed.isEmpty && keepersMissing.isEmpty
    }

    public var problem: String? {
        if approved.isEmpty { return "Nothing was approved." }
        if !missing.isEmpty { return "\(Self.count(missing.count)) no longer in the folder." }
        if !changed.isEmpty { return "\(Self.count(changed.count)) changed since the scan." }
        if !keepersMissing.isEmpty { return "A copy you chose to keep is gone or changed, so its duplicates are left alone." }
        return nil
    }

    private static func count(_ n: Int) -> String {
        n == 1 ? "1 file is" : "\(n) files are"
    }
}

/// Proof of a file deletion: the folder before and after, and whether exactly
/// the approved files, and nothing else, are gone.
public struct FileDeletionReceipt: Hashable, Sendable {
    public let deleted: Set<FileItem.ID>
    public let deletedBytes: Int64
    public let folderCountBefore: Int
    public let folderCountAfter: Int
    /// Approved files that are somehow still there.
    public let stillThere: Set<FileItem.ID>
    /// True when the folder after is the folder before minus exactly the approved files.
    public let onlyApprovedRemoved: Bool

    public init(
        deleted: Set<FileItem.ID>,
        deletedBytes: Int64,
        folderCountBefore: Int,
        folderCountAfter: Int,
        stillThere: Set<FileItem.ID>,
        onlyApprovedRemoved: Bool
    ) {
        self.deleted = deleted
        self.deletedBytes = deletedBytes
        self.folderCountBefore = folderCountBefore
        self.folderCountAfter = folderCountAfter
        self.stillThere = stillThere
        self.onlyApprovedRemoved = onlyApprovedRemoved
    }

    public var isExact: Bool { stillThere.isEmpty && onlyApprovedRemoved }

    public static func audit(approved: [FileItem], before: Set<FileItem.ID>, after: Set<FileItem.ID>) -> FileDeletionReceipt {
        let ids = Set(approved.map(\.id))
        let deleted = before.subtracting(after)
        return FileDeletionReceipt(
            deleted: deleted,
            deletedBytes: approved.filter { deleted.contains($0.id) }.reduce(0) { $0 + $1.bytes },
            folderCountBefore: before.count,
            folderCountAfter: after.count,
            stillThere: ids.intersection(after),
            onlyApprovedRemoved: after == before.subtracting(ids)
        )
    }
}
