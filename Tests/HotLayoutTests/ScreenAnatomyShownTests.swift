import XCTest

@testable import HotLayout

/// `shownCases` of the media-chrome table: the event of a shown screen carries the request about
/// the status bar icons and, for a modal layer, where it lies. The reader asks nothing of the
/// system; the host gets the request.
final class ScreenAnatomyShownTests: XCTestCase {
    func testShownCases() {
        let rows = Contract.rows(ScreenAnatomyCasesTests.chrome, "shownCases")
        XCTAssertEqual(rows.count, 11)
        for row in rows {
            let name = ScreenAnatomyCasesTests.name(row)
            let stack = (row["stack"]?.arrayValue ?? []).compactMap(\.objectValue)
            func entry(_ object: JSONObject) -> FlowDocument.Screen {
                FlowDocument.Screen(
                    screenId: object["screenId"]?.stringValue ?? "", presentation: object["presentation"]?.stringValue == "modal" ? .modal : .page,
                    placement: object["modalPlacement"]?.stringValue.flatMap(ModalPlacement.init(rawValue:)),
                    statusBar: ScreenAnatomy.statusBarIcons(object["statusBarIcons"]).flatMap(StatusBarIcons.init(rawValue:))
                )
            }
            var screens = stack.map(entry)
            let transition = row["transition"]?.stringValue
            // A closed layer leaves the page beneath: the table lists the stack AFTER the pop.
            if transition == "pop" { screens.append(FlowDocument.Screen(screenId: "layer", presentation: .modal)) }
            var flow = Flow(document: FlowDocument(documentId: "d", screens: screens, initialScreenId: screens.first?.screenId, entryPoints: [:]), entry: nil)
            var shown: ScreenShownEvent?
            switch transition {
            case "start": shown = flow.shownEvent(cause: .entry)
            case "push":
                let target = stack.last ?? JSONObject()
                var instances: [ListInstance] = []
                if let record = target["record"]?.objectValue {
                    let fields = JSONObject(record.map { (String($0.key.split(separator: ".").last ?? ""), $0.value) })
                    instances = [ListInstance(item: String(record.keys.first?.split(separator: ".").first ?? ""), fields: fields)]
                }
                shown = flow.press(["type": "navigate", "params": ["screenId": .string(target["screenId"]?.stringValue ?? "")]], instances: instances).shown
            case "pop":
                _ = flow.press(["type": "navigate", "params": ["screenId": "layer"]])
                shown = flow.press(["type": "navigate.back"]).shown
            default: XCTFail("unknown transition: \(name)")
            }
            XCTAssertEqual(ActionCasesTests.shownJSON(shown), row["expect"], name)
        }
    }
}
