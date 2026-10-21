import SwiftUI

#if canImport(UIKit)
import UIKit

/// How far the scroll view around the content is scrolled from its top, in points. The offset comes from the
/// scroll view itself: a geometry preference of the content does not fire while the content is only scrolled
/// (it fires on layout), and the scrolled state of the app bar would never switch on.
private struct ScrollTopObserver: UIViewRepresentable {
    let onChange: (Double) -> Void

    func makeUIView(context: Context) -> Probe {
        let probe = Probe()
        probe.isUserInteractionEnabled = false
        probe.onChange = onChange
        return probe
    }

    func updateUIView(_ probe: Probe, context: Context) { probe.onChange = onChange }

    final class Probe: UIView {
        var onChange: ((Double) -> Void)?
        private var token: NSKeyValueObservation?
        private weak var scroll: UIScrollView?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil else { return }
            var up: UIView? = superview
            while let view = up, !(view is UIScrollView) { up = view.superview }
            guard let found = up as? UIScrollView, found !== scroll else { return }
            scroll = found
            token = found.observe(\.contentOffset, options: [.initial, .new]) { [weak self] scroll, _ in
                self?.onChange?(Double(scroll.contentOffset.y + scroll.adjustedContentInset.top))
            }
        }

        deinit { token?.invalidate() }
    }
}

extension View {
    /// Reports the scroll offset of the enclosing scroll view while the user scrolls.
    func reportsScrollTop(_ onChange: @escaping (Double) -> Void) -> some View {
        background(ScrollTopObserver(onChange: onChange).frame(width: 0, height: 0))
    }
}
#else
extension View {
    func reportsScrollTop(_ onChange: @escaping (Double) -> Void) -> some View { self }
}
#endif
