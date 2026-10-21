import Foundation

/// The carousel field of a sideways row (`x-style.layout.carousel`): which nodes can be a
/// carousel, how the field is read, the width of a card, the snap stops, the active stop and
/// the dots. Plain numbers: the theme and the measuring are done by the caller.
struct CarouselSpec: Equatable {
    enum Indicator: Equatable { case dots, none }

    /// Whole cards in view, 1…6; `nil` keeps the natural widths.
    var perView: Int?
    /// A spacing token or a whole number of points, as the document wrote it; `nil` is the default.
    var peek: JSONValue?
    var indicator: Indicator = .dots
}

enum CarouselRules {
    static let perViewRange = 1...6
    static let maxSpacing = 128.0
    static let defaultPeek = "lg"
    static let maxDots = 10
    static let inactiveDotOpacity = 0.3
    static let minCard = 1.0
    static let stopMerge = 0.5
    static let dotSizeToken = "sm"
    static let dotGapToken = "sm"
    static let indicatorGapToken = "sm"
    static let dotColorToken = "primary"

    // MARK: Who is a carousel

    /// A row that scrolls, or a data list laid out in a row. A list with `columns` does not read
    /// its direction at all, so it is never a carousel. Props decide, not the type alone.
    static func isHost(type: String, props: JSONObject) -> Bool {
        switch WidgetType(type) {
        case .row: return props["scrollable"]?.boolValue == true
        case .repeater: return props["direction"]?.stringValue == "row" && RepeaterPlan.columns(props) == nil
        default: return false
        }
    }

    /// The field as the reader reads it; `nil` when it is not an object.
    static func read(_ value: JSONValue?) -> CarouselSpec? {
        guard let object = value?.objectValue else { return nil }
        var spec = CarouselSpec()
        if let number = object["perView"]?.numberValue, number == number.rounded(), let whole = SafeInt.exactly(number), perViewRange.contains(whole) {
            spec.perView = whole
        }
        switch object["peek"] {
        case .string(let token)?: if !token.isEmpty { spec.peek = .string(token) }
        case .number(let number)?: if number == number.rounded(), number >= 0, number <= maxSpacing { spec.peek = .number(number) }
        default: break
        }
        if object["indicator"]?.stringValue == "none" { spec.indicator = .none }
        return spec
    }

    /// The carousel of a node: it must be a host and the field must be readable.
    static func of(_ node: DocumentNode) -> CarouselSpec? {
        guard isHost(type: node.type, props: node.props) else { return nil }
        return read(node.props["carousel"])
    }

    // MARK: Card and stops

    /// The peek in points. A token the theme does not declare is the default token.
    static func peekPixels(_ peek: JSONValue?, spacing: (String) -> Double?) -> Double {
        if case .number(let number)? = peek { return number }
        if case .string(let token)? = peek, let value = spacing(token) { return value }
        return spacing(defaultPeek) ?? 16
    }

    /// The width of a card box for `perView`: `(viewport − padding start − perView × gap − peek) ÷
    /// perView`, never rounded. `nil` when it is not a card (narrower than one point): natural widths.
    static func cardWidth(viewport: Double, paddingStart: Double, gap: Double, peek: Double, perView: Int) -> Double? {
        let width = (viewport - paddingStart - Double(perView) * gap - peek) / Double(perView)
        return width.isFinite && width >= minCard ? width : nil
    }

    struct Stops: Equatable {
        var stops: [Double]
        var maxScroll: Double
        /// Which stop shows each card at its start (or the end of the scroll).
        var stopOfCard: [Int]
    }

    /// The snap stops: the start of every card, until the end of the scroll; the end of the scroll
    /// is a stop always. `cards` are outer widths (box and margin) in document order.
    static func stops(viewport: Double, paddingStart: Double, paddingEnd: Double, gap: Double, cards: [Double]) -> Stops {
        var starts: [Double] = []
        var cursor = 0.0
        for (index, card) in cards.enumerated() {
            starts.append(cursor)
            cursor += card + (index < cards.count - 1 ? gap : 0)
        }
        let maxScroll = max(0, paddingStart + cursor + paddingEnd - viewport)
        var stops: [Double] = []
        var stopOfCard: [Int] = []
        for start in starts {
            if maxScroll > 0 && start < maxScroll - stopMerge {
                stops.append(start)
            } else if stops.last != maxScroll {
                stops.append(maxScroll)
            }
            stopOfCard.append(stops.count - 1)
        }
        if stops.isEmpty { stops.append(0) }
        if maxScroll > 0, let last = stops.last, last < maxScroll - stopMerge { stops.append(maxScroll) }
        return Stops(stops: stops, maxScroll: maxScroll, stopOfCard: stopOfCard)
    }

    /// The stop nearest to the offset (from the logical start); a tie is the earlier one.
    static func activeStop(_ stops: [Double], offset: Double) -> Int {
        let at = offset.isFinite ? max(0, offset) : 0
        var best = 0
        var distance = Double.infinity
        for (index, stop) in stops.enumerated() where abs(stop - at) < distance {
            best = index
            distance = abs(stop - at)
        }
        return best
    }

    // MARK: Dots

    static func dotsRowWidth(count: Int, dotSize: Double, dotGap: Double) -> Double {
        count > 0 ? Double(count) * dotSize + Double(count - 1) * dotGap : 0
    }

    /// How many dots are drawn: one per stop; none for a single stop, more than ten stops, or a
    /// row wider than the area. A number that is not a number does not fit.
    static func dotCount(indicator: CarouselSpec.Indicator, stops: Int, viewport: Double, dotSize: Double, dotGap: Double) -> Int {
        guard indicator == .dots, stops > 1, stops <= maxDots else { return 0 }
        return dotsRowWidth(count: stops, dotSize: dotSize, dotGap: dotGap) <= viewport ? stops : 0
    }

    /// The height under the area: the gap and a dot; nothing when no dots are drawn.
    static func indicatorBlock(dots: Int, gap: Double, dotSize: Double) -> Double {
        dots > 0 ? gap + dotSize : 0
    }

    // MARK: State

    /// The key of the state: the node and the chain of template instances it stands in.
    static func stateKey(nodeId: String, instancePath: [Int]) -> String {
        let parts: [Any] = [nodeId] + instancePath
        guard let data = try? JSONSerialization.data(withJSONObject: parts), let text = String(data: data, encoding: .utf8) else { return nodeId }
        return text
    }
}

/// What the carousels of the screens in the stack remember: the active stop, per frame of the
/// stack and per node (with its template instances). A frame leaving the stack takes its entries.
final class CarouselMemory {
    private var stops: [String: Int] = [:]

    static func key(frame: Int, screenId: String, state: String) -> String {
        "\(frame)\u{1F}\(screenId)\u{1F}\(state)"
    }

    func stop(for key: String) -> Int? { stops[key] }

    func set(_ stop: Int, for key: String) { stops[key] = stop }

    /// Keeps the entries of the frames still in the stack (frame index and screen).
    func prune(frames: [String]) {
        let live = Set(frames.enumerated().map { "\($0.offset)\u{1F}\($0.element)\u{1F}" })
        stops = stops.filter { entry in live.contains { entry.key.hasPrefix($0) } }
    }

    var count: Int { stops.count }
}
