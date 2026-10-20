#if canImport(AppKit)
import AppKit
import SwiftUI
import XCTest

@testable import HotLayout

/// The real screen in an off-screen window, driven through the accessibility interface of the
/// platform: what a person using VoiceOver does.
@MainActor
extension XCTestCase {
    /// Hosts the screen in a window and lets it draw.
    func host<Screen: View>(_ screen: Screen) -> NSHostingView<Screen> {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.accessibilitySetValue(true as NSNumber, forAttribute: NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface"))
        app.accessibilitySetValue(true as NSNumber, forAttribute: NSAccessibility.Attribute(rawValue: "AXManualAccessibility"))
        let view = NSHostingView(rootView: screen)
        view.frame = NSRect(x: 0, y: 0, width: 360, height: 640)
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        // The window is there for the layout and the accessibility tree only: off screen, transparent,
        // deaf to the mouse and never in front, so that a test run does not flash over the person's windows.
        window.setFrameOrigin(NSPoint(x: -20000, y: -20000))
        window.alphaValue = 0
        window.ignoresMouseEvents = true
        window.orderBack(nil)
        spin()
        return view
    }

    func spin(_ seconds: Double = 0.4) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    /// The accessibility objects below a view, by the Objective-C interface: SwiftUI hands out
    /// private node classes that do not conform to the Swift protocols.
    func elements(_ root: Any?) -> [NSObject] {
        var found: [NSObject] = []
        func walk(_ object: Any?, depth: Int) {
            guard let element = object as? NSObject, depth < 30 else { return }
            found.append(element)
            let selector = NSSelectorFromString("accessibilityChildren")
            guard element.responds(to: selector), let children = element.perform(selector)?.takeUnretainedValue() as? [Any] else { return }
            for child in children { walk(child, depth: depth + 1) }
        }
        walk(root, depth: 0)
        return found
    }

    func text(_ element: NSObject, _ name: String) -> String? {
        let selector = NSSelectorFromString(name)
        guard element.responds(to: selector) else { return nil }
        return element.perform(selector)?.takeUnretainedValue() as? String
    }

    func find(_ view: NSView, label: String) -> NSObject? {
        elements(view).first { text($0, "accessibilityLabel") == label }
    }

    func press(_ element: NSObject) -> Bool {
        let selector = NSSelectorFromString("accessibilityPerformPress")
        guard element.responds(to: selector) else { return false }
        return element.perform(selector) != nil
    }
}
#endif
