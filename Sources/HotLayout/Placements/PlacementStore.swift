import CryptoKit
import Foundation

/// Where the reader keeps the last map it read from the network.
///
/// Only text that was read successfully from a fresh network answer is kept, together with its
/// `ETag`, so a later `304` can be answered from it. The keys are addresses: the address of the
/// map, never a name shared by two projects.
public protocol HotlayoutPlacementStore: Sendable {
    func value(forKey key: String) -> String?
    func set(_ value: String?, forKey key: String)
}

/// Keeps the values in `UserDefaults` (a map is at most 256 KB).
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

/// A document kept from the network with the `ETag` it came with.
public struct HotlayoutPlacementCachedDocument: Equatable, Sendable {
    public let data: Data
    public let etag: String?

    public init(data: Data, etag: String?) {
        self.data = data
        self.etag = etag
    }
}

/// Where the reader keeps the documents it read (up to 8 MB each, so not in `UserDefaults`).
///
/// The key is the address of the document. The reader keeps a document only for a place the map in
/// use still names, and removes the others (`keys()` lists what is kept).
public protocol HotlayoutPlacementDocumentStore: Sendable {
    func document(forKey key: String) -> HotlayoutPlacementCachedDocument?
    func setDocument(_ document: HotlayoutPlacementCachedDocument?, forKey key: String)
    func keys() -> [String]
}

/// Keeps the documents as files in the caches directory, which the system may empty when the
/// device is short of space: a missing copy is only a missing fallback.
public final class HotlayoutFilePlacementDocumentStore: HotlayoutPlacementDocumentStore, @unchecked Sendable {
    private let directory: URL
    private let lock = NSLock()

    /// - Parameter directory: where the files go; `Caches/hotlayout-placements` by default.
    public init(directory: URL? = nil) {
        self.directory = directory
            ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!.appendingPathComponent("hotlayout-placements", isDirectory: true)
    }

    private struct Meta: Codable {
        let key: String
        let etag: String?
    }

    private func stem(_ key: String) -> URL {
        let digest = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(digest)
    }

    public func document(forKey key: String) -> HotlayoutPlacementCachedDocument? {
        lock.lock()
        defer { lock.unlock() }
        let stem = stem(key)
        guard let metaData = try? Data(contentsOf: stem.appendingPathExtension("meta")),
            let meta = try? JSONDecoder().decode(Meta.self, from: metaData), meta.key == key,
            let data = try? Data(contentsOf: stem.appendingPathExtension("body"))
        else { return nil }
        return HotlayoutPlacementCachedDocument(data: data, etag: meta.etag)
    }

    public func setDocument(_ document: HotlayoutPlacementCachedDocument?, forKey key: String) {
        lock.lock()
        defer { lock.unlock() }
        let stem = stem(key)
        let body = stem.appendingPathExtension("body")
        let metaURL = stem.appendingPathExtension("meta")
        guard let document else {
            try? FileManager.default.removeItem(at: metaURL)
            try? FileManager.default.removeItem(at: body)
            return
        }
        guard (try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)) != nil,
            let meta = try? JSONEncoder().encode(Meta(key: key, etag: document.etag))
        else { return }
        // The body first: a meta file without a body is a missing copy, never a half one.
        guard (try? document.data.write(to: body, options: .atomic)) != nil else { return }
        try? meta.write(to: metaURL, options: .atomic)
    }

    public func keys() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "meta" }.compactMap { url in
            (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(Meta.self, from: $0) }?.key
        }
    }
}

/// Keeps the documents in memory only.
public final class HotlayoutMemoryPlacementDocumentStore: HotlayoutPlacementDocumentStore, @unchecked Sendable {
    private let lock = NSLock()
    private var documents: [String: HotlayoutPlacementCachedDocument] = [:]

    public init() {}

    public func document(forKey key: String) -> HotlayoutPlacementCachedDocument? {
        lock.lock()
        defer { lock.unlock() }
        return documents[key]
    }

    public func setDocument(_ document: HotlayoutPlacementCachedDocument?, forKey key: String) {
        lock.lock()
        defer { lock.unlock() }
        documents[key] = document
    }

    public func keys() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return Array(documents.keys)
    }
}
