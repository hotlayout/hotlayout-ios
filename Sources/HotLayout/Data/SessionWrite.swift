import Foundation

/// Which data paths the reader may write to. The document names the path of a write, and a
/// document arrives over the network: the host says what it expects. By default every path of the
/// shape of a data path is allowed (a forbidden segment such as `__proto__` never is).
public struct WritablePaths: Sendable {
    private let allows: @Sendable (String) -> Bool

    /// Only these paths.
    public init(_ paths: Set<String>) {
        allows = { paths.contains($0) }
    }

    /// The paths a predicate accepts.
    public init(where predicate: @escaping @Sendable (String) -> Bool) {
        allows = predicate
    }

    func permits(_ path: String) -> Bool { allows(path) }

    /// Whether the reader writes under `path`: the gate of the contract (the shape of a data path
    /// without a forbidden segment), then the host's list when there is one.
    static func permits(_ gate: WritablePaths?, _ path: String) -> Bool {
        WriteActions.isWritablePath(path) && (gate?.permits(path) ?? true)
    }
}

/// The session of a screen: what the person chose or typed, as a flat map from a data path to a
/// value. A write goes here and to the host at the same moment; the layers read it back.
enum SessionWrite {
    /// Puts `value` under `path` unless the gate refuses it; returns whether it was written.
    /// A refused path is written neither to the session nor to the host.
    @discardableResult
    static func apply(path: String, value: JSONValue, to session: inout DataScope, gate: WritablePaths?, sink: ReportSink? = nil) -> Bool {
        guard WritablePaths.permits(gate, path) else {
            sink?.add(.ignoredInput, "write: \(path.prefix(64))", "the path is not one the host lets the reader write to; nothing was written")
            return false
        }
        session[path] = value
        return true
    }
}
