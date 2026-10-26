import XCTest
@testable import HyperWindow

final class CGPointTests: XCTestCase {
    func test_distanceRemainsFiniteForLargeFiniteCoordinates() {
        let coordinate = CGFloat.greatestFiniteMagnitude / 4
        let distance = CGPoint.zero.distance(to: CGPoint(x: coordinate, y: coordinate))

        XCTAssertTrue(distance.isFinite)
        XCTAssertEqual(distance / coordinate, sqrt(2), accuracy: 1e-15)
    }
}
