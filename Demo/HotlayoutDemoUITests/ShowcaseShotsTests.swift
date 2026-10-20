import XCTest

/// Screenshots of the showcase apps after the taps a person makes (`TEST_RUNNER_SHOWCASE_SHOTS_DIR=<folder>`);
/// without the folder the tests do nothing. Each opens one app on its first screen, follows the taps and saves
/// `<name>-ios.png`.
final class ShowcaseShotsTests: XCTestCase {
    private var folder: String? { ProcessInfo.processInfo.environment["SHOWCASE_SHOTS_DIR"] }

    private func shot(_ name: String, app appName: String, screen: String? = nil, taps: [(label: String, hold: Bool)]) throws {
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
        try app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(folder)/\(name)-ios.png"))
    }

    func testObsidianQuest() throws { try shot("obsidian-quest", app: "obsidian", taps: [("Quest: ", false)]) }
    func testSunnyQuest() throws { try shot("sunny-quest", app: "sunny", taps: [("Quest: ", false)]) }
    func testOrbitMission() throws { try shot("orbit-mission", app: "orbit", taps: [("Mission: ", false)]) }
    func testOrbitStreak() throws { try shot("orbit-streak", app: "orbit", taps: [("Streak", false)]) }
    func testOrbitPeek() throws { try shot("orbit-peek", app: "orbit", taps: [("Mission: ", true)]) }
    func testOrbitReward() throws { try shot("orbit-reward", app: "orbit", screen: "rewards", taps: [("Reward: ", false)]) }
    func testOrbitRedeem() throws { try shot("orbit-redeem", app: "orbit", screen: "rewards", taps: [("Reward: ", true)]) }
}
