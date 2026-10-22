import XCTest

@testable import HotLayout

/// Where a release of the carousel ends: a flick moves one stop on, a slow release goes to the
/// nearest stop to the landing point.
final class CarouselReleaseTests: XCTestCase {
    private let stops = [0.0, 100, 200, 300]
    private let threshold = CarouselRules.flickThreshold(scale: 3)

    private func release(offset: Double, landing: Double? = nil, speed: Double, forward: Bool) -> Int {
        CarouselRules.releaseStop(stops, offset: offset, landing: landing ?? offset, speed: speed, forward: forward, threshold: threshold)
    }

    func testThresholdIsFlutters() {
        XCTAssertEqual(CarouselRules.flickThreshold(scale: 3), 1 / 0.15, accuracy: 1e-9)
        XCTAssertEqual(CarouselRules.flickThreshold(scale: 2), 10, accuracy: 1e-9)
    }

    func testFlickMovesOneStopWhateverTheLandingPoint() {
        for (index, stop) in stops.enumerated() {
            // The throw would land two stops on; the flick still moves one.
            let forward = release(offset: stop, landing: stop + 250, speed: 3000, forward: true)
            XCTAssertEqual(forward, min(index + 1, stops.count - 1), "forward from stop \(index)")
            let back = release(offset: stop, landing: stop - 250, speed: 3000, forward: false)
            XCTAssertEqual(back, max(index - 1, 0), "back from stop \(index)")
        }
    }

    func testFlickFromBetweenStopsGoesToTheNextOneInItsDirection() {
        XCTAssertEqual(release(offset: 140, speed: 500, forward: true), 2)
        XCTAssertEqual(release(offset: 140, speed: 500, forward: false), 1)
        XCTAssertEqual(release(offset: 60, speed: 500, forward: false), 0)
    }

    func testSlowReleaseGoesToTheNearestStopOfTheLanding() {
        XCTAssertEqual(release(offset: 100, landing: 140, speed: 2, forward: true), 1)
        XCTAssertEqual(release(offset: 100, landing: 160, speed: 2, forward: true), 2)
        XCTAssertEqual(release(offset: 200, landing: 130, speed: 0, forward: false), 1)
    }

    func testSpeedAtTheThresholdIsNoFlick() {
        XCTAssertEqual(release(offset: 100, landing: 160, speed: threshold, forward: true), 2)
        XCTAssertEqual(release(offset: 100, landing: 130, speed: threshold + 1, forward: true), 2)
    }

    func testEdgesClamp() {
        XCTAssertEqual(release(offset: 300, speed: 3000, forward: true), 3)
        XCTAssertEqual(release(offset: 0, speed: 3000, forward: false), 0)
        XCTAssertEqual(CarouselRules.releaseStop([], offset: 0, landing: 0, speed: 9000, forward: true, threshold: 1), 0)
        XCTAssertEqual(CarouselRules.releaseStop([0], offset: 0, landing: 0, speed: 9000, forward: true, threshold: 1), 0)
    }
}
