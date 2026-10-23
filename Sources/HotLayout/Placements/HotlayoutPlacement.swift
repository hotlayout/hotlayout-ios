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
    /// answer is used when it is readable and kept as the last known map (under the address of
    /// the map, so one project's map never serves another). When the network gives no readable
    /// map, the last known map is used, then `bundledMap` (the text of a copy shipped with the
    /// app). The document is `documents/{documentId}/published.json` under the same base, with
    /// the same rules; a document the network cannot give falls back on the last one read, except
    /// after a 404, which means it is gone.
    ///
    /// A request that is redirected, or that is not finished 20 seconds after it started, is no
    /// answer. A map is read up to 262 144 bytes, a document up to 8 MB.
    ///
    /// Documents are kept for the places the map in use names, one for each, and the others are
    /// removed after a fresh map is read.
    ///
    /// Never throws: every failure is a `report`.
    ///
    /// - Parameters:
    ///   - projectBase: the base address of the project in the storage.
    ///   - bundledMap: the text of a map shipped with the app, for a first start without a network.
    ///   - store: where the last known map is kept; `UserDefaults` by default.
    ///   - documents: where the documents read last are kept; files in the caches directory by default.
    ///   - session: the session to ask with; an ephemeral one with a 20-second limit by default.
    public static func load(
        name: String,
        projectBase: URL,
        bundledMap: String? = nil,
        store: HotlayoutPlacementStore = HotlayoutUserDefaultsPlacementStore(),
        documents: HotlayoutPlacementDocumentStore = HotlayoutFilePlacementDocumentStore(),
        session: URLSession? = nil
    ) async -> HotlayoutPlacement {
        let transport = PlacementTransport(session: session ?? PlacementTransport.defaultSession())
        let mapURL = projectBase.appendingPathComponent("placements").appendingPathComponent("published.json")
        let mapKey = mapURL.absoluteString
        let lastKnown = store.value(forKey: mapKey)
        let lastKnownReadable = lastKnown.map { HotlayoutPlacementMap(text: $0).reading == .map } ?? false
        let etag = lastKnownReadable ? store.value(forKey: mapKey + ".etag") : nil
        let reply = await transport.get(mapURL, etag: etag, maxBytes: PlacementBody.maxBytes)
        // A cancelled load changes nothing: the caller has moved on.
        guard !Task.isCancelled else { return cancelled(name) }

        let outcome = PlacementAnswer.map(reply)
        let decision = PlacementSource.pick(network: outcome, lastKnown: lastKnown, bundled: bundledMap)
        if decision.remember, case .map(let text) = outcome {
            store.set(text, forKey: mapKey)
            store.set(reply.etag, forKey: mapKey + ".etag")
        }

        let resolution = decision.map.resolve(name)
        if decision.status == .fresh { prune(documents, base: projectBase, keeping: decision.map.documentIds()) }
        var document: HotlayoutDocument?
        var documentOutcome: PlacementDocumentOutcome?
        if resolution.status == .document, let id = resolution.documentId {
            let read = await loadDocument(id: id, base: projectBase, documents: documents, transport: transport)
            guard !Task.isCancelled else { return cancelled(name) }
            document = read.document
            documentOutcome = read.outcome
        }
        let showing = PlacementShowing.of(resolution, document: documentOutcome)
        return HotlayoutPlacement(
            name: name, mapStatus: decision.status, resolution: resolution,
            document: showing.showsDocument ? document : nil, entry: showing.entry, report: showing.report
        )
    }

    /// What a load that was cancelled returns; the caller drops it.
    private static func cancelled(_ name: String) -> HotlayoutPlacement {
        HotlayoutPlacement(
            name: name, mapStatus: .offline, resolution: HotlayoutPlacementResolution(status: .unreadable),
            document: nil, entry: nil, report: .unreadable
        )
    }

    /// What the host is told about this state; see `HotlayoutPlacementEvent`.
    public var event: HotlayoutPlacementEvent {
        let shown = document != nil
        return HotlayoutPlacementEvent(
            status: shown ? "document" : "nothing", report: report, mapStatus: mapStatus,
            documentId: shown ? resolution.documentId : nil, entry: shown ? entry : nil
        )
    }

    private static let documentMaxBytes = 8 * 1024 * 1024

    private static func documentKey(_ id: String, base: URL) -> String {
        documentURL(id, base: base).absoluteString
    }

    private static func documentURL(_ id: String, base: URL) -> URL {
        base.appendingPathComponent("documents").appendingPathComponent(id).appendingPathComponent("published.json")
    }

    /// Removes the kept documents of this project that the map no longer names.
    private static func prune(_ documents: HotlayoutPlacementDocumentStore, base: URL, keeping ids: Set<String>) {
        let prefix = base.appendingPathComponent("documents").absoluteString + "/"
        let keep = Set(ids.map { documentKey($0, base: base) })
        for key in documents.keys() where key.hasPrefix(prefix) && !keep.contains(key) {
            documents.setDocument(nil, forKey: key)
        }
    }

    private static func loadDocument(
        id: String, base: URL, documents: HotlayoutPlacementDocumentStore, transport: PlacementTransport
    ) async -> (document: HotlayoutDocument?, outcome: PlacementDocumentOutcome) {
        let key = documentKey(id, base: base)
        let kept = documents.document(forKey: key).flatMap { cached in (try? HotlayoutDocument.load(cached.data)).map { (cached, $0) } }
        let reply = await transport.get(documentURL(id, base: base), etag: kept?.0.etag, maxBytes: documentMaxBytes)
        func outcome(_ document: HotlayoutDocument) -> (HotlayoutDocument?, PlacementDocumentOutcome) {
            (document, .ok(entryPoints: Set(document.entryPoints.keys)))
        }
        switch PlacementAnswer.document(reply) {
        case .read:
            if reply.body.count <= documentMaxBytes, !Task.isCancelled, let document = try? HotlayoutDocument.load(reply.body) {
                documents.setDocument(HotlayoutPlacementCachedDocument(data: reply.body, etag: reply.etag), forKey: key)
                return outcome(document)
            }
        case .notModified:
            if let kept { return outcome(kept.1) }
        case .missing:
            // Gone: a copy kept from before must not bring it back.
            if !Task.isCancelled { documents.setDocument(nil, forKey: key) }
            return (nil, .missing)
        case .unreadable:
            break
        }
        // No answer, or one that is not a document: the last document read, else nothing.
        if let kept { return outcome(kept.1) }
        return (nil, .unreadable)
    }
}
