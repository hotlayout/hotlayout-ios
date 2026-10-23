import Foundation

/// Where the reader keeps the last map and the last documents it read from the network.
///
/// Only text that was read successfully from a fresh network answer is kept, together with its
/// `ETag`, so a later `304` can be answered from it.
public protocol HotlayoutPlacementStore: Sendable {
    func value(forKey key: String) -> String?
    func set(_ value: String?, forKey key: String)
}

/// Keeps the values in `UserDefaults` (a map is at most 64 KB).
public final class HotlayoutUserDefaultsPlacementStore: HotlayoutPlacementStore, @unchecked Sendable {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public func value(forKey key: String) -> String? { defaults.string(forKey: "hotlayout.placements." + key) }

    public func set(_ value: String?, forKey key: String) {
        if let value { defaults.set(value, forKey: "hotlayout.placements." + key) } else { defaults.removeObject(forKey: "hotlayout.placements." + key) }
    }
}

/// Keeps the values in memory only: they are gone when the app quits.
public final class HotlayoutMemoryPlacementStore: HotlayoutPlacementStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]

    public init() {}

    public func value(forKey key: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return values[key]
    }

    public func set(_ value: String?, forKey key: String) {
        lock.lock()
        defer { lock.unlock() }
        values[key] = value
    }
}
