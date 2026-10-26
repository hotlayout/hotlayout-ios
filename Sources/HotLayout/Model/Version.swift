import Foundation

/// The contract versions this reader is written against.
///
/// The versions of the PACKAGE and of the contract are independent: a package release may
/// fix a bug without touching the contract, and a contract minor may need no code here.
public enum HotlayoutVersions {
    /// Widget schema (`x-schemaVersion` of `screen-schema.json`).
    public static let schema = "9.30.0"
    /// Theme contract (`x-themeContractVersion` of `theme.json`).
    public static let theme = "4.0.1"
    /// Icon set (`iconSetVersion` of `icons.json`).
    public static let iconSet = "1.0.0"

    /// Compares a document version with the version this reader supports.
    public static func check(_ documentVersion: String, readerVersion: String = HotlayoutVersions.schema) -> VersionVerdict {
        guard let document = Semver(documentVersion) else {
            return .incompatible(reason: "“\(documentVersion)” is not a version (expected major.minor.patch)", relation: .notAVersion)
        }
        guard let reader = Semver(readerVersion) else {
            preconditionFailure("HotLayout: malformed reader version \(readerVersion)")
        }
        if document.major != reader.major {
            return .incompatible(
                reason: "major \(document.major) is not readable by a major-\(reader.major) reader",
                relation: document.major > reader.major ? .documentNewer : .documentOlder
            )
        }
        // Versions are compared as numbers: 9.10.0 is newer than 9.9.0.
        if document.minor > reader.minor { return .newerMinor(documentVersion: documentVersion) }
        return .compatible
    }

    /// The version gate for a whole document: reads `schemaVersion` and judges it.
    ///
    /// A document without a string version is "not a version", never "assume the latest".
    public static func checkDocument(_ document: JSONValue) -> VersionVerdict {
        guard let version = document["schemaVersion"]?.stringValue else {
            return .incompatible(reason: "the document has no schemaVersion string", relation: .notAVersion)
        }
        return check(version)
    }
}

/// The relation of an incompatible document to this reader.
public enum IncompatibleRelation: String, Equatable, Sendable {
    case documentNewer = "document-newer"
    case documentOlder = "document-older"
    case notAVersion = "not-a-version"
}

/// Whether the reader can read a document of a given schema version.
///
/// The rule is the contract's (`x-compatibility.policy`): the MAJOR must match
/// (`majorMustMatch`), a newer minor only adds optional fields (`minorAdditionsAreOptional`),
/// so it is read and what the reader does not know is skipped; a patch takes no part.
public enum VersionVerdict: Equatable, Sendable {
    case compatible
    case newerMinor(documentVersion: String)
    case incompatible(reason: String, relation: IncompatibleRelation)

    /// Whether the reader reads the document.
    public var isReadable: Bool {
        if case .incompatible = self { return false }
        return true
    }
}

private struct Semver {
    let major: Int
    let minor: Int
    let patch: Int

    init?(_ text: String) {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        var numbers: [Int] = []
        for part in parts {
            // Digits only: "+1" or " 1" is not a version, and `Int("+1")` would accept it.
            guard !part.isEmpty, part.utf8.count <= 9, part.allSatisfy({ $0.isASCII && $0.isNumber }), let number = Int(part) else { return nil }
            numbers.append(number)
        }
        major = numbers[0]
        minor = numbers[1]
        patch = numbers[2]
    }
}

@available(*, deprecated, renamed: "HotlayoutVersions.check(_:readerVersion:)")
public func checkVersion(_ documentVersion: String, readerVersion: String = HotlayoutVersions.schema) -> VersionVerdict {
    HotlayoutVersions.check(documentVersion, readerVersion: readerVersion)
}

@available(*, deprecated, renamed: "HotlayoutVersions.checkDocument(_:)")
public func checkDocumentVersion(_ document: JSONValue) -> VersionVerdict {
    HotlayoutVersions.checkDocument(document)
}
