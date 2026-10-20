import XCTest

/// Writes the accessibility tree of the screens the behaviour tests drive (to find the elements).
final class ProbeTests: XCTestCase {
    func testDumpTrees() throws {
        guard let folder = ProcessInfo.processInfo.environment["PROBE_OUT"] else { throw XCTSkip("PROBE_OUT not set") }
        let screens: [(String, String?)] = [
            ("rewards-showcase-screens", "home"), ("motion-blur-screens", "home"),
            ("longpress-groups-sheet-screens", "history"), ("float-nav-swipe-screens", "home"),
            ("survey-screens", "goal"), ("inputs-screens", "profile"), ("bottom-zone-screens", "home"),
            ("carousel-steps-screens", "streak"), ("app-bar-screens", "challenges"), ("full-catalog-screen", nil),
            ("buttons-chips-screens", "gallery"), ("composition-screens", nil),
        ]
        for (fixture, screen) in screens {
            let app = launchFixture(fixture, screen: screen)
            sleep(2)
            let name = [fixture, screen ?? "start"].joined(separator: "-")
            try app.debugDescription.write(toFile: "\(folder)/\(name).txt", atomically: true, encoding: .utf8)
        }
    }
}
