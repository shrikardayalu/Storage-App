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

    public init(
        featurePrint: [Float],
        sharpness: Double,
        brightness: Double,
        darkFraction: Double,
        textLines: [String] = [],
        textCoverage: Double = 0
    ) {
        self.featurePrint = featurePrint
        self.sharpness = sharpness
        self.brightness = brightness
        self.darkFraction = darkFraction
        self.textLines = textLines
        self.textCoverage = textCoverage
    }
}

/// Brightness and sharpness of a gray image, measured the same way on every
/// photo so thresholds mean the same thing everywhere.
public enum ImageStats {
    /// - Parameter gray: one byte per pixel, row by row, `width × height` long.
    public static func measure(gray: [UInt8], width: Int, height: Int) -> (sharpness: Double, brightness: Double, darkFraction: Double) {
        guard width > 2, height > 2, gray.count >= width * height else { return (0, 0, 1) }
        var sum = 0.0
        var dark = 0
        for value in gray.prefix(width * height) {
            sum += Double(value)
            if value < 26 { dark += 1 }
        }
        let count = Double(width * height)

        // 4-neighbour Laplacian over the interior; its variance is a standard blur measure.
        var lapSum = 0.0
        var lapSquares = 0.0
        for y in 1..<(height - 1) {
            let row = y * width
            for x in 1..<(width - 1) {
                let i = row + x
                let centre = 4 * Int(gray[i])
                let lap = Double(Int(gray[i - 1]) + Int(gray[i + 1]) + Int(gray[i - width]) + Int(gray[i + width]) - centre)
                lapSum += lap
                lapSquares += lap * lap
            }
        }
        let inner = Double((width - 2) * (height - 2))
        let mean = lapSum / inner
        return (lapSquares / inner - mean * mean, sum / count / 255, Double(dark) / count)
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

/// Where the junk finder draws its lines. Starting values, to be tuned on the
/// test album (Build Plan step 7: most planted junk found, very few good photos flagged).
public struct JunkRules: Hashable, Sendable {
    /// Feature-print distance under which two photos count as the same photo.
    public var sameDistance: Float
    /// Feature-print distance under which two photos taken close together count as near-duplicates.
    public var nearDistance: Float
    /// How far apart near-duplicates can be taken.
    public var nearWindow: TimeInterval
    /// Below this sharpness a photo is blurry.
    public var blurrySharpness: Double
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
        nearWindow: TimeInterval = 60 * 60,
        blurrySharpness: Double = 30,
        darkBrightness: Double = 0.08,
        darkFraction: Double = 0.85,
        documentLines: Int = 6,
        documentCoverage: Double = 0.15,
        oldScreenshotAge: TimeInterval = 30 * 86_400
    ) {
        self.sameDistance = sameDistance
        self.nearDistance = nearDistance
        self.nearWindow = nearWindow
        self.blurrySharpness = blurrySharpness
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

/// Everything the junk finder suggests for the test album. Nothing in it is
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

/// Finds duplicates and junk in the test album from each photo's signals.
public enum JunkFinder {
    /// - Parameters:
    ///   - items: the test album. Videos and burst shots are left to Steps 5 and 6.
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

    /// The single strongest reason to flag `item`, if any.
    static func reason(for item: MediaItem, signals: PhotoSignals?, now: Date, rules: JunkRules) -> JunkReason? {
        if item.category == .screenshot {
            // Screenshots are sharp and full of text by nature; only their age counts.
            return now.timeIntervalSince(item.creationDate) > rules.oldScreenshotAge ? .oldScreenshot : nil
        }
        guard let signals else { return nil }
        if signals.brightness < rules.darkBrightness, signals.darkFraction > rules.darkFraction { return .dark }
        let isPage = signals.textLines.count >= rules.documentLines || signals.textCoverage >= rules.documentCoverage
        if isPage { return isReceipt(signals.textLines) ? .receipt : .document }
        if signals.sharpness < rules.blurrySharpness { return .blurry }
        return nil
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
        let measured = items
            .filter { signals[$0.id]?.featurePrint.isEmpty == false }
            .sorted { ($0.creationDate, $0.id) < ($1.creationDate, $1.id) }
        var groups: [[MediaItem]] = []
        var exact: [Bool] = []

        for item in measured {
            let print = signals[item.id]!.featurePrint
            var joined = false
            for index in groups.indices {
                var allSame = exact[index]
                let fits = groups[index].allSatisfy { other in
                    guard other.category == item.category, sameShape(other, item) else { return false }
                    let otherPrint = signals[other.id]!.featurePrint
                    if distance(print, otherPrint, under: rules.sameDistance) != nil { return true }
                    allSame = false
                    let close = abs(item.creationDate.timeIntervalSince(other.creationDate)) <= rules.nearWindow
                    return close && distance(print, otherPrint, under: rules.nearDistance) != nil
                }
                if fits {
                    groups[index].append(item)
                    exact[index] = allSame
                    joined = true
                    break
                }
            }
            if !joined {
                groups.append([item])
                exact.append(true)
            }
        }

        return zip(groups, exact)
            .filter { $0.0.count > 1 }
            .map { DuplicateGroup(items: $0.0.sorted { isBetter($0, than: $1, signals: signals) }, isExact: $0.1) }
            .sorted { ($0.savedBytes(keeping: $0.suggestedKeeper), $1.id) > ($1.savedBytes(keeping: $1.suggestedKeeper), $0.id) }
    }

    /// The copy to keep: clearly more pixels wins, then the sharper one, then the bigger file, then the older one.
    static func isBetter(_ a: MediaItem, than b: MediaItem, signals: [MediaItem.ID: PhotoSignals]) -> Bool {
        let pa = a.pixelWidth * a.pixelHeight
        let pb = b.pixelWidth * b.pixelHeight
        if Double(max(pa, pb)) > Double(min(pa, pb)) * 1.2 { return pa > pb }
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
