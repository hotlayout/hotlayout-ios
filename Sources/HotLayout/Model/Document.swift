import Foundation

/// One node of a screen tree, read tolerantly.
///
/// Props and the node fields stay JSON: each widget reads what it understands, so a field of
/// a newer minor (or one of the wrong shape) is simply not read (`unknownStyleField:
/// 'ignore-field'`), and the rest of the node works.
public struct DocumentNode: Identifiable, Equatable, Sendable {
    public let id: String
    public let type: String
    public let props: JSONObject
    /// Every field of the node as it lies in the document (`style`, `styleWhen`, `visibleIf`,
    /// `weight`, `fill`, …). Readers of node fields look here.
    public let fields: JSONObject
    public let children: [DocumentNode]
    /// `columns` of this node came from a width-class layer (read as 1…6, not as the base's 2…4).
    let columnsFromOverride: Bool

    public var style: JSONValue? { fields["style"] }
    public var styleWhen: JSONValue? { fields["styleWhen"] }
    public var visibleIf: JSONValue? { fields["visibleIf"] }

    init(id: String, type: String, props: JSONObject = JSONObject(), fields: JSONObject = JSONObject(), children: [DocumentNode] = []) {
        self.init(id: id, type: type, props: props, fields: fields, children: children, columnsFromOverride: false)
    }

    init(id: String, type: String, props: JSONObject, fields: JSONObject, children: [DocumentNode], columnsFromOverride: Bool) {
        self.columnsFromOverride = columnsFromOverride
        self.id = id
        self.type = type
        self.props = props
        self.fields = fields
        self.children = children
    }
}

public enum ScreenPresentation: String, Equatable, Sendable {
    case page
    case modal
}

/// An entry of `screens`: a screen and how it is shown.
public struct ScreenEntry: Equatable, Sendable {
    public let screenId: String
    public let name: String
    public let presentation: ScreenPresentation
    /// `bottom` or `center` (9.9.0); only known words are kept (`unknownModalPlacement`).
    public let modalPlacement: String?
    /// `light` or `dark`: the screen's request about the icons of the system status bar
    /// (`statusBarIcons`). The reader does not touch the status bar; the request goes to the
    /// host with the screen-shown event.
    public let statusBarIcons: String?
    /// Blur radius under a modal layer, 1…40 (9.20.0); `nil` without a valid field or on a page.
    public let backdropBlur: Int?
    /// `false` only for a modal layer that waits for an action inside it (9.26.0).
    public let dismissible: Bool
    public let root: DocumentNode
}

/// `localization` of a document: the source language, the listed languages and the
/// translation table (`strings[locale][key]`).
public struct DocumentLocalization: Equatable, Sendable {
    public let defaultLocale: String
    public let locales: [String]
    public let strings: [String: [String: String]]
}

/// A document as the reader holds it: the screens it could read and what it skipped.
public struct HotlayoutDocument: Equatable, Sendable {
    public let schemaVersion: String
    public let documentId: String
    public let name: String
    public let initialScreenId: String?
    public let entryPoints: [String: String]
    public let screens: [ScreenEntry]
    public let localization: DocumentLocalization?
    public let reports: [HotlayoutReport]

    public func screen(_ screenId: String) -> ScreenEntry? {
        screens.first { $0.screenId == screenId }
    }

    public static func == (lhs: HotlayoutDocument, rhs: HotlayoutDocument) -> Bool {
        lhs.documentId == rhs.documentId && lhs.schemaVersion == rhs.schemaVersion && lhs.screens == rhs.screens
            && lhs.localization == rhs.localization && lhs.entryPoints == rhs.entryPoints
            && lhs.initialScreenId == rhs.initialScreenId
    }
}

/// Why a document or a theme could not be read at all. Everything smaller than this is a report.
public enum HotlayoutLoadError: Error, Equatable, CustomStringConvertible, Sendable {
    case malformedJSON(String)
    case notADocument(String)
    /// The JSON is not a theme contract this reader can use (`loadTheme`).
    case notATheme(String)
    case incompatibleVersion(VersionVerdict)
    case maxDepthExceeded(screenId: String)

    public var description: String {
        switch self {
        case .malformedJSON(let reason): return "malformed JSON: \(reason)"
        case .notADocument(let reason): return "not a document: \(reason)"
        case .notATheme(let reason): return "not a theme: \(reason)"
        case .incompatibleVersion(let verdict): return "incompatible version: \(verdict)"
        case .maxDepthExceeded(let screenId): return "screen “\(screenId)” is deeper than \(DocumentReader.maxParseDepth) levels"
        }
    }
}

extension HotlayoutDocument {
    /// Loads a document: JSON, the version gate, the guards, then a tolerant read of the tree.
    ///
    /// - Throws: `HotlayoutLoadError`.
    public static func load(_ data: Data) throws -> HotlayoutDocument {
        let json: JSONValue
        do {
            json = try JSONValue.parse(data)
        } catch {
            throw HotlayoutLoadError.malformedJSON(String(describing: error))
        }
        return try load(json)
    }

    /// Loads a document from JSON that is already parsed.
    public static func load(_ json: JSONValue) throws -> HotlayoutDocument {
        try DocumentReader.read(json)
    }
}

@available(*, deprecated, renamed: "HotlayoutDocument.load(_:)")
public func loadDocument(_ data: Data) throws -> HotlayoutDocument { try HotlayoutDocument.load(data) }

@available(*, deprecated, renamed: "HotlayoutDocument.load(_:)")
public func loadDocument(_ json: JSONValue) throws -> HotlayoutDocument { try HotlayoutDocument.load(json) }

/// The tolerant reader of the document tree.
enum DocumentReader {
    /// Widgets of the schema; any other type is an unknown widget.
    static let knownWidgets = Set(WidgetType.allCases.map(\.rawValue))

    /// Levels UNDER a screen root that are drawn. A deeper tree is refused before any
    /// recursion (the legal maximum is far smaller).
    static let maxParseDepth = 32
    /// A key an open map cannot have (`protoKeyWithoutValidation: 'drop-entry'`).
    static let forbiddenKey = "__proto__"

    static func read(_ raw: JSONValue) throws -> HotlayoutDocument {
        let json = withoutForbiddenKeys(raw)
        guard let object = json.objectValue else { throw HotlayoutLoadError.notADocument("the document is not an object") }

        let verdict = HotlayoutVersions.checkDocument(json)
        guard verdict.isReadable else { throw HotlayoutLoadError.incompatibleVersion(verdict) }

        let sink = ReportSink()
        var screens: [ScreenEntry] = []
        for (index, item) in (object["screens"]?.arrayValue ?? []).enumerated() {
            guard let entry = item.objectValue, let screenId = entry["screenId"]?.stringValue, !screenId.isEmpty else {
                sink.add(.ignoredInput, "screens[\(index)]", "a screen entry without a screenId string is skipped")
                continue
            }
            guard let rootValue = entry["root"], rootValue.objectValue != nil else {
                sink.add(.ignoredInput, "screen “\(screenId)”", "a screen without a root object is skipped")
                continue
            }
            if treeDepth(rootValue) > maxParseDepth + 1 { throw HotlayoutLoadError.maxDepthExceeded(screenId: screenId) }
            guard let root = node(rootValue, location: "screen “\(screenId)”", position: "root", sink: sink) else { continue }
            let placement = entry["modalPlacement"]?.stringValue
            let isModal = entry["presentation"]?.stringValue == "modal"
            screens.append(
                ScreenEntry(
                    screenId: screenId,
                    name: entry["name"]?.stringValue ?? "",
                    presentation: isModal ? .modal : .page,
                    modalPlacement: placement == "bottom" || placement == "center" ? placement : nil,
                    statusBarIcons: ScreenAnatomy.statusBarIcons(entry["statusBarIcons"]),
                    backdropBlur: isModal ? ModalRules.blurRadius(entry["backdropBlur"]) : nil,
                    dismissible: !(isModal && entry["dismissible"]?.boolValue == false),
                    root: root
                )
            )
        }
        if screens.isEmpty { throw HotlayoutLoadError.notADocument("the document has no readable screen") }

        var entryPoints: [String: String] = [:]
        for (name, target) in object["entryPoints"]?.objectValue ?? JSONObject() {
            if let target = target.stringValue { entryPoints[name] = target }
        }

        return HotlayoutDocument(
            schemaVersion: object["schemaVersion"]?.stringValue ?? "",
            documentId: object["documentId"]?.stringValue ?? "",
            name: object["name"]?.stringValue ?? "",
            initialScreenId: object["initialScreenId"]?.stringValue,
            entryPoints: entryPoints,
            screens: screens,
            localization: localization(object["localization"], sink: sink),
            reports: sink.reports
        )
    }

    /// Reads one node. A child that is not an object or has no type is skipped and reported;
    /// a node without an id gets one from its position, so that the rest of it is drawn.
    static func node(_ value: JSONValue, location: String, position: String, sink: ReportSink) -> DocumentNode? {
        guard let object = value.objectValue else {
            sink.add(.ignoredInput, "\(location): \(position)", "a node that is not an object is skipped")
            return nil
        }
        guard let type = object["type"]?.stringValue, !type.isEmpty else {
            sink.add(.ignoredInput, "\(location): \(position)", "a node without a type is skipped")
            return nil
        }
        let id: String
        if let own = object["id"]?.stringValue, !own.isEmpty {
            id = own
        } else {
            id = "#\(position)"
            sink.add(.ignoredInput, "\(location): \(position)", "a node without an id string; an id is made from its position")
        }
        let here = "\(location): node “\(id)”"
        var props = JSONObject()
        if let value = object["props"] {
            if let own = value.objectValue { props = own } else { sink.add(.ignoredInput, here, "props are not an object; the widget draws with its defaults") }
        }
        if WidgetType(rawValue: type) == nil {
            sink.add(.unknownWidget, here, "unknown widget “\(type)”; its children are drawn")
        }
        var children: [DocumentNode] = []
        if let list = object["children"] {
            if let items = list.arrayValue {
                for (index, child) in items.enumerated() {
                    if let read = node(child, location: here, position: "children[\(index)]", sink: sink) { children.append(read) }
                }
            } else {
                sink.add(.ignoredInput, here, "children are not a list; the node is drawn without them")
            }
        }
        var fields = object
        fields["children"] = nil
        fields["props"] = nil
        return DocumentNode(id: id, type: type, props: props, fields: fields, children: children)
    }

    static func localization(_ value: JSONValue?, sink: ReportSink) -> DocumentLocalization? {
        guard let value, !value.isNull else { return nil }
        guard let object = value.objectValue, let source = object["defaultLocale"]?.stringValue else {
            sink.add(.ignoredInput, "localization", "localization without a defaultLocale string is ignored; texts are shown as written")
            return nil
        }
        let locales = (object["locales"]?.arrayValue ?? []).compactMap(\.stringValue)
        var strings: [String: [String: String]] = [:]
        for (locale, table) in object["strings"]?.objectValue ?? JSONObject() {
            var entries: [String: String] = [:]
            for (key, text) in table.objectValue ?? JSONObject() {
                if let text = text.stringValue { entries[key] = text }
            }
            strings[locale] = entries
        }
        return DocumentLocalization(defaultLocale: source, locales: locales, strings: strings)
    }

    /// Depth of a node tree where the root is 1. Iterative: a recursive measurement would
    /// crash on the very input it exists to refuse.
    static func treeDepth(_ root: JSONValue) -> Int {
        var deepest = 0
        var pending: [(JSONValue, Int)] = [(root, 1)]
        while let (node, depth) = pending.popLast() {
            deepest = max(deepest, depth)
            if deepest > maxParseDepth + 1 { return deepest }
            for child in node["children"]?.arrayValue ?? [] { pending.append((child, depth + 1)) }
        }
        return deepest
    }

    /// The same value without own `__proto__` keys at any depth.
    static func withoutForbiddenKeys(_ value: JSONValue) -> JSONValue {
        switch value {
        case .object(let object):
            var copy = JSONObject()
            for (key, item) in object where key != forbiddenKey { copy[key] = withoutForbiddenKeys(item) }
            return .object(copy)
        case .array(let items):
            return .array(items.map(withoutForbiddenKeys))
        default:
            return value
        }
    }
}
