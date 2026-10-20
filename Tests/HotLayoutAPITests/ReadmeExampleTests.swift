import Foundation
import XCTest

/// The README shows the regions of `ReadmeExample.swift` as they are: an example that stopped
/// compiling would fail the build, and one changed only in the README fails here.
final class ReadmeExampleTests: XCTestCase {
    func testTheReadmeCarriesTheCompiledExample() throws {
        let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let source = try String(contentsOf: here.appendingPathComponent("ReadmeExample.swift"), encoding: .utf8)
        let readme = try String(contentsOf: here.appendingPathComponent("../../README.md").standardized, encoding: .utf8)
        for name in ["readme", "readme-async"] {
            let parts = source.components(separatedBy: "// #region \(name)\n")
            XCTAssertEqual(parts.count, 2, name)
            let region = try XCTUnwrap(parts.last?.components(separatedBy: "// #endregion \(name)").first)
            XCTAssertTrue(readme.contains("```swift\n" + region + "```"), "README does not carry the region \(name) as it is")
        }
    }
}
