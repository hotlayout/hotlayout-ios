import Foundation

/// The endless motion of a node (`x-motion`): `float` drifts, `pulse` breathes. A motion is a
/// paint transform over the box the node has at rest; it changes no layout.
struct NodeMotion: Equatable {
    enum Axis: String { case vertical, horizontal, both }

    enum Kind: Equatable {
        case float(axis: Axis, amplitude: Int)
        case pulse(scale: Double, opacity: Double?)
    }

    let kind: Kind
    /// One cycle, milliseconds.
    let duration: Int
    /// The time the node stands at rest before the first cycle; zero is no field.
    let delay: Int

    static let durationRange = 400...60000
    static let delayRange = 1...60000
    static let amplitudeRange = 1...48
    static let scaleRange = 0.5...1.5
    static let opacityRange = 0.0...1.0

    /// A pose: a shift (x toward the end of the line is positive, y down), a scale and an opacity.
    struct Pose: Equatable {
        var x = 0.0
        var y = 0.0
        var scale = 1.0
        var opacity = 1.0

        static let rest = Pose()
        var isRest: Bool { self == .rest }
    }

    /// The motion of a value, or `nil` when it is not a motion this reader can draw: a form it
    /// does not know, a missing field, a number out of bounds or an extra field means NO motion.
    static func read(_ value: JSONValue?) -> NodeMotion? {
        guard let object = value?.objectValue,
            let duration = whole(object["duration"]), durationRange.contains(duration)
        else { return nil }
        var delay = 0
        if object["delay"] != nil {
            guard let read = whole(object["delay"]), delayRange.contains(read) else { return nil }
            delay = read
        }
        func only(_ own: Set<String>) -> Bool { object.keys.allSatisfy { $0 == "kind" || $0 == "duration" || $0 == "delay" || own.contains($0) } }
        switch object["kind"]?.stringValue {
        case "float":
            guard only(["axis", "amplitude"]), let axis = object["axis"]?.stringValue.flatMap(Axis.init(rawValue:)),
                let amplitude = whole(object["amplitude"]), amplitudeRange.contains(amplitude)
            else { return nil }
            return NodeMotion(kind: .float(axis: axis, amplitude: amplitude), duration: duration, delay: delay)
        case "pulse":
            guard only(["scale", "opacity"]), let scale = finite(object["scale"]), scaleRange.contains(scale) else { return nil }
            var opacity: Double?
            if object["opacity"] != nil {
                guard let read = finite(object["opacity"]), opacityRange.contains(read) else { return nil }
                opacity = read
            }
            return NodeMotion(kind: .pulse(scale: scale, opacity: opacity), duration: duration, delay: delay)
        default:
            return nil
        }
    }

    private static func finite(_ value: JSONValue?) -> Double? {
        guard let number = value?.numberValue, number.isFinite else { return nil }
        return number
    }

    private static func whole(_ value: JSONValue?) -> Int? {
        guard let number = finite(value), number == number.rounded(.towardZero), abs(number) < 1e9 else { return nil }
        return Int(number)
    }

    /// Where the node is painted `elapsedMs` after it appeared: `theta = 2π·((t − delay) mod
    /// duration) / duration`, rest before the delay ends; "reduce motion" is rest.
    func pose(at elapsedMs: Double, reducedMotion: Bool = false, rightToLeft: Bool = false) -> Pose {
        if reducedMotion { return .rest }
        let elapsed = elapsedMs - Double(delay)
        guard elapsed.isFinite, elapsed >= 0 else { return .rest }
        let cycle = Double(duration)
        let phase = elapsed - cycle * (elapsed / cycle).rounded(.down)
        let theta = 2 * Double.pi * phase / cycle
        switch kind {
        case .float(let axis, let amplitude):
            let a = Double(amplitude)
            let mirror = rightToLeft ? -1.0 : 1.0
            let x = axis == .vertical ? 0 : mirror * a * sin(theta)
            let y: Double
            switch axis {
            case .horizontal: y = 0
            case .vertical: y = -a * sin(theta)
            case .both: y = -a * sin(2 * theta)
            }
            // Negative zero is not a pose anybody asked for.
            return Pose(x: x + 0, y: y + 0)
        case .pulse(let scale, let opacity):
            let progress = (1 - cos(theta)) / 2
            return Pose(scale: 1 + (scale - 1) * progress, opacity: 1 + ((opacity ?? 1) - 1) * progress)
        }
    }
}
