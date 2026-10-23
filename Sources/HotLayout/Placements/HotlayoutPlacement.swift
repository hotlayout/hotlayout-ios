import Foundation

/// A named place of the app and what stands in it: the answer of `HotlayoutPlacement.load`.
///
/// The app names the place (`home.banner`); which published document stands there is decided in
/// the admin, without a release of the app. `document` is `nil` for every place that draws
/// nothing; `report` says why.
public struct HotlayoutPlacement: Sendable {
    public let name: String
    /// Where the map in use came from and why (`fresh` is the only status without a problem).
    public let mapStatus: HotlayoutPlacementMapStatus
    public let resolution: HotlayoutPlacementResolution
    /// The document to draw, or `nil`.
    public let document: HotlayoutDocument?
    /// The entry point to start from; `nil` is the initial screen of the document.
    public let entry: String?
    /// Why nothing is drawn, or that the entry point was missing. `nil` when all is well.
    public let report: HotlayoutPlacementReport?

    /// Loads a place.
    ///
    /// The map is `placements/published.json` under `projectBase`, asked with its `ETag`; the
    /// answer is used when it is readable and kept as the last known map. When the network gives
    /// no readable map, the last known map is used, then `bundledMap` (the text of a copy
    /// shipped with the app). The document is `documents/{documentId}/published.json` under the
    /// same base, with the same rules; a document the network cannot give falls back on the last
    /// one read, except after a 404, which means it is gone.
    ///
    /// Never throws: every failure is a `report`.
    ///
    /// - Parameters:
    ///   - projectBase: the base address of the project in the storage.
    ///   - bundledMap: the text of a map shipped with the app, for a first start without a network.
    ///   - store: where the last known map and documents are kept; `UserDefaults` by default.
    ///   - session: the session to ask with; an ephemeral one with a 15-second limit by default.
    public static func load(
        name: String,
        projectBase: URL,
        bundledMap: String? = nil,
        store: HotlayoutPlacementStore = HotlayoutUserDefaultsPlacementStore(),
        session: URLSession? = nil
    ) async -> HotlayoutPlacement {
        let transport = PlacementTransport(session: session ?? PlacementTransport.defaultSession())
        let scope = projectBase.absoluteString
        let mapKey = "\(scope)#map"
        let lastKnown = store.value(forKey: mapKey)
        let lastKnownReadable = lastKnown.map { HotlayoutPlacementMap(text: $0).reading == .map } ?? false
        let mapURL = projectBase.appendingPathComponent("placements").appendingPathComponent("published.json")
        let answer = await transport.get(mapURL, etag: lastKnownReadable ? store.value(forKey: mapKey + ".etag") : nil)

        let outcome: PlacementNetworkOutcome
        switch answer.kind {
        case .ok: outcome = .map(String(decoding: answer.body, as: UTF8.self))
        case .notModified: outcome = .notModified
        case .notFound: outcome = .notFound
        case .failed: outcome = .offline
        }
        let decision = PlacementSource.pick(network: outcome, lastKnown: lastKnown, bundled: bundledMap)
        if decision.remember, case .map(let text) = outcome {
            store.set(text, forKey: mapKey)
            store.set(answer.etag, forKey: mapKey + ".etag")
        }

        let resolution = decision.map.resolve(name)
        var document: HotlayoutDocument?
        var documentOutcome: PlacementDocumentOutcome?
        if resolution.status == .document, let id = resolution.documentId {
            let read = await loadDocument(id: id, base: projectBase, scope: scope, store: store, transport: transport)
            document = read.document
            documentOutcome = read.outcome
        }
        let showing = PlacementShowing.of(resolution, document: documentOutcome)
        return HotlayoutPlacement(
            name: name, mapStatus: decision.status, resolution: resolution,
            document: showing.showsDocument ? document : nil, entry: showing.entry, report: showing.report
        )
    }

    private static let documentMaxBytes = 8 * 1024 * 1024

    private static func loadDocument(
        id: String, base: URL, scope: String, store: HotlayoutPlacementStore, transport: PlacementTransport
    ) async -> (document: HotlayoutDocument?, outcome: PlacementDocumentOutcome) {
        let key = "\(scope)#document.\(id)"
        let kept = store.value(forKey: key).flatMap { text in (try? HotlayoutDocument.load(Data(text.utf8))).map { (text, $0) } }
        let url = base.appendingPathComponent("documents").appendingPathComponent(id).appendingPathComponent("published.json")
        let answer = await transport.get(url, etag: kept == nil ? nil : store.value(forKey: key + ".etag"))
        func outcome(_ document: HotlayoutDocument) -> (HotlayoutDocument?, PlacementDocumentOutcome) {
            (document, .ok(entryPoints: Set(document.entryPoints.keys)))
        }
        switch answer.kind {
        case .ok where answer.body.count <= documentMaxBytes:
            if let document = try? HotlayoutDocument.load(answer.body) {
                store.set(String(decoding: answer.body, as: UTF8.self), forKey: key)
                store.set(answer.etag, forKey: key + ".etag")
                return outcome(document)
            }
        case .notModified:
            if let kept { return outcome(kept.1) }
        case .notFound:
            // Gone: a copy kept from before must not bring it back.
            store.set(nil, forKey: key)
            store.set(nil, forKey: key + ".etag")
            return (nil, .missing)
        default:
            break
        }
        // No answer, or one that is not a document: the last document read, else nothing.
        if let kept { return outcome(kept.1) }
        return (nil, .unreadable)
    }
}

/// One GET with an optional `If-None-Match`.
struct PlacementTransport: Sendable {
    enum Kind { case ok, notModified, notFound, failed }
    struct Answer {
        let kind: Kind
        let body: Data
        let etag: String?
    }

    let session: URLSession

    static func defaultSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }

    func get(_ url: URL, etag: String?) async -> Answer {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if let etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        guard let (body, response) = try? await session.data(for: request), let http = response as? HTTPURLResponse else {
            return Answer(kind: .failed, body: Data(), etag: nil)
        }
        switch http.statusCode {
        case 200: return Answer(kind: .ok, body: body, etag: http.value(forHTTPHeaderField: "ETag"))
        case 304: return Answer(kind: .notModified, body: Data(), etag: nil)
        case 404: return Answer(kind: .notFound, body: Data(), etag: nil)
        default: return Answer(kind: .failed, body: Data(), etag: nil)
        }
    }
}
