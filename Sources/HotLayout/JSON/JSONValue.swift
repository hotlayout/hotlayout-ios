import Foundation

/// A JSON value as the document, the theme and the host data carry it.
///
/// The reader keeps documents in this form instead of decoding them into strict `Codable`
/// types: a document arrives over the network and may be newer than the reader, or produced
/// by something other than the builder. A piece of the wrong shape must be skipped and
/// reported, never crash the screen, and a strict decoder fails the whole document on the
/// first surprise.
public enum JSONValue: Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object(JSONObject)

    /// The string, or `nil` for any other kind of value.
    public var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    /// A finite number. `NaN` and infinity cannot come from JSON, but the host may build a
    /// value in code.
    public var numberValue: Double? {
        if case .number(let value) = self, value.isFinite { return value }
        return nil
    }

    /// The boolean, or `nil` for any other kind of value.
    public var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    /// The elements, or `nil` for any other kind of value.
    public var arrayValue: [JSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    /// The object, or `nil` for any other kind of value.
    public var objectValue: JSONObject? {
        if case .object(let value) = self { return value }
        return nil
    }

    /// Whether the value is JSON `null`.
    public var isNull: Bool {
        if case .null = self { return true }
        return false
    }

    /// Own key of an object; `nil` for anything that is not an object.
    public subscript(key: String) -> JSONValue? {
        objectValue?[key]
    }
}

/// A JSON object that remembers the order of its keys.
///
/// Order matters in a few places of the contract (the first entry wins, a document is walked
/// in its own order), and `JSONSerialization` loses it. A repeated key keeps its first
/// position and takes the last value, as `JSON.parse` does.
public struct JSONObject: Equatable, Sendable, Sequence {
    /// The keys in the order they first appeared.
    public private(set) var keys: [String] = []
    private var storage: [String: JSONValue] = [:]

    public init() {}

    public init(_ pairs: [(String, JSONValue)]) {
        for (key, value) in pairs { self[key] = value }
    }

    /// The number of keys.
    public var count: Int { keys.count }
    /// Whether the object has no key.
    public var isEmpty: Bool { keys.isEmpty }

    /// The value of a key; assigning `nil` removes the key.
    public subscript(key: String) -> JSONValue? {
        get { storage[key] }
        set {
            if let newValue {
                if storage.updateValue(newValue, forKey: key) == nil { keys.append(key) }
            } else if storage.removeValue(forKey: key) != nil {
                keys.removeAll { $0 == key }
            }
        }
    }

    /// Iterates the pairs in key order.
    public func makeIterator() -> AnyIterator<(key: String, value: JSONValue)> {
        var index = 0
        return AnyIterator {
            guard index < keys.count else { return nil }
            defer { index += 1 }
            let key = keys[index]
            return (key, storage[key] ?? .null)
        }
    }

    /// Objects are equal when their keys and values are; the order of keys takes no part.
    public static func == (lhs: JSONObject, rhs: JSONObject) -> Bool {
        lhs.storage == rhs.storage
    }
}

/// Literals for building values in code. A `nil` literal is `.null`, but where the context is an
/// `Optional<JSONValue>` it is `Optional.none`: write `.null` when you mean JSON null.
extension JSONValue: ExpressibleByStringLiteral, ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral,
    ExpressibleByBooleanLiteral, ExpressibleByNilLiteral, ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral
{
    public init(stringLiteral value: String) { self = .string(value) }
    public init(integerLiteral value: Int) { self = .number(Double(value)) }
    public init(floatLiteral value: Double) { self = .number(value) }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(nilLiteral: ()) { self = .null }
    public init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
    public init(dictionaryLiteral elements: (String, JSONValue)...) { self = .object(JSONObject(elements)) }
}

extension JSONObject: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (String, JSONValue)...) { self.init(elements) }
}
