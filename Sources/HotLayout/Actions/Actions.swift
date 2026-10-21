import Foundation

/// Problems of an action parameter against its form (`x-actions.problems`), in the order the
/// checks run: missing, then too long, then the form.
public enum ActionParamProblem: String, Equatable, Sendable {
    case missing
    case tooLong = "too-long"
    case notHTTPS = "not-https"
    case malformed
    case forbiddenScheme = "forbidden-scheme"
}

/// A catalog action the HOST performs, with parameters that passed their form.
public enum StandardAction: Equatable, Sendable {
    case openURL(url: String)
    case deeplink(url: String, scheme: String)
    case close
}

/// A parameter of a standard action that did not pass its form, and why.
public struct InvalidActionParam: Equatable, Sendable {
    public let param: String
    public let problem: ActionParamProblem

    public init(param: String, problem: ActionParamProblem) {
        self.param = param
        self.problem = problem
    }
}

/// The action as the host receives it through `onAction`.
///
/// The reader opens nothing itself (`standardActionExecution: 'host-only-reader-opens-nothing'`):
/// an address is checked by its form and handed over as `standard` or `invalid`, never both.
/// `track` is not part of it: the analytics event goes separately, before the action.
public struct HotlayoutAction: Equatable, Sendable {
    public let type: String
    /// Parameters after `paramBindings` were applied; `nil` when there are none.
    public let params: [String: String]?
    public let standard: StandardAction?
    public let invalid: InvalidActionParam?

    public init(type: String, params: [String: String]? = nil, standard: StandardAction? = nil, invalid: InvalidActionParam? = nil) {
        self.type = type
        self.params = params
        self.standard = standard
        self.invalid = invalid
    }
}

/// The tactile response a press asks the host for (`x-haptic.words`). The reader never vibrates:
/// map the word to the haptics of the platform in `onHaptic`.
public enum HapticFeedback: String, CaseIterable, Equatable, Sendable {
    case light, medium, heavy, selection, success, warning
}

/// The analytics event of a press (`track`), sent once per press, before the action.
public struct TrackEvent: Equatable, Sendable {
    public let event: String
    public let params: [String: String]?
}

/// The action catalog (`x-actions`): forms of parameters and what the host receives.
public enum ActionCatalog {
    struct Param {
        let name: String
        let required: Bool
        let form: String
        let bindable: Bool
    }

    struct Entry {
        let type: ActionType
        let hostExecutes: Bool
        let params: [Param]
    }

    static let entries: [Entry] = [
        Entry(type: .none, hostExecutes: false, params: []),
        Entry(type: .navigate, hostExecutes: false, params: [Param(name: "screenId", required: true, form: "screenId", bindable: false)]),
        Entry(type: .navigateBack, hostExecutes: false, params: []),
        Entry(type: .navigateSection, hostExecutes: false, params: [Param(name: "screenId", required: true, form: "screenId", bindable: false)]),
        Entry(type: .openUrl, hostExecutes: true, params: [Param(name: "url", required: true, form: "httpsUrl", bindable: true)]),
        Entry(type: .deeplink, hostExecutes: true, params: [Param(name: "url", required: true, form: "appLink", bindable: true)]),
        Entry(type: .close, hostExecutes: true, params: []),
        Entry(
            type: .setValue, hostExecutes: false,
            params: [
                Param(name: "path", required: true, form: "dataPath", bindable: false),
                Param(name: "value", required: false, form: "literal", bindable: false),
                Param(name: "valueType", required: false, form: "valueType", bindable: false),
            ]),
        Entry(type: .toggleValue, hostExecutes: false, params: [Param(name: "path", required: true, form: "dataPath", bindable: false)]),
    ]

    static func entry(_ type: String) -> Entry? { ActionType(type).flatMap { type in entries.first { $0.type == type } } }

    /// `x-actions.forms` — one source with the artifact (compared by a test).
    static let urlMaxLength = 2048
    private static let urlChars = "A-Za-z0-9\\-._~:/?#\\[\\]@!$&'()*+,;=%"
    private static let port = "(?:[1-9][0-9]{0,3}|[1-5][0-9]{4}|6[0-4][0-9]{3}|65[0-4][0-9]{2}|655[0-2][0-9]|6553[0-5])"
    static let httpsURLPattern =
        "^https:\\/\\/(?:[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?\\.)+(?:[A-Za-z]{2,}|xn--[A-Za-z0-9-]*[A-Za-z0-9])(?::\(port))?(?:[/?#][\(urlChars)]*)?$"
    static let appLinkPattern = "^([a-z][a-z0-9+.-]{1,31}):[\(urlChars)]+$"
    static let forbiddenSchemes: Set<String> = [
        "javascript", "data", "file", "blob", "vbscript", "filesystem", "content", "jar", "resource", "intent",
        "android-app", "about", "chrome", "view-source", "http", "https", "ftp", "ws", "wss",
    ]
    private static let httpsURL = try! NSRegularExpression(pattern: httpsURLPattern)
    private static let appLink = try! NSRegularExpression(pattern: appLinkPattern)
    private static let paramKey = try! NSRegularExpression(pattern: "^(?!(?:__proto__|constructor|prototype)$)\\S+$")
    private static let trackName = try! NSRegularExpression(pattern: "^(?!(?:constructor|prototype)$)[A-Za-z][A-Za-z0-9_]*$")
    private static let dataPathSegment = try! NSRegularExpression(pattern: "^[A-Za-z_][A-Za-z0-9_-]*$")
    static let forbiddenSegments: Set<String> = ["__proto__", "constructor", "prototype"]

    /// The scheme of an app link, or `nil` if the value does not have the form.
    static func appLinkScheme(_ value: String) -> String? {
        let whole = NSRange(value.startIndex..., in: value)
        guard let match = appLink.firstMatch(in: value, range: whole), match.range == whole,
            let range = Range(match.range(at: 1), in: value)
        else { return nil }
        return String(value[range])
    }

    /// The problem of a parameter value against its form, or `nil` when it passes. The form
    /// is an EXPRESSION, not a platform URL parser: the value is neither trimmed nor normalized.
    public static func formProblem(_ form: String, _ value: String?) -> ActionParamProblem? {
        guard let value, !value.isEmpty else { return .missing }
        guard form == "httpsUrl" || form == "appLink" else { return nil }
        if value.utf16.count > urlMaxLength { return .tooLong }
        if form == "httpsUrl" {
            guard value.hasPrefix("https://") else { return .notHTTPS }
            return matches(httpsURL, value) ? nil : .malformed
        }
        guard let scheme = appLinkScheme(value) else { return .malformed }
        return forbiddenSchemes.contains(scheme) ? .forbiddenScheme : nil
    }

    static func isParamKey(_ key: String) -> Bool {
        key.utf16.count <= 32 && matches(paramKey, key)
    }

    static func isDataPath(_ value: String) -> Bool {
        guard !value.isEmpty, value.utf16.count <= 128 else { return false }
        return value.split(separator: ".", omittingEmptySubsequences: false).allSatisfy {
            matches(dataPathSegment, String($0)) && !forbiddenSegments.contains(String($0))
        }
    }

    /// What the host receives for an action of the document, read with the node's data scope.
    static func handed(_ action: JSONObject, scope: DataScope, sink: ReportSink? = nil, location: String = "action") -> HotlayoutAction {
        let type = action["type"]?.stringValue ?? ""
        let entry = entry(type)
        var params: [String: String] = [:]
        if let literals = action["params"] {
            if let object = literals.objectValue {
                for (name, value) in object {
                    if isParamKey(name), let text = value.stringValue, text.utf16.count <= urlMaxLength {
                        params[name] = text
                    } else {
                        sink?.add(.ignoredInput, "\(location): params.\(name.prefix(32))", "an action parameter that is not a plain string value is dropped")
                    }
                }
            } else if !literals.isNull {
                sink?.add(.ignoredInput, "\(location): params", "params is not an object; the parameters were ignored")
            }
        }
        // A parameter is whole data or whole literal: a binding replaces the literal only with a
        // non-empty string, and never where the catalog says the parameter is not bindable.
        for (name, path) in action["paramBindings"]?.objectValue ?? JSONObject() {
            guard isParamKey(name), let path = path.stringValue, isDataPath(path) else { continue }
            if let param = entry?.params.first(where: { $0.name == name }), !param.bindable { continue }
            if let value = scope[path]?.stringValue, !value.isEmpty, value.utf16.count <= urlMaxLength { params[name] = value }
        }
        let base = params.isEmpty ? nil : params
        guard let entry, entry.hostExecutes else { return HotlayoutAction(type: type, params: base) }
        for param in entry.params {
            if let problem = formProblem(param.form, params[param.name]), param.required || problem != .missing {
                return HotlayoutAction(type: type, params: base, invalid: InvalidActionParam(param: param.name, problem: problem))
            }
        }
        switch entry.type {
        case .openUrl: return HotlayoutAction(type: type, params: base, standard: .openURL(url: params["url"] ?? ""))
        case .deeplink:
            let url = params["url"] ?? ""
            return HotlayoutAction(type: type, params: base, standard: .deeplink(url: url, scheme: appLinkScheme(url) ?? ""))
        default: return HotlayoutAction(type: type, params: base, standard: .close)
        }
    }

    /// The analytics event of an action; a `track` of the wrong form is ignored WHOLE.
    static func track(_ action: JSONObject, sink: ReportSink? = nil, location: String = "action") -> TrackEvent? {
        guard let value = action["track"], !value.isNull else { return nil }
        guard let object = value.objectValue, let event = object["event"]?.stringValue, event.utf16.count <= 40, matches(trackName, event) else {
            sink?.add(.ignoredInput, "\(location): track", "track is not an event of the form the contract names; no analytics event is sent")
            return nil
        }
        guard let raw = object["params"], !raw.isNull else { return TrackEvent(event: event, params: nil) }
        guard let map = raw.objectValue, map.count <= 25 else {
            sink?.add(.ignoredInput, "\(location): track.params", "track.params is not a flat map of the form the contract names; no analytics event is sent")
            return nil
        }
        var params: [String: String] = [:]
        for (key, item) in map {
            guard key.utf16.count <= 40, matches(trackName, key), !forbiddenSegments.contains(key), let text = item.stringValue, text.utf16.count <= 100 else {
                sink?.add(
                    .ignoredInput, "\(location): track.params", "track.params is not a flat map of the form the contract names; no analytics event is sent")
                return nil
            }
            params[key] = text
        }
        return TrackEvent(event: event, params: params.isEmpty ? nil : params)
    }

    /// Haptic feedback a press asks the host for (`x-haptic`), or `nil`.
    static func haptic(_ action: JSONObject) -> HapticFeedback? {
        action["haptic"]?.stringValue.flatMap(HapticFeedback.init(rawValue:))
    }
}

/// Helper for the HOST: performs a standard action on Apple platforms. The reader never calls
/// it; the host decides (and may ask the person first).
public enum StandardActions {
    /// The URL to open for a standard action, or `nil` for `close` and for an app link whose
    /// scheme the host did not allow.
    public static func url(for action: HotlayoutAction, allowedDeeplinkSchemes: Set<String> = []) -> URL? {
        switch action.standard {
        case .openURL(let url)?: return URL(string: url)
        case .deeplink(let url, let scheme)? where allowedDeeplinkSchemes.contains(scheme): return URL(string: url)
        default: return nil
        }
    }
}
