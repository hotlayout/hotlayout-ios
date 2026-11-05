import Combine
import SwiftUI

/// What a swipe button hands over to start the fill over the screen.
struct SwipeRippleSpec {
    /// The centre of the collapsed circle, in global coordinates.
    var center: CGPoint
    /// The diameter of the halo and of the core of the circle.
    var halo: Double
    var core: Double
    /// The colour of the thumb: the core is this colour, the halo the same at `SwipeMotion.haloOpacity`.
    var color: Color
    var indicatorColor: Color
    var indicatorSize: Double
    /// Runs once, when the screen is covered. Not called when the fill is cancelled before.
    var onCovered: () -> Void
}

/// One fill in flight. The button drops it when it leaves before the screen is covered.
@MainActor
final class SwipeRippleHandle {
    fileprivate weak var store: SwipeRippleStore?
    fileprivate let id: Int

    fileprivate init(store: SwipeRippleStore, id: Int) {
        self.store = store
        self.id = id
    }

    /// Removes the fill if the screen has not been covered yet; nothing runs.
    func cancel() { store?.cancel(id) }
}

/// The fills over one screen: the circles that grow, and the stage they are in.
///
/// The fill is a layer of the screen, not of the button: the button leaves the tree when the screen
/// changes, and the fill must still be there to show the next screen from under it. The circle grows
/// linearly to cover the farthest corner, then the action runs (the screen changes under the fill, with
/// no motion of its own), then the fill fades away over the next screen.
@MainActor
final class SwipeRippleStore: ObservableObject {
    struct Entry: Identifiable {
        let id: Int
        let spec: SwipeRippleSpec
        let startedAt: Date
        /// The fill lies over the window of the app, not over the screen that owns the store.
        let inWindow: Bool
        /// When the action had run and the fill began to fade.
        var revealedAt: Date?
    }

    @Published private(set) var entries: [Entry] = []

    /// Puts a layer over the window and returns how to take it away; `nil` where there is no window.
    /// Fills that do not ask for the window are drawn in the screen that owns the store.
    typealias Mount = @MainActor (SwipeRippleStore) -> (@MainActor () -> Void)?

    private let mount: Mount?
    private var unmount: (@MainActor () -> Void)?
    private var report: ((Bool) -> Void)?
    private var timers: [Int: Task<Void, Never>] = [:]
    private var next = 0
    private let now: () -> Date

    init(mount: Mount? = nil, now: @escaping () -> Date = { Date() }) {
        self.mount = mount
        self.now = now
    }

    /// Whether a fill covers the screen now: the screen then changes with no motion of its own.
    var covers: Bool { !entries.isEmpty }

    /// Starts a fill; `nil` when there is no place to draw it (the action then runs at once).
    /// `report` hears `true` before the action when the screen starts to be covered, `false` once the
    /// last fill is gone.
    func start(_ spec: SwipeRippleSpec, report: ((Bool) -> Void)? = nil, overWindow: Bool = false) -> SwipeRippleHandle? {
        let wasCovering = covers
        if overWindow, !entries.contains(where: \.inWindow) {
            guard let mount, let remove = mount(self) else { return nil }
            unmount = remove
        }
        next += 1
        let id = next
        if report != nil { self.report = report }
        entries.append(Entry(id: id, spec: spec, startedAt: now(), inWindow: overWindow))
        timers[id] = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(SwipeMotion.rippleMs * 1_000_000))
            guard !Task.isCancelled else { return }
            self?.covered(id)
        }
        if !wasCovering { report?(true) }
        return SwipeRippleHandle(store: self, id: id)
    }

    private func covered(_ id: Int) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].revealedAt = now()
        let action = entries[index].spec.onCovered
        timers[id] = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(SwipeMotion.revealMs * 1_000_000))
            guard !Task.isCancelled else { return }
            self?.remove(id)
        }
        action()
    }

    fileprivate func cancel(_ id: Int) {
        // From the moment the action has run the fill belongs to the screen and goes on to its end.
        guard let entry = entries.first(where: { $0.id == id }), entry.revealedAt == nil else { return }
        timers[id]?.cancel()
        remove(id)
    }

    private func remove(_ id: Int) {
        timers[id] = nil
        guard entries.contains(where: { $0.id == id }) else { return }
        entries.removeAll { $0.id == id }
        if !entries.contains(where: \.inWindow) {
            unmount?()
            unmount = nil
        }
        guard entries.isEmpty else { return }
        let report = report
        self.report = nil
        // A button that leaves the tree asks for this while the tree is being updated, and the host
        // may change its views on the answer.
        DispatchQueue.main.async { report?(false) }
    }
}

/// The place a button asks for a fill: the store of the screen it is in.
struct SwipeRippleScope {
    let store: SwipeRippleStore
    /// The host's `onScreenCovered`.
    var report: ((Bool) -> Void)?

    /// A host that hears `onScreenCovered` keeps its own routes: the fill then lies over the whole window.
    @MainActor
    func start(_ spec: SwipeRippleSpec) -> SwipeRippleHandle? { store.start(spec, report: report, overWindow: report != nil) }
}

private struct SwipeRippleKey: EnvironmentKey {
    static let defaultValue: SwipeRippleScope? = nil
}

extension EnvironmentValues {
    /// Where a swipe button puts the fill over the screen; `nil` outside a screen: the button has no fill.
    var swipeRipple: SwipeRippleScope? {
        get { self[SwipeRippleKey.self] }
        set { self[SwipeRippleKey.self] = newValue }
    }
}

// MARK: Drawing

/// The fills of a store over the box they are laid in, cut by its edges.
struct SwipeRippleLayers: View {
    @ObservedObject var store: SwipeRippleStore
    /// The layer over the window draws the fills that asked for it, the layer of the screen the others.
    var inWindow = false

    var body: some View {
        GeometryReader { proxy in
            let origin = proxy.frame(in: .global).origin
            ZStack(alignment: .topLeading) {
                ForEach(store.entries.filter { $0.inWindow == inWindow }) { entry in
                    SwipeRippleLayer(entry: entry, size: proxy.size, origin: origin)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .clipped()
        }
        .accessibilityHidden(true)
    }
}

struct SwipeRippleLayer: View {
    let entry: SwipeRippleStore.Entry
    let size: CGSize
    let origin: CGPoint

    var body: some View {
        let center = CGPoint(x: entry.spec.center.x - origin.x, y: entry.spec.center.y - origin.y)
        let scale = SwipeMotion.rippleScale(
            centerX: Double(center.x), centerY: Double(center.y), screenWidth: Double(size.width), screenHeight: Double(size.height),
            core: entry.spec.core)
        TimelineView(.animation) { timeline in
            let frame = Self.frame(entry, at: timeline.date, scale: scale)
            SwipeRippleDrawing(spec: entry.spec, center: center, size: size, frame: frame)
                // While it grows the fill takes the presses; once the action has run it lets them through.
                .contentShape(Rectangle())
                .allowsHitTesting(frame.growing)
                .onTapGesture {}
        }
    }

    struct Frame: Equatable {
        var scale: Double
        var opacity: Double
        var growing: Bool
    }

    static func frame(_ entry: SwipeRippleStore.Entry, at date: Date, scale: Double) -> Frame {
        if let revealed = entry.revealedAt {
            return Frame(scale: scale, opacity: SwipeMotion.revealAt(date.timeIntervalSince(revealed) * 1000), growing: false)
        }
        return Frame(scale: SwipeMotion.rippleAt(scale: scale, elapsed: date.timeIntervalSince(entry.startedAt) * 1000), opacity: 1, growing: true)
    }
}

/// One frame of the fill: the halo and the core of the circle at a scale, and the indicator at its centre.
struct SwipeRippleDrawing: View {
    let spec: SwipeRippleSpec
    let center: CGPoint
    let size: CGSize
    let frame: SwipeRippleLayer.Frame

    var body: some View {
        ZStack(alignment: .topLeading) {
            Circle()
                .fill(spec.color.opacity(SwipeMotion.haloOpacity))
                .frame(width: spec.halo * frame.scale, height: spec.halo * frame.scale)
                .position(center)
            Circle()
                .fill(spec.color)
                .frame(width: spec.core * frame.scale, height: spec.core * frame.scale)
                .position(center)
            SwipeSpinner(size: spec.indicatorSize, color: spec.indicatorColor, still: false)
                .position(center)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .opacity(frame.opacity)
    }
}

// MARK: Over the window

/// For a host that keeps its own stack of screens (`onScreenCovered`): the fills lie in a layer over the
/// whole window, above the views of the host, so they outlive the screen the button was on.
@MainActor
enum SwipeRippleWindow {
    #if canImport(AppKit) && !canImport(UIKit)
    /// The view the layer is put in on macOS (not a product platform: this is for the tests of the package).
    static var appKitContent: () -> NSView? = { NSApplication.shared.keyWindow?.contentView ?? NSApplication.shared.windows.first?.contentView }
    #endif

    static let mount: SwipeRippleStore.Mount = { store in
        #if canImport(UIKit)
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        guard let window = scene?.windows.first(where: \.isKeyWindow) ?? scene?.windows.first else { return nil }
        let layer = UIHostingController(rootView: SwipeRippleLayers(store: store, inWindow: true).ignoresSafeArea())
        layer.view.backgroundColor = .clear
        layer.view.frame = window.bounds
        layer.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        window.addSubview(layer.view)
        return { layer.view.removeFromSuperview() }
        #elseif canImport(AppKit)
        guard let content = appKitContent() else { return nil }
        let layer = NSHostingView(rootView: SwipeRippleLayers(store: store, inWindow: true).ignoresSafeArea())
        layer.frame = content.bounds
        layer.autoresizingMask = [.width, .height]
        content.addSubview(layer)
        return { layer.removeFromSuperview() }
        #else
        return nil
        #endif
    }
}
