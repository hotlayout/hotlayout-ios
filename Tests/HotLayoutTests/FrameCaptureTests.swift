#if canImport(AppKit)
import AppKit
import SwiftUI
import XCTest

@testable import HotLayout

/// Writes the frames of these minors as PNG files for looking at, next to the canvas of the builder. It
/// does nothing unless `HOTLAYOUT_FRAME_DIR` names a folder.
@MainActor
final class FrameCaptureTests: XCTestCase {
    private func write(_ view: NSView, to url: URL) throws {
        let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: url)
    }

    private func document(_ name: String, screen: String? = nil) throws -> HotlayoutDocument {
        var json = try Contract.json("fixtures/\(name).json")
        if let screen, var object = json.objectValue {
            object["initialScreenId"] = .string(screen)
            json = .object(object)
        }
        return try HotlayoutDocument.load(json)
    }

    func testWriteFrames() throws {
        guard let folder = ProcessInfo.processInfo.environment["HOTLAYOUT_FRAME_DIR"] else { throw XCTSkip("HOTLAYOUT_FRAME_DIR is not set") }
        let directory = URL(fileURLWithPath: folder)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        // The end state of the appearances and the rest pose of the motions: what the canvas of the builder shows.
        let motion = host(
            HotlayoutScreen(document: try document("motion-turn-screens"), locale: "en")
                .environment(\.nodeMotionClockMs, 0).environment(\.appearClockMs, 100_000))
        try write(motion, to: directory.appendingPathComponent("ios-motion-turn-rest.png"))
        // The same screen on the real clocks, a moment after the show: the motions are turning.
        let live = host(HotlayoutScreen(document: try document("motion-turn-screens"), locale: "en"))
        spin(1.2)
        try write(live, to: directory.appendingPathComponent("ios-motion-turn-live.png"))

        let stories = host(
            HotlayoutScreen(document: try document("carousel-auto-advance-screens"), data: ["account.cardIndex": 0], locale: "en"))
        spin(0.6)
        try write(stories, to: directory.appendingPathComponent("ios-auto-advance-stories-start.png"))
        let end = host(
            HotlayoutScreen(document: try document("carousel-auto-advance-screens"), data: ["account.cardIndex": 2], locale: "en"))
        spin(0.6)
        try write(end, to: directory.appendingPathComponent("ios-auto-advance-stories-end.png"))
        let promo = host(HotlayoutScreen(document: try document("carousel-auto-advance-screens", screen: "promo"), locale: "en"))
        spin(0.6)
        try write(promo, to: directory.appendingPathComponent("ios-auto-advance-promo.png"))
        // The timer on the real screen, with no data from the host: after one interval of the stories the second one shows.
        let advanced = host(HotlayoutScreen(document: try document("carousel-auto-advance-screens"), locale: "en"))
        spin(5.8)
        try write(advanced, to: directory.appendingPathComponent("ios-auto-advance-stories-after-one-step.png"))
    }
}
#endif
