import SwiftUI
import XCTest

@testable import HotLayout

/// A one-screen document of the given root children, and a way to put the real screen on a
/// platform host that draws it (the reader calls its `onAppear` and its reports only then).
@MainActor
extension XCTestCase {
    func screenDocument(_ screens: [(String, [JSONValue])], version: String = "9.28.0") throws -> HotlayoutDocument {
        try loadDocument([
            "schemaVersion": .string(version), "documentId": "d", "name": "n", "initialScreenId": .string(screens[0].0),
            "screens": .array(
                screens.map { id, children in
                    [
                        "screenId": .string(id), "name": .string(id),
                        "root": ["id": .string("root-\(id)"), "type": "Screen", "props": [:], "children": .array(children)],
                    ]
                }),
        ])
    }

    func runLoop(_ seconds: Double) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    /// The screen in a window nobody sees, drawn and given time to settle. The returned object keeps it alive.
    func showScreen<Screen: View>(_ screen: Screen, wait: Double = 0.5) -> AnyObject {
        #if canImport(UIKit)
        let controller = UIHostingController(rootView: screen)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        runLoop(wait)
        return window
        #else
        let view = host(screen)
        runLoop(wait)
        return view
        #endif
    }

    /// What the real screen looks like once it has settled: the pixels of its window (a plain `ImageRenderer`
    /// draws nothing of the screen, which builds itself while it appears).
    func screenPixels<Screen: View>(_ screen: Screen, wait: Double = 0.4) throws -> (image: CGImage, bytes: Data) {
        let held = showScreen(screen, wait: wait)
        #if canImport(UIKit)
        let window = try XCTUnwrap(held as? UIWindow)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let rendered = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { context in
            window.layer.render(in: context.cgContext)
        }
        let image = try XCTUnwrap(rendered.cgImage)
        #else
        let view = try XCTUnwrap(held as? NSView)
        let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        let image = try XCTUnwrap(rep.cgImage)
        #endif
        return (image, try XCTUnwrap(image.dataProvider?.data as Data?))
    }
}
