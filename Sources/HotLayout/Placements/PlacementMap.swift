import Foundation

/// The version of the placement contract this reader is written against
/// (`x-placementsVersion` of `placements.json`).
extension HotlayoutVersions {
    public static let placements = "1.1.0"
}

/// What stands in a named place of the app, after a tolerant read of the map.
public struct HotlayoutPlacementResolution: Equatable, Sendable {
    public enum Status: String, Equatable, Sendable {
        /// A document is placed here (`documentId`, maybe an `entry`).
        case document
        /// The place is declared and empty on purpose.
        case empty
        /// No such place: not in the map, or a name that can never be a place.
        case unknown
        /// The map could not be read, or this place's record is broken.
        case unreadable
    }

    public let status: Status
    public let documentId: String?
    public let entry: String?

    public init(status: Status, documentId: String? = nil, entry: String? = nil) {
        self.status = status
        self.documentId = documentId
        self.entry = entry
    }
}

/// The placement map of a project (`placements/published.json`), read tolerantly.
///
/// The map comes from the network, so it is untrusted: an unknown field is skipped, a broken
/// record spoils only its own place, a key is looked up among the map's own keys, and a
/// `documentId` must have the form of a path segment before it can become part of an address.
/// The limits on the number of places and on the file size are the builder's: a reader does
/// not check them.
public struct HotlayoutPlacementMap: Equatable, Sendable {
    /// What the file turned out to be.
    public enum Reading: Equatable, Sendable {
        case map
        /// Not a map at all: not JSON, not an object, no version or no `placements`.
        case corrupt
        /// A map of another major version of the contract.
        case unsupported
    }

    public let reading: Reading
    let places: JSONObject

    /// Reads the text of the file; see `init(data:)`. Text that is not JSON is `corrupt`, not an error.
    public init(text: String) {
        self.init(data: Data(text.utf8))
    }

    /// Reads the bytes of the file. A body over 262 144 bytes, one that is not strict UTF-8 or one
    /// nested deeper than 32 levels is `corrupt`; one leading byte order mark is skipped.
    public init(data: Data) {
        guard let text = PlacementBody.text(of: data), let json = try? JSONValue.parse(text) else {
            self.init(reading: .corrupt, places: [:])
            return
        }
        self.init(json: json)
    }

    /// Reads a parsed file.
    public init(json: JSONValue) {
        guard let object = json.objectValue,
            let version = object["placementsVersion"]?.stringValue,
            let parsed = PlacementVersion(version)
        else {
            self.init(reading: .corrupt, places: [:])
            return
        }
        guard parsed.major == PlacementVersion(HotlayoutVersions.placements)?.major else {
            self.init(reading: .unsupported, places: [:])
            return
        }
        guard let places = object["placements"]?.objectValue else {
            self.init(reading: .corrupt, places: [:])
            return
        }
        self.init(reading: .map, places: places)
    }

    private init(reading: Reading, places: JSONObject) {
        self.reading = reading
        self.places = places
    }

    /// The ids of the documents the places of this map name (the ones of a readable form), the
    /// scheduled ones included.
    func documentIds() -> Set<String> {
        guard reading == .map else { return [] }
        return Set(places.keys.compactMap { resolve($0).documentId }).union(scheduledDocumentIds())
    }

    /// What a name turned out to be in the map; the permanent content is already checked.
    enum Lookup {
        case unknown
        case unreadable
        case place(JSONObject, permanent: HotlayoutPlacementResolution)

        var resolution: HotlayoutPlacementResolution {
            switch self {
            case .unknown: return HotlayoutPlacementResolution(status: .unknown)
            case .unreadable: return HotlayoutPlacementResolution(status: .unreadable)
            case .place(_, let permanent): return permanent
            }
        }
    }

    /// The order of the checks is part of the rule: a map that could not be read gives
    /// `unreadable` to any name; a name of the wrong form is `unknown`; then the map's own key.
    func lookup(_ name: String) -> Lookup {
        guard reading == .map else { return .unreadable }
        guard PlacementForms.isName(name), let record = places[name] else { return .unknown }
        guard let place = record.objectValue, let documentId = place["documentId"] else { return .unreadable }
        let permanent = Self.permanent(place, documentId: documentId)
        return permanent.status == .unreadable ? .unreadable : .place(place, permanent: permanent)
    }

    /// What stands in the place `name` for good, without a schedule; see `resolve(_:at:)`.
    public func resolve(_ name: String) -> HotlayoutPlacementResolution { lookup(name).resolution }

    private static func permanent(_ place: JSONObject, documentId: JSONValue) -> HotlayoutPlacementResolution {
        if documentId.isNull { return HotlayoutPlacementResolution(status: .empty) }
        guard let id = documentId.stringValue, PlacementForms.isDocumentId(id) else { return HotlayoutPlacementResolution(status: .unreadable) }
        // `entry: null` is the same as no entry: backends often write null for absence.
        guard let entry = place["entry"], !entry.isNull else { return HotlayoutPlacementResolution(status: .document, documentId: id) }
        guard let entryName = entry.stringValue, PlacementForms.isEntry(entryName) else { return HotlayoutPlacementResolution(status: .unreadable) }
        return HotlayoutPlacementResolution(status: .document, documentId: id, entry: entryName)
    }
}

/// The forms of the contract (`x-limits` of `placements.json`), written by hand: the check is
/// ASCII-only and has no regex whose `$` could match before a final newline.
enum PlacementForms {
    static let nameMax = 64
    static let entryMax = 48
    static let documentIdMax = 64

    private static func isLower(_ byte: UInt8) -> Bool { byte >= 0x61 && byte <= 0x7A }
    private static func isDigit(_ byte: UInt8) -> Bool { byte >= 0x30 && byte <= 0x39 }
    private static func isUpper(_ byte: UInt8) -> Bool { byte >= 0x41 && byte <= 0x5A }

    /// `^[a-z][a-z0-9]*(\.[a-z0-9-]+)*$`, at most 64 characters.
    static func isName(_ name: String) -> Bool {
        let bytes = Array(name.utf8)
        guard !bytes.isEmpty, bytes.count <= nameMax, isLower(bytes[0]) else { return false }
        var inFirstSegment = true
        var segmentLength = 0
        for byte in bytes {
            if byte == 0x2E {
                guard segmentLength > 0 else { return false }
                inFirstSegment = false
                segmentLength = 0
                continue
            }
            let allowed = isLower(byte) || isDigit(byte) || (!inFirstSegment && byte == 0x2D)
            guard allowed else { return false }
            segmentLength += 1
        }
        return segmentLength > 0
    }

    /// `^(?!\.+$)[A-Za-z0-9._-]{1,64}$`: a path segment that cannot leave the documents folder.
    static func isDocumentId(_ id: String) -> Bool {
        let bytes = Array(id.utf8)
        guard !bytes.isEmpty, bytes.count <= documentIdMax else { return false }
        var onlyDots = true
        for byte in bytes {
            if byte != 0x2E { onlyDots = false }
            guard isLower(byte) || isUpper(byte) || isDigit(byte) || byte == 0x2E || byte == 0x5F || byte == 0x2D else { return false }
        }
        return !onlyDots
    }

    /// `^[a-z0-9][a-z0-9-]*$`, at most 48 characters.
    static func isEntry(_ entry: String) -> Bool {
        let bytes = Array(entry.utf8)
        guard !bytes.isEmpty, bytes.count <= entryMax, isLower(bytes[0]) || isDigit(bytes[0]) else { return false }
        return bytes.allSatisfy { isLower($0) || isDigit($0) || $0 == 0x2D }
    }
}

/// `MAJOR.MINOR.PATCH` with no sign, no space and no leading zero. The parts stay digit strings:
/// a major is compared as text, so a long number is another major and never wraps around.
struct PlacementVersion: Equatable {
    let major: String
    let minor: String
    let patch: String

    init?(_ text: String) {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        for part in parts {
            guard !part.isEmpty, part.utf8.allSatisfy({ $0 >= 0x30 && $0 <= 0x39 }), part == "0" || part.first != "0" else { return nil }
        }
        major = String(parts[0])
        minor = String(parts[1])
        patch = String(parts[2])
    }
}
