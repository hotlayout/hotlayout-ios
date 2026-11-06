import Foundation

/// Orders the keeping of documents against the pruning that follows a fresh map.
///
/// A read that started under one map may end after a newer fresh map has removed the documents it
/// no longer names; keeping its answer then would bring back a document of a map that is gone.
/// Every prune of a project starts a new epoch, and a document is kept only by a read of the
/// current epoch. The check and the write happen under one lock, as the prune does, so no write
/// slips in between.
final class PlacementPruneGate: @unchecked Sendable {
    static let shared = PlacementPruneGate()

    private let lock = NSLock()
    private var epochs: [String: Int] = [:]

    /// The epoch of the project whose documents live under `prefix`.
    func epoch(_ prefix: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return epochs[prefix, default: 0]
    }

    /// Runs `prune` as the start of a new epoch and returns that epoch.
    func prune(_ prefix: String, _ prune: () -> Void) -> Int {
        lock.lock()
        defer { lock.unlock() }
        let next = epochs[prefix, default: 0] &+ 1
        epochs[prefix] = next
        prune()
        return next
    }

    /// Runs `write` only while `epoch` is still the epoch of the project.
    func keep(_ prefix: String, epoch: Int, _ write: () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        if epochs[prefix, default: 0] == epoch { write() }
    }
}
