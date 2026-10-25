import XCTest
@testable import StorageCore

final class ByteFormatterTests: XCTestCase {
    func testBytesBelowOneKilobyte() {
        XCTAssertEqual(ByteFormatter.string(0), "0 bytes")
        XCTAssertEqual(ByteFormatter.string(1), "1 byte")
        XCTAssertEqual(ByteFormatter.string(999), "999 bytes")
    }

    func testKilobytesMegabytesGigabytes() {
        XCTAssertEqual(ByteFormatter.string(1_000), "1.0 KB")
        XCTAssertEqual(ByteFormatter.string(512_000), "512 KB")
        XCTAssertEqual(ByteFormatter.string(4_200_000), "4.2 MB")
        XCTAssertEqual(ByteFormatter.string(512_000_000), "512 MB")
        XCTAssertEqual(ByteFormatter.string(1_400_000_000), "1.4 GB")
        XCTAssertEqual(ByteFormatter.string(23_600_000_000), "24 GB")
        XCTAssertEqual(ByteFormatter.string(2_000_000_000_000), "2.0 TB")
    }

    func testValuesThatWouldRoundToOneThousandMoveUpAUnit() {
        XCTAssertEqual(ByteFormatter.string(999_700), "1.0 MB")
        XCTAssertEqual(ByteFormatter.string(999_600_000), "1.0 GB")
    }

    func testOneDecimalBelowTenNoneAbove() {
        XCTAssertEqual(ByteFormatter.string(9_940_000), "9.9 MB")
        XCTAssertEqual(ByteFormatter.string(9_960_000), "10 MB")
    }

    func testValueAndUnitMatchFullString() {
        for bytes: Int64 in [0, 999, 1_500, 999_700, 42_000_000, 7_300_000_000] {
            XCTAssertEqual("\(ByteFormatter.value(bytes)) \(ByteFormatter.unitLabel(bytes))", ByteFormatter.string(bytes))
        }
    }

    func testTwoDecimalsMatchesSettings() {
        XCTAssertEqual(ByteFormatter.string(125_110_000_000, precision: .twoDecimals), "125.11 GB")
        XCTAssertEqual(ByteFormatter.string(2_894_000_000, precision: .twoDecimals), "2.89 GB")
        XCTAssertEqual(ByteFormatter.string(512_346_000, precision: .twoDecimals), "512.35 MB")
        XCTAssertEqual(ByteFormatter.string(999_996_000, precision: .twoDecimals), "1.00 GB")
        XCTAssertEqual(ByteFormatter.string(999, precision: .twoDecimals), "999 bytes")
        XCTAssertEqual(ByteFormatter.accessibilityString(125_110_000_000, precision: .twoDecimals), "125.11 gigabytes")
    }

    func testAccessibilityStringSpellsOutUnits() {
        XCTAssertEqual(ByteFormatter.accessibilityString(1_400_000_000), "1.4 gigabytes")
        XCTAssertEqual(ByteFormatter.accessibilityString(250_000_000), "250 megabytes")
    }

    func testDurationFormatting() {
        XCTAssertEqual(DurationFormatter.string(0), "0:00")
        XCTAssertEqual(DurationFormatter.string(42), "0:42")
        XCTAssertEqual(DurationFormatter.string(605), "10:05")
        XCTAssertEqual(DurationFormatter.string(3_725), "1:02:05")
    }
}
