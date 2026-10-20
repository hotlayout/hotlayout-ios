import Foundation
import XCTest

@testable import HotLayout

/// Reads the contract copies in the test resources (`scripts/sync-contract.sh`).
enum Contract {
    static var root: URL {
        guard let url = Bundle.module.url(forResource: "contract", withExtension: nil) else {
            fatalError("Test resources have no contract copy: run scripts/sync-contract.sh")
        }
        return url
    }

    static func json(_ relativePath: String) throws -> JSONValue {
        let data = try Data(contentsOf: root.appendingPathComponent(relativePath))
        return try JSONValue.parse(data)
    }

    static func rows(_ table: JSONValue, _ group: String) -> [JSONObject] {
        (table[group]?.arrayValue ?? []).compactMap(\.objectValue)
    }

    /// A flat data map of a row: `null` is absence, as the tables say.
    static func scope(_ value: JSONValue?) -> DataScope {
        var scope: DataScope = [:]
        for (key, item) in value?.objectValue ?? JSONObject() where !item.isNull { scope[key] = item }
        return scope
    }
}

/// A row that did not give the table's answer: kept by name, compared as a whole set so that
/// an exception that is no longer needed fails the test too.
struct Mismatch: CustomStringConvertible {
    let name: String
    let expected: String
    let actual: String
    var description: String { "«\(name)»\n   expected: \(Mismatch.visible(expected))\n     actual: \(Mismatch.visible(actual))" }

    static func visible(_ text: String) -> String {
        text.unicodeScalars.map { scalar in
            scalar.value < 0x80 && scalar.value >= 0x20 ? String(scalar) : String(format: "\\u{%04X}", scalar.value)
        }.joined()
    }
}

/// Asserts that the rows that differ are exactly the documented exceptions.
func assertOnlyKnownDifferences(_ mismatches: [Mismatch], known: [String: String], group: String, file: StaticString = #filePath, line: UInt = #line) {
    var unexpected: [Mismatch] = []
    for mismatch in mismatches {
        if let shown = known[mismatch.name], shown == mismatch.actual { continue }
        unexpected.append(mismatch)
    }
    let stale = Set(known.keys.filter { $0.hasPrefix("\(group): ") }).subtracting(mismatches.map(\.name))
    XCTAssert(unexpected.isEmpty, "\(group): \(unexpected.count) row(s) differ from the table:\n" + unexpected.map(\.description).joined(separator: "\n"), file: file, line: line)
    XCTAssert(stale.isEmpty, "\(group): exceptions name rows that now pass or no longer exist: \(stale.sorted())", file: file, line: line)
}
