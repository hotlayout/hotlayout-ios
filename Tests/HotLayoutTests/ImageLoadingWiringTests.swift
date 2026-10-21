import SwiftUI
import XCTest

@testable import HotLayout

/// Pictures on the real screen and through the real loader (schema 9.28.0): a refused address is a
/// report and no request, a host's own answer is final except for a script, a picture is loaded within
/// the limits of the contract, and a report that comes after the first frame reaches `onReport`.
@MainActor
final class ImageLoadingWiringTests: XCTestCase {
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

    final class Recorder {
        var batches: [[HotlayoutReport]] = []
        var all: [HotlayoutReport] { batches.flatMap { $0 } }
    }

    private func image(_ id: String, _ source: JSONValue) -> JSONValue {
        ["id": .string(id), "type": "Image", "props": ["source": source, "aspectRatio": "1:1"]]
    }

    private func url(_ address: String) -> JSONValue { ["kind": "url", "url": .string(address)] }

    private func show(_ children: [JSONValue], images: ImagePolicy, data: DataScope = [:], recorder: Recorder, wait: Double = 0.6) throws -> AnyObject {
        let document = try screenDocument([("a", children)])
        let screen = HotlayoutScreen(document: document, data: data, locale: "en", images: images, onReport: { recorder.batches.append($0) })
        return showScreen(screen, wait: wait)
    }

    // MARK: A refused address

    func testARefusedAddressOfTheDocumentMakesNoRequestAndIsReportedCut() throws {
        let server = try start { _ in .data(PNGFile.small) }
        let recorder = Recorder()
        let long = "https://127.0.0.1/" + String(repeating: "p", count: 300)
        let held = try show(
            [
                image("http-ip", url("http://127.0.0.1:\(server.port)/never.png")), image("ip", url("https://127.0.0.1/a.png")),
                image("name", url("https://localhost/a.png")), image("script", url("javascript:alert(1)")), image("long", url(long)),
            ], images: ImagePolicy(), recorder: recorder)
        withExtendedLifetime(held) {}
        XCTAssertEqual(server.requests.map(\.path), [], "no request for an address the default rule refuses")
        let said = recorder.all.map(\.reason)
        XCTAssertTrue(said.contains { $0.contains("https://127.0.0.1/a.png") }, "\(said)")
        XCTAssertTrue(said.contains { $0.contains("https://localhost/a.png") }, "\(said)")
        XCTAssertTrue(said.contains { $0.contains("javascript:alert(1)") }, "\(said)")
        let ofLong = try XCTUnwrap(said.first { $0.contains("https://127.0.0.1/ppp") })
        XCTAssertFalse(ofLong.contains(String(repeating: "p", count: 150)), "the address of the document is cut at 120 characters")
        XCTAssertTrue(recorder.all.allSatisfy { $0.kind == .ignoredInput && $0.location.contains("image") })
    }

    func testAnAddressFromDataIsReportedBySchemeAndHostOnly() throws {
        let recorder = Recorder()
        let source: JSONValue = ["kind": "binding", "path": "offer.image", "fallback": "placeholder"]
        let held = try show(
            [image("img", source)], images: ImagePolicy(), data: ["offer.image": "https://127.0.0.1/private/path?token=SECRET-TOKEN"], recorder: recorder)
        withExtendedLifetime(held) {}
        let said = recorder.all.map { $0.location + " " + $0.reason }.joined(separator: "\n")
        XCTAssertTrue(said.contains("https://127.0.0.1"), said)
        XCTAssertFalse(said.contains("SECRET-TOKEN") || said.contains("private"), "the path and the query of an address from data are not in a report: \(said)")
    }

    // MARK: The host decides

    func testTheDefaultRuleDecidesWhichAddressIsAskedFor() throws {
        let server = try start { _ in .data(PNGFile.small) }
        let base = server.base
        // A host that sends every address the default rule accepts to its own server, and refuses the rest.
        let policy = ImagePolicy(resolve: { address in ImagePolicy.httpsOnly(address) != nil ? URL(string: "\(base)/accepted.png") : nil })
        let recorder = Recorder()
        let held = try show(
            [image("ok", url("https://cdn.example.com/a.png")), image("ip", url("https://127.0.0.1/a.png"))], images: policy, recorder: recorder)
        withExtendedLifetime(held) {}
        XCTAssertEqual(server.requests.map(\.path), ["/accepted.png"], "only the public address is asked for")
        XCTAssertEqual(recorder.all.filter { $0.reason.contains("is not loaded") }.count, 1)
    }

    func testAScriptAddressTheHostAllowsIsStillNeverAPicture() throws {
        let server = try start { _ in .data(PNGFile.small) }
        let base = server.base
        let recorder = Recorder()
        let held = try show(
            [image("script", url("JavaScript:alert(1)")), image("dev", url("\(base)/dev.png"))], images: ImagePolicy(resolve: { URL(string: $0) }), recorder: recorder)
        withExtendedLifetime(held) {}
        XCTAssertEqual(server.requests.map(\.path), ["/dev.png"], "the host's own answer is final, except a script")
        XCTAssertTrue(recorder.all.contains { $0.reason.contains("JavaScript:alert(1)") && $0.reason.contains("is not loaded") }, "\(recorder.all)")
    }

    // MARK: Reports that arrive late

    func testAPictureThatFailsAfterTheFirstFrameReachesTheHost() throws {
        let server = try start { _ in
            Thread.sleep(forTimeInterval: 0.4)
            return LocalServer.Response(status: 404, headers: ["Content-Length": "0"])
        }
        let base = server.base
        let recorder = Recorder()
        // A refused address is reported on the first frame; the picture that fails comes more than a third of a second later.
        let policy = ImagePolicy(resolve: { $0.contains("127.0.0.1/a.png") ? nil : URL(string: $0) })
        let held = try show([image("ip", url("https://127.0.0.1/a.png")), image("gone", url("\(base)/gone.png"))], images: policy, recorder: recorder, wait: 1.5)
        withExtendedLifetime(held) {}
        XCTAssertTrue(recorder.batches.first?.contains { $0.reason.contains("https://127.0.0.1/a.png") } == true, "the refusal is in the first batch")
        let late = recorder.batches.enumerated().first { $0.element.contains { $0.reason.contains("could not be loaded") } }
        XCTAssertNotNil(late, "the failure of a picture reaches onReport: \(recorder.batches)")
        XCTAssertGreaterThan(late?.offset ?? 0, 0, "it came in a later batch than the first frame's")
        let text = late?.element.map(\.reason).joined() ?? ""
        XCTAssertTrue(text.contains("http://127.0.0.1"), text)
        XCTAssertFalse(text.contains("gone.png"), "only the scheme and the host of the address")
    }

    // MARK: The network of one picture

    private func fetch(_ base: String, _ path: String, policy: ImagePolicy = ImagePolicy(resolve: { URL(string: $0) })) async throws -> PlatformImage? {
        let resolved = try XCTUnwrap(policy.resolve("\(base)\(path)"))
        return await ImageStore.shared.image(for: resolved)
    }

    func testThreeRedirectsAreFollowedAndAFourthIsNot() async throws {
        let server = try start { request in
            switch request.path {
            case "/r0": return .redirect("/r1")
            case "/r1": return .redirect("/r2")
            case "/r2": return .redirect("/final")
            case "/s0": return .redirect("/s1")
            case "/s1": return .redirect("/s2")
            case "/s2": return .redirect("/s3")
            case "/s3": return .redirect("/final")
            default: return .data(PNGFile.small)
            }
        }
        let three = try await fetch(server.base, "/r0")
        XCTAssertNotNil(three, "three redirects are followed")
        let four = try await fetch(server.base, "/s0")
        XCTAssertNil(four, "the fourth redirect is not followed")
        XCTAssertEqual(server.requests.filter { $0.path == "/final" }.count, 1, "the final address was reached by the first chain only")
    }

    func testEveryRedirectTargetIsJudgedByTheHostsRule() async throws {
        let server = try start { $0.path.hasPrefix("/cdn/") ? .redirect("/internal/admin.png") : .data(PNGFile.small) }
        let base = server.base
        let policy = ImagePolicy(resolve: { address in address.hasPrefix("\(base)/cdn/") ? URL(string: address) : nil })
        _ = try await fetch(base, "/cdn/banner.png", policy: policy)
        XCTAssertFalse(server.requests.contains { $0.path.hasPrefix("/internal/") }, "a target the host's rule refuses is not followed")
    }

    func testNoRefererIsSentOnTheRequestOrOnAnyRedirect() async throws {
        let server = try start { $0.path == "/a.png" ? .redirect("/b.png") : .data(PNGFile.small) }
        let loaded = try await fetch(server.base, "/a.png")
        XCTAssertNotNil(loaded)
        XCTAssertEqual(server.requests.map(\.path), ["/a.png", "/b.png"])
        for request in server.requests { XCTAssertNil(request.headers["referer"], request.path) }
    }

    func testAPictureLongerThanTheLimitIsRefusedBeforeItIsRead() async throws {
        let limit = ImagePolicy.defaultMaxDownloadBytes
        XCTAssertEqual(limit, 10_485_760)
        let server = try start { request in
            var body = PNGFile.small
            // A real picture followed by padding: the first is exactly at the limit, the second one byte over it.
            body.append(Data(count: (request.path == "/exact.png" ? limit : limit + 1) - body.count))
            return .data(body)
        }
        let exact = try await fetch(server.base, "/exact.png")
        XCTAssertNotNil(exact, "a body of exactly the limit is read")
        let over = try await fetch(server.base, "/over.png")
        XCTAssertNil(over, "one byte more is the placeholder")
    }

    func testTheWholeTransferHasADeadline() async throws {
        let server = try start { _ in
            LocalServer.Response(status: 200, headers: ["Content-Type": "image/png"], chunks: AnyIterator {
                Thread.sleep(forTimeInterval: 0.25)
                return Data(count: 1)
            })
        }
        let address = try XCTUnwrap(URL(string: "\(server.base)/drip.png"))
        let started = Date()
        let data = await BoundedDownload(entry: ImageSources.shared.entry(for: address), deadline: 1).run(address)
        XCTAssertNil(data)
        XCTAssertLessThan(Date().timeIntervalSince(started), 6, "a server that drips bytes is cut at the deadline")
        // The real loader takes the contract's deadline, not a number of its own.
        XCTAssertEqual(BoundedDownload.configuration().timeoutIntervalForResource, BoundedDownload.deadlineSeconds)
    }

    func testALargePictureIsMadeSmallerWithItsProportionKept() async throws {
        let file = PNGFile.blank(width: 9000, height: 3000)
        let server = try start { _ in .data(file) }
        let loaded = try await fetch(server.base, "/wide.png")
        let image = try XCTUnwrap(loaded, "a larger picture is made smaller, not refused")
        XCTAssertEqual(Double(max(image.size.width, image.size.height)), 4096, accuracy: 1)
        XCTAssertEqual(Double(image.size.width / image.size.height), 3, accuracy: 0.01)
    }
}
