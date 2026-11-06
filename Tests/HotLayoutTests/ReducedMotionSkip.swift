import XCTest

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

extension XCTestCase {
    /// The tests that time a motion cannot see it when the system asks to reduce motion: the views then
    /// jump to the end state, by design. GitHub's macOS runners have that setting on and it cannot be
    /// turned off there, so these tests run only on a machine that plays motion.
    func skipUnderReducedMotion() throws {
        #if canImport(UIKit)
        if UIAccessibility.isReduceMotionEnabled { throw XCTSkip("the device asks to reduce motion") }
        #elseif canImport(AppKit)
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { throw XCTSkip("the system asks to reduce motion") }
        #endif
    }
}
