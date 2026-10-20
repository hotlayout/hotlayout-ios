import XCTest

@testable import HotLayout

/// The motion of a node against the shared table (`motion/motion-cases.json`): the pose at a
/// moment, the values the reader accepts, the bounds of every number; and the numbers of the
/// motion of the dot of a navigation item (its table groups run in `ScreenAnatomyCasesTests`
/// through `NavBarRules`, which the dot draws with).
final class MotionCasesTests: XCTestCase {
    static let table = try! Contract.json("fixtures/motion/motion-cases.json")
    static let zone = try! Contract.json("fixtures/bottom-zone/bottom-zone-cases.json")

    /// Groups of `motion-cases.json` this reader does not run. The blur under a layer and the
    /// glass of a node are another piece of the reader.
    static let notRun: [String: String] = [
        "blurCases": "`backdropBlur` of a screen entry: run with the modal layers (`ModalCasesTests`), which draw the blur",
    ]

    func testEveryGroupIsRunOrNamed() {
        let run: Set<String> = ["poseCases", "documentCases", "glassCases"]
        let groups = Contract.groups(Self.table)
        XCTAssertEqual(groups.subtracting(run).subtracting(Self.notRun.keys), [], "groups that are neither run nor named")
        XCTAssertEqual(run.union(Self.notRun.keys).subtracting(groups), [], "names that are no longer groups")
    }

    private func name(_ row: JSONObject) -> String { row["name"]?.stringValue ?? "?" }

    /// The radius of the glass of a node: the same whole number 1…40 as the blur under a layer;
    /// anything else is no glass.
    func testGlassRadiusFromTheStyle() {
        let rows = Contract.rows(Self.table, "glassCases")
        XCTAssertEqual(rows.count, 11)
        let resolver = StyleResolver(theme: HotlayoutThemeSet.builtIn.theme(nil))
        for row in rows {
            let look = resolver.box(["backdropBlur": row["value"] ?? .null], scope: [:])
            let expected = row["valid"]?.boolValue == true ? row["value"]?.numberValue.map { Int($0) } : nil
            XCTAssertEqual(look.backdropBlur, expected, name(row))
        }
    }

    func testPoses() throws {
        let rows = Contract.rows(Self.table, "poseCases")
        XCTAssertEqual(rows.count, 29)
        for row in rows {
            let motion = try XCTUnwrap(NodeMotion.read(row["motion"]), name(row))
            let pose = motion.pose(at: row["t"]?.numberValue ?? 0, reducedMotion: row["reducedMotion"]?.boolValue ?? false, rightToLeft: row["direction"]?.stringValue == "rtl")
            let expect = row["expected"]
            XCTAssertEqual(pose.x, expect?["x"]?.numberValue ?? .nan, accuracy: 1e-6, name(row))
            XCTAssertEqual(pose.y, expect?["y"]?.numberValue ?? .nan, accuracy: 1e-6, name(row))
            XCTAssertEqual(pose.scale, expect?["scale"]?.numberValue ?? .nan, accuracy: 1e-6, name(row))
            XCTAssertEqual(pose.opacity, expect?["opacity"]?.numberValue ?? .nan, accuracy: 1e-6, name(row))
        }
    }

    /// The value of `motion` on a node: what the reader draws and what it leaves standing; the
    /// root screen never moves.
    func testDocuments() {
        let rows = Contract.rows(Self.table, "documentCases")
        XCTAssertEqual(rows.count, 28)
        for row in rows {
            let read = NodeMotion.read(row["motion"])
            let root = row["onRoot"]?.boolValue ?? false
            XCTAssertEqual(read != nil && !root, row["valid"]?.boolValue, name(row))
        }
    }

    func testBoundsMirrorTheArtifact() throws {
        let block = try Contract.json("screen-schema.json")["x-motion"]
        let ranges = block?["ranges"]
        func range(_ key: String) -> (Double, Double) { (ranges?[key]?["min"]?.numberValue ?? .nan, ranges?[key]?["max"]?.numberValue ?? .nan) }
        XCTAssertEqual(range("duration").0, Double(NodeMotion.durationRange.lowerBound))
        XCTAssertEqual(range("duration").1, Double(NodeMotion.durationRange.upperBound))
        XCTAssertEqual(range("delay").0, Double(NodeMotion.delayRange.lowerBound))
        XCTAssertEqual(range("delay").1, Double(NodeMotion.delayRange.upperBound))
        XCTAssertEqual(range("amplitude").0, Double(NodeMotion.amplitudeRange.lowerBound))
        XCTAssertEqual(range("amplitude").1, Double(NodeMotion.amplitudeRange.upperBound))
        XCTAssertEqual(range("scale").0, NodeMotion.scaleRange.lowerBound)
        XCTAssertEqual(range("scale").1, NodeMotion.scaleRange.upperBound)
        XCTAssertEqual(range("opacity").0, NodeMotion.opacityRange.lowerBound)
        XCTAssertEqual(range("opacity").1, NodeMotion.opacityRange.upperBound)
        XCTAssertEqual(block?["kinds"]?.arrayValue?.compactMap(\.stringValue), ["float", "pulse"])
    }

    func testBadgeMotionMirrorsTheArtifact() throws {
        let block = try Contract.json("screen-schema.json")["x-style"]?["layout"]?["navBadgeMotion"]
        XCTAssertNotNil(block)
        XCTAssertEqual(block?["appear"]?["durationMs"]?.numberValue, NavBarRules.appearMs)
        XCTAssertEqual(block?["disappear"]?["durationMs"]?.numberValue, NavBarRules.disappearMs)
        XCTAssertEqual(block?["appear"]?["scale"]?.arrayValue?.compactMap(\.numberValue), [0, NavBarRules.peakScale, 1])
        XCTAssertEqual(block?["appear"]?["at"]?.arrayValue?.compactMap(\.numberValue), [0, NavBarRules.peakAt, 1])
    }
}
