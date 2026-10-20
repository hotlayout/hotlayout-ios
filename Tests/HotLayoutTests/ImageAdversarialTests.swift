import XCTest

@testable import HotLayout

/// Pictures of a document are fetched by the host app from addresses an untrusted document names.
/// These tests drive the reader's own loader (`ImageStore`) against a real HTTP stack on
/// 127.0.0.1. The host's policy is told to allow that server, as a host allows its CDN.
@MainActor
final class ImageAdversarialTests: XCTestCase {
    private var server: LocalServer?

    override func setUp() async throws {
        ImageStore.shared.reset()
    }

    override func tearDown() async throws {
        server?.stop()
        server = nil
        ImageStore.shared.reset()
        HTTPCookieStorage.shared.cookies?.filter { $0.domain.contains("127.0.0.1") }.forEach(HTTPCookieStorage.shared.deleteCookie)
    }

    private func start(_ handler: @escaping (LocalServer.Request) -> LocalServer.Response) throws -> LocalServer {
        let made = try LocalServer(handler: handler)
        server = made
        return made
    }

    // MARK: Holes

    /// A picture 20 000 × 20 000 is a 60 KB file and a 1.6 GB bitmap: on a phone the host app is
    /// killed for memory the moment it is drawn. The loader must refuse (or scale down) a picture
    /// whose longer side is beyond the bound before it reaches the view.
    func testDecompressionBombIsRefusedBeforeItIsDrawn() async throws {
        let bomb = PNGFile.blank(width: 20_000, height: 20_000)
        XCTAssertLessThan(bomb.count, 200_000, "the file itself is small")
        let server = try start { _ in .data(bomb) }
        let image = await ImageStore.shared.image(for: try XCTUnwrap(URL(string: "\(server.base)/bomb.png")))
        let side = image.map { Double(max($0.size.width, $0.size.height)) } ?? 0
        XCTAssertLessThanOrEqual(side, 4096, "a picture of 20 000 pixels a side reached the view")
    }

    /// A server that never ends its body is read into memory without a limit: `URLSession.data(from:)`
    /// buffers the whole response. 48 MB here; nothing stops 2 GB.
    func testPictureBodyIsNotReadPastABound() async throws {
        let piece = Data(count: 1 << 20)
        var sent = 0
        let server = try start { _ in
            LocalServer.Response(
                status: 200, headers: ["Content-Type": "image/png"],
                chunks: AnyIterator {
                    guard sent < 48 else { return nil }
                    sent += 1
                    return piece
                })
        }
        let loaded = await ImageStore.shared.image(for: try XCTUnwrap(URL(string: "\(server.base)/endless.png")))
        XCTAssertNil(loaded)
        // The loader stops reading at 10 MiB; what the server managed to write beyond it sits in the buffers of the
        // loopback socket (several megabytes on the simulator), not in the loader.
        XCTAssertLessThanOrEqual(server.bytesWritten, 24 << 20, "the loader accepted \(server.bytesWritten >> 20) MB for one picture")
    }

    /// Pictures are fetched with `URLSession.shared`: the cookies of the HOST APP go to whatever
    /// address the document names (a GET with the bank's session to an endpoint of the bank's API),
    /// and the picture server's cookies land in the host's jar.
    func testPictureRequestCarriesNoCookieOfTheHost() async throws {
        let server = try start { request in
            .data(PNGFile.small, headers: request.path == "/set.png" ? ["Set-Cookie": "tracker=from-document; Path=/"] : [:])
        }
        let hostURL = try XCTUnwrap(URL(string: "\(server.base)/"))
        let session = try XCTUnwrap(HTTPCookie(properties: [.name: "session", .value: "host-secret", .domain: "127.0.0.1", .path: "/"]))
        HTTPCookieStorage.shared.setCookie(session)
        _ = await ImageStore.shared.image(for: try XCTUnwrap(URL(string: "\(server.base)/get.png")))
        let sentCookie = server.requests.first { $0.path == "/get.png" }?.headers["cookie"] ?? ""
        XCTAssertFalse(sentCookie.contains("host-secret"), "the host's session cookie went with a document picture: \(sentCookie)")

        _ = await ImageStore.shared.image(for: try XCTUnwrap(URL(string: "\(server.base)/set.png")))
        let jar = HTTPCookieStorage.shared.cookies(for: hostURL)?.map(\.name) ?? []
        XCTAssertFalse(jar.contains("tracker"), "a picture server wrote a cookie into the host app's jar")
    }

    /// The host's policy is asked about the address the document names, not about where the
    /// server sends the request next: a host that allows only its CDN path gets a request to any
    /// address the CDN (or an open redirect on it) names.
    func testRedirectIsAskedOfTheHostPolicy() async throws {
        let server = try start { request in
            request.path.hasPrefix("/cdn/") ? .redirect("/internal/admin.png") : .data(PNGFile.small)
        }
        let base = server.base
        let policy = ImagePolicy(resolve: { address in address.hasPrefix("\(base)/cdn/") ? URL(string: address) : nil })
        let url = try XCTUnwrap(policy.resolve("\(base)/cdn/banner.png"))
        XCTAssertNil(policy.resolve("\(base)/internal/admin.png"), "the policy refuses the internal address")
        _ = await ImageStore.shared.image(for: url)
        XCTAssertFalse(server.requests.contains { $0.path.hasPrefix("/internal/") }, "the loader followed a redirect to an address the host's policy refuses")
    }

    /// The default policy takes any `https:` address with a host: numeric IPv4 in every base, the
    /// loopback, private networks, link-local metadata addresses, IPv6 literals and `localhost`.
    /// From inside a bank's app on the office Wi-Fi that is a request into the internal network.
    func testDefaultPolicyRefusesAddressesThatAreNotPublicNames() {
        let refused = [
            "https://2130706433/a.png", "https://0x7f000001/a.png", "https://017700000001/a.png", "https://127.1/a.png",
            "https://127.0.0.1/a.png", "https://10.0.0.1/a.png", "https://192.168.1.1/a.png", "https://172.16.0.1/a.png",
            "https://169.254.169.254/latest/meta-data", "https://[::1]/a.png", "https://[::ffff:127.0.0.1]/a.png",
            "https://localhost/a.png", "https://user:pass@cdn.example.com/a.png",
        ]
        let passed = refused.filter { ImagePolicy.httpsOnly($0) != nil }
        XCTAssertEqual(passed, [], "the default image policy loads these addresses")
    }

    // MARK: Guards

    func testDefaultPolicyRefusesOtherSchemesAndShapes() {
        for address in [
            "http://cdn.example.com/a.png", "file:///etc/passwd", "data:image/png;base64,AAAA", "javascript:alert(1)",
            "HTTPS://cdn.example.com/a.png", " https://cdn.example.com/a.png", "https:/cdn.example.com", "https://", "//cdn.example.com/a.png",
            "https://" + String(repeating: "a", count: 2100) + ".com/a.png",
        ] {
            XCTAssertNil(ImagePolicy.httpsOnly(address), address)
        }
        XCTAssertNotNil(ImagePolicy.httpsOnly("https://cdn.example.com/a.png"))
    }

    /// A bound address from data goes through the same policy as a literal one; a data value that is
    /// not a string, or is empty, falls back to the asset token and never to the literal text.
    func testBoundAddressGoesThroughThePolicy() {
        var context = Harness.context(rightToLeft: false)
        context.scope = ["u.pic": "file:///private/var/mobile/secret.png", "u.num": 5]
        XCTAssertNil(ImageSource.url(["kind": "binding", "path": "u.pic"], context: context))
        XCTAssertNil(ImageSource.url(["kind": "binding", "path": "u.num"], context: context))
        XCTAssertNil(ImageSource.url(["kind": "url", "url": "file:///etc/hosts"], context: context))
        XCTAssertNil(ImageSource.url(["kind": "asset", "asset": "logo"], context: context), "no asset URL the host did not give")
    }

    /// A failed address is not asked for again: a list of a hundred rows with one bad picture is
    /// one request, not a hundred.
    func testFailedAddressIsAskedOnce() async throws {
        let server = try start { _ in LocalServer.Response(status: 404, headers: ["Content-Length": "0"]) }
        let url = try XCTUnwrap(URL(string: "\(server.base)/missing.png"))
        for _ in 0..<5 { _ = await ImageStore.shared.image(for: url) }
        XCTAssertEqual(server.requests.count, 1)
    }

    /// A body that is not a picture gives no picture (and no crash).
    func testGarbageBodyIsNoPicture() async throws {
        let server = try start { _ in .data(Data("<html>not a picture</html>".utf8), type: "image/png") }
        let image = await ImageStore.shared.image(for: try XCTUnwrap(URL(string: "\(server.base)/fake.png")))
        XCTAssertNil(image)
    }
}
