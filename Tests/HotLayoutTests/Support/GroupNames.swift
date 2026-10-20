import Foundation

@testable import HotLayout

extension Contract {
    /// The names of the groups of a shared table: its keys that end in `Cases` and hold a list.
    static func groups(_ table: JSONValue) -> Set<String> {
        var names: Set<String> = []
        for (key, value) in table.objectValue ?? JSONObject() where key.hasSuffix("Cases") && value.arrayValue != nil { names.insert(key) }
        return names
    }
}
