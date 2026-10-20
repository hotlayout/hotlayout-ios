import SwiftUI
import XCTest

@testable import HotLayout

/// Every screen of every fixture is drawn once, off screen: the reader must not crash on any
/// document of this major, whatever widgets it has.
@MainActor
final class RenderSmokeTests: XCTestCase {
    func testEveryFixtureScreenDraws() throws {
        let folder = Contract.root.appendingPathComponent("fixtures")
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).filter { $0.pathExtension == "json" }
        var drawn = 0
        for file in files {
            let json = try JSONValue.parse(Data(contentsOf: file))
            let document = try loadDocument(json)
            for screen in document.screens {
                guard case .object(var object) = json else { continue }
                object["initialScreenId"] = .string(screen.screenId)
                let single = try loadDocument(.object(object))
                let view = HotlayoutScreen(document: single, locale: "en", now: Date(timeIntervalSince1970: 1_791_000_000))
                    .frame(width: 393, height: 852)
                let renderer = ImageRenderer(content: view)
                XCTAssertNotNil(renderer.cgImage, "\(file.lastPathComponent): \(screen.screenId)")
                drawn += 1
            }
        }
        XCTAssertGreaterThanOrEqual(drawn, 90)
    }
}
