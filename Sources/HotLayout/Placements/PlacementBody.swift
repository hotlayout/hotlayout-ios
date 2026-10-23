import Foundation

/// The rules for the bytes of a placement map, applied before the JSON parser sees them: the
/// size, strict UTF-8, one leading byte order mark and the nesting depth.
enum PlacementBody {
    /// The largest body the reader accepts (the builder publishes at most a quarter of it).
    static let maxBytes = 262_144
    /// The deepest nesting accepted anywhere in the body; the root is level 1.
    static let maxDepth = 32

    /// The text of a body, or `nil` when the body is not a candidate for a map at all:
    /// over the size limit, not strict UTF-8, or nested deeper than `maxDepth`.
    /// One leading U+FEFF is dropped; a second one stays and fails the JSON parse.
    static func text(of data: Data) -> String? {
        guard data.count <= maxBytes else { return nil }
        var bytes = [UInt8](data)
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { bytes.removeFirst(3) }
        guard let text = strictUTF8(bytes), !nestsDeeper(bytes) else { return nil }
        return text
    }

    /// Decodes UTF-8 and refuses what the standard decoder would repair: a stray or truncated
    /// sequence, an overlong form, an encoded surrogate, a code point above U+10FFFF.
    static func strictUTF8(_ bytes: [UInt8]) -> String? {
        var iterator = bytes.makeIterator()
        var decoder = UTF8()
        var scalars = String.UnicodeScalarView()
        while true {
            switch decoder.decode(&iterator) {
            case .scalarValue(let scalar): scalars.append(scalar)
            case .emptyInput: return String(scalars)
            case .error: return nil
            }
        }
    }

    /// Whether brackets nest deeper than `maxDepth` outside of strings.
    static func nestsDeeper(_ bytes: [UInt8]) -> Bool {
        var depth = 0
        var inString = false
        var escaped = false
        for byte in bytes {
            if inString {
                if escaped { escaped = false } else if byte == 0x5C { escaped = true } else if byte == 0x22 { inString = false }
                continue
            }
            switch byte {
            case 0x22: inString = true
            case 0x5B, 0x7B:
                depth += 1
                if depth > maxDepth { return true }
            case 0x5D, 0x7D: depth = max(0, depth - 1)
            default: break
            }
        }
        return false
    }
}
