import Foundation

/// Item count and storage for one slice of the library.
public struct CategoryTotal: Hashable, Sendable {
    public var count: Int
    public var bytes: Int64

    public init(count: Int = 0, bytes: Int64 = 0) {
        self.count = count
        self.bytes = bytes
    }

    public static let zero = CategoryTotal()
}
