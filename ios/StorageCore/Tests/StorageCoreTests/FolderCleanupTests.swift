import XCTest
@testable import StorageCore

/// Step 8: the app only sees the picked folder, and deleted files are actually gone.
final class FolderCleanupTests: XCTestCase {
    private let folder = URL(fileURLWithPath: "/var/mobile/Storage App Test", isDirectory: true)

    private func file(_ path: String, mb: Double, daysAgo: Double = 1, hash: String? = nil) -> FileItem {
        FileItem(
            path: path,
            bytes: Int64(mb * 1_000_000),
            modified: referenceDate.addingTimeInterval(-daysAgo * 86_400),
            contentHash: hash
        )
    }

    /// The planted "Storage App Test" folder.
    private func plantedFolder() -> [FileItem] {
        [
            file("Holiday.mov", mb: 420, daysAgo: 3),
            file("Backup.zip", mb: 150, daysAgo: 20),
            file("Manual.pdf", mb: 12, daysAgo: 400, hash: nil),
            file("Report.pdf", mb: 4, daysAgo: 30, hash: "abc"),
            file("Report copy.pdf", mb: 4, daysAgo: 2, hash: "abc"),
            file("Old/Report.pdf", mb: 4, daysAgo: 1, hash: "abc"),
            file("Invoice.pdf", mb: 0.2, daysAgo: 300),
            file("Notes.txt", mb: 0.01, daysAgo: 2),
        ]
    }

    private func report() -> FileReport {
        FileCleanup.report(for: FolderScan(folderName: "Storage App Test", files: plantedFolder()), now: referenceDate)
    }

    // MARK: Finding

    func testFindsLargeDuplicateAndOldFiles() {
        let report = report()
        XCTAssertEqual(report.large.map(\.id), ["Holiday.mov", "Backup.zip", "Manual.pdf"])
        XCTAssertEqual(report.duplicates.count, 1)
        XCTAssertEqual(report.old.map(\.id), ["Invoice.pdf"], "a large old file is listed once, as large")
        XCTAssertFalse(report.large.contains { $0.id == "Notes.txt" })
    }

    func testKeepsTheOriginalNotTheCopy() {
        let group = report().duplicates[0]
        XCTAssertEqual(group.suggestedKeeper, "Report.pdf")
        XCTAssertEqual(group.savedBytes(keeping: "Report.pdf"), 8_000_000)
    }

    func testSameSizeDifferentContentIsNotADuplicate() {
        let scan = FolderScan(folderName: "F", files: [file("a.bin", mb: 1, hash: "x"), file("b.bin", mb: 1, hash: "y")])
        XCTAssertTrue(FileCleanup.report(for: scan, now: referenceDate).duplicates.isEmpty)
    }

    func testCopyNames() {
        for name in ["Report copy.pdf", "Report (1).pdf", "Report 2.pdf", "Report-1.pdf", "Report copy 2.pdf"] {
            XCTAssertTrue(FileCleanup.looksLikeCopy(name), name)
        }
        for name in ["Report.pdf", "Copyright.pdf", "2024 Taxes.pdf"] {
            XCTAssertFalse(FileCleanup.looksLikeCopy(name), name)
        }
    }

    // MARK: Staying inside the picked folder

    func testOnlyPathsStrictlyInsideThePickedFolderCount() {
        XCTAssertTrue(PickedFolder.contains(root: folder, candidate: folder.appendingPathComponent("a.zip")))
        XCTAssertTrue(PickedFolder.contains(root: folder, candidate: folder.appendingPathComponent("Sub/b.zip")))
        XCTAssertFalse(PickedFolder.contains(root: folder, candidate: folder), "the folder itself is never a file to delete")
        XCTAssertFalse(PickedFolder.contains(root: folder, candidate: URL(fileURLWithPath: "/var/mobile/Storage App Test 2/a.zip")))
        XCTAssertFalse(PickedFolder.contains(root: folder, candidate: URL(fileURLWithPath: "/var/mobile/Other/a.zip")))
        XCTAssertFalse(PickedFolder.contains(root: folder, candidate: folder.appendingPathComponent("../Other/a.zip")))
        XCTAssertEqual(PickedFolder.relativePath(of: folder.appendingPathComponent("Sub/b.zip"), in: folder), "Sub/b.zip")
        XCTAssertNil(PickedFolder.relativePath(of: URL(fileURLWithPath: "/etc/hosts"), in: folder))
    }

    // MARK: Deleting

    func testDeletesExactlyTheApprovedFiles() async throws {
        let outside = file("Elsewhere.mov", mb: 500)
        let mock = MockFolderFiles(files: plantedFolder(), outsideFiles: [outside])
        let scan = try await mock.scan(folder)
        let approved = [scan["Holiday.mov"]!, scan["Report copy.pdf"]!]

        let receipt = try await mock.delete(approved, keeping: [scan["Report.pdf"]!], in: folder)
        XCTAssertTrue(receipt.isExact)
        XCTAssertEqual(receipt.deleted, ["Holiday.mov", "Report copy.pdf"])
        XCTAssertEqual(receipt.deletedBytes, 424_000_000)
        XCTAssertEqual(receipt.folderCountBefore - receipt.folderCountAfter, 2)
        let left = await mock.files.map(\.id)
        XCTAssertFalse(left.contains("Holiday.mov"))
        XCTAssertTrue(left.contains("Report.pdf"))
        let untouched = await mock.outsideFiles
        XCTAssertEqual(untouched, [outside])
    }

    func testAFileChangedSinceTheReviewBlocksEverything() async throws {
        let mock = MockFolderFiles(files: plantedFolder())
        let scan = try await mock.scan(folder)
        await mock.replace(file("Backup.zip", mb: 151, daysAgo: 0))

        do {
            _ = try await mock.delete([scan["Holiday.mov"]!, scan["Backup.zip"]!], keeping: [], in: folder)
            XCTFail("should refuse")
        } catch FileChangeError.unsafe(let check) {
            XCTAssertEqual(check.changed, ["Backup.zip"])
        }
        let count = await mock.deleteCount
        XCTAssertEqual(count, 0)
        let left = await mock.files.count
        XCTAssertEqual(left, plantedFolder().count, "nothing was deleted")
    }

    func testAMissingKeeperBlocksDeletingItsCopies() async throws {
        let mock = MockFolderFiles(files: plantedFolder())
        let scan = try await mock.scan(folder)
        let keeper = scan["Report.pdf"]!
        await mock.replace(file("Report.pdf", mb: 4, daysAgo: 0, hash: "abc"))

        do {
            _ = try await mock.delete([scan["Report copy.pdf"]!], keeping: [keeper], in: folder)
            XCTFail("should refuse")
        } catch FileChangeError.unsafe(let check) {
            XCTAssertEqual(check.keepersMissing, ["Report.pdf"])
        }
    }

    func testReportRefusesDeletingEveryCopy() {
        let report = report()
        XCTAssertThrowsError(try report.validate(remove: ["Report.pdf", "Report copy.pdf", "Old/Report.pdf"], keepers: []))
        XCTAssertThrowsError(try report.validate(remove: ["Report copy.pdf"], keepers: []))
        XCTAssertNoThrow(try report.validate(remove: ["Report copy.pdf", "Holiday.mov"], keepers: ["Report.pdf"]))
    }

    func testReceiptNoticesFilesThatAreStillThere() {
        let approved = [file("a", mb: 1), file("b", mb: 1)]
        let receipt = FileDeletionReceipt.audit(approved: approved, before: ["a", "b", "c"], after: ["b", "c"])
        XCTAssertFalse(receipt.isExact)
        XCTAssertEqual(receipt.stillThere, ["b"])
        XCTAssertEqual(receipt.deletedBytes, 1_000_000)
    }
}
