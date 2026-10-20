import Foundation

/// Something the reader skipped or replaced while reading a document, a theme or the data.
///
/// The document and the theme arrive over the network: a piece of the wrong shape is ignored
/// (the rest of the screen is drawn) and goes into a report, so that the host can log it.
/// Nothing in a report is shown to the end user.
public struct HotlayoutReport: Equatable, Hashable, Sendable, CustomStringConvertible {
    public enum Kind: String, Equatable, Hashable, Sendable {
        /// A piece of the wrong shape was ignored (`ignored-input`).
        case ignoredInput = "ignored-input"
        /// A widget this reader does not know; its children were drawn (`unknownWidget`).
        case unknownWidget = "unknown-widget"
        /// A token the theme does not declare; the field default applies (`unknownToken`).
        case unknownToken = "unknown-token"
    }

    public let kind: Kind
    /// Where in the document: `screen “home”: node “hero”: props.content`.
    public let location: String
    public let reason: String

    init(kind: Kind, location: String, reason: String) {
        self.kind = kind
        self.location = location
        self.reason = reason
    }

    public var description: String { "[\(kind.rawValue)] \(location): \(reason)" }
}

/// Collects reports while a document or a screen is read. A reference type so that deep
/// readers can add to one list without threading it back up.
final class ReportSink: @unchecked Sendable {
    private let lock = NSLock()
    private var collected: [HotlayoutReport] = []
    private var seen: Set<HotlayoutReport> = []
    private var delivered = 0
    private var observer: (() -> Void)?
    private var notified = false
    /// A hostile document could produce a report per node per frame; the list is bounded.
    static let limit = 500

    init() {}

    /// Calls `handler` (outside the lock) when a report is added after the last `drain`: a report that
    /// comes after the first frame (a refused picture address, a picture that failed) reaches the host
    /// too. At most one call is pending until the reports are drained. `nil` stops it.
    func observe(_ handler: (() -> Void)?) {
        lock.lock()
        defer { lock.unlock() }
        observer = handler
    }

    func add(_ kind: HotlayoutReport.Kind, _ location: String, _ reason: String) {
        lock.lock()
        let report = HotlayoutReport(kind: kind, location: location, reason: reason)
        guard collected.count < Self.limit, seen.insert(report).inserted else {
            lock.unlock()
            return
        }
        collected.append(report)
        let notify = observer != nil && !notified ? observer : nil
        if notify != nil { notified = true }
        lock.unlock()
        notify?()
    }

    var reports: [HotlayoutReport] {
        lock.lock()
        defer { lock.unlock() }
        return collected
    }

    /// The reports added since the last drain: each report is handed to the host once.
    func drain() -> [HotlayoutReport] {
        lock.lock()
        defer { lock.unlock() }
        let fresh = Array(collected[delivered...])
        delivered = collected.count
        notified = false
        return fresh
    }
}
