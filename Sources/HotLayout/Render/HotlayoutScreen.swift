import Combine
import SwiftUI

/// Where a press came from: the node, the screen, and the record the node reads.
public struct ActionSource: Equatable, Sendable {
    /// The node pressed; `modal-dismiss` (`layerDismissal`) for a layer closed by a tap on its scrim
    /// or by a drag, which no node of the document asked for.
    public let nodeId: String
    public let screenId: String
    public let record: DataScope?

    /// The `nodeId` of a modal layer closed by its scrim or by a drag.
    public static let layerDismissal = "modal-dismiss"
}

/// Texts that belong to the reader rather than to the document; pass them in the language of
/// your app.
public struct ScreenLabels: Equatable, Sendable {
    /// What a screen reader says for the back arrow of an app bar, which has no text of its own.
    public var back: String

    public init(back: String = "Back") {
        self.back = back
    }
}

/// Draws a HotLayout document: the screen the flow is on, with the stack of screens the
/// reader navigates itself (`navigate`, `navigate.back`, `navigate.section`).
///
/// The reader opens nothing by itself. Every other action — `openUrl`, `deeplink`, `close`
/// and the actions of the app — goes to `onAction`, already checked: a standard action carries
/// `standard` or `invalid`. `StandardActions.url(for:)` helps a host that wants to open it.
///
/// `onAction` comes in two forms. A plain closure is called and returns at once. An `async`
/// closure is awaited by a button that confirms by a swipe: the thumb stays busy until the
/// closure returns, however long it takes (without it, eight seconds or until the screen changes).
public struct HotlayoutScreen: View {
    /// The host's handler of an action, plain or awaited.
    enum HostActionHandler {
        case plain((HotlayoutAction, ActionSource) -> Void)
        case awaited((HotlayoutAction, ActionSource) async -> Void)
    }

    let document: HotlayoutDocument
    let themeSet: HotlayoutThemeSet
    let themeId: String?
    let data: DataScope
    let locale: String?
    let entry: String?
    let timeZone: TimeZone?
    let now: Date?
    let images: ImagePolicy
    let labels: ScreenLabels
    var onAction: HostActionHandler?
    let onTrack: ((TrackEvent, ActionSource) -> Void)?
    let onHaptic: ((HapticFeedback, ActionSource) -> Void)?
    let onNavigate: ((NavigationEvent) -> Bool)?
    let onWrite: ((String, JSONValue) -> Void)?
    let writablePaths: WritablePaths?
    let autofill: Bool
    let onScreenChange: ((ScreenShownEvent) -> Void)?
    let onReport: (([HotlayoutReport]) -> Void)?

    @State private var flow: Flow?
    @State private var session: DataScope = [:]
    @State private var carousels = CarouselMemory()
    /// Lives as long as the screen does, not as long as one value of this view: a parent that
    /// draws again makes a new `HotlayoutScreen`, and the reports must not start over.
    @State private var sink = ReportSink()
    /// Fires on the main queue, after the frame, when there may be reports to hand over.
    @State private var reportsAdded = PassthroughSubject<Void, Never>()
    /// The screen-shown events after the first one, handed to the newest `onScreenChange`.
    @State private var screensShown = PassthroughSubject<ScreenShownEvent, Never>()

    /// - Parameters:
    ///   - document: a document from `HotlayoutDocument.load(_:)`.
    ///   - theme: the theme contract of the project (`HotlayoutThemeSet.load(_:)`); the built-in theme without one.
    ///   - themeId: a theme of the set to draw with; the set's default without one.
    ///   - data: the host's data, a flat map from a data path to a value.
    ///   - locale: the device locale as the platform gives it (`ar-EG`, `pt_BR`).
    ///   - entry: a named entry point of the document; an unknown name starts on the initial screen.
    ///   - timeZone: the time zone of dates; the device's without one.
    ///   - now: the moment countdowns and «days until» count from; the clock without one. With a moment given
    ///     the host owns the clock: no countdown ticks.
    ///   - images: where pictures may come from and how large they may be.
    ///   - labels: texts of the reader itself, in the language of your app.
    ///   - onAction: every action the reader does not perform itself.
    ///   - onTrack: the analytics event of a press, once per press, before the action.
    ///   - onHaptic: the haptic feedback a press asks for, before the analytics event; the reader
    ///     never vibrates by itself.
    ///   - onNavigate: asked BEFORE the reader changes screens by itself; return `false` to cancel,
    ///     and the reader does nothing.
    ///   - onWrite: a value the person entered or chose (a field, a choice, `setValue`, `toggleValue`),
    ///     already put into the session of the screen: a string, a flag or a number.
    ///   - writablePaths: the data paths the reader may write to; by default every path of the
    ///     form of a data path. A path that is refused is written to neither the session nor the host.
    ///   - autofill: `false` turns every autofill hint of the fields off.
    ///   - onScreenChange: the screen-shown event, once per show, the first one included.
    ///   - onReport: what the reader skipped or replaced in the document, the theme or while
    ///     drawing; each report is handed over once, as it appears.
    public init(
        document: HotlayoutDocument,
        theme: HotlayoutThemeSet = .builtIn,
        themeId: String? = nil,
        data: DataScope = [:],
        locale: String? = Locale.current.identifier,
        entry: String? = nil,
        timeZone: TimeZone? = nil,
        now: Date? = nil,
        images: ImagePolicy = ImagePolicy(),
        labels: ScreenLabels = ScreenLabels(),
        onAction: ((HotlayoutAction, ActionSource) -> Void)? = nil,
        onTrack: ((TrackEvent, ActionSource) -> Void)? = nil,
        onHaptic: ((HapticFeedback, ActionSource) -> Void)? = nil,
        onNavigate: ((NavigationEvent) -> Bool)? = nil,
        onWrite: ((String, JSONValue) -> Void)? = nil,
        writablePaths: WritablePaths? = nil,
        autofill: Bool = true,
        onScreenChange: ((ScreenShownEvent) -> Void)? = nil,
        onReport: (([HotlayoutReport]) -> Void)? = nil
    ) {
        self.document = document
        self.themeSet = theme
        self.themeId = themeId
        self.data = data
        self.locale = locale
        self.entry = entry
        self.timeZone = timeZone
        self.now = now
        self.images = images
        self.labels = labels
        self.onAction = onAction.map(HostActionHandler.plain)
        self.onTrack = onTrack
        self.onHaptic = onHaptic
        self.onNavigate = onNavigate
        self.onWrite = onWrite
        self.writablePaths = writablePaths
        self.autofill = autofill
        self.onScreenChange = onScreenChange
        self.onReport = onReport
    }

    /// The same screen with an `async` `onAction`: a button that confirms by a swipe stays busy
    /// until the closure returns. The other parameters are those of the plain form.
    public init(
        document: HotlayoutDocument,
        theme: HotlayoutThemeSet = .builtIn,
        themeId: String? = nil,
        data: DataScope = [:],
        locale: String? = Locale.current.identifier,
        entry: String? = nil,
        timeZone: TimeZone? = nil,
        now: Date? = nil,
        images: ImagePolicy = ImagePolicy(),
        labels: ScreenLabels = ScreenLabels(),
        onAction: @escaping (HotlayoutAction, ActionSource) async -> Void,
        onTrack: ((TrackEvent, ActionSource) -> Void)? = nil,
        onHaptic: ((HapticFeedback, ActionSource) -> Void)? = nil,
        onNavigate: ((NavigationEvent) -> Bool)? = nil,
        onWrite: ((String, JSONValue) -> Void)? = nil,
        writablePaths: WritablePaths? = nil,
        autofill: Bool = true,
        onScreenChange: ((ScreenShownEvent) -> Void)? = nil,
        onReport: (([HotlayoutReport]) -> Void)? = nil
    ) {
        self.init(
            document: document, theme: theme, themeId: themeId, data: data, locale: locale, entry: entry, timeZone: timeZone, now: now,
            images: images, labels: labels, onTrack: onTrack, onHaptic: onHaptic, onNavigate: onNavigate, onWrite: onWrite,
            writablePaths: writablePaths, autofill: autofill, onScreenChange: onScreenChange, onReport: onReport
        )
        self.onAction = .awaited(onAction)
    }

    private var currentFlow: Flow {
        flow ?? Flow(document: FlowDocument(document), entry: entry)
    }

    /// The data of the host under the session the person wrote into.
    private var hostScope: DataScope {
        RecordScope.merge(DataLayers(session: session, data: data))
    }

    public var body: some View {
        let flow = currentFlow
        let resolution = Localization.resolve(document.localization, requested: locale)
        let rightToLeft = TextDirectionRule.isRightToLeft(resolution.directionLocale) ?? false
        let frames = flow.stack
        let pageIndex =
            frames.lastIndex { frame in
                frame == frames.first || document.screen(frame.screenId)?.presentation != .modal
            } ?? 0
        let pageScreen = frames.indices.contains(pageIndex) ? document.screen(frames[pageIndex].screenId) : nil

        // The insets are read from the reader, which respects the safe area; the stack reaches over
        // the top and bottom ones itself (a view that ignores the safe area is told they are zero).
        GeometryReader { area in
            let insets = ScreenInsets(top: Double(area.safeAreaInsets.top), bottom: Double(area.safeAreaInsets.bottom))
            // One class for the whole screen, from the box the host gave it: a page takes the class of
            // that box, a modal layer is always compact (its own box is narrower than 600).
            let areaWidth = Double(area.size.width)
            let place = ScreenPlace(resolution: resolution, rightToLeft: rightToLeft, areaClass: WidthClass.of(width: areaWidth))
            let layerScreens = Dictionary(
                uniqueKeysWithValues: frames.indices.filter { $0 > pageIndex }.compactMap { index in document.screen(frames[index].screenId).map { (index, $0) } })
            ModalStack(
                layers: layerScreens.keys.sorted().compactMap { index in
                    layerScreens[index].map { screen in
                        let placement = screen.placement.map { JSONValue.string($0.rawValue) }
                        return ModalStackLayer(
                            id: index, shape: WideChrome.modalShape(placement: placement, areaWidth: areaWidth), placement: placement,
                            blur: screen.backdropBlur, dismissible: screen.dismissible)
                    }
                },
                margin: StyleResolver(theme: themeSet.theme(themeId)).spacing(.string("xl")) ?? ModalRules.defaultMargin,
                insets: insets,
                dismiss: dismissLayer,
                page: {
                    if let pageScreen {
                        screenView(pageScreen, frame: frames[pageIndex], index: pageIndex, place: place, insets: insets, asLayer: false)
                    } else {
                        Color.clear
                    }
                },
                layer: { layer in
                    if let screen = layerScreens[layer.id] {
                        // A layer holds no top inset; a sheet holds the bottom one under its content, a window none.
                        screenView(
                            screen, frame: frames[layer.id], index: layer.id, place: place,
                            insets: ScreenInsets(top: 0, bottom: layer.shape == .sheet ? insets.bottom : 0), asLayer: true,
                            sheetWindow: layer.shape == .sheetWindow)
                    }
                }
            )
            .ignoresSafeArea(.all, edges: .vertical)
        }
        .environment(\.layoutDirection, rightToLeft ? .rightToLeft : .leftToRight)
        .environment(\.glassOnDarkTheme, themeSet.theme(themeId).appearance == .dark)
        .environment(\.countdownClockPinned, now != nil)
        .onAppear {
            if self.flow == nil {
                let started = Flow(document: FlowDocument(document), entry: entry)
                self.flow = started
                if let event = started.shownEvent(cause: .entry) { onScreenChange?(event) }
                record(document.reports + themeSet.reports)
            }
            // Reports added later (a picture that failed, a report of drawing) are delivered too.
            let added = reportsAdded
            sink.observe { DispatchQueue.main.async { added.send() } }
            deliverReports()
        }
        .onDisappear { sink.observe(nil) }
        // The action of `onReceive` is the one of the newest body (that of `onChange` is not), so the
        // host's newest `onReport` hears every report and its newest `onScreenChange` every show.
        .onReceive(reportsAdded) { handOverReports() }
        .onReceive(screensShown) { onScreenChange?($0) }
        .onChange(of: DrawnDocument(document: document)) { new in
            var updated = currentFlow
            if let event = updated.update(document: FlowDocument(new.document)) { screensShown.send(event) }
            self.flow = updated
            record(new.document.reports)
            deliverReports()
        }
        .onChange(of: data) { newData in
            // New data: every frame of the stack looks for its record again (`x-liveRecord`).
            // The stack and the events stay: an update of the record is not a show.
            var updated = currentFlow
            let host = RecordScope.merge(DataLayers(session: session, data: newData))
            if updated.refresh(collections: { host[$0] }) { self.flow = updated }
            deliverReports()
        }
        .onChange(of: entry) { newEntry in
            var updated = currentFlow
            if let event = updated.restart(entry: newEntry) { screensShown.send(event) }
            self.flow = updated
            deliverReports()
        }
    }

    /// The document as `onChange` compares it: by its id and the digest of its drawable content,
    /// made once when it was read, not by walking the tree on every update.
    private struct DrawnDocument: Equatable {
        let document: HotlayoutDocument

        static func == (lhs: DrawnDocument, rhs: DrawnDocument) -> Bool { lhs.document.contentKey == rhs.document.contentKey }
    }

    /// What every screen of the stack shares: the language and the class of the area.
    private struct ScreenPlace {
        let resolution: LocaleResolution
        let rightToLeft: Bool
        let areaClass: WidthClass
    }

    private func screenView(
        _ screen: ScreenEntry, frame: FlowFrame, index: Int, place: ScreenPlace, insets: ScreenInsets, asLayer: Bool, sheetWindow: Bool = false
    ) -> some View {
        let widthClass = WideChrome.contentWidthClass(presentation: screen.presentation, area: place.areaClass)
        let root = screen.root.inWidthClass(widthClass)
        let resolver = StyleResolver(theme: themeSet.theme(themeId))
        let host = hostScope
        let scope = RecordScope.overlay(host, frame.record) ?? host
        var context = RenderContext(
            resolver: resolver,
            screenId: screen.screenId,
            localization: document.localization,
            locale: place.resolution,
            scope: scope,
            timeZone: timeZone,
            now: (now ?? Date()).timeIntervalSince1970 * 1000,
            rightToLeft: place.rightToLeft,
            inherited: NodeStyle.root(resolver),
            sink: sink,
            images: images,
            pressHandler: { action, node, instances in perform(action, node: node, instances: instances) },
            backLabel: labels.back,
            write: { path, value in write(path, value) },
            carousels: carousels,
            frameIndex: index
        )
        context.widthClass = widthClass
        // One plan per screen, made before anything is drawn: a list cannot know what the lists before it drew.
        let budget = ListBudget.plan(root: root, scope: scope)
        context.listBudget = budget
        let report = budget.report(screenId: screen.screenId).map { HotlayoutReport(kind: .ignoredInput, location: $0.location, reason: $0.reason) }
        return ScreenRootView(root: root, context: context, shrinks: asLayer, insets: insets, autofill: autofill, sheetWindow: sheetWindow)
            .onAppear { record(report.map { [$0] } ?? []) }
            .onChange(of: report) { record($0.map { [$0] } ?? []) }
    }

    // MARK: Reports

    private func record(_ reports: [HotlayoutReport]) {
        for report in reports { sink.add(report.kind, report.location, report.reason) }
    }

    /// Hands the reports that appeared since the last time to the host, after the frame that made
    /// them was drawn (a report of drawing is added while SwiftUI evaluates the body).
    private func deliverReports() {
        let added = reportsAdded
        DispatchQueue.main.async { added.send() }
    }

    private func handOverReports() {
        guard let onReport else { return }
        let fresh = sink.drain()
        if !fresh.isEmpty { onReport(fresh) }
    }

    // MARK: Presses

    /// A value entered or chosen: into the session of the screen and to the host at the same
    /// moment, unless the gate refuses the path (then to neither).
    private func write(_ path: String, _ value: JSONValue) {
        guard SessionWrite.apply(path: path, value: value, to: &session, gate: writablePaths, sink: sink) else { return }
        onWrite?(path, value)
        deliverReports()
    }

    /// Hands an action to the host's handler; an `async` one runs as a task the caller may wait for.
    private func handOver(_ action: HotlayoutAction, _ source: ActionSource) -> Task<Void, Never>? {
        switch onAction {
        case .plain(let handler)?:
            handler(action, source)
            return nil
        case .awaited(let handler)?:
            return Task { @MainActor in await handler(action, source) }
        case nil:
            return nil
        }
    }

    /// A press of a write action (`setValue`, `toggleValue`): the reader does it itself, through the
    /// same write as a field, after the haptic request and the analytics event.
    private func performWrite(_ action: JSONObject, node: DocumentNode, instances: [ListInstance]) -> PressRun {
        let host = hostScope
        let scope = RecordScope.overlay(host, currentFlow.nodeRecord(instances: instances)) ?? host
        let screenId = currentFlow.top?.screenId ?? ""
        let location = "screen “\(screenId)”: node “\(node.id)”: action"
        guard let effects = WritePress.effects(of: action, read: { scope[$0] }, sink: sink, location: location) else {
            return PressRun(runner: .none, task: nil)
        }
        let source = ActionSource(nodeId: node.id, screenId: screenId, record: nil)
        PressDelivery.deliver(PressOutcome(track: effects.track, haptic: effects.haptic), source: source, onHaptic: onHaptic, onTrack: onTrack, onAction: nil)
        if case .write(let path, let value) = effects.step { write(path, value) }
        deliverReports()
        return PressRun(runner: .reader, task: nil)
    }

    /// Closes the modal layer on top without a press: a tap on the scrim or a drag that closes a
    /// sheet. The host is asked first, as for `navigate.back`; the source names no node of the document.
    private func dismissLayer(animated: Bool) {
        var updated = currentFlow
        let screenId = updated.top?.screenId ?? ""
        let source = ActionSource(nodeId: ActionSource.layerDismissal, screenId: screenId, record: updated.nodeRecord(instances: []))
        let shown = updated.dismissLayer { kind, from, to, action in
            onNavigate?(NavigationEvent(kind: kind, from: from, to: to, action: action, source: source)) ?? true
        }
        guard let shown else { return }
        show(updated, animated: animated)
        screensShown.send(shown)
        deliverReports()
    }

    /// Puts a new stack on the screen, with the motion of a screen change unless `animated` is false.
    private func show(_ updated: Flow, animated: Bool) {
        carousels.prune(frames: updated.stack.map(\.screenId))
        if animated {
            withAnimation(.easeOut(duration: 0.22)) { self.flow = updated }
        } else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { self.flow = updated }
        }
    }

    private func perform(_ action: JSONObject, node: DocumentNode, instances: [ListInstance] = []) -> PressRun {
        if WriteActions.isWriteType(action["type"]?.stringValue) {
            return performWrite(action, node: node, instances: instances)
        }
        let before = currentFlow
        var updated = before
        let screenId = before.top?.screenId ?? ""
        // Every callback of one press names the same source: the node and the record it reads.
        let source = ActionSource(nodeId: node.id, screenId: screenId, record: before.nodeRecord(instances: instances))
        let outcome = updated.press(
            action, instances: instances, data: hostScope, sink: sink, location: "screen “\(screenId)”: node “\(node.id)”: action",
            announce: { PressDelivery.announce($0, source: source, onHaptic: onHaptic, onTrack: onTrack) },
            allowNavigation: { kind, from, to, handed in
                onNavigate?(NavigationEvent(kind: kind, from: from, to: to, action: handed, source: source)) ?? true
            }
        )
        let task = PressDelivery.hand(outcome, source: source, onAction: { handOver($0, $1) })
        if updated != before { show(updated, animated: true) }
        if let shown = outcome.shown { screensShown.send(shown) }
        deliverReports()
        return PressRun(runner: SwipeConfirmRules.runner(type: action["type"]?.stringValue, outcome: outcome), task: task)
    }
}
