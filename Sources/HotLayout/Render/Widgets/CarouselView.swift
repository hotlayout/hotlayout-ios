import SwiftUI

/// Everything a carousel needs from the document and the theme, already in points.
struct CarouselSetup {
    var spec: CarouselSpec
    var peek: Double
    var gap: Double
    var padding: Sides
    var vertical: VerticalAlignment
    var rightToLeft: Bool
    var dotSize: Double
    var dotGap: Double
    var indicatorGap: Double
    var dotColor: Color
    /// Where the active stop is remembered; `nil` keeps nothing.
    var memory: CarouselMemory?
    var memoryKey: String
}

private struct ViewportKey: PreferenceKey {
    static let defaultValue: CGFloat? = nil
    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) { value = nextValue() ?? value }
}

private struct OffsetKey: PreferenceKey {
    static let defaultValue: CGFloat? = nil
    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) { value = nextValue() ?? value }
}

private struct CardWidthsKey: PreferenceKey {
    static let defaultValue: [Int: CGFloat] = [:]
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// Snaps the end of a scroll to the nearest stop. The stops are offsets from the logical start;
/// a scroll view in right-to-left text counts its offset from the other edge.
@available(iOS 17.0, macOS 14.0, *)
private struct CarouselSnap: ScrollTargetBehavior {
    var stops: [Double]
    var rightToLeft: Bool

    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        guard stops.count > 1 else { return }
        let maxScroll = max(0, context.contentSize.width - context.containerSize.width)
        let physical = target.rect.origin.x
        let logical = rightToLeft ? maxScroll - physical : physical
        let stop = stops[CarouselRules.activeStop(stops, offset: logical)]
        let clamped = min(stop, maxScroll)
        target.rect.origin.x = rightToLeft ? maxScroll - clamped : clamped
    }
}

extension View {
    @ViewBuilder
    fileprivate func carouselSnap(stops: [Double], rightToLeft: Bool) -> some View {
        if #available(iOS 17.0, macOS 14.0, *) {
            // On the scroll view itself: the behavior of a scroll view is read from the view it
            // modifies, and on the content inside it nothing reads it (the scroll never snapped).
            self.scrollTargetBehavior(CarouselSnap(stops: stops, rightToLeft: rightToLeft))
        } else {
            #if canImport(UIKit)
            self.background(LegacySnapInstaller(stops: stops, rightToLeft: rightToLeft))
            #else
            self
            #endif
        }
    }
}

/// A row of cards that scrolls sideways, snaps to the stops and shows the position as dots.
/// `card` draws the card `index` at a given box width (`nil`: its natural width).
struct CarouselView<Card: View>: View {
    let setup: CarouselSetup
    let count: Int
    /// A viewport the caller already knows (tests); the view measures its own otherwise.
    var knownViewport: CGFloat?
    @ViewBuilder let card: (Int, Double?) -> Card

    @State private var measuredViewport: CGFloat?
    @State private var widths: [Int: CGFloat] = [:]
    @State private var offset: CGFloat = 0
    @State private var restored = false

    private static var space: String { "hotlayout.carousel" }

    private var viewport: CGFloat? { knownViewport ?? measuredViewport }

    private var cardWidth: Double? {
        guard let viewport, let perView = setup.spec.perView else { return nil }
        return CarouselRules.cardWidth(viewport: Double(viewport), paddingStart: setup.padding.start, gap: setup.gap, peek: setup.peek, perView: perView)
    }

    private var stops: CarouselRules.Stops {
        let measured = (0..<count).map { widths[$0].map(Double.init) }
        guard let viewport, !measured.contains(where: { $0 == nil }) else {
            return CarouselRules.stops(viewport: 0, paddingStart: 0, paddingEnd: 0, gap: 0, cards: [])
        }
        return CarouselRules.stops(
            viewport: Double(viewport), paddingStart: setup.padding.start, paddingEnd: setup.padding.end,
            gap: setup.gap, cards: measured.compactMap { $0 }
        )
    }

    private var activeStop: Int {
        let stops = stops.stops
        if !restored, let remembered = setup.memory?.stop(for: setup.memoryKey) { return min(remembered, stops.count - 1) }
        return CarouselRules.activeStop(stops, offset: Double(offset))
    }

    var body: some View {
        let plan = stops
        let dots =
            viewport.map {
                CarouselRules.dotCount(
                    indicator: setup.spec.indicator, stops: plan.stops.count, viewport: Double($0), dotSize: setup.dotSize, dotGap: setup.dotGap)
            } ?? 0
        VStack(spacing: setup.indicatorGap) {
            scroller(plan)
            if dots > 0 { dotRow(count: dots, active: activeStop) }
        }
        .accessibilityElement(children: .contain)
    }

    private func scroller(_ plan: CarouselRules.Stops) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: setup.vertical, spacing: setup.gap) {
                    ForEach(0..<count, id: \.self) { index in
                        card(index, cardWidth)
                            .background(
                                GeometryReader { geometry in
                                    Color.clear.preference(key: CardWidthsKey.self, value: [index: geometry.size.width])
                                })
                    }
                }
                .padding(EdgeInsets(top: setup.padding.top, leading: setup.padding.start, bottom: setup.padding.bottom, trailing: setup.padding.end))
                .background(alignment: .leading) {
                    GeometryReader { geometry in
                        let frame = geometry.frame(in: .named(Self.space))
                        Color.clear.preference(key: OffsetKey.self, value: setup.rightToLeft ? (viewport ?? 0) - frame.maxX : -frame.minX)
                    }
                }
                .overlay(alignment: .leading) { anchors(plan) }
            }
            .carouselSnap(stops: plan.stops, rightToLeft: setup.rightToLeft)
            .coordinateSpace(name: Self.space)
            .background(GeometryReader { geometry in Color.clear.preference(key: ViewportKey.self, value: geometry.size.width) })
            .onPreferenceChange(ViewportKey.self) { measuredViewport = $0 }
            .onPreferenceChange(CardWidthsKey.self) { widths = $0 }
            .onPreferenceChange(OffsetKey.self) { value in
                guard let value else { return }
                offset = value
                if restored { remember(CarouselRules.activeStop(plan.stops, offset: Double(value))) }
            }
            .onChange(of: plan) { restore($0, proxy: proxy) }
            .onAppear { restore(plan, proxy: proxy) }
            .opacity(viewport == nil ? 0 : 1)
        }
    }

    /// Empty marks at the stops, so that the scroll can be put back on a remembered stop.
    private func anchors(_ plan: CarouselRules.Stops) -> some View {
        ZStack(alignment: .leading) {
            ForEach(Array(plan.stops.enumerated()), id: \.offset) { index, stop in
                Color.clear.frame(width: 1, height: 1)
                    .offset(x: setup.rightToLeft ? -stop : stop)
                    .id(index)
            }
        }
        .allowsHitTesting(false)
    }

    private func remember(_ stop: Int) {
        setup.memory?.set(stop, for: setup.memoryKey)
    }

    /// Once the stops are known, puts the scroll on the stop the frame remembers (no animation).
    private func restore(_ plan: CarouselRules.Stops, proxy: ScrollViewProxy) {
        guard !restored, viewport != nil, widths.count == count, count > 0 else { return }
        let remembered = setup.memory?.stop(for: setup.memoryKey) ?? 0
        // The stops of a plan made before every card was measured are just [0]: wait for the real ones.
        if remembered >= plan.stops.count && plan.stops.count <= 1 { return }
        restored = true
        guard remembered > 0, remembered < plan.stops.count else { return }
        let stop = remembered
        // After the layout pass that measured the cards: a jump made inside it finds no content.
        DispatchQueue.main.async {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { proxy.scrollTo(stop, anchor: .leading) }
        }
    }

    private func dotRow(count: Int, active: Int) -> some View {
        HStack(spacing: setup.dotGap) {
            ForEach(0..<count, id: \.self) { index in
                Circle().fill(setup.dotColor).frame(width: setup.dotSize, height: setup.dotSize)
                    .opacity(index == active ? 1 : CarouselRules.inactiveDotOpacity)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }
}

extension CarouselSetup {
    /// The setup of the carousel of `node`, from the theme the context carries.
    static func make(spec: CarouselSpec, node: DocumentNode, gap: Double, padding: Sides, vertical: VerticalAlignment, context: RenderContext) -> CarouselSetup
    {
        let resolver = context.resolver
        func spacing(_ token: String) -> Double? { resolver.spacing(.string(token)) }
        let key = CarouselMemory.key(
            frame: context.frameIndex, screenId: context.screenId,
            state: CarouselRules.stateKey(nodeId: node.id, instancePath: context.instancePath)
        )
        return CarouselSetup(
            spec: spec, peek: CarouselRules.peekPixels(spec.peek, spacing: spacing), gap: gap, padding: padding, vertical: vertical,
            rightToLeft: context.rightToLeft,
            dotSize: spacing(CarouselRules.dotSizeToken) ?? 8, dotGap: spacing(CarouselRules.dotGapToken) ?? 8,
            indicatorGap: spacing(CarouselRules.indicatorGapToken) ?? 8,
            dotColor: (context.theme.coreColor(CarouselRules.dotColorToken)).color,
            memory: context.carousels, memoryKey: key
        )
    }
}

extension RowView {
    /// The placement of a card: natural, or the box width `perView` gave it.
    static func cardPlacement(width: Double?) -> Placement {
        var placement = Placement.natural
        placement.cardWidth = width
        return placement
    }
}

#if canImport(UIKit)
import UIKit

/// iOS 16 has no scroll target behavior. A hidden view finds the `UIScrollView` SwiftUI built
/// around it and, when a finger lifts, ends the deceleration on the stop the throw would reach.
private struct LegacySnapInstaller: UIViewRepresentable {
    var stops: [Double]
    var rightToLeft: Bool

    func makeCoordinator() -> LegacySnap { LegacySnap() }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.stops = stops
        context.coordinator.rightToLeft = rightToLeft
        DispatchQueue.main.async { context.coordinator.attach(from: view) }
    }
}

private final class LegacySnap: NSObject {
    var stops: [Double] = []
    var rightToLeft = false
    private weak var scrollView: UIScrollView?

    func attach(from view: UIView) {
        guard scrollView == nil else { return }
        var ancestor = view.superview
        while let current = ancestor, !(current is UIScrollView) { ancestor = current.superview }
        guard let found = ancestor as? UIScrollView else { return }
        scrollView = found
        found.decelerationRate = .fast
        found.panGestureRecognizer.addTarget(self, action: #selector(pan(_:)))
    }

    @objc private func pan(_ pan: UIPanGestureRecognizer) {
        guard pan.state == .ended || pan.state == .cancelled, stops.count > 1, let scrollView else { return }
        let maxScroll = max(0, scrollView.contentSize.width - scrollView.bounds.width)
        let velocity = pan.velocity(in: scrollView).x
        // Offset from the logical start; a right-to-left scroll view counts from the other edge
        // in this reader (its content is mirrored, the offset is physical).
        let physical = scrollView.contentOffset.x - scrollView.adjustedContentInset.left
        let logical = rightToLeft ? maxScroll - physical : physical
        // The finger moves with the content, so a leftward drag (negative velocity) advances.
        let direction = rightToLeft ? -1.0 : 1.0
        let projected = logical - direction * Double(velocity) * 0.12
        let stop = min(stops[CarouselRules.activeStop(stops, offset: projected)], maxScroll)
        let target = rightToLeft ? maxScroll - stop : stop
        scrollView.setContentOffset(CGPoint(x: target + scrollView.adjustedContentInset.left, y: scrollView.contentOffset.y), animated: true)
    }
}
#endif
