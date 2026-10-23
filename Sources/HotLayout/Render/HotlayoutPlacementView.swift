import SwiftUI

/// Draws the document that stands in a named place of the app, and nothing when the place is
/// empty, unknown or unreadable. See `HotlayoutPlacement.load` for where it comes from.
///
/// The place is loaded once per `name` and `projectBase`; the view does not poll. What the view
/// does not draw it reports: `onPlacement` is called with the first settled state of a place and
/// with every change of `placement.event` after it, so the host can show its own fallback when
/// `placement.document` is `nil` and take it away when the document comes back. When the name or
/// the project changes, the old place is dropped at once and the new one is reported afresh.
public struct HotlayoutPlacementView<Content: View>: View {
    let name: String
    let projectBase: URL
    let bundledMap: String?
    let store: HotlayoutPlacementStore
    let documents: HotlayoutPlacementDocumentStore
    let session: URLSession?
    let onPlacement: ((HotlayoutPlacement) -> Void)?
    let content: (HotlayoutDocument, String?) -> Content

    @State private var placement: HotlayoutPlacement?
    @State private var events = EventBox()

    private final class EventBox {
        var tracker = PlacementEventTracker()
    }

    /// Draws the placed document with a screen of your own making.
    ///
    /// - Parameter content: gets the document and the entry point to start from (`nil` is the
    ///   initial screen); return a `HotlayoutScreen` with the options you need.
    public init(
        name: String,
        projectBase: URL,
        bundledMap: String? = nil,
        store: HotlayoutPlacementStore = HotlayoutUserDefaultsPlacementStore(),
        documents: HotlayoutPlacementDocumentStore = HotlayoutFilePlacementDocumentStore(),
        session: URLSession? = nil,
        onPlacement: ((HotlayoutPlacement) -> Void)? = nil,
        @ViewBuilder content: @escaping (HotlayoutDocument, String?) -> Content
    ) {
        self.name = name
        self.projectBase = projectBase
        self.bundledMap = bundledMap
        self.store = store
        self.documents = documents
        self.session = session
        self.onPlacement = onPlacement
        self.content = content
    }

    public var body: some View {
        Group {
            if let document = placement?.document {
                content(document, placement?.entry)
            } else {
                // Not an empty `Group` alone: the `.task` below needs a view on the first frame.
                Color.clear.frame(width: 0, height: 0)
            }
        }
        .task(id: "\(projectBase.absoluteString)\n\(name)") {
            // Another place: what was drawn belongs to the old one.
            placement = nil
            events.tracker.reset()
            let loaded = await HotlayoutPlacement.load(
                name: name, projectBase: projectBase, bundledMap: bundledMap, store: store, documents: documents, session: session
            )
            // A task that was replaced or cancelled while it loaded must not write.
            guard !Task.isCancelled else { return }
            placement = loaded
            if events.tracker.next(loaded.event) != nil { onPlacement?(loaded) }
        }
    }
}

extension HotlayoutPlacementView where Content == HotlayoutScreen {
    /// Draws the placed document with a `HotlayoutScreen` and the options most hosts need.
    /// For the rest of the options use the initializer with a `content` closure.
    public init(
        name: String,
        projectBase: URL,
        bundledMap: String? = nil,
        store: HotlayoutPlacementStore = HotlayoutUserDefaultsPlacementStore(),
        documents: HotlayoutPlacementDocumentStore = HotlayoutFilePlacementDocumentStore(),
        session: URLSession? = nil,
        theme: HotlayoutThemeSet = .builtIn,
        data: DataScope = [:],
        locale: String? = Locale.current.identifier,
        onAction: ((HotlayoutAction, ActionSource) -> Void)? = nil,
        onTrack: ((TrackEvent, ActionSource) -> Void)? = nil,
        onScreenChange: ((ScreenShownEvent) -> Void)? = nil,
        onReport: (([HotlayoutReport]) -> Void)? = nil,
        onPlacement: ((HotlayoutPlacement) -> Void)? = nil
    ) {
        self.init(
            name: name, projectBase: projectBase, bundledMap: bundledMap, store: store, documents: documents, session: session, onPlacement: onPlacement
        ) { document, entry in
            HotlayoutScreen(
                document: document, theme: theme, data: data, locale: locale, entry: entry,
                onAction: onAction, onTrack: onTrack, onScreenChange: onScreenChange, onReport: onReport
            )
        }
    }
}
