import SwiftUI
#if canImport(UIKit)
    import UIKit
#endif

/// Draws the document that stands in a named place of the app, and nothing when the place is
/// empty, unknown or unreadable. See `HotlayoutPlacement.load` for where it comes from.
///
/// The place is loaded once per `name` and `projectBase`; the view does not poll. The map is not
/// asked again when a scheduled window begins or ends: the view sets a timer for the next edge of
/// the schedule and resolves the place again by the device clock (`clock`), and does so too when
/// the app comes back to the foreground, since the clock may have been set. What the view
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
    let clock: @Sendable () -> Date
    let onPlacement: ((HotlayoutPlacement) -> Void)?
    let content: (HotlayoutDocument, String?) -> Content

    @State private var placement: HotlayoutPlacement?
    @State private var events = EventBox()
    /// Bumped to start the timer over: after a load and when the app returns to the foreground.
    @State private var scheduleRun = 0
    @Environment(\.scenePhase) private var scenePhase

    private final class EventBox {
        var tracker = PlacementEventTracker()
        var context: HotlayoutPlacement.Context?
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
        clock: @escaping @Sendable () -> Date = { Date() },
        onPlacement: ((HotlayoutPlacement) -> Void)? = nil,
        @ViewBuilder content: @escaping (HotlayoutDocument, String?) -> Content
    ) {
        self.name = name
        self.projectBase = projectBase
        self.bundledMap = bundledMap
        self.store = store
        self.documents = documents
        self.session = session
        self.clock = clock
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
            events.context = nil
            events.tracker.reset()
            let loaded = await HotlayoutPlacement.read(
                name: name, projectBase: projectBase, bundledMap: bundledMap, store: store, documents: documents, session: session, clock: clock
            )
            // A task that was replaced or cancelled while it loaded must not write.
            guard !Task.isCancelled else { return }
            events.context = loaded.context
            apply(loaded.placement)
            scheduleRun += 1
        }
        .task(id: scheduleRun) { await followSchedule() }
        .onChange(of: scenePhase) { phase in
            if phase == .active { scheduleRun += 1 }
        }
        #if canImport(UIKit) && !os(watchOS)
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in scheduleRun += 1 }
        #endif
    }

    private func apply(_ loaded: HotlayoutPlacement) {
        placement = loaded
        if events.tracker.next(loaded.event) != nil { onPlacement?(loaded) }
    }

    /// Resolves the place again by the clock and sleeps to the next edge of its schedule, over and
    /// over, until the task is replaced. The map is not asked: only a document that a new window
    /// brings is. A place whose resolution did not change is left alone.
    private func followSchedule() async {
        while !Task.isCancelled, let context = events.context {
            let now = clock()
            let resolution = context.map.resolve(name, at: now)
            if resolution != placement?.resolution {
                let shown = await HotlayoutPlacement.show(name, context: context, at: now)
                guard !Task.isCancelled else { return }
                apply(shown)
            }
            guard let next = context.map.nextBoundary(name, after: clock()) else { return }
            let ms = PlacementTimer.sleepMs(until: next, from: clock())
            do { try await Task.sleep(for: .milliseconds(ms)) } catch { return }
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
        clock: @escaping @Sendable () -> Date = { Date() },
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
            name: name, projectBase: projectBase, bundledMap: bundledMap, store: store, documents: documents, session: session, clock: clock, onPlacement: onPlacement
        ) { document, entry in
            HotlayoutScreen(
                document: document, theme: theme, data: data, locale: locale, entry: entry,
                onAction: onAction, onTrack: onTrack, onScreenChange: onScreenChange, onReport: onReport
            )
        }
    }
}
