import Foundation

/// Errors of `JSONValue.parse`. The reader never shows them to the end user; the host gets
/// them through `HotlayoutLoadError` and decides what to draw instead.
public struct JSONParseError: Error, Equatable, CustomStringConvertible, Sendable {
    /// The byte offset of the error in the input.
    public let offset: Int
    /// What is wrong, in a few words.
    public let reason: String
    /// `JSON: reason at byte offset`.
    public var description: String { "JSON: \(reason) at byte \(offset)" }
}

extension JSONValue {
    /// The deepest nesting the parser accepts. A document is far shallower (32 levels under
    /// a screen root are drawn); the bound exists so that a hostile payload cannot exhaust
    /// the stack.
    static let maxParseDepth = 256

    /// Parses JSON text. Hand-written instead of `JSONSerialization` because the contract needs
    /// what that does not give: the order of object keys is kept, a repeated key takes the last
    /// value as `JSON.parse` does, and the nesting depth is checked before any recursion, so a
    /// hostile payload cannot exhaust the stack. Strict about syntax (a broken payload is a load error, not a guess),
    /// lenient about nothing else: shapes are judged later, piece by piece.
    public static func parse(_ data: Data) throws -> JSONValue {
        var parser = Parser(bytes: [UInt8](data))
        parser.skipWhitespace()
        let value = try parser.value(depth: 0)
        parser.skipWhitespace()
        guard parser.index == parser.bytes.count else { throw parser.error("unexpected trailing characters") }
        return value
    }

    /// Parses JSON text; see `parse(_:)` for `Data`.
    public static func parse(_ text: String) throws -> JSONValue {
        try parse(Data(text.utf8))
    }
}

private struct Parser {
    let bytes: [UInt8]
    var index = 0

    init(bytes: [UInt8]) { self.bytes = bytes }

    func error(_ reason: String) -> JSONParseError { JSONParseError(offset: index, reason: reason) }

    mutating func skipWhitespace() {
        while index < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[index]) { index += 1 }
    }

    mutating func value(depth: Int) throws -> JSONValue {
        guard depth <= JSONValue.maxParseDepth else { throw error("nesting too deep") }
        guard index < bytes.count else { throw error("unexpected end") }
        switch bytes[index] {
        case UInt8(ascii: "{"): return try object(depth: depth)
        case UInt8(ascii: "["): return try array(depth: depth)
        case UInt8(ascii: "\""): return .string(try string())
        case UInt8(ascii: "t"):
            try literal("true")
            return .bool(true)
        case UInt8(ascii: "f"):
            try literal("false")
            return .bool(false)
        case UInt8(ascii: "n"):
            try literal("null")
            return .null
        default: return .number(try number())
        }
    }

    mutating func literal(_ word: String) throws {
        let utf8 = Array(word.utf8)
        guard index + utf8.count <= bytes.count, Array(bytes[index..<index + utf8.count]) == utf8 else {
            throw error("unexpected character")
        }
        index += utf8.count
    }

    mutating func object(depth: Int) throws -> JSONValue {
        index += 1
        var object = JSONObject()
        skipWhitespace()
        if index < bytes.count, bytes[index] == UInt8(ascii: "}") {
            index += 1
            return .object(object)
        }
        while true {
            skipWhitespace()
            guard index < bytes.count, bytes[index] == UInt8(ascii: "\"") else { throw error("expected a key") }
            let key = try string()
            skipWhitespace()
            guard index < bytes.count, bytes[index] == UInt8(ascii: ":") else { throw error("expected ':'") }
            index += 1
            skipWhitespace()
            object[key] = try value(depth: depth + 1)
            skipWhitespace()
            guard index < bytes.count else { throw error("unexpected end in an object") }
            if bytes[index] == UInt8(ascii: ",") {
                index += 1
                continue
            }
            if bytes[index] == UInt8(ascii: "}") {
                index += 1
                return .object(object)
            }
            throw error("expected ',' or '}'")
        }
    }

    mutating func array(depth: Int) throws -> JSONValue {
        index += 1
        var items: [JSONValue] = []
        skipWhitespace()
        if index < bytes.count, bytes[index] == UInt8(ascii: "]") {
            index += 1
            return .array(items)
        }
        while true {
            skipWhitespace()
            items.append(try value(depth: depth + 1))
            skipWhitespace()
            guard index < bytes.count else { throw error("unexpected end in an array") }
            if bytes[index] == UInt8(ascii: ",") {
                index += 1
                continue
            }
            if bytes[index] == UInt8(ascii: "]") {
                index += 1
                return .array(items)
            }
            throw error("expected ',' or ']'")
        }
    }

    mutating func number() throws -> Double {
        let start = index
        if index < bytes.count, bytes[index] == UInt8(ascii: "-") { index += 1 }
        func digits() -> Int {
            let from = index
            while index < bytes.count, bytes[index] >= 0x30, bytes[index] <= 0x39 { index += 1 }
            return index - from
        }
        guard digits() > 0 else { throw error("malformed number") }
        if index < bytes.count, bytes[index] == UInt8(ascii: ".") {
            index += 1
            guard digits() > 0 else { throw error("malformed number") }
        }
        if index < bytes.count, bytes[index] == UInt8(ascii: "e") || bytes[index] == UInt8(ascii: "E") {
            index += 1
            if index < bytes.count, bytes[index] == UInt8(ascii: "+") || bytes[index] == UInt8(ascii: "-") { index += 1 }
            guard digits() > 0 else { throw error("malformed number") }
        }
        let text = String(decoding: bytes[start..<index], as: UTF8.self)
        guard let value = Double(text) else { throw error("malformed number") }
        return value
    }

    mutating func hex4() throws -> UInt32 {
        guard index + 4 <= bytes.count else { throw error("short unicode escape") }
        var result: UInt32 = 0
        for _ in 0..<4 {
            let byte = bytes[index]
            let digit: UInt32
            switch byte {
            case 0x30...0x39: digit = UInt32(byte - 0x30)
            case 0x41...0x46: digit = UInt32(byte - 0x41 + 10)
            case 0x61...0x66: digit = UInt32(byte - 0x61 + 10)
            default: throw error("malformed unicode escape")
            }
            result = result * 16 + digit
            index += 1
        }
        return result
    }

    mutating func string() throws -> String {
        index += 1
        var buffer: [UInt8] = []
        while true {
            guard index < bytes.count else { throw error("unterminated string") }
            let byte = bytes[index]
            if byte == UInt8(ascii: "\"") {
                index += 1
                break
            }
            if byte < 0x20 { throw error("control character in a string") }
            if byte != UInt8(ascii: "\\") {
                buffer.append(byte)
                index += 1
                continue
            }
            index += 1
            guard index < bytes.count else { throw error("unterminated escape") }
            let escape = bytes[index]
            index += 1
            switch escape {
            case UInt8(ascii: "\""): buffer.append(0x22)
            case UInt8(ascii: "\\"): buffer.append(0x5C)
            case UInt8(ascii: "/"): buffer.append(0x2F)
            case UInt8(ascii: "b"): buffer.append(0x08)
            case UInt8(ascii: "f"): buffer.append(0x0C)
            case UInt8(ascii: "n"): buffer.append(0x0A)
            case UInt8(ascii: "r"): buffer.append(0x0D)
            case UInt8(ascii: "t"): buffer.append(0x09)
            case UInt8(ascii: "u"):
                var scalar = try hex4()
                if (0xD800...0xDBFF).contains(scalar), index + 6 <= bytes.count,
                    bytes[index] == UInt8(ascii: "\\"), bytes[index + 1] == UInt8(ascii: "u")
                {
                    let save = index
                    index += 2
                    let low = try hex4()
                    if (0xDC00...0xDFFF).contains(low) {
                        scalar = 0x10000 + ((scalar - 0xD800) << 10) + (low - 0xDC00)
                    } else {
                        index = save
                    }
                }
                // A lone surrogate is not a character: it becomes U+FFFD, as in JavaScript text output.
                let character = Unicode.Scalar(scalar) ?? "\u{FFFD}"
                buffer.append(contentsOf: Array(String(character).utf8))
            default:
                throw error("unknown escape")
            }
        }
        return String(decoding: buffer, as: UTF8.self)
    }
}
