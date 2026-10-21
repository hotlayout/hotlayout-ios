import SwiftUI

#if canImport(UIKit)
import UIKit
typealias PlatformImage = UIImage
#else
import AppKit
typealias PlatformImage = NSImage
#endif

/// A decoded picture crossing from the loading task; it is never changed after it is made.
private struct Decoded: @unchecked Sendable { let image: PlatformImage? }

/// The memory cache of decoded pictures and the loads in flight, shared by every image of every
/// screen: a picture in a list of rows is fetched once. A picture is kept by its address AND the
/// side it was decoded at, so screens with different `maxPixelSide` do not share a decode. A
/// picture that failed is not asked for again for `failureLifetime`, or until the app becomes
/// active again (the network may be back).
@MainActor
final class ImageStore {
    static let shared = ImageStore()

    /// How long a failed address is not asked for again.
    static let failureLifetime: TimeInterval = 60

    private let cache = NSCache<NSString, PlatformImage>()
    private var inFlight: [String: Task<Decoded, Never>] = [:]
    private var failed: [String: Date] = [:]
    private let now: () -> Date
    private var activation: NSObjectProtocol?

    init(now: @escaping () -> Date = Date.init) {
        self.now = now
        cache.totalCostLimit = 64 * 1024 * 1024
        cache.countLimit = 200
        #if canImport(UIKit)
        activation = NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.forgetFailures() }
        }
        #endif
    }

    deinit {
        if let activation { NotificationCenter.default.removeObserver(activation) }
    }

    /// The key of a picture: the address and the longest side it is decoded at.
    private static func key(_ url: URL, maxSide: Int) -> String { "\(maxSide) \(url.absoluteString)" }

    private func key(_ url: URL) -> String { Self.key(url, maxSide: ImageSources.shared.entry(for: url).limits.maxSide) }

    func cached(_ url: URL) -> PlatformImage? { cache.object(forKey: key(url) as NSString) }

    func reset() {
        cache.removeAllObjects()
        failed.removeAll()
    }

    /// Lets every failed address be asked for again.
    func forgetFailures() { failed.removeAll() }

    /// The picture at the address, or `nil` when it cannot be had (a bad status, not a picture).
    func image(for url: URL) async -> PlatformImage? {
        let entry = ImageSources.shared.entry(for: url)
        let key = Self.key(url, maxSide: entry.limits.maxSide)
        if let hit = cache.object(forKey: key as NSString) { return hit }
        if let failedAt = failed[key] {
            if now().timeIntervalSince(failedAt) < Self.failureLifetime { return nil }
            failed[key] = nil
        }
        if let running = inFlight[key] { return await running.value.image }
        let task = Task.detached(priority: .utility) { () -> Decoded in
            guard let data = await BoundedDownload(entry: entry).run(url),
                let cg = BoundedDecode.cgImage(data, maxSide: entry.limits.maxSide)
            else { return Decoded(image: nil) }
            #if canImport(UIKit)
            return Decoded(image: UIImage(cgImage: cg))
            #else
            return Decoded(image: NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height)))
            #endif
        }
        inFlight[key] = task
        let image = await task.value.image
        inFlight[key] = nil
        if let image {
            cache.setObject(image, forKey: key as NSString, cost: Int(image.size.width * image.size.height * 4))
        } else if !Task.isCancelled {
            failed[key] = now()
        }
        return image
    }
}

/// Loads one picture for a view. Nothing is shown until it is there; the view draws the
/// placeholder meanwhile and when the address fails.
@MainActor
final class ImageLoader: ObservableObject {
    @Published private(set) var image: PlatformImage?
    private var task: Task<Void, Never>?
    private var loaded: URL?

    /// `onFailure` is called on the main actor when the picture could not be had (not when the load was cancelled).
    func load(_ url: URL?, onFailure: ((URL) -> Void)? = nil) {
        guard url != loaded else { return }
        loaded = url
        task?.cancel()
        image = nil
        guard let url else { return }
        if let hit = ImageStore.shared.cached(url) {
            image = hit
            return
        }
        task = Task { [weak self] in
            let picture = await ImageStore.shared.image(for: url)
            guard !Task.isCancelled, self?.loaded == url else { return }
            self?.image = picture
            if picture == nil { onFailure?(url) }
        }
    }

    deinit { task?.cancel() }
}
