import XCTest

@testable import HotLayout

/// The tables of schema 9.28.0 that are rules as functions: the address of a picture, the list
/// budget, the numbers of a theme and the paint of a text. The same rules through the real screen
/// are in `Contract928WiringTests`.
@MainActor
final class Contract928CasesTests: XCTestCase {
    static let images = try! Contract.json("fixtures/image-source/image-source-cases.json")
    static let budget = try! Contract.json("fixtures/repeater-filter/list-budget-cases.json")
    static let numbers = try! Contract.json("fixtures/theme-numbers/theme-number-cases.json")
    static let silent = try! Contract.json("fixtures/accessible-name/silent-text-cases.json")

    static func name(_ row: JSONObject) -> String { row["name"]?.stringValue ?? "?" }

    /// Groups of these tables that are rules of the validator of the builder, which this reader does not run.
    static let notRun: [String: String] = [
        "repeater-filter/validatorCases": "the worst case of a screen that the builder checks before it publishes; the reader draws any document it can read",
    ]

    /// Every group of the four tables is run here, in the wiring tests, or named with its reason.
    func testEveryGroupIsRunOrNamed() {
        let run: Set<String> = [
            "image-source/defaultCases", "image-source/neverAnImageCases", "repeater-filter/budgetCases", "theme-numbers/numberCases",
            "accessible-name/silentCases", "accessible-name/paintCases",
        ]
        let tables = ["image-source": Self.images, "repeater-filter": Self.budget, "theme-numbers": Self.numbers, "accessible-name": Self.silent]
        var groups: Set<String> = []
        for (folder, table) in tables {
            for group in Contract.groups(table) { groups.insert("\(folder)/\(group)") }
        }
        let known = run.union(Self.notRun.keys)
        XCTAssertEqual(groups.subtracting(known), [], "groups of the 9.28.0 tables that are neither run nor named")
        for name in known {
            let parts = name.split(separator: "/").map(String.init)
            XCTAssertNotNil(tables[parts[0]]?[parts[1]]?.arrayValue, "\(name) is no longer a group")
        }
    }

    // MARK: The address of a picture

    private func address(_ row: JSONObject) -> String {
        if let url = row["url"]?.stringValue { return url }
        let spec = row["urlOfLength"]?.objectValue ?? JSONObject()
        let prefix = spec["prefix"]?.stringValue ?? ""
        let length = Int(spec["length"]?.numberValue ?? 0)
        return prefix + String(repeating: spec["pad"]?.stringValue ?? "", count: length - prefix.count)
    }

    func testDefaultCases() {
        let rows = Contract.rows(Self.images, "defaultCases")
        XCTAssertEqual(rows.count, 78)
        for row in rows {
            let address = address(row)
            let expectedProblem = row["problem"]?.stringValue
            XCTAssertEqual(ActionCatalog.formProblem("httpsUrl", address)?.rawValue, expectedProblem, "the form: \(Self.name(row))")
            // The default rule of a picture is exactly that form: a problem is a refusal, no problem is the address itself.
            XCTAssertEqual(ImagePolicy.httpsOnly(address)?.absoluteString != nil, expectedProblem == nil, "the default rule: \(Self.name(row))")
            XCTAssertEqual(ImagePolicy().resolve(address) != nil, expectedProblem == nil, "the policy: \(Self.name(row))")
        }
    }

    func testNeverAnImageCases() {
        let rows = Contract.rows(Self.images, "neverAnImageCases")
        XCTAssertEqual(rows.count, 16)
        // A host that allows every address it can build a URL from: its answer is final, except for a script.
        let allowAll = ImagePolicy(resolve: { URL(string: $0) })
        for row in rows {
            let address = address(row)
            let never = row["never"]?.boolValue
            XCTAssertEqual(ImageSourceRules.neverAnImage(address), never, Self.name(row))
            if let url = URL(string: address) {
                let loaded = allowAll.resolve(address) != nil
                XCTAssertEqual(loaded, !ImageSourceRules.neverAnImage(url.absoluteString), "the policy: \(Self.name(row))")
                if never == true, ImageSourceRules.neverAnImage(url.absoluteString) { XCTAssertFalse(loaded, Self.name(row)) }
            } else {
                XCTAssertNil(allowAll.resolve(address), "no URL, no picture: \(Self.name(row))")
            }
        }
    }

    func testTheReportOfAnAddressNamesAsLittleAsTheDocumentAllows() {
        let long = "https://example.com/" + String(repeating: "a", count: 300)
        XCTAssertEqual(ImageSourceRules.documentAddress(long).count, 121)
        XCTAssertEqual(ImageSourceRules.documentAddress("https://x.example/a.png"), "https://x.example/a.png")
        XCTAssertEqual(ImageSourceRules.schemeAndHost("https://cdn.example.com/secret/path?token=abc#f"), "https://cdn.example.com")
        XCTAssertEqual(ImageSourceRules.schemeAndHost("https://user:pw@127.0.0.1:8080/x?token=1"), "https://127.0.0.1")
        XCTAssertEqual(ImageSourceRules.schemeAndHost("https://[::1]:8443/x"), "https://[::1]")
        XCTAssertEqual(ImageSourceRules.schemeAndHost("http://localhost:5173/a.png"), "http://localhost")
        XCTAssertEqual(ImageSourceRules.schemeAndHost("javascript:alert(document.cookie)"), "javascript:")
        XCTAssertTrue(ImageSourceRules.schemeAndHost("no scheme at all, a token=abc").hasPrefix("("))
    }

    func testTheLimitsAreTheArtifactsNumbers() throws {
        let network = try Contract.json("screen-schema.json")["x-imageSource"]
        XCTAssertEqual(Double(ImagePolicy.defaultMaxDownloadBytes), network?["network"]?["maxBodyBytes"]?.numberValue)
        XCTAssertEqual(Double(ImagePolicy.defaultMaxPixelSide), network?["decode"]?["maxDecodedSide"]?.numberValue)
        XCTAssertEqual(Double(BoundedDownload.maxRedirects), network?["network"]?["redirects"]?["max"]?.numberValue)
        XCTAssertEqual(BoundedDownload.deadlineSeconds, network?["network"]?["deadlineSeconds"]?.numberValue)
        XCTAssertEqual(Double(ImageSourceRules.reportDocumentLength), 120)
        XCTAssertEqual(Set(ImageSourceRules.neverSchemes), Set((network?["host"]?["neverAnImage"]?["schemes"]?.arrayValue ?? []).compactMap(\.stringValue)))
    }

    // MARK: The list budget

    /// A list of the table as a real `Repeater` node: the collection is named after the list, the
    /// template holds the lists inside it.
    private func listJSON(_ spec: JSONObject, _ collections: inout DataScope) -> JSONValue {
        let name = spec["name"]?.stringValue ?? "?"
        let count = Int(spec["records"]?.numberValue ?? 0)
        collections["c_\(name)"] = .array((0..<count).map { .object(JSONObject([("id", .number(Double($0)))])) })
        let inside = (spec["inside"]?.arrayValue ?? []).compactMap(\.objectValue).map { listJSON($0, &collections) }
        let template: JSONValue =
            inside.isEmpty
            ? ["id": .string("t_\(name)"), "type": "Text", "props": [:]]
            : ["id": .string("t_\(name)"), "type": "Column", "props": [:], "children": .array(inside)]
        return ["id": .string(name), "type": "Repeater", "props": ["source": .string("c_\(name)"), "item": .string("i_\(name)")], "children": [template]]
    }

    func testBudgetCases() throws {
        let rows = Contract.rows(Self.budget, "budgetCases")
        XCTAssertEqual(rows.count, 14)
        for row in rows {
            var collections: DataScope = [:]
            let lists = (row["lists"]?.arrayValue ?? []).compactMap(\.objectValue).map { listJSON($0, &collections) }
            let root = try Harness.node(["id": "row-root", "type": "Column", "props": [:], "children": .array(lists)])
            let plan = ListBudget.plan(root: root, scope: collections, budget: Int(row["budget"]?.numberValue ?? Double(ListBudget.perScreen)))
            for (list, expected) in row["drawn"]?.objectValue ?? JSONObject() {
                XCTAssertEqual(plan.drawnByList[list] ?? 0, Int(expected.numberValue ?? -1), "drawn «\(list)»: \(Self.name(row))")
            }
            XCTAssertEqual(plan.total, Int(row["total"]?.numberValue ?? -1), "total: \(Self.name(row))")
            XCTAssertEqual(plan.notDrawn, Int(row["notDrawn"]?.numberValue ?? -1), "notDrawn: \(Self.name(row))")
        }
    }

    func testTheBudgetIsTheArtifactsNumber() throws {
        XCTAssertEqual(Double(ListBudget.perScreen), try Contract.json("screen-schema.json")["x-listBudget"]?["perScreen"]?.numberValue)
    }

    func testAGroupHeaderIsNoInstanceAndTheListsInsideItCountAfterTheirInstance() throws {
        let inner: JSONValue = [
            "id": "inner", "type": "Repeater", "props": ["source": "c", "item": "ci"], "children": [["id": "it", "type": "Text", "props": [:]]],
        ]
        let outer: JSONValue = [
            "id": "outer", "type": "Repeater", "props": ["source": "c", "item": "o", "groupBy": "o.day"],
            "children": [["id": "row", "type": "Text", "props": [:]], ["id": "header", "type": "Column", "props": [:], "children": [inner]]],
        ]
        let records: JSONValue = [["day": "a"], ["day": "a"], ["day": "b"]]
        let root = try Harness.node(["id": "r", "type": "Column", "props": [:], "children": [outer]])
        let plan = ListBudget.plan(root: root, scope: ["c": records], budget: 100)
        // Three outer instances; the header stands above two of them (the first of each group), and the list in it draws 3 records each.
        XCTAssertEqual(plan.drawnByList["outer"], 3)
        XCTAssertEqual(plan.drawnByList["inner"], 6)
        XCTAssertEqual(plan.total, 9)
    }

    // MARK: The numbers of a theme

    private func setting(_ value: JSONValue, _ path: [String], to number: JSONValue) -> JSONValue {
        guard let head = path.first else { return number }
        switch value {
        case .object(var object):
            object[head] = setting(object[head] ?? .object(JSONObject()), Array(path.dropFirst()), to: number)
            return .object(object)
        case .array(var items):
            if let index = Int(head), items.indices.contains(index) { items[index] = setting(items[index], Array(path.dropFirst()), to: number) }
            return .array(items)
        default:
            return value
        }
    }

    /// The built-in theme with the number of the row put at its place, read as a theme from the network.
    private func read(_ row: JSONObject) throws -> (set: HotlayoutThemeSet, id: String) {
        let place = row["place"]?.objectValue ?? JSONObject()
        let brightness = row["brightness"]?.stringValue ?? "light"
        var contract = try XCTUnwrap(Contract.json("theme.json")["contract"])
        let themes = contract["themes"]?.objectValue ?? JSONObject()
        let id = try XCTUnwrap(themes.first { $0.value["brightness"]?.stringValue == brightness }?.key)
        let token = place["token"]?.stringValue ?? ""
        var path = ["themes", id, place["dictionary"]?.stringValue ?? "", token]
        if place["dictionary"]?.stringValue == "typography", themes[id]?["typography"]?[token] == nil {
            // A custom text style needs the fields the reader requires.
            contract = setting(contract, path, to: ["fontSize": 14, "lineHeight": 1.4, "fontWeight": 400])
        }
        if let layer = place["layer"]?.numberValue { path.append(String(Int(layer))) }
        if let stop = place["stop"]?.numberValue { path += ["stops", String(Int(stop))] }
        if let field = place["field"]?.stringValue { path.append(field) }
        let given: JSONValue
        if let word = row["value"]?.stringValue {
            given = .number(word.hasPrefix("-") ? -Double.infinity : Double.infinity)
        } else {
            given = row["value"] ?? .null
        }
        contract = setting(contract, path, to: given)
        return (try HotlayoutThemeSet.load(contract), id)
    }

    private func drawn(_ row: JSONObject, _ read: (set: HotlayoutThemeSet, id: String)) throws -> Double {
        let place = row["place"]?.objectValue ?? JSONObject()
        let theme = read.set.theme(read.id)
        let token = place["token"]?.stringValue ?? ""
        let field = place["field"]?.stringValue
        switch place["dictionary"]?.stringValue {
        case "spacing": return try XCTUnwrap(theme.spacing[token])
        case "radius": return try XCTUnwrap(theme.radius[token])
        case "typography":
            let style = try XCTUnwrap(theme.typography[token])
            switch field {
            case "fontSize": return style.fontSize
            case "lineHeight": return style.lineHeight
            case "fontWeight": return Double(style.fontWeight)
            case "letterSpacing": return style.letterSpacing
            default: XCTFail("field \(field ?? "-")"); return 0
            }
        case "elevation":
            let layer = try XCTUnwrap(theme.elevation[token]?[Int(place["layer"]?.numberValue ?? 0)])
            switch field {
            case "offsetX": return layer.offsetX
            case "offsetY": return layer.offsetY
            case "blur": return layer.blur
            case "spread": return layer.spread
            case "opacity": return layer.color.alpha
            default: XCTFail("field \(field ?? "-")"); return 0
            }
        case "gradient":
            return try XCTUnwrap(theme.gradient[token]?.stops[Int(place["stop"]?.numberValue ?? 0)]).position
        default:
            XCTFail("dictionary"); return 0
        }
    }

    func testNumberCases() throws {
        let rows = Contract.rows(Self.numbers, "numberCases")
        XCTAssertEqual(rows.count, 31)
        for row in rows {
            let theme = try read(row)
            XCTAssertEqual(try drawn(row, theme), row["expected"]?.numberValue ?? .nan, accuracy: 1e-9, Self.name(row))
            let place = row["place"]?.objectValue ?? JSONObject()
            let token = place["token"]?.stringValue ?? "", dictionary = place["dictionary"]?.stringValue ?? ""
            let mine = theme.set.reports.filter { $0.location.contains("\(dictionary).\(token)") }
            if let by = row["replacedBy"]?.stringValue {
                let word = by == "built-in" ? "the built-in value" : "the nearest bound"
                XCTAssertTrue(mine.contains { $0.reason.contains(word) }, "a report of the replacement by \(word): \(Self.name(row)): \(mine)")
            } else {
                XCTAssertEqual(mine, [], "no report: \(Self.name(row))")
            }
        }
    }

    func testTheBoundsAreTheArtifactsNumbers() throws {
        let bounds = try XCTUnwrap(Contract.json("screen-schema.json")["x-themeNumbers"]?["bounds"])
        let mine: [String: ThemeNumbers.Bounds] = [
            "spacing": ThemeNumbers.spacing, "radius": ThemeNumbers.radius, "fontSize": ThemeNumbers.fontSize, "lineHeight": ThemeNumbers.lineHeight,
            "fontWeight": ThemeNumbers.fontWeight, "letterSpacing": ThemeNumbers.letterSpacing, "shadowOffset": ThemeNumbers.shadowOffset,
            "shadowBlur": ThemeNumbers.shadowBlur, "shadowSpread": ThemeNumbers.shadowSpread, "shadowOpacity": ThemeNumbers.unit,
            "gradientPosition": ThemeNumbers.unit,
        ]
        XCTAssertEqual(Set(mine.keys), Set((bounds.objectValue ?? JSONObject()).keys))
        for (name, ours) in mine {
            XCTAssertEqual(ours.low, bounds[name]?["min"]?.numberValue, name)
            XCTAssertEqual(ours.high, bounds[name]?["max"]?.numberValue, name)
        }
    }

    /// A JSON parser reads `1e309` as infinity: the text of a theme with it is replaced, not skipped.
    func testInfinityFromTheTextOfATheme() throws {
        let text = #"{"themeContractVersion":"4.0.1","defaultThemeId":"light","themes":{"light":{"id":"light","brightness":"light","spacing":{"md":1e309,"hero":-1e309}}}}"#
        let set = try HotlayoutThemeSet.load(Data(text.utf8))
        XCTAssertEqual(set.theme("light").spacing["md"], 12, "the built-in value of the same token")
        XCTAssertEqual(set.theme("light").spacing["hero"], 0, "the nearest bound")
    }

    // MARK: The paint of a text

    func testPaintCases() {
        let rows = Contract.rows(Self.silent, "paintCases")
        XCTAssertEqual(rows.count, 6)
        for row in rows {
            let opacities = (row["opacities"]?.arrayValue ?? []).map { $0.numberValue }
            XCTAssertEqual(SilentText.paintsNothing(opacities: opacities, colorOpacity: row["colorOpacity"]?.numberValue), row["paintsNothing"]?.boolValue, Self.name(row))
        }
    }
}
