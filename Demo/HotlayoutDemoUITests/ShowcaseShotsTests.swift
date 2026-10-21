import XCTest

/// Screenshots of the showcase apps after the taps a person makes (`TEST_RUNNER_SHOWCASE_SHOTS_DIR=<folder>`);
/// without the folder the tests do nothing. Each opens one app on its first screen, follows the taps, scrolls the
/// body up by the given number of drags and saves `<name>-ios.png`.
final class ShowcaseShotsTests: XCTestCase {
    private var folder: String? { ProcessInfo.processInfo.environment["SHOWCASE_SHOTS_DIR"] }

    private func shot(_ name: String, app appName: String, screen: String? = nil, taps: [(label: String, hold: Bool)], drags: Int = 0) throws {
        guard let folder else { throw XCTSkip("SHOWCASE_SHOTS_DIR not set") }
        let app = XCUIApplication()
        app.launchArguments = ["-app", appName, "-locale", "en"] + (screen.map { ["-screen", $0] } ?? [])
        app.launch()
        sleep(5)
        for step in taps {
            let target = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", step.label)).firstMatch
            XCTAssertTrue(target.waitForExistence(timeout: 8), "no «\(step.label)»")
            if step.hold {
                target.press(forDuration: 1.0)
            } else {
                target.tap()
            }
            sleep(3)
        }
        for _ in 0..<drags {
            let top = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0))
            top.withOffset(CGVector(dx: 0, dy: 700)).press(
                forDuration: 0.2, thenDragTo: top.withOffset(CGVector(dx: 0, dy: 200)), withVelocity: 300, thenHoldForDuration: 0.6)
            sleep(2)
        }
        try app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(folder)/\(name)-ios.png"))
    }

    func testObsidianHome() throws { try shot("obsidian-home", app: "obsidian", taps: []) }
    func testOrbitHome() throws { try shot("orbit-home", app: "orbit", taps: []) }
    func testObsidianQuest() throws { try shot("obsidian-quest", app: "obsidian", taps: [("Quest: ", false)]) }
    func testSunnyQuest() throws { try shot("sunny-quest", app: "sunny", taps: [("Quest: ", false)]) }
    func testOrbitMission() throws { try shot("orbit-mission", app: "orbit", taps: [("Mission: ", false)]) }
    func testOrbitMissionScrolled() throws { try shot("orbit-mission-scrolled", app: "orbit", taps: [("Mission: ", false)], drags: 1) }
    func testSunnyHomeScrolled() throws { try shot("sunny-home-scrolled", app: "sunny", taps: [], drags: 1) }
    func testOrbitStreak() throws { try shot("orbit-streak", app: "orbit", taps: [("Streak", false)]) }
    func testOrbitPeek() throws { try shot("orbit-peek", app: "orbit", taps: [("Mission: ", true)]) }
    func testOrbitReward() throws { try shot("orbit-reward", app: "orbit", screen: "rewards", taps: [("Reward: ", false)]) }
    func testOrbitRedeem() throws { try shot("orbit-redeem", app: "orbit", screen: "rewards", taps: [("Reward: ", true)]) }
}
