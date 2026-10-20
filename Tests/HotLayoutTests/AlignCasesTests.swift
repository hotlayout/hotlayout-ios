import SwiftUI
import XCTest

@testable import HotLayout

/// The shared table of alignment (`fixtures/align/align-cases.json`): which axis is the main
/// one, what gives a column a height, how far children move, where they stand in a box (the
/// rules as functions and the real layouts, in both directions of the script), the body of a
/// screen, and the data of the artifact.
@MainActor
final class AlignCasesTests: XCTestCase {
    static let table = try! Contract.json("fixtures/align/align-cases.json")

    static func assertClose(_ a: [Double], _ b: [Double], _ accuracy: Double, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.count, b.count, message, file: file, line: line)
        for (x, y) in zip(a, b) { XCTAssertEqual(x, y, accuracy: accuracy, "\(message): \(a) vs \(b)", file: file, line: line) }
    }

    private func number(_ value: JSONValue?) -> Double { value?.numberValue ?? 0 }

    func testTableShape() {
        let groups = ["readCases", "heightSourceCases", "shiftCases", "boxCases", "screenCases", "ruleCases"]
        XCTAssertEqual(groups.map { Contract.rows(Self.table, $0).count }.reduce(0, +), 139)
    }

    func testReadCases() {
        for row in Contract.rows(Self.table, "readCases") {
            let node = row["node"]?.objectValue ?? JSONObject()
            let read = AlignRules.read(type: node["type"]?.stringValue ?? "", props: node["props"]?.objectValue ?? JSONObject())
            let expect = row["expect"]?.objectValue ?? JSONObject()
            let name = row["name"]?.stringValue ?? "?"
            switch expect["mainAxis"]?.stringValue {
            case nil:
                XCTAssertNil(read, name)
            case let word?:
                XCTAssertEqual(read?.mainAxis, word == "block" ? .block : .inline, name)
                XCTAssertEqual(read?.align.rawValue, expect["align"]?.stringValue, name)
                XCTAssertEqual(read?.justify.rawValue, expect["justify"]?.stringValue, name)
            }
        }
    }

    func testHeightSourceCases() {
        for row in Contract.rows(Self.table, "heightSourceCases") {
            let node = row["node"]?.objectValue ?? JSONObject()
            let type = node["type"]?.stringValue ?? ""
            let props = node["props"]?.objectValue ?? JSONObject()
            var fields = JSONObject()
            if let fill = node["fill"] { fields["fill"] = fill }
            let own = row["own"]?.objectValue ?? JSONObject()
            let parent = row["parent"]?.stringValue
            let ownHeight = own["height"]?.boolValue == true, ownMin = own["minHeight"]?.boolValue == true
            let expect = row["expect"]?.objectValue ?? JSONObject()
            let name = row["name"]?.stringValue ?? "?"
            // A node that is not a host has no source either.
            let host = AlignRules.read(type: type, props: props) != nil
            let isColumn = host && AlignRules.read(type: type, props: props)?.mainAxis == .block && type != "Screen"
            let source = isColumn ? AlignRules.heightSource(fields: fields, parent: parent, ownHeight: ownHeight, ownMinHeight: ownMin) : nil
            XCTAssertEqual(source?.rawValue, expect["source"]?.stringValue, name)
            // A row and the body of a screen distribute what their box gives them; a column only
            // what its source gives (`NodeView.hostSpace` asks `heightSource`).
            let space = host ? (!isColumn || source != nil) : nil
            XCTAssertEqual(space, expect["space"]?.boolValue, name)
        }
    }

    func testShiftCases() {
        for row in Contract.rows(Self.table, "shiftCases") {
            let shifts = AlignRules.shifts(free: number(row["free"]), count: Int(number(row["count"])), justify: JustifyWord(rawValue: row["justify"]?.stringValue ?? "") ?? .start)
            let expected = (row["expect"]?.arrayValue ?? []).map { number($0) }
            XCTAssertEqual(shifts.count, expected.count, row["name"]?.stringValue ?? "?")
            for (a, b) in zip(shifts, expected) { XCTAssertEqual(a, b, accuracy: 1e-9, row["name"]?.stringValue ?? "?") }
        }
    }

    // MARK: boxes

    private func input(_ row: JSONObject) -> AlignedBoxInput {
        let children = (row["children"]?.arrayValue ?? []).compactMap(\.objectValue).map {
            AlignedChild(width: number($0["width"]), height: number($0["height"]), stretch: $0["stretch"]?.boolValue == true)
        }
        return AlignedBoxInput(
            axis: row["axis"]?.stringValue == "block" ? .block : .inline,
            inline: number(row["inline"]), block: row["block"]?.numberValue, minBlock: row["minBlock"]?.numberValue,
            gap: number(row["gap"]), align: AlignWord(rawValue: row["align"]?.stringValue ?? "") ?? .start,
            justify: JustifyWord(rawValue: row["justify"]?.stringValue ?? "") ?? .start,
            rightToLeft: row["rtl"]?.boolValue == true, children: children
        )
    }

    private func expectedRects(_ row: JSONObject) -> [AlignedRect] {
        (row["expect"]?["rects"]?.arrayValue ?? []).compactMap(\.objectValue).map {
            AlignedRect(x: number($0["x"]), y: number($0["y"]), width: number($0["width"]), height: number($0["height"]))
        }
    }

    func testBoxCasesAsRules() {
        for row in Contract.rows(Self.table, "boxCases") {
            let name = row["name"]?.stringValue ?? "?"
            let box = AlignRules.alignedChildRects(input(row))
            XCTAssertEqual(box.block, number(row["expect"]?["block"]), accuracy: 1e-9, name)
            XCTAssertEqual(box.free, number(row["expect"]?["free"]), accuracy: 1e-9, name)
            let expected = expectedRects(row)
            XCTAssertEqual(box.rects.count, expected.count, name)
            for (a, b) in zip(box.rects, expected) {
                Self.assertClose([a.x, a.y, a.width, a.height], [b.x, b.y, b.width, b.height], 1e-9, name)
            }
        }
    }

    /// The same rows through the real layouts: children are fixed-size views, the host is a
    /// `ColumnLayout` or a `RowLayout`, the script runs in the direction of the row. Frames are
    /// read back in the coordinate space of the host, from its left edge.
    func testBoxCasesThroughTheLayouts() {
        for row in Contract.rows(Self.table, "boxCases") {
            let name = row["name"]?.stringValue ?? "?"
            let probe = LayoutProbe.measure(input(row))
            guard let frames = probe else {
                XCTFail("\(name): the layout was not drawn")
                continue
            }
            let expected = expectedRects(row)
            XCTAssertEqual(frames.count, expected.count, name)
            for (index, (a, b)) in zip(frames, expected).enumerated() {
                Self.assertClose([a.minX, a.minY, a.width, a.height].map { Double($0) }, [b.x, b.y, b.width, b.height], 0.01, "\(name) [child \(index)]")
            }
        }
    }

    // MARK: screen

    func testScreenCases() {
        for row in Contract.rows(Self.table, "screenCases") {
            let name = row["name"]?.stringValue ?? "?"
            let heights = (row["children"]?.arrayValue ?? []).map { number($0) }
            let gap = number(row["gap"])
            let content: Double? = heights.isEmpty ? nil : heights.reduce(0, +) + gap * Double(heights.count - 1)
            let padding = row["padding"]?.objectValue ?? JSONObject()
            let bottom = row["bottom"]?.objectValue ?? JSONObject()
            // The zones the screen is laid out by (`ScreenZonesLayout` asks `ScreenAnatomy.zones`).
            let pinned = bottom["pinnedHeight"]?.numberValue, nav = bottom["navBarHeight"]?.numberValue
            let zones = ScreenAnatomy.zones(AnatomyInput(
                height: number(row["height"]), shrink: row["shrink"]?.boolValue == true, appBarHeight: row["appBarHeight"]?.numberValue,
                paddingTop: number(padding["top"]), paddingBottom: number(padding["bottom"]), gap: gap, bodyContentHeight: content,
                bottom: pinned != nil || nav != nil ? BottomZoneInput(pinnedHeight: pinned, navBarHeight: nav, safeBottom: 0) : nil
            ))
            // The body of a screen that justifies is given the whole area; what the flow leaves is free.
            let free = max(0, zones.body.height - zones.contentHeight)
            let shifts = AlignRules.shifts(free: free, count: heights.count, justify: JustifyWord(rawValue: row["justify"]?.stringValue ?? "") ?? .start)
            var cursor = zones.contentTop
            var tops: [Double] = []
            for (index, height) in heights.enumerated() {
                tops.append(cursor + shifts[index])
                cursor += height + gap
            }
            let expect = row["expect"]?.objectValue ?? JSONObject()
            XCTAssertEqual(zones.body.top, number(expect["body"]?["top"]), accuracy: 1e-9, name)
            XCTAssertEqual(zones.body.height, number(expect["body"]?["height"]), accuracy: 1e-9, name)
            XCTAssertEqual(free, number(expect["free"]), accuracy: 1e-9, name)
            XCTAssertEqual(zones.scrolls, expect["scrolls"]?.boolValue, name)
            let expectedTops = (expect["tops"]?.arrayValue ?? []).map { number($0) }
            XCTAssertEqual(tops.count, expectedTops.count, name)
            for (a, b) in zip(tops, expectedTops) { XCTAssertEqual(a, b, accuracy: 1e-9, name) }
        }
    }

    // MARK: the data of the artifact

    func testRuleCases() throws {
        let schema = try Contract.json("screen-schema.json")
        let alignment = schema["x-style"]?["layout"]?["alignment"]
        for row in Contract.rows(Self.table, "ruleCases") {
            var value = alignment
            for key in (row["rule"]?.stringValue ?? "").split(separator: ".") { value = value?[String(key)] }
            XCTAssertEqual(value, row["expect"], row["name"]?.stringValue ?? "?")
        }
    }

    func testWordsMirrorTheArtifact() throws {
        let schema = try Contract.json("screen-schema.json")
        let alignment = schema["x-style"]?["layout"]?["alignment"]
        XCTAssertEqual((alignment?["main"]?["values"]?.arrayValue ?? []).compactMap(\.stringValue), JustifyWord.allCases.map(\.rawValue))
        XCTAssertEqual((alignment?["main"]?["column"]?["heightSources"]?.arrayValue ?? []).compactMap(\.stringValue), ["style.height", "style.minHeight", "fill"])
        XCTAssertEqual(alignment?["main"]?["withoutProp"]?.stringValue, "start")
        XCTAssertEqual(alignment?["cross"]?["block"]?["withoutProp"]?.stringValue, "start")
        XCTAssertEqual(alignment?["cross"]?["inline"]?["withoutProp"]?.stringValue, "center")
        let natural = schema["x-style"]?["layout"]?["column"]?["naturalWidthAlign"]
        XCTAssertEqual(natural?["prop"]?.stringValue, "align")
        XCTAssertEqual(natural?["withoutProp"]?.stringValue, "start")
    }
}

/// Draws a host with fixed-size children and reads the frames back.
@MainActor
enum LayoutProbe {
    struct Frames: PreferenceKey {
        static let defaultValue: [Int: CGRect] = [:]
        static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) { value.merge(nextValue()) { $1 } }
    }

    final class Box { var frames: [Int: CGRect] = [:] }

    static func measure(_ input: AlignedBoxInput) -> [CGRect]? {
        let box = Box()
        let content = host(input).onPreferenceChange(Frames.self) { box.frames = $0 }
        let renderer = ImageRenderer(content: content)
        guard renderer.cgImage != nil, box.frames.count == input.children.count else { return nil }
        return (0..<input.children.count).map { box.frames[$0] ?? .zero }
    }

    @ViewBuilder
    static func children(_ input: AlignedBoxInput) -> some View {
        ForEach(Array(input.children.enumerated()), id: \.offset) { index, child in
            Group {
                if child.stretch && input.axis == .block {
                    Color.clear.frame(maxWidth: .infinity).frame(height: child.height)
                } else {
                    Color.clear.modifier(NamedWidth(width: child.width, height: child.height, alignment: .topLeading, clampsToParent: input.axis == .block))
                }
            }
            .background(GeometryReader { proxy in
                Color.clear.preference(key: Frames.self, value: [index: proxy.frame(in: .named("host"))])
            })
        }
    }

    @ViewBuilder
    static func host(_ input: AlignedBoxInput) -> some View {
        let direction: LayoutDirection = input.rightToLeft ? .rightToLeft : .leftToRight
        Group {
            if input.axis == .block {
                ColumnLayout(gap: input.gap, align: input.align, justify: input.justify, block: input.block.map { CGFloat($0) }, minBlock: input.minBlock.map { CGFloat($0) }) { children(input) }
            } else {
                RowLayout(gap: input.gap, justify: input.justify, align: input.align, block: input.block.map { CGFloat($0) }) { children(input) }
            }
        }
        .frame(width: input.inline, alignment: .topLeading)
        .coordinateSpace(name: "host")
        .environment(\.layoutDirection, direction)
        .frame(width: input.inline, alignment: .topLeading)
    }
}
