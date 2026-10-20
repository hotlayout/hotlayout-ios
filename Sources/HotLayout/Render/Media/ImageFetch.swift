import Foundation
import ImageIO

/// What one picture may cost the host app.
struct ImageLimits: Sendable {
    var maxBytes: Int
    /// The longest side, in pixels, a picture is decoded at.
    var maxSide: Int
}

/// The policy that resolved an address, remembered by the URL it returned, so that a redirect of
/// that picture can be put to the same policy. A URL nobody registered (a host asset, a call made
/// without a policy) follows a redirect only to an address the default policy accepts.
final class ImageSources: @unchecked Sendable {
    static let shared = ImageSources()

    struct Entry: Sendable {
        let resolve: @Sendable (String) -> URL?
        let limits: ImageLimits
    }

    private let lock = NSLock()
    private var entries: [URL: Entry] = [:]
    private static let capacity = 4096

    func register(_ url: URL, resolve: @escaping @Sendable (String) -> URL?, limits: ImageLimits) {
        lock.lock()
        defer { lock.unlock() }
        if entries.count >= Self.capacity { entries.removeAll() }
        entries[url] = Entry(resolve: resolve, limits: limits)
    }

    func entry(for url: URL) -> Entry {
        lock.lock()
        defer { lock.unlock() }
        return entries[url]
            ?? Entry(
                resolve: ImagePolicy.httpsOnly,
                limits: ImageLimits(maxBytes: ImagePolicy.defaultMaxDownloadBytes, maxSide: ImagePolicy.defaultMaxPixelSide)
            )
    }
}

/// One bounded, isolated download. Its session is ephemeral with no cookie storage and no URL
/// cache, it stops reading at the byte ceiling, it puts every redirect to the host's policy (at
/// most three are followed), it sends no `Referer`, and the whole transfer, redirects included,
/// has a deadline (`x-imageSource.network`).
final class BoundedDownload: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    static let maxRedirects = 3
    static let deadlineSeconds: TimeInterval = 30

    private let entry: ImageSources.Entry
    private var data = Data()
    private var redirects = 0
    private var failed = false
    private var status = 200
    private var continuation: CheckedContinuation<Data?, Never>?
    private var session: URLSession?
    private let deadline: TimeInterval

    init(entry: ImageSources.Entry, deadline: TimeInterval = BoundedDownload.deadlineSeconds) {
        self.entry = entry
        self.deadline = deadline
    }

    static func configuration(deadline: TimeInterval = BoundedDownload.deadlineSeconds) -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.timeoutIntervalForRequest = deadline
        // One picture, redirects included: past it the picture is the placeholder.
        configuration.timeoutIntervalForResource = deadline
        configuration.waitsForConnectivity = false
        return configuration
    }

    func run(_ url: URL) async -> Data? {
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Data?, Never>) in
                self.continuation = continuation
                let session = URLSession(configuration: Self.configuration(deadline: self.deadline), delegate: self, delegateQueue: nil)
                self.session = session
                var request = URLRequest(url: url)
                request.httpShouldHandleCookies = false
                request.setValue(nil, forHTTPHeaderField: "Referer")
                session.dataTask(with: request).resume()
            }
        } onCancel: {
            self.finish(nil)
        }
    }

    private func finish(_ result: Data?) {
        let pending = continuation
        continuation = nil
        session?.invalidateAndCancel()
        session = nil
        pending?.resume(returning: result)
    }

    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        redirects += 1
        guard redirects <= Self.maxRedirects, let target = request.url, let allowed = entry.resolve(target.absoluteString) else {
            failed = true
            completionHandler(nil)
            return
        }
        var next = request
        next.url = allowed
        next.httpShouldHandleCookies = false
        next.setValue(nil, forHTTPHeaderField: "Referer")
        completionHandler(next)
    }

    func urlSession(
        _ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        if let http = response as? HTTPURLResponse { status = http.statusCode }
        if !(200..<300).contains(status) || response.expectedContentLength > Int64(entry.limits.maxBytes) {
            failed = true
            completionHandler(.cancel)
            return
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive chunk: Data) {
        guard !failed else { return }
        if data.count + chunk.count > entry.limits.maxBytes {
            failed = true
            dataTask.cancel()
            return
        }
        data.append(chunk)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        finish(error == nil && !failed ? data : nil)
    }
}

/// Decoding with a bound on the longer side: the size is read from the header BEFORE any pixel is
/// made, and a larger picture is made smaller, with its proportion kept, not refused.
enum BoundedDecode {
    static func cgImage(_ data: Data, maxSide: Int) -> CGImage? {
        let options: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithData(data as CFData, options as CFDictionary), CGImageSourceGetCount(source) > 0,
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, options as CFDictionary) as? [CFString: Any],
            let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
            let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
            width >= 1, height >= 1, width.isFinite, height.isFinite
        else { return nil }
        let thumbnail: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: SafeInt.clamped(Swift.max(1, Swift.min(Swift.max(width, height), Double(maxSide)))),
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnail as CFDictionary)
    }
}
