import Foundation

/// Refuses every redirect: the address is the storage of the project, and a jump elsewhere
/// (even to another path of the same host) is foreign content or a captive portal. The 3xx answer
/// itself is then what the task returns.
final class PlacementRedirectRefusal: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

/// One GET with an optional `If-None-Match`, bounded in size and in time.
struct PlacementTransport: Sendable {
    let session: URLSession
    /// How long a request may take from its start to the end of the body.
    var deadline: Duration = .milliseconds(PlacementAnswer.deadlineMs)

    static func defaultSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 20
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }

    /// The reply, or one with status 0 that never completed when the request failed or ran out of
    /// time. At most `maxBytes + 1` bytes are read, so a reply over the limit is seen as such
    /// without being fetched whole.
    func get(_ url: URL, etag: String?, maxBytes: Int) async -> PlacementReply {
        let work = Task { await fetch(url, etag: etag, maxBytes: maxBytes) }
        let timer = Task {
            try? await Task.sleep(for: deadline)
            work.cancel()
        }
        let reply = await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
        timer.cancel()
        return reply
    }

    private func fetch(_ url: URL, etag: String?, maxBytes: Int) async -> PlacementReply {
        let failed = PlacementReply(status: 0, body: Data(), completedAtMs: nil)
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if let etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        let started = ContinuousClock.now
        do {
            let (bytes, response) = try await session.bytes(for: request, delegate: PlacementRedirectRefusal())
            guard let http = response as? HTTPURLResponse else { return failed }
            var body = Data()
            if http.statusCode == 200 {
                if response.expectedContentLength > Int64(maxBytes) {
                    body = Data(count: maxBytes + 1)
                } else {
                    for try await byte in bytes {
                        body.append(byte)
                        if body.count > maxBytes { break }
                    }
                }
            }
            try Task.checkCancellation()
            let elapsed = started.duration(to: .now)
            let ms = Int(elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000)
            return PlacementReply(status: http.statusCode, body: body, completedAtMs: ms, etag: http.value(forHTTPHeaderField: "ETag"))
        } catch {
            return failed
        }
    }
}
