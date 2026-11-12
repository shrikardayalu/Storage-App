import Foundation

/// Why a photo is better left as it is: a memory someone would want kept,
/// not junk and not a Live Photo to flatten.
public enum KeepReason: String, CaseIterable, Hashable, Codable, Sendable {
    case favorite
    case edited
    case people
    case animals
    case scenic
    case striking
    /// The photo hasn't been looked at yet, so nothing is suggested for it.
    case notChecked

    /// A few words for the row, after "kept Live:" or on its own.
    public var note: String {
        switch self {
        case .favorite: "a favorite"
        case .edited: "you edited it"
        case .people: "people in it"
        case .animals: "a pet or animal"
        case .scenic: "scenery"
        case .striking: "a great shot"
        case .notChecked: "not checked yet"
        }
    }
}

/// Where the lines are drawn for a photo worth keeping.
public struct WorthRules: Hashable, Sendable {
    /// How sure Vision must be of a label ("sunset", "people") before it counts.
    public var labelConfidence: Double
    /// A face this big (share of the frame) is someone the photo is about, not a passer-by.
    public var faceArea: Double
    /// From this score up, Vision rates the photo as a great shot, whatever is in it.
    public var strikingAesthetics: Double
    /// From this score up a photo looks fine: scenery counts as scenery, and a soft photo isn't called blurry.
    public var pleasantAesthetics: Double

    public init(
        labelConfidence: Double = 0.3,
        faceArea: Double = 0.004,
        strikingAesthetics: Double = 0.55,
        pleasantAesthetics: Double = 0.1
    ) {
        self.labelConfidence = labelConfidence
        self.faceArea = faceArea
        self.strikingAesthetics = strikingAesthetics
        self.pleasantAesthetics = pleasantAesthetics
    }

    public static let standard = WorthRules()
}

/// Decides whether a photo looks like one someone would want kept, from
/// what Photos and Vision say about it. It errs towards keeping: a wrong
/// "keep" only leaves a photo alone, a wrong "junk" suggests deleting a memory.
public enum PhotoWorth {
    /// Words in Vision's labels that mean people are in the picture.
    static let peopleWords: Set<String> = [
        "people", "person", "adult", "child", "children", "baby", "infant", "toddler", "teen", "kid",
        "crowd", "portrait", "selfie", "face", "bride", "groom", "wedding", "family", "man", "woman", "boy", "girl",
    ]
    static let animalWords: Set<String> = [
        "pet", "dog", "puppy", "cat", "kitten", "animal", "bird", "horse", "rabbit", "hamster", "fish", "wildlife",
        "mammal", "reptile", "canine", "feline",
    ]
    static let scenicWords: Set<String> = [
        "sunset", "sunrise", "sky", "cloud", "cloudy", "clouds", "mountain", "mountains", "hill", "valley", "canyon",
        "cliff", "beach", "ocean", "sea", "coast", "shore", "lake", "river", "waterfall", "landscape", "forest",
        "desert", "island", "glacier", "volcano", "aurora", "rainbow", "fireworks", "moon", "star", "stars",
        "skyline", "cityscape", "snow", "sunbeam", "horizon", "meadow", "field", "garden", "vista", "nature",
    ]

    /// Why `item` is worth keeping, or nil when nothing says so.
    /// - Parameter countEdits: whether having been edited is a reason by itself.
    public static func keepReason(
        for item: MediaItem,
        signals: PhotoSignals?,
        rules: WorthRules = .standard,
        countEdits: Bool = true
    ) -> KeepReason? {
        if item.traits.contains(.favorite) { return .favorite }
        if countEdits, item.traits.contains(.edited) { return .edited }
        guard let signals else { return nil }
        return keepReason(for: signals, rules: rules)
    }

    /// Why a photo with these signals is worth keeping, from what's in the picture alone.
    public static func keepReason(for signals: PhotoSignals, rules: WorthRules = .standard) -> KeepReason? {
        if signals.faceCount > 0, signals.faceArea >= rules.faceArea { return .people }
        if has(peopleWords, in: signals, rules: rules) { return .people }
        if has(animalWords, in: signals, rules: rules) { return .animals }
        // A practical picture (a label, a parking spot) is never scenery or a great shot.
        if signals.isUtility { return nil }
        if let aesthetics = signals.aesthetics, aesthetics >= rules.strikingAesthetics { return .striking }
        // Scenery counts unless Vision rates the shot as poor.
        if has(scenicWords, in: signals, rules: rules), (signals.aesthetics ?? rules.pleasantAesthetics) >= rules.pleasantAesthetics {
            return .scenic
        }
        return nil
    }

    /// Whether Vision is sure enough of a label made of any of `words` ("blue_sky" has "sky").
    static func has(_ words: Set<String>, in signals: PhotoSignals, rules: WorthRules) -> Bool {
        signals.labels.contains { label, confidence in
            confidence >= rules.labelConfidence
                && label.lowercased().split(whereSeparator: { !$0.isLetter }).contains { words.contains(String($0)) }
        }
    }
}

/// Which Live Photos don't need to be Live. A still does fine for a photo
/// of a meal or a sign; people, pets, scenery, favorites and great shots are
/// where the moving part matters, so those stay Live unless the person picks them.
public enum LiveStills {
    /// Why this Live Photo is better left Live, or nil when a still would do.
    /// A photo that hasn't been measured is never suggested.
    public static func keepReason(for item: MediaItem, signals: PhotoSignals?, rules: WorthRules = .standard) -> KeepReason? {
        if item.traits.contains(.favorite) { return .favorite }
        guard let signals else { return .notChecked }
        // An edit alone doesn't mean the moving part matters.
        return PhotoWorth.keepReason(for: item, signals: signals, rules: rules, countEdits: false)
    }

    /// Why each of these Live Photos stays Live. Photos missing from the result are suggested as stills.
    public static func keepReasons(
        for livePhotos: [MediaItem],
        signals: [MediaItem.ID: PhotoSignals],
        rules: WorthRules = .standard
    ) -> [MediaItem.ID: KeepReason] {
        var reasons: [MediaItem.ID: KeepReason] = [:]
        for item in livePhotos {
            if let reason = keepReason(for: item, signals: signals[item.id], rules: rules) { reasons[item.id] = reason }
        }
        return reasons
    }
}
