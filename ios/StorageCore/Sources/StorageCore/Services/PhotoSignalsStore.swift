import Foundation

/// Keeps photo measurements between launches, so a library of tens of
/// thousands of photos is only measured once. It's a cache: losing it only
/// means measuring again, and nothing in it leaves the phone.
///
/// The file is a run of blocks, each a 4-byte length followed by a property
/// list of records. New measurements are added to the end, so saving a few
/// hundred photos never rewrites the whole file.
public struct PhotoSignalsStore: Sendable {
    /// Where the measurements are kept; nil keeps nothing (tests and previews).
    public let fileURL: URL?

    public init(fileURL: URL?) {
        self.fileURL = fileURL
    }

    public static let inMemory = PhotoSignalsStore(fileURL: nil)

    /// Every saved measurement. A block that can't be read ends the load;
    /// what came before it is still used.
    public func load() -> [MediaItem.ID: PhotoSignals] {
        guard let fileURL, let data = try? Data(contentsOf: fileURL, options: .mappedIfSafe) else { return [:] }
        var signals: [MediaItem.ID: PhotoSignals] = [:]
        var offset = 0
        while offset + 4 <= data.count {
            let length = data.subdata(in: offset..<offset + 4).reduce(0) { $0 << 8 | Int($1) }
            offset += 4
            guard length > 0, offset + length <= data.count,
                  let records = try? PropertyListDecoder().decode([Record].self, from: data.subdata(in: offset..<offset + length)) else { break }
            offset += length
            for record in records { signals[record.id] = record.signals }
        }
        return signals
    }

    /// Adds measurements to the end of the file.
    public func append(_ signals: [MediaItem.ID: PhotoSignals]) {
        guard let fileURL, !signals.isEmpty, let block = Self.block(signals) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: block)
        } else {
            try? block.write(to: fileURL, options: .atomic)
        }
    }

    /// Replaces the file with exactly these measurements, dropping photos that are gone.
    public func rewrite(_ signals: [MediaItem.ID: PhotoSignals]) {
        guard let fileURL else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? (Self.block(signals) ?? Data()).write(to: fileURL, options: .atomic)
    }

    private static func block(_ signals: [MediaItem.ID: PhotoSignals]) -> Data? {
        guard !signals.isEmpty else { return nil }
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        guard let body = try? encoder.encode(signals.map { Record(id: $0.key, signals: $0.value) }) else { return nil }
        var block = Data(capacity: body.count + 4)
        for shift in [24, 16, 8, 0] { block.append(UInt8(truncatingIfNeeded: body.count >> shift)) }
        block.append(body)
        return block
    }

    /// One photo's measurements as stored. The feature print's values lie
    /// between -1 and 1, so each is kept as a 16-bit number: half the size,
    /// and far finer than the distances the junk finder compares.
    struct Record: Codable {
        var id: String
        var print: Data
        var sharpness: Double
        var brightness: Double
        var darkFraction: Double
        var textLines: [String]
        var textCoverage: Double
        // Added later, so files saved before them still load. A record
        // without a version is from the first round and gets measured again.
        var peakSharpness: Double?
        var faceCount: Int?
        var faceArea: Double?
        var faceQuality: Double?
        var labels: [String: Double]?
        var aesthetics: Double?
        var isUtility: Bool?
        var version: Int?

        init(id: String, signals: PhotoSignals) {
            self.id = id
            var bytes = Data(capacity: signals.featurePrint.count * 2)
            for value in signals.featurePrint {
                let scaled = Int16((max(-1, min(1, value)) * 32_767).rounded())
                bytes.append(UInt8(truncatingIfNeeded: scaled >> 8))
                bytes.append(UInt8(truncatingIfNeeded: scaled))
            }
            print = bytes
            sharpness = signals.sharpness
            brightness = signals.brightness
            darkFraction = signals.darkFraction
            textLines = signals.textLines
            textCoverage = signals.textCoverage
            peakSharpness = signals.peakSharpness
            faceCount = signals.faceCount
            faceArea = signals.faceArea
            faceQuality = signals.faceQuality
            labels = signals.labels
            aesthetics = signals.aesthetics
            isUtility = signals.isUtility
            version = signals.version
        }

        var signals: PhotoSignals {
            var values: [Float] = []
            values.reserveCapacity(print.count / 2)
            var index = print.startIndex
            while index + 1 < print.endIndex {
                let scaled = Int16(bitPattern: UInt16(print[index]) << 8 | UInt16(print[index + 1]))
                values.append(Float(scaled) / 32_767)
                index += 2
            }
            return PhotoSignals(
                featurePrint: values, sharpness: sharpness, brightness: brightness,
                darkFraction: darkFraction, textLines: textLines, textCoverage: textCoverage,
                peakSharpness: peakSharpness, faceCount: faceCount ?? 0, faceArea: faceArea ?? 0,
                faceQuality: faceQuality, labels: labels ?? [:], aesthetics: aesthetics,
                isUtility: isUtility ?? false, version: version ?? 1
            )
        }
    }
}
