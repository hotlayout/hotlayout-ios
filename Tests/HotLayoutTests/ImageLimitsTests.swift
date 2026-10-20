import XCTest

@testable import HotLayout

/// The limits a host can set on picture loading, and the cases next to the hostile ones.
@MainActor
final class ImageLimitsTests: XCTestCase {
    private var server: LocalServer?

    override func setUp() async throws { ImageStore.shared.reset() }

    override func tearDown() async throws {
        server?.stop()
        server = nil
        ImageStore.shared.reset()
    }

    private func start(_ handler: @escaping (LocalServer.Request) -> LocalServer.Response) throws -> LocalServer {
        let made = try LocalServer(handler: handler)
        server = made
        return made
    }

    func testContentLengthOverTheCapIsRefusedAtOnce() async throws {
        let server = try start { _ in .data(PNGFile.small) }
        let base = server.base
        let policy = ImagePolicy(maxDownloadBytes: 10, resolve: { URL(string: $0) })
        let url = try XCTUnwrap(policy.resolve("\(base)/big.png"))
        let image = await ImageStore.shared.image(for: url)
        XCTAssertNil(image, "a picture larger than the host's cap is the placeholder")
    }

    func testPictureWithinTheCapLoads() async throws {
        let server = try start { _ in .data(PNGFile.small) }
        let base = server.base
        let policy = ImagePolicy(resolve: { URL(string: $0) })
        let url = try XCTUnwrap(policy.resolve("\(base)/ok.png"))
        let image = await ImageStore.shared.image(for: url)
        XCTAssertNotNil(image)
    }

    func testLargePictureIsScaledDownToTheLongerSide() async throws {
        let file = PNGFile.blank(width: 6000, height: 6000)
        let server = try start { _ in .data(file) }
        let base = server.base
        let policy = ImagePolicy(resolve: { URL(string: $0) })
        let url = try XCTUnwrap(policy.resolve("\(base)/large.png"))
        let loaded = await ImageStore.shared.image(for: url)
        let image = try XCTUnwrap(loaded)
        XCTAssertLessThanOrEqual(Int(max(image.size.width, image.size.height)), ImagePolicy.defaultMaxPixelSide)
    }

    func testRedirectTheHostPolicyAllowsIsFollowed() async throws {
        let server = try start { $0.path == "/a.png" ? .redirect("/b.png") : .data(PNGFile.small) }
        let base = server.base
        let policy = ImagePolicy(resolve: { URL(string: $0) })
        let url = try XCTUnwrap(policy.resolve("\(base)/a.png"))
        let image = await ImageStore.shared.image(for: url)
        XCTAssertNotNil(image)
        XCTAssertTrue(server.requests.contains { $0.path == "/b.png" })
    }

    func testDefaultPolicyAcceptsAPublicName() {
        XCTAssertNotNil(ImagePolicy.httpsOnly("https://cdn.example.com:8443/a.png?x=1"))
        XCTAssertNil(ImagePolicy.httpsOnly("https://cdn.example.com@evil.example.org.example/"), "userinfo-shaped host")
    }
}
