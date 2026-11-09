import XCTest
@testable import HyperWindow


final class CornerTests: XCTestCase {
    func test_cornerForPositionSelectsEachQuadrant() {
        let size = CGSize(width: 100, height: 100)

        XCTAssertEqual(Corner.corner(for: CGPoint(x: 25, y: 25), in: size), .topLeft)
        XCTAssertEqual(Corner.corner(for: CGPoint(x: 75, y: 25), in: size), .topRight)
        XCTAssertEqual(Corner.corner(for: CGPoint(x: 75, y: 75), in: size), .bottomRight)
        XCTAssertEqual(Corner.corner(for: CGPoint(x: 25, y: 75), in: size), .bottomLeft)
    }

    func test_cornerMidpointsPreferRightAndBottom() {
        let size = CGSize(width: 100, height: 100)

        XCTAssertEqual(Corner.corner(for: CGPoint(x: 50, y: 25), in: size), .topRight)
        XCTAssertEqual(Corner.corner(for: CGPoint(x: 25, y: 50), in: size), .bottomLeft)
        XCTAssertEqual(Corner.corner(for: CGPoint(x: 50, y: 50), in: size), .bottomRight)
    }

    func test_cornerForNaNPositionDefaultsToBottomRight() {
        XCTAssertEqual(
            Corner.corner(for: CGPoint(x: CGFloat.nan, y: 25), in: CGSize(width: 100, height: 100)),
            .bottomRight
        )
    }
}
