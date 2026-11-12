import Foundation

/// What the app measured about one photo, from a small copy of it. The app's
/// analyzer fills it in with Vision and a pixel pass; tests build them by hand.
public struct PhotoSignals: Hashable, Codable, Sendable {
    /// Vision's feature print: photos that look alike have nearby prints.
    public var featurePrint: [Float]
    /// Variance of the Laplacian on a gray copy (0–255 scale). Low means blurry.
    public var sharpness: Double
    /// Mean brightness, 0 (black) to 1 (white).
    public var brightness: Double
    /// Share of pixels that are nearly black, 0 to 1.
    public var darkFraction: Double
    /// Lines of text Vision read, top to bottom.
    public var textLines: [String]
    /// Share of the picture covered by text, 0 to 1.
    public var textCoverage: Double
    /// Sharpness of the sharpest parts of the picture. A sunset or a portrait
    /// with a soft background is smooth overall but still has a crisp part; a
    /// shaken or out-of-focus shot has none. Nil when it wasn't measured.
    public var peakSharpness: Double?
    /// How many faces Vision found.
    public var faceCount: Int
    /// Share of the picture the biggest face covers, 0 to 1.
    public var faceArea: Double
    /// How well the worst-caught face came out (eyes open, in focus), 0 to 1. Nil with no faces.
    public var faceQuality: Double?
    /// What Vision sees in the picture ("sunset_sunrise", "people", "dog"), each with how sure it is, 0 to 1.
    public var labels: [String: Double]
    /// How good the photo looks, -1 to 1, on phones that can score it (iOS 18 and later).
    public var aesthetics: Double?
    /// Vision's call that this is a practical picture (a note, a label, a parking spot), not a memory.
    public var isUtility: Bool
    /// Which round of measuring made these. Older ones are measured again.
    public var version: Int

    /// Bumped whenever a new measurement is added, so saved ones are redone.
    public static let currentVersion = 2

    public init(
        featurePrint: [Float],
        sharpness: Double,
        brightness: Double,
        darkFraction: Double,
        textLines: [String] = [],
        textCoverage: Double = 0,
        peakSharpness: Double? = nil,
        faceCount: Int = 0,
        faceArea: Double = 0,
        faceQuality: Double? = nil,
        labels: [String: Double] = [:],
        aesthetics: Double? = nil,
        isUtility: Bool = false,
        version: Int = PhotoSignals.currentVersion
    ) {
        self.featurePrint = featurePrint
        self.sharpness = sharpness
        self.brightness = brightness
        self.darkFraction = darkFraction
        self.textLines = textLines
        self.textCoverage = textCoverage
        self.peakSharpness = peakSharpness
        self.faceCount = faceCount
        self.faceArea = faceArea
        self.faceQuality = faceQuality
        self.labels = labels
        self.aesthetics = aesthetics
        self.isUtility = isUtility
        self.version = version
    }
}

/// Brightness and sharpness of a gray image, measured the same way on every
/// photo so thresholds mean the same thing everywhere.
public enum ImageStats {
    /// - Parameter gray: one byte per pixel, row by row, `width × height` long.
    /// - Returns: `peakSharpness` is the second-sharpest tile of a 4 × 4 grid,
    ///   so one stray bright dot doesn't count as a crisp part.
    public static func measure(gray: [UInt8], width: Int, height: Int) -> (sharpness: Double, brightness: Double, darkFraction: Double, peakSharpness: Double) {
        guard width > 2, height > 2, gray.count >= width * height else { return (0, 0, 1, 0) }
        var sum = 0.0
        var dark = 0
        for value in gray.prefix(width * height) {
            sum += Double(value)
            if value < 26 { dark += 1 }
        }
        let count = Double(width * height)

        // 4-neighbour Laplacian over the interior; its variance is a standard blur measure.
        let grid = 4
        var lapSum = 0.0
        var lapSquares = 0.0
        var tileSum = [Double](repeating: 0, count: grid * grid)
        var tileSquares = [Double](repeating: 0, count: grid * grid)
        var tileCount = [Double](repeating: 0, count: grid * grid)
        for y in 1..<(height - 1) {
            let row = y * width
            let tileRow = min(grid - 1, y * grid / height) * grid
            for x in 1..<(width - 1) {
                let i = row + x
                let centre = 4 * Int(gray[i])
                let lap = Double(Int(gray[i - 1]) + Int(gray[i + 1]) + Int(gray[i - width]) + Int(gray[i + width]) - centre)
                lapSum += lap
                lapSquares += lap * lap
                let tile = tileRow + min(grid - 1, x * grid / width)
                tileSum[tile] += lap
                tileSquares[tile] += lap * lap
                tileCount[tile] += 1
            }
        }
        let inner = Double((width - 2) * (height - 2))
        let mean = lapSum / inner
        let tiles = (0..<(grid * grid)).compactMap { tile -> Double? in
            guard tileCount[tile] > 0 else { return nil }
            let tileMean = tileSum[tile] / tileCount[tile]
            return tileSquares[tile] / tileCount[tile] - tileMean * tileMean
        }.sorted(by: >)
        let overall = lapSquares / inner - mean * mean
        let peak = tiles.count > 1 ? tiles[1] : (tiles.first ?? overall)
        return (overall, sum / count / 255, Double(dark) / count, peak)
    }
}

/// Why something was flagged. Every finding is a suggestion the person reviews.
public enum JunkReason: String, CaseIterable, Identifiable, Hashable, Codable, Sendable {
    case duplicate
    case dark
    case blurry
    case receipt
    case document
    case oldScreenshot

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .duplicate: "Duplicates"
        case .dark: "Black and pocket shots"
        case .blurry: "Blurry shots"
        case .receipt: "Receipts"
        case .document: "Documents"
        case .oldScreenshot: "Old screenshots"
        }
    }

    /// Whether findings start ticked. Receipts and documents might still be needed, so they start unticked.
    public var startsSelected: Bool {
        switch self {
        case .receipt, .document: false
        default: true
        }
    }
}

/// Where the junk finder draws its lines (Build Plan step 7: most junk found,
/// very few good photos flagged).
public struct JunkRules: Hashable, Sendable {
    /// Feature-print distance under which two photos count as the same photo.
    public var sameDistance: Float
    /// Feature-print distance under which two photos taken close together count as near-duplicates.
    public var nearDistance: Float
    /// How far apart near-duplicates can be taken.
    public var nearWindow: TimeInterval
    /// Near-duplicates of a photo worth keeping (people, scenery, a great
    /// shot) must be this close: only the same frame taken twice, not a
    /// second take of the sunset.
    public var keeperNearDistance: Float
    /// Below this sharpness a photo is blurry...
    public var blurrySharpness: Double
    /// ...as long as its sharpest parts are below this too.
    public var blurryPeakSharpness: Double
    /// What makes a photo worth keeping whatever its sharpness.
    public var worth: WorthRules
    /// Black or pocket shot: this dark on average, with this much of the frame nearly black.
    public var darkBrightness: Double
    public var darkFraction: Double
    /// A photo of a page: at least this many lines of text, or this much of the frame covered by text.
    public var documentLines: Int
    public var documentCoverage: Double
    /// Screenshots older than this count as old.
    public var oldScreenshotAge: TimeInterval

    public init(
        sameDistance: Float = 0.08,
        nearDistance: Float = 0.32,
        nearWindow: TimeInterval = 10 * 60,
        keeperNearDistance: Float = 0.2,
        blurrySharpness: Double = 30,
        blurryPeakSharpness: Double = 60,
        worth: WorthRules = .standard,
        darkBrightness: Double = 0.08,
        darkFraction: Double = 0.85,
        documentLines: Int = 6,
        documentCoverage: Double = 0.15,
        oldScreenshotAge: TimeInterval = 30 * 86_400
    ) {
        self.sameDistance = sameDistance
        self.nearDistance = nearDistance
        self.nearWindow = nearWindow
        self.keeperNearDistance = keeperNearDistance
        self.blurrySharpness = blurrySharpness
        self.blurryPeakSharpness = blurryPeakSharpness
        self.worth = worth
        self.darkBrightness = darkBrightness
        self.darkFraction = darkFraction
        self.documentLines = documentLines
        self.documentCoverage = documentCoverage
        self.oldScreenshotAge = oldScreenshotAge
    }

    public static let standard = JunkRules()
}

/// Photos that are the same shot, best first. The first is kept unless the person picks another.
public struct DuplicateGroup: Identifiable, Hashable, Sendable {
    public let items: [MediaItem]
    /// True when every copy is the same picture, not just a near-duplicate.
    public let isExact: Bool

    /// Stable while the group's members don't change.
    public var id: String { items.map(\.id).sorted().joined(separator: "|") }

    public var suggestedKeeper: MediaItem.ID { items[0].id }

    public init(items: [MediaItem], isExact: Bool) {
        self.items = items
        self.isExact = isExact
    }

    public func savedBytes(keeping keeper: MediaItem.ID) -> Int64 {
        items.filter { $0.id != keeper }.reduce(0) { $0 + $1.currentBytes }
    }
}

/// One photo flagged for a single reason.
public struct JunkFinding: Identifiable, Hashable, Sendable {
    public let item: MediaItem
    public let reason: JunkReason

    public var id: MediaItem.ID { item.id }

    public init(item: MediaItem, reason: JunkReason) {
        self.item = item
        self.reason = reason
    }
}

/// Everything the junk finder suggests for the library. Nothing in it is
/// removed until the person reviews and approves it.
public struct JunkReport: Hashable, Sendable {
    public let duplicates: [DuplicateGroup]
    /// Single-photo findings, one reason each. Never includes a duplicate group's member.
    public let findings: [JunkFinding]

    public init(duplicates: [DuplicateGroup], findings: [JunkFinding]) {
        self.duplicates = duplicates
        self.findings = findings
    }

    public var isEmpty: Bool { duplicates.isEmpty && findings.isEmpty }

    public func findings(for reason: JunkReason) -> [JunkFinding] {
        findings.filter { $0.reason == reason }
    }

    /// Space freed by removing the suggested extras of every group and every finding.
    public var suggestedBytes: Int64 {
        duplicates.reduce(0) { $0 + $1.savedBytes(keeping: $1.suggestedKeeper) }
            + findings.reduce(0) { $0 + $1.item.currentBytes }
    }

    /// How many photos the report suggests removing.
    public var suggestedCount: Int {
        duplicates.reduce(0) { $0 + $1.items.count - 1 } + findings.count
    }

    /// Refuses a removal that would take every copy of a duplicate group, or a picked keeper.
    /// - Parameters:
    ///   - remove: what the person approved removing.
    ///   - keepers: the copy they kept in each duplicate group they touched.
    public func validate(remove: Set<MediaItem.ID>, keepers: Set<MediaItem.ID>) throws {
        guard remove.isDisjoint(with: keepers) else {
            throw PhotoChangeError.junkChanged("A photo you chose to keep was also marked for removal.")
        }
        for group in duplicates {
            let ids = Set(group.items.map(\.id))
            if ids.isSubset(of: remove) {
                throw PhotoChangeError.junkChanged("Every copy of a duplicate was marked for removal.")
            }
            if !ids.isDisjoint(with: remove), ids.isDisjoint(with: keepers) {
                throw PhotoChangeError.junkChanged("A duplicate has no copy picked to keep.")
            }
        }
    }
}

/// Finds duplicates and junk in the library from each photo's signals.
public enum JunkFinder {
    /// - Parameters:
    ///   - items: the scanned library. Videos and burst shots are left to Steps 5 and 6.
    ///   - signals: measurements per photo. Photos without signals are only checked for age.
    ///   - now: what "old" is measured from.
    public static func find(
        in items: [MediaItem],
        signals: [MediaItem.ID: PhotoSignals],
        now: Date,
        rules: JunkRules = .standard
    ) -> JunkReport {
        let candidates = items.filter { $0.category != .video && $0.burstID == nil }
        let duplicates = duplicateGroups(candidates, signals: signals, rules: rules)
        let grouped = Set(duplicates.flatMap(\.items).map(\.id))

        var findings: [JunkFinding] = []
        for item in candidates where !grouped.contains(item.id) {
            if let reason = reason(for: item, signals: signals[item.id], now: now, rules: rules) {
                findings.append(JunkFinding(item: item, reason: reason))
            }
        }
        findings.sort { ($0.item.currentBytes, $1.item.id) > ($1.item.currentBytes, $0.item.id) }
        return JunkReport(duplicates: duplicates, findings: findings)
    }

    /// The single strongest reason to flag `item`, if any. Favorites and
    /// edited photos are never flagged, and a photo worth keeping (people,
    /// pets, scenery, a great shot) is never flagged for being soft or dark.
    static func reason(for item: MediaItem, signals: PhotoSignals?, now: Date, rules: JunkRules) -> JunkReason? {
        if !item.traits.isDisjoint(with: [.favorite, .edited]) { return nil }
        if item.category == .screenshot {
            // Screenshots are sharp and full of text by nature; only their age counts.
            return now.timeIntervalSince(item.creationDate) > rules.oldScreenshotAge ? .oldScreenshot : nil
        }
        guard let signals else { return nil }
        let keep = PhotoWorth.keepReason(for: item, signals: signals, rules: rules.worth) != nil
        if !keep, signals.brightness < rules.darkBrightness, signals.darkFraction > rules.darkFraction { return .dark }
        let isPage = signals.textLines.count >= rules.documentLines || signals.textCoverage >= rules.documentCoverage
        if isPage { return isReceipt(signals.textLines) ? .receipt : .document }
        if !keep, isBlurry(signals, rules: rules) { return .blurry }
        return nil
    }

    /// Soft all over, with no crisp part anywhere, and not a photo Vision rates as good-looking.
    static func isBlurry(_ signals: PhotoSignals, rules: JunkRules) -> Bool {
        guard signals.sharpness < rules.blurrySharpness else { return false }
        if let peak = signals.peakSharpness, peak >= rules.blurryPeakSharpness { return false }
        if let aesthetics = signals.aesthetics, aesthetics >= rules.worth.pleasantAesthetics { return false }
        return true
    }

    /// Prices plus a word receipts use.
    static func isReceipt(_ lines: [String]) -> Bool {
        let text = lines.joined(separator: "\n").lowercased()
        let words = ["total", "subtotal", "tax", "change due", "cash", "visa", "mastercard", "receipt", "amount", "balance", "tip"]
        guard words.contains(where: { text.contains($0) }) else { return false }
        let prices = text.matches(of: #/\d+[.,]\d{2}\b/#).count
        return prices >= 2
    }

    /// Groups photos that look the same. Each photo joins a group only if it is
    /// close to every photo already in it, so a run of similar shots doesn't chain together.
    static func duplicateGroups(_ items: [MediaItem], signals: [MediaItem.ID: PhotoSignals], rules: JunkRules) -> [DuplicateGroup] {
        // Items and prints side by side, so the inner loop never looks an ID
        // up: a whole library is tens of thousands of photos.
        // `keeper`: a photo worth keeping, whose near-duplicates must be the same frame.
        let measured: [(item: MediaItem, print: [Float], keeper: Bool)] = items
            .compactMap { item in
                guard let found = signals[item.id], !found.featurePrint.isEmpty else { return nil }
                return (item, found.featurePrint, PhotoWorth.keepReason(for: item, signals: found, rules: rules.worth) != nil)
            }
            .sorted { ($0.item.creationDate, $0.item.id) < ($1.item.creationDate, $1.item.id) }
        // Each photo's distance to one fixed print. Two prints can't be closer
        // to each other than their distances to a third differ, so most pairs
        // are ruled out with one subtraction instead of a full comparison.
        // Without this a whole library takes many seconds to group.
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
        // Each group holds indexes into `measured`.
        var groups: [[Int]] = []
        var exact: [Bool] = []

        for (position, entry) in measured.enumerated() {
            var joined = false
            for index in groups.indices {
                // To join, the photo must at least be close to the group's first member.
                let first = groups[index][0]
                let inWindow = abs(entry.item.creationDate.timeIntervalSince(measured[first].item.creationDate)) <= rules.nearWindow
                // NaN (prints of different lengths) never skips; the full check decides.
                if abs(fromReference[position] - fromReference[first]) >= (inWindow ? nearLimit : rules.sameDistance) + 0.001 {
                    continue
                }
                var allSame = exact[index]
                let fits = groups[index].allSatisfy { member in
                    let other = measured[member]
                    guard other.item.category == entry.item.category, sameShape(other.item, entry.item) else { return false }
                    if distance(entry.print, other.print, under: rules.sameDistance) != nil { return true }
                    allSame = false
                    let close = abs(entry.item.creationDate.timeIntervalSince(other.item.creationDate)) <= rules.nearWindow
                    let limit = entry.keeper || other.keeper ? min(rules.keeperNearDistance, rules.nearDistance) : rules.nearDistance
                    return close && distance(entry.print, other.print, under: limit) != nil
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
                let sorted = members.map { measured[$0].item }.sorted { isBetter($0, than: $1, signals: signals) }
                // A favorite is never an extra copy to remove: it's the keeper, or it's left out.
                let items = [sorted[0]] + sorted.dropFirst().filter { !$0.traits.contains(.favorite) }
                return items.count > 1 ? DuplicateGroup(items: items, isExact: isExact) : nil
            }
            .sorted { ($0.savedBytes(keeping: $0.suggestedKeeper), $1.id) > ($1.savedBytes(keeping: $1.suggestedKeeper), $0.id) }
    }

    /// The copy to keep: a favorite, then an edited one, then clearly more
    /// pixels, then the one where faces came out better, then the sharper
    /// one, then the bigger file, then the older one.
    static func isBetter(_ a: MediaItem, than b: MediaItem, signals: [MediaItem.ID: PhotoSignals]) -> Bool {
        for trait in [MediaTraits.favorite, .edited] where a.traits.contains(trait) != b.traits.contains(trait) {
            return a.traits.contains(trait)
        }
        let pa = a.pixelWidth * a.pixelHeight
        let pb = b.pixelWidth * b.pixelHeight
        if Double(max(pa, pb)) > Double(min(pa, pb)) * 1.2 { return pa > pb }
        if let fa = signals[a.id]?.faceQuality, let fb = signals[b.id]?.faceQuality, abs(fa - fb) > 0.1 { return fa > fb }
        let sa = signals[a.id]?.sharpness ?? 0
        let sb = signals[b.id]?.sharpness ?? 0
        if abs(sa - sb) > max(sa, sb) * 0.1 { return sa > sb }
        if a.currentBytes != b.currentBytes { return a.currentBytes > b.currentBytes }
        return (a.creationDate, a.id) < (b.creationDate, b.id)
    }

    /// Same orientation and aspect ratio within 2%. A crop or rotation isn't a duplicate.
    static func sameShape(_ a: MediaItem, _ b: MediaItem) -> Bool {
        guard a.pixelWidth > 0, a.pixelHeight > 0, b.pixelWidth > 0, b.pixelHeight > 0 else { return false }
        let ra = Double(a.pixelWidth) / Double(a.pixelHeight)
        let rb = Double(b.pixelWidth) / Double(b.pixelHeight)
        return abs(ra - rb) / max(ra, rb) < 0.02
    }

    /// Euclidean distance between two prints, or nil as soon as it reaches `limit`.
    static func distance(_ a: [Float], _ b: [Float], under limit: Float) -> Float? {
        guard a.count == b.count, !a.isEmpty else { return nil }
        let cap = limit * limit
        var sum: Float = 0
        for i in a.indices {
            let d = a[i] - b[i]
            sum += d * d
            if sum >= cap { return nil }
        }
        return sum.squareRoot()
    }
}
