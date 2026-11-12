import XCTest
@testable import StorageCore

/// The duplicate grouping was rewritten to be fast on a whole library. These
/// tests hold it to the plain version it replaced: on thousands of made-up
/// libraries, it must come out with exactly the same groups.
final class DuplicateGroupingTests: XCTestCase {
    /// Repeatable randomness, so a failure can be run again.
    private struct Dice: RandomNumberGenerator {
        var state: UInt64

        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    /// A library with everything the grouping has to tell apart: the same
    /// picture saved twice, shots a moment apart, look-alikes taken days apart,
    /// other shapes and kinds, photos worth keeping, favorites, and prints that
    /// can't be compared (another length, or broken numbers).
    private func library(seed: UInt64, count: Int, dimension: Int) -> (items: [MediaItem], signals: [MediaItem.ID: PhotoSignals]) {
        var dice = Dice(state: seed)
        func unit(_ values: [Float]) -> [Float] {
            let length = values.reduce(0) { $0 + $1 * $1 }.squareRoot()
            return length > 0 ? values.map { $0 / length } : values
        }
        func random() -> [Float] {
            unit((0..<dimension).map { _ in Float.random(in: -1...1, using: &dice) })
        }
        func near(_ base: [Float], by amount: Float) -> [Float] {
            unit(base.map { $0 + Float.random(in: -amount...amount, using: &dice) / Float(dimension).squareRoot() })
        }

        let scenes = (0..<max(3, count / 6)).map { _ in random() }
        var items: [MediaItem] = []
        var signals: [MediaItem.ID: PhotoSignals] = [:]
        for index in 0..<count {
            let id = "p\(index)"
            let scene = scenes[Int.random(in: 0..<scenes.count, using: &dice)]
            // How far from its scene: the same picture, a near-duplicate, or just alike.
            let spread: Float = [0, 0.02, 0.1, 0.25, 0.5, 1.2][Int.random(in: 0..<6, using: &dice)]
            var print = Int.random(in: 0..<5, using: &dice) == 0 ? random() : near(scene, by: spread)
            switch Int.random(in: 0..<40, using: &dice) {
            case 0: print = Array(print.prefix(dimension / 2))
            case 1: print[0] = .nan
            case 2: print[1] = .infinity
            case 3: print = []
            default: break
            }
            // Mostly bunched within minutes of each other, some days away, some at the same instant.
            let minutes: Double = [
                Double(Int.random(in: 0..<30, using: &dice)),
                Double.random(in: 0..<40, using: &dice),
                Double.random(in: 0..<60 * 24 * 30, using: &dice),
            ][Int.random(in: 0..<3, using: &dice)]
            let wide = Int.random(in: 0..<6, using: &dice) != 0
            let size: (Int, Int) = Int.random(in: 0..<30, using: &dice) == 0 ? (0, 0) : (wide ? (4032, 3024) : (3024, 4032))
            var traits: MediaTraits = []
            if Int.random(in: 0..<12, using: &dice) == 0 { traits.insert(.favorite) }
            if Int.random(in: 0..<12, using: &dice) == 0 { traits.insert(.edited) }
            items.append(MediaItem(
                id: id,
                category: Int.random(in: 0..<8, using: &dice) == 0 ? .screenshot : .photo,
                format: .heic, filename: "\(id).HEIC",
                creationDate: referenceDate.addingTimeInterval(minutes * 60),
                pixelWidth: size.0, pixelHeight: size.1, duration: nil,
                originalBytes: Int64.random(in: 500_000...4_000_000, using: &dice),
                thumbnailSeed: 1, traits: traits
            ))
            // One in ten was never measured.
            guard Int.random(in: 0..<10, using: &dice) != 0 else { continue }
            let hasFace = Int.random(in: 0..<5, using: &dice) == 0
            signals[id] = PhotoSignals(
                featurePrint: print,
                sharpness: Double.random(in: 5...600, using: &dice),
                brightness: 0.5, darkFraction: 0.02,
                faceCount: hasFace ? 1 : 0, faceArea: hasFace ? 0.1 : 0,
                faceQuality: hasFace ? Double.random(in: 0...1, using: &dice) : nil
            )
        }
        return (items, signals)
    }

    func testGroupsMatchThePlainVersionOnRandomLibraries() {
        var compared = 0
        var grouped = 0
        for seed in 1...400 {
            let size = [2, 5, 12, 40, 90, 160][Int(seed) % 6]
            let dimension = [4, 16, 48][Int(seed) % 3]
            let (items, signals) = library(seed: UInt64(seed), count: size, dimension: dimension)
            // Tight and loose rules, so both the exact and the near paths decide things.
            for rules in [JunkRules.standard, JunkRules(sameDistance: 0.2, nearDistance: 0.6, nearWindow: 5 * 60, keeperNearDistance: 0.4)] {
                let fast = JunkFinder.duplicateGroups(items, signals: signals, rules: rules)
                let plain = Self.plainDuplicateGroups(items, signals: signals, rules: rules)
                XCTAssertEqual(fast, plain, "seed \(seed), \(size) photos, prints of \(dimension)")
                compared += 1
                grouped += plain.count
            }
        }
        // The libraries have to actually contain duplicates for this to mean anything.
        XCTAssertEqual(compared, 800)
        XCTAssertGreaterThan(grouped, 2_000)
    }

    func testAGroupsIDIsItsMembersInAnyOrder() {
        let a = MediaItem(id: "b", category: .photo, format: .heic, filename: "b.HEIC", creationDate: referenceDate,
                          pixelWidth: 4, pixelHeight: 3, duration: nil, originalBytes: 10, thumbnailSeed: 1)
        let b = MediaItem(id: "a", category: .photo, format: .heic, filename: "a.HEIC", creationDate: referenceDate,
                          pixelWidth: 4, pixelHeight: 3, duration: nil, originalBytes: 10, thumbnailSeed: 1)
        XCTAssertEqual(DuplicateGroup(items: [a, b], isExact: true).id, "a|b")
        XCTAssertEqual(DuplicateGroup(items: [b, a], isExact: true).id, "a|b")
    }

    /// Not a pass-or-fail test: prints how long a big library takes, old way and new.
    /// Run with `SIMPLESHRINK_BENCH=1 swift test -c release --filter Timing`.
    func testTimingOnABigLibrary() throws {
        guard ProcessInfo.processInfo.environment["SIMPLESHRINK_BENCH"] != nil else {
            throw XCTSkip("Set SIMPLESHRINK_BENCH to run the timing.")
        }
        let count = Int(ProcessInfo.processInfo.environment["SIMPLESHRINK_BENCH"] ?? "") ?? 12_000
        var (items, signals) = library(seed: 99, count: count, dimension: 768)
        // A library is mostly photos that look like nothing else in it.
        var dice = Dice(state: 7)
        for (index, item) in items.enumerated() where index % 12 != 0 {
            guard var found = signals[item.id], found.featurePrint.count == 768 else { continue }
            let values = (0..<768).map { _ in Float.random(in: -1...1, using: &dice) }
            let length = values.reduce(0) { $0 + $1 * $1 }.squareRoot()
            found.featurePrint = values.map { $0 / length }
            signals[item.id] = found
        }
        items = items.enumerated().map { index, item in
            MediaItem(id: item.id, category: item.category, format: item.format, filename: item.filename,
                      creationDate: referenceDate.addingTimeInterval(Double(index) * 300),
                      pixelWidth: item.pixelWidth, pixelHeight: item.pixelHeight, duration: nil,
                      originalBytes: item.originalBytes, thumbnailSeed: 1, traits: item.traits)
        }

        var start = Date()
        let fast = JunkFinder.duplicateGroups(items, signals: signals, rules: .standard)
        let fastTime = Date().timeIntervalSince(start)
        start = Date()
        let plain = Self.plainDuplicateGroups(items, signals: signals, rules: .standard)
        let plainTime = Date().timeIntervalSince(start)
        Swift.print(String(format: "TIMING %d photos: new %.2f s, old %.2f s, %d groups", count, fastTime, plainTime, fast.count))
        XCTAssertEqual(fast, plain)
    }

    // MARK: The version it replaced

    /// The grouping as it was before it was made fast, kept here word for word
    /// as the answer the new one is checked against.
    private static func plainDuplicateGroups(_ items: [MediaItem], signals: [MediaItem.ID: PhotoSignals], rules: JunkRules) -> [DuplicateGroup] {
        let measured: [(item: MediaItem, print: [Float], keeper: Bool)] = items
            .compactMap { item in
                guard let found = signals[item.id], !found.featurePrint.isEmpty else { return nil }
                return (item, found.featurePrint, PhotoWorth.keepReason(for: item, signals: found, rules: rules.worth) != nil)
            }
            .sorted { ($0.item.creationDate, $0.item.id) < ($1.item.creationDate, $1.item.id) }
        let reference = measured.first?.print ?? []
        let fromReference: [Float] = measured.map { entry in
            guard entry.print.count == reference.count else { return .nan }
            var sum: Float = 0
            for i in reference.indices {
                let d = entry.print[i] - reference[i]
                sum += d * d
            }
            return sum.squareRoot()
        }
        let nearLimit = max(rules.sameDistance, rules.nearDistance)
        var groups: [[Int]] = []
        var exact: [Bool] = []

        for (position, entry) in measured.enumerated() {
            var joined = false
            for index in groups.indices {
                let first = groups[index][0]
                let inWindow = abs(entry.item.creationDate.timeIntervalSince(measured[first].item.creationDate)) <= rules.nearWindow
                if abs(fromReference[position] - fromReference[first]) >= (inWindow ? nearLimit : rules.sameDistance) + 0.001 {
                    continue
                }
                var allSame = exact[index]
                let fits = groups[index].allSatisfy { member in
                    let other = measured[member]
                    guard other.item.category == entry.item.category, JunkFinder.sameShape(other.item, entry.item) else { return false }
                    if JunkFinder.distance(entry.print, other.print, under: rules.sameDistance) != nil { return true }
                    allSame = false
                    let close = abs(entry.item.creationDate.timeIntervalSince(other.item.creationDate)) <= rules.nearWindow
                    let limit = entry.keeper || other.keeper ? min(rules.keeperNearDistance, rules.nearDistance) : rules.nearDistance
                    return close && JunkFinder.distance(entry.print, other.print, under: limit) != nil
                }
                if fits {
                    groups[index].append(position)
                    exact[index] = allSame
                    joined = true
                    break
                }
            }
            if !joined {
                groups.append([position])
                exact.append(true)
            }
        }

        return zip(groups, exact)
            .compactMap { members, isExact -> DuplicateGroup? in
                guard members.count > 1 else { return nil }
                let sorted = members.map { measured[$0].item }.sorted { JunkFinder.isBetter($0, than: $1, signals: signals) }
                let items = [sorted[0]] + sorted.dropFirst().filter { !$0.traits.contains(.favorite) }
                return items.count > 1 ? DuplicateGroup(items: items, isExact: isExact) : nil
            }
            .sorted { ($0.savedBytes(keeping: $0.suggestedKeeper), $1.id) > ($1.savedBytes(keeping: $1.suggestedKeeper), $0.id) }
    }
}
