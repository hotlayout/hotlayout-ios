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
/// screen: a picture in a list of rows is fetched once, and a picture that failed is not asked
/// for again until the cache is emptied.
@MainActor
final class ImageStore {
    static let shared = ImageStore()

    private let cache = NSCache<NSURL, PlatformImage>()
    private var inFlight: [URL: Task<Decoded, Never>] = [:]
    private var failed: Set<URL> = []

    init() {
        cache.totalCostLimit = 64 * 1024 * 1024
        cache.countLimit = 200
    }

    func cached(_ url: URL) -> PlatformImage? { cache.object(forKey: url as NSURL) }

    func reset() {
        cache.removeAllObjects()
        failed.removeAll()
    }

    /// The picture at the address, or `nil` when it cannot be had (a bad status, not a picture).
    func image(for url: URL) async -> PlatformImage? {
        if let hit = cached(url) { return hit }
        if failed.contains(url) { return nil }
        if let running = inFlight[url] { return await running.value.image }
        let task = Task.detached(priority: .utility) { () -> Decoded in
            let entry = ImageSources.shared.entry(for: url)
            guard let data = await BoundedDownload(entry: entry).run(url),
                let cg = BoundedDecode.cgImage(data, maxSide: entry.limits.maxSide)
            else { return Decoded(image: nil) }
            #if canImport(UIKit)
            return Decoded(image: UIImage(cgImage: cg))
            #else
            return Decoded(image: NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height)))
            #endif
        }
        inFlight[url] = task
        let image = await task.value.image
        inFlight[url] = nil
        if let image {
            cache.setObject(image, forKey: url as NSURL, cost: Int(image.size.width * image.size.height * 4))
        } else if !Task.isCancelled {
            failed.insert(url)
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
