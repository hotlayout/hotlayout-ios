import Foundation

/// Why a screen was shown (`x-screenShown`).
public enum ScreenShownCause: String, Equatable, Sendable {
    case entry, forward, back, `switch`
}

/// The screen-shown event: once per change of the top of the stack.
public struct ScreenShownEvent: Equatable, Sendable {
    public let documentId: String
    public let screenId: String
    /// The named entry point the flow started from; `nil` when none was named or it is unknown.
    public let entry: String?
    public let presentation: ScreenPresentation
    public let cause: ScreenShownCause
    public let depth: Int
    /// The record the screen was opened with.
    public let record: DataScope?
    /// `bottom` / `center`, only for a modal screen that names it.
    public let modalPlacement: String?
    /// The request of the shown screen about the icons of the status bar (`light` / `dark`), only
    /// when the screen names one. The host does what it likes with it.
    public let statusBarIcons: String?
}

/// A screen change the reader is about to make by itself, asked of the host first
/// (`HotlayoutScreen.onNavigate`).
public struct NavigationEvent: Equatable, Sendable {
    public enum Kind: String, Equatable, Sendable {
        /// `navigate` to a screen of the document: a screen is put on the stack.
        case push
        /// `navigate.back`, a tap on the scrim of a modal layer or a drag that closes a sheet.
        case back
        /// `navigate.section`: the stack becomes the one named screen.
        case `switch`
    }

    public let kind: Kind
    /// The screen on top of the stack now.
    public let from: String
    /// The screen that will be on top.
    public let to: String
    /// The action that asks for the change, as `onAction` would receive it.
    public let action: HotlayoutAction
    public let source: ActionSource
}

/// One frame of the screen stack: a screen and the record it was opened with. The record is
/// kept as a chain of links (one per list instance it came from), so that it can follow the
/// data (`x-liveRecord`).
struct FlowFrame: Equatable, Sendable {
    let screenId: String
    let chain: [RecordLink]

    init(screenId: String, chain: [RecordLink] = []) {
        self.screenId = screenId
        self.chain = chain
    }

    /// The record of the frame; `nil` for a screen opened without one.
    var record: DataScope? { chain.isEmpty ? nil : LiveRecord.record(of: chain) }
}

/// The screens of a document as navigation sees them.
struct FlowDocument: Equatable, Sendable {
    struct Screen: Equatable, Sendable {
        let screenId: String
        let presentation: ScreenPresentation
        let modalPlacement: String?
        let statusBarIcons: String?

        init(screenId: String, presentation: ScreenPresentation, modalPlacement: String? = nil, statusBarIcons: String? = nil) {
            self.screenId = screenId
            self.presentation = presentation
            self.modalPlacement = modalPlacement
            self.statusBarIcons = statusBarIcons
        }
    }

    let documentId: String
    let screens: [Screen]
    let initialScreenId: String?
    let entryPoints: [String: String]
    /// The collections of each entity the document names (`x-liveRecord.search.entity`).
    let entitySources: EntitySources

    init(documentId: String, screens: [Screen], initialScreenId: String?, entryPoints: [String: String], entitySources: EntitySources = [:]) {
        self.documentId = documentId
        self.screens = screens
        self.initialScreenId = initialScreenId
        self.entryPoints = entryPoints
        self.entitySources = entitySources
    }

    init(_ document: HotlayoutDocument) {
        self.init(
            documentId: document.documentId,
            screens: document.screens.map {
                Screen(screenId: $0.screenId, presentation: $0.presentation, modalPlacement: $0.modalPlacement, statusBarIcons: $0.statusBarIcons)
            },
            initialScreenId: document.initialScreenId,
            entryPoints: document.entryPoints,
            entitySources: LiveRecord.entitySources(roots: document.screens.map(\.root))
        )
    }

    func screen(_ screenId: String) -> Screen? { screens.first { $0.screenId == screenId } }

    /// The first screen: the named entry point, else the initial screen, else the first one
    /// (`unknownEntryPoint: 'use-initial'`).
    func start(entry: String?) -> String? {
        if let entry, let named = entryPoints[entry], screen(named) != nil { return named }
        if let initial = initialScreenId, screen(initial) != nil { return initial }
        return screens.first?.screenId
    }
}

/// A Repeater instance a pressed node is drawn inside: the entity prefix and one record.
struct ListInstance: Equatable, Sendable {
    /// The collection the list read (`Repeater.source`); empty when the caller does not know it
    /// (such a record is not found again in new data).
    let source: String
    let item: String
    let fields: JSONObject

    init(item: String, fields: JSONObject, source: String = "") {
        self.source = source
        self.item = item
        self.fields = fields
    }
}

/// What a press did. Order of delivery (`PressDelivery`): `haptic`, `track`, then either
/// `handed` or `shown`.
struct PressOutcome: Equatable, Sendable {
    var track: TrackEvent?
    var haptic: HapticFeedback?
    var handed: HotlayoutAction?
    /// The record handed to the host together with the action (`source.record`).
    var hostRecord: DataScope?
    var shown: ScreenShownEvent?
}

/// The screen stack and how actions move it. A value type: the SwiftUI screen keeps it in
/// state, and the tables drive it without any view.
///
/// Rules: `navigate` pushes a screen of the document (an unknown one is the host's);
/// `navigate.back` pops, and on the first screen it is the host's; `navigate.section` resets
/// the stack to the section screen (the same single screen: nothing, no event); every other
/// action goes to the host. Navigation never happens when the host cancels it.
struct Flow: Equatable, Sendable {
    private(set) var document: FlowDocument
    private(set) var entry: String?
    private(set) var stack: [FlowFrame]

    /// Starts a flow and returns the first show.
    init(document: FlowDocument, entry: String?) {
        self.document = document
        self.entry = entry
        self.stack = []
        _ = restart(entry: entry)
    }

    /// The named entry, as the event reports it: only a name the document knows.
    var shownEntry: String? {
        guard let entry, document.entryPoints[entry] != nil else { return nil }
        return entry
    }

    var top: FlowFrame? { stack.last }

    /// The event of the current top screen.
    func shownEvent(cause: ScreenShownCause) -> ScreenShownEvent? {
        guard let top = stack.last else { return nil }
        let screen = document.screen(top.screenId)
        // The first shown screen is never modal: a malformed document is drawn as a page.
        let modal = stack.count > 1 && screen?.presentation == .modal
        return ScreenShownEvent(
            documentId: document.documentId,
            screenId: top.screenId,
            entry: shownEntry,
            presentation: modal ? .modal : .page,
            cause: cause,
            depth: stack.count,
            record: top.record,
            modalPlacement: modal ? screen?.modalPlacement : nil,
            statusBarIcons: screen?.statusBarIcons
        )
    }

    /// The host starts the flow again, with another entry.
    @discardableResult
    mutating func restart(entry: String?) -> ScreenShownEvent? {
        self.entry = entry
        guard let first = document.start(entry: entry) else {
            stack = []
            return nil
        }
        stack = [FlowFrame(screenId: first)]
        return shownEvent(cause: .entry)
    }

    /// The host renders a new version of the same document. If the stack holds a screen the
    /// new version lacks, the flow starts again from the entry (`stackScreenGone`).
    @discardableResult
    mutating func update(document newDocument: FlowDocument) -> ScreenShownEvent? {
        document = newDocument
        if stack.allSatisfy({ newDocument.screen($0.screenId) != nil }) { return nil }
        return restart(entry: entry)
    }

    /// The record scope of a node on the top screen: the screen's record, overlaid by the
    /// records of the list instances it is drawn in, outer first.
    func nodeRecord(instances: [ListInstance]) -> DataScope? {
        let chain = nodeChain(instances: instances)
        return chain.isEmpty ? nil : LiveRecord.record(of: chain)
    }

    func nodeChain(instances: [ListInstance]) -> [RecordLink] {
        LiveRecord.chain(frame: stack.last?.chain ?? [], instances: instances)
    }

    /// The host gave new collections: every frame searches for its links again. The stack, the
    /// events and the show cause do not change — an update of the record is not a show.
    /// Returns whether any frame changed.
    @discardableResult
    mutating func refresh(collections: (String) -> JSONValue?) -> Bool {
        let next = stack.map {
            FlowFrame(screenId: $0.screenId, chain: LiveRecord.refresh($0.chain, collections: collections, sources: document.entitySources))
        }
        guard next != stack else { return false }
        stack = next
        return true
    }

    /// A press of a node with `action` on the top screen.
    ///
    /// - Parameters:
    ///   - data: the host's data layers under the record (session, host, data — merged).
    ///   - location: where the action stands, for the reports.
    ///   - announce: receives the haptic request and the analytics event before anything else
    ///     happens: before the host is asked about a navigation (also one it then cancels).
    ///   - allowNavigation: the host's answer to «may the reader make this change» (`false`
    ///     cancels): the kind, the screen on top, the screen that would be on top, the action.
    mutating func press(
        _ action: JSONObject, instances: [ListInstance] = [], data: DataScope = [:], sink: ReportSink? = nil, location: String = "action",
        announce: (PressOutcome) -> Void = { _ in },
        allowNavigation: (NavigationEvent.Kind, String, String, HotlayoutAction) -> Bool = { _, _, _, _ in true }
    ) -> PressOutcome {
        var outcome = PressOutcome()
        outcome.haptic = ActionCatalog.haptic(action)
        outcome.track = ActionCatalog.track(action, sink: sink, location: location)
        announce(outcome)
        let chain = nodeChain(instances: instances)
        let record = chain.isEmpty ? nil : LiveRecord.record(of: chain)
        let scope = RecordScope.overlay(data, record) ?? data
        let handed = ActionCatalog.handed(action, scope: scope, sink: sink, location: location)
        let type = handed.type
        let target = handed.params?["screenId"]

        func toHost() {
            outcome.handed = handed
            outcome.hostRecord = record
        }

        switch ActionType(type) {
        case ActionType.none?:
            return outcome
        case .navigate:
            guard let target, let screen = document.screen(target) else {
                toHost()
                return outcome
            }
            guard allowNavigation(.push, stack.last!.screenId, target, handed) else { return outcome }
            let carried = RecordScope.carriesRecord(
                insideListItem: !instances.isEmpty, presentation: screen.presentation, carryRecord: action["carryRecord"]?.boolValue == true)
            stack.append(FlowFrame(screenId: target, chain: carried ? chain : []))
            outcome.shown = shownEvent(cause: .forward)
        case .navigateBack:
            guard stack.count > 1 else {
                toHost()
                return outcome
            }
            guard allowNavigation(.back, stack.last!.screenId, stack[stack.count - 2].screenId, handed) else { return outcome }
            stack.removeLast()
            outcome.shown = shownEvent(cause: .back)
        case .navigateSection:
            guard let target, document.screen(target) != nil else {
                toHost()
                return outcome
            }
            // The same single screen: nothing changes and nothing is shown.
            guard let next = NavBarRules.sectionStack(stack.map(\.screenId), target: target) else { return outcome }
            guard allowNavigation(.switch, stack.last!.screenId, target, handed) else { return outcome }
            stack = next.map { FlowFrame(screenId: $0) }
            outcome.shown = shownEvent(cause: .switch)
        default:
            toHost()
        }
        return outcome
    }
}
