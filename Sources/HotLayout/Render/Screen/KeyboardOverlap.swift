import SwiftUI

#if canImport(UIKit)
import UIKit

/// How far the on-screen keyboard reaches into the view it is attached to, in points. The
/// screen keeps its own size when the keyboard comes; the pinned block rides above it, the
/// navigation bar stays under it (`x-style.layout.bottomZone.keyboard`).
private struct KeyboardOverlapModifier: ViewModifier {
    @Binding var overlap: Double
    @State private var frame: CGRect = .zero
    @State private var keyboard: CGRect = .zero

    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { proxy in
                    Color.clear.onAppear { frame = proxy.frame(in: .global) }
                        .onChange(of: proxy.frame(in: .global)) { frame = $0 }
                }
            )
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
                keyboard = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect) ?? .zero
                update()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                keyboard = .zero
                update()
            }
            .onChange(of: frame) { _ in update() }
    }

    private func update() {
        let value = keyboard.isEmpty ? 0 : max(0, Double(frame.maxY - keyboard.minY))
        if value != overlap { overlap = value }
    }
}

extension View {
    func keyboardOverlap(_ overlap: Binding<Double>) -> some View {
        modifier(KeyboardOverlapModifier(overlap: overlap))
    }
}
#else
extension View {
    /// There is no on-screen keyboard to account for.
    func keyboardOverlap(_ overlap: Binding<Double>) -> some View { self }
}
#endif
