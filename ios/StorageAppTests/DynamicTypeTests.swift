import SwiftUI
import UIKit
import XCTest
@testable import StorageApp

/// Display headlines follow the text-size setting, within a cap.
final class DynamicTypeTests: XCTestCase {
    private func size(_ base: CGFloat, at category: UIContentSizeCategory) -> CGFloat {
        Font.displaySize(base, relativeTo: .largeTitle, traits: UITraitCollection(preferredContentSizeCategory: category))
    }

    func testDefaultTextSizeKeepsTheDesignSize() {
        XCTAssertEqual(size(40, at: .large), 40, accuracy: 0.5)
    }

    func testLargerTextGrowsHeadlines() {
        XCTAssertGreaterThan(size(40, at: .extraExtraExtraLarge), 40)
    }

    func testSmallerTextShrinksHeadlines() {
        XCTAssertLessThan(size(40, at: .extraSmall), 40)
    }

    func testTheLargestSettingsAreCapped() {
        XCTAssertEqual(size(40, at: .accessibilityExtraExtraExtraLarge), 40 * Font.displayMaxScale, accuracy: 0.01)
    }

    func testEveryTextStyleMapsToUIKit() {
        let styles: [Font.TextStyle] = [.largeTitle, .title, .title2, .title3, .headline, .subheadline, .body, .callout, .footnote, .caption, .caption2]
        XCTAssertEqual(Set(styles.map(\.uiKit)).count, styles.count)
    }
}
