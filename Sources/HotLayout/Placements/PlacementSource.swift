import Foundation

/// Why the map in use is the one in use. "The network is silent", "the map is broken" and
/// "the project has published no map" are different things: the host shows different things
/// and support looks in different places.
public enum HotlayoutPlacementMapStatus: String, Equatable, Sendable {
    /// The network answered with a readable map (or 304 and a readable last known one).
    case fresh
    /// No answer: a connection error, a timeout, a 5xx, a 403, or a 304 with nothing to keep.
    case offline
    /// The network answered with something that is not a map.
    case corrupt
    /// The network answered with a map of another major version.
    case unsupported
    /// The network answered 404: the project has not published placements.
    case notPublished
}

/// What the network said about the map file.
enum PlacementNetworkOutcome: Equatable {
    case map(String)
    /// An answer that cannot be a map: over the size limit, not strict UTF-8, or too deeply nested.
    case corrupt
    case notModified
    case notFound
    case offline
}

struct PlacementSourceDecision {
    enum Source: Equatable { case network, lastKnown, bundled, none }
    let source: Source
    let status: HotlayoutPlacementMapStatus
    /// Whether the text of the network answer becomes the new last known map.
    let remember: Bool
    let map: HotlayoutPlacementMap
}

enum PlacementSource {
    /// Which map to use. The order of the fallbacks is the same for every cause: the last known
    /// map, then the copy bundled with the app. Without any map, a project that published none
    /// has every place `unknown`; otherwise every place is `unreadable`.
    static func pick(network: PlacementNetworkOutcome, lastKnown: String?, bundled: String?) -> PlacementSourceDecision {
        switch network {
        case .map(let text):
            let read = HotlayoutPlacementMap(text: text)
            if read.reading == .map { return PlacementSourceDecision(source: .network, status: .fresh, remember: true, map: read) }
            return fallback(lastKnown: lastKnown, bundled: bundled, status: read.reading == .unsupported ? .unsupported : .corrupt)
        case .corrupt:
            return fallback(lastKnown: lastKnown, bundled: bundled, status: .corrupt)
        case .notModified:
            if let lastKnown {
                let last = HotlayoutPlacementMap(text: lastKnown)
                if last.reading == .map { return PlacementSourceDecision(source: .lastKnown, status: .fresh, remember: false, map: last) }
            }
            // 304 with nothing readable to keep is the same as no answer.
            return fallback(lastKnown: nil, bundled: bundled, status: .offline)
        case .notFound:
            return fallback(lastKnown: lastKnown, bundled: bundled, status: .notPublished)
        case .offline:
            return fallback(lastKnown: lastKnown, bundled: bundled, status: .offline)
        }
    }

    private static func fallback(lastKnown: String?, bundled: String?, status: HotlayoutPlacementMapStatus) -> PlacementSourceDecision {
        for (text, source) in [(lastKnown, PlacementSourceDecision.Source.lastKnown), (bundled, .bundled)] {
            guard let text else { continue }
            let map = HotlayoutPlacementMap(text: text)
            if map.reading == .map { return PlacementSourceDecision(source: source, status: status, remember: false, map: map) }
        }
        let none = status == .notPublished
            ? HotlayoutPlacementMap(text: "{\"placementsVersion\":\"\(HotlayoutVersions.placements)\",\"placements\":{}}")
            : HotlayoutPlacementMap(text: "")
        return PlacementSourceDecision(source: .none, status: status, remember: false, map: none)
    }
}

/// What the host is told when a place does not draw a document.
public enum HotlayoutPlacementReport: String, Equatable, Sendable {
    /// The place is declared and empty.
    case empty
    /// The app asked for a place the map does not have.
    case unknown
    /// The map, or this place's record, could not be read.
    case unreadable
    /// The document is gone (404, after the reader's own fallbacks).
    case documentMissing
    /// The document could not be read.
    case documentUnreadable
    /// The entry point is not in the document: the document is drawn from its first screen.
    case entryMissing
}

enum PlacementDocumentOutcome {
    case ok(entryPoints: Set<String>)
    case missing
    case unreadable
}

struct PlacementShowing: Equatable {
    let showsDocument: Bool
    /// The entry point to start from; `nil` is the initial screen.
    let entry: String?
    let report: HotlayoutPlacementReport?

    /// What a place draws. An entry point the document lacks starts the initial screen
    /// (`unknownEntryPoint: use-initial`) and the host hears of it: it is a setup mistake that
    /// somebody has to fix.
    static func of(_ resolution: HotlayoutPlacementResolution, document: PlacementDocumentOutcome?) -> PlacementShowing {
        func nothing(_ report: HotlayoutPlacementReport) -> PlacementShowing { PlacementShowing(showsDocument: false, entry: nil, report: report) }
        guard resolution.status == .document else {
            switch resolution.status {
            case .empty: return nothing(.empty)
            case .unknown: return nothing(.unknown)
            default: return nothing(.unreadable)
            }
        }
        switch document {
        case .none, .unreadable?: return nothing(.documentUnreadable)
        case .missing?: return nothing(.documentMissing)
        case .ok(let entryPoints)?:
            guard let entry = resolution.entry else { return PlacementShowing(showsDocument: true, entry: nil, report: nil) }
            if entryPoints.contains(entry) { return PlacementShowing(showsDocument: true, entry: entry, report: nil) }
            return PlacementShowing(showsDocument: true, entry: nil, report: .entryMissing)
        }
    }
}

/// What one request to the project storage came back with: the status, the body and the time the
/// body ended (`nil` when it never did).
struct PlacementReply {
    let status: Int
    let body: Data
    let completedAtMs: Int?
    var etag: String? = nil
}

/// What the reader does with an answer. The deadline covers the request from its start to the end
/// of the body; a redirect is never followed.
enum PlacementAnswer {
    /// The longest a request may take, in milliseconds.
    static let deadlineMs = 20_000

    private static func inTime(_ reply: PlacementReply) -> Bool {
        guard let done = reply.completedAtMs else { return false }
        return done <= deadlineMs
    }

    /// The answer about the map.
    static func map(_ reply: PlacementReply) -> PlacementNetworkOutcome {
        guard inTime(reply) else { return .offline }
        switch reply.status {
        case 200:
            guard let text = PlacementBody.text(of: reply.body) else { return .corrupt }
            return .map(text)
        case 304: return .notModified
        case 404: return .notFound
        default: return .offline
        }
    }

    enum Document: Equatable { case read, notModified, missing, unreadable }

    /// The answer about a document; a body that is `read` still has to be a document.
    static func document(_ reply: PlacementReply) -> Document {
        guard inTime(reply) else { return .unreadable }
        switch reply.status {
        case 200: return .read
        case 304: return .notModified
        case 404: return .missing
        default: return .unreadable
        }
    }
}

/// What the host is told about a place: the five fields, one event for each change of any.
public struct HotlayoutPlacementEvent: Equatable, Sendable {
    /// `document` or `nothing`.
    public let status: String
    public let report: HotlayoutPlacementReport?
    public let mapStatus: HotlayoutPlacementMapStatus
    public let documentId: String?
    public let entry: String?

    public init(status: String, report: HotlayoutPlacementReport?, mapStatus: HotlayoutPlacementMapStatus, documentId: String?, entry: String?) {
        self.status = status
        self.report = report
        self.mapStatus = mapStatus
        self.documentId = documentId
        self.entry = entry
    }
}

/// Tells a state once: the first settled state, then every change of any field of the event.
struct PlacementEventTracker {
    private var last: HotlayoutPlacementEvent?

    mutating func next(_ event: HotlayoutPlacementEvent) -> HotlayoutPlacementEvent? {
        guard event != last else { return nil }
        last = event
        return event
    }

    mutating func reset() { last = nil }
}
