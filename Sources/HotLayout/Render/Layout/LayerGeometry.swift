import Foundation

extension AlignWord {
    /// The word a layer or a stack names, `nil` for anything the reader does not understand.
    init?(_ value: JSONValue?) {
        guard let text = value?.stringValue, let word = AlignWord(rawValue: text) else { return nil }
        self = word
    }
}

/// A reference to a spacing step as the document writes it: a token name or a whole number of
/// logical pixels 0…128.
enum SpacingReference: Equatable {
    case token(String)
    case pixels(Int)

    static let maxPixels = 128

    /// `nil` for anything the reader does not understand (a CSS length, a fraction, a negative
    /// number, a number above 128).
    init?(_ value: JSONValue?) {
        switch value {
        case .string(let name)?:
            guard ContractShapes.isTokenName(name) else { return nil }
            self = .token(name)
        case .number(let number)?:
            guard number.isFinite, number == number.rounded(), number >= 0, number <= Double(Self.maxPixels) else { return nil }
            self = .pixels(SafeInt.clamped(number, limit: Self.maxPixels))
        default:
            return nil
        }
    }

    var json: JSONValue {
        switch self {
        case .token(let name): return .string(name)
        case .pixels(let value): return .number(Double(value))
        }
    }
}

/// One axis of an offset, as read: a direction word (`start` / `end`, or `top` / `bottom`)
/// and the amount.
struct LayerAxisOffset: Equatable {
    let toward: String
    let by: SpacingReference
}

/// The place of a layer in a stack, as the reader reads it (`readLayerValue`): everything
/// unreadable is already dropped, and a half does not take the other half with it.
struct LayerRead: Equatable {
    var alignHorizontal: AlignWord?
    var alignVertical: AlignWord?
    var offsetX: LayerAxisOffset?
    var offsetY: LayerAxisOffset?
    /// Whole degrees clockwise in left-to-right text; 0 is no rotation.
    var rotate: Int = 0

    static let horizontalDirections: Set<String> = ["start", "end"]
    static let verticalDirections: Set<String> = ["top", "bottom"]
    static let rotateRange = -180...180

    /// `nil` when the value is not an object: then the node is an ordinary layer.
    static func read(_ value: JSONValue?) -> LayerRead? {
        guard let object = value?.objectValue else { return nil }
        let offset = object["offset"]?.objectValue ?? JSONObject()
        var rotate = 0
        if let number = object["rotate"]?.numberValue, number == number.rounded(), let whole = SafeInt.exactly(number), rotateRange.contains(whole) {
            rotate = whole
        }
        return LayerRead(
            alignHorizontal: AlignWord(object["alignHorizontal"]),
            alignVertical: AlignWord(object["alignVertical"]),
            offsetX: axis(offset["x"], directions: horizontalDirections),
            offsetY: axis(offset["y"], directions: verticalDirections),
            rotate: rotate
        )
    }

    private static func axis(_ value: JSONValue?, directions: Set<String>) -> LayerAxisOffset? {
        guard let object = value?.objectValue, let toward = object["toward"]?.stringValue, directions.contains(toward),
            let by = SpacingReference(object["by"])
        else { return nil }
        return LayerAxisOffset(toward: toward, by: by)
    }
}

/// Where an overlay stands: the geometry of the contract (`layerGeometry`), on plain numbers.
enum LayerGeometry {
    struct Input {
        var stack: CGSize
        var layer: CGSize
        var alignHorizontal: AlignWord
        var alignVertical: AlignWord
        /// The offset in logical pixels; `nil` is none on that axis.
        var offsetX: (toward: String, by: Double)?
        var offsetY: (toward: String, by: Double)?
        var rotate: Int = 0
        var rightToLeft: Bool
    }

    struct Result: Equatable {
        /// The UNROTATED box after alignment and offset, in the PHYSICAL coordinates of the
        /// stack: `x` from its left edge, `y` from its top edge.
        var rect: CGRect
        /// Degrees clockwise as drawn; the sign is flipped in right-to-left text.
        var angle: Double
        var protrudes: Bool
    }

    static func along(_ room: CGFloat, _ size: CGFloat, _ word: AlignWord) -> CGFloat {
        switch word {
        case .start: return 0
        case .end: return room - size
        case .center: return (room - size) / 2
        }
    }

    /// The angle as drawn: right-to-left text mirrors the layout, and the turn must keep its
    /// look relative to its corner, so the sign changes.
    static func drawnAngle(_ rotate: Int, rightToLeft: Bool) -> Double {
        (rightToLeft ? -Double(rotate) : Double(rotate)) + 0
    }

    static func place(_ input: Input) -> Result {
        let stack = input.stack
        let layer = input.layer
        // Alignment, then the offset along the axes of the stack; the physical x is the last step.
        var inlineStart = along(stack.width, layer.width, input.alignHorizontal)
        if let offset = input.offsetX { inlineStart += offset.toward == "end" ? CGFloat(offset.by) : -CGFloat(offset.by) }
        var y = along(stack.height, layer.height, input.alignVertical)
        if let offset = input.offsetY { y += offset.toward == "bottom" ? CGFloat(offset.by) : -CGFloat(offset.by) }
        let x = input.rightToLeft ? stack.width - inlineStart - layer.width : inlineStart
        let angle = drawnAngle(input.rotate, rightToLeft: input.rightToLeft)
        let rect = CGRect(x: x, y: y, width: layer.width, height: layer.height)
        return Result(rect: rect, angle: angle, protrudes: protrudes(rect, angle: angle, in: stack))
    }

    private static func protrudes(_ rect: CGRect, angle: Double, in stack: CGSize) -> Bool {
        let radians = angle * .pi / 180
        let epsilon = 1e-9
        let center = CGPoint(x: rect.midX, y: rect.midY)
        for (sx, sy) in [(-1.0, -1.0), (1, -1), (1, 1), (-1, 1)] {
            let dx = sx * Double(rect.width) / 2
            let dy = sy * Double(rect.height) / 2
            let px = Double(center.x) + dx * cos(radians) - dy * sin(radians)
            let py = Double(center.y) + dx * sin(radians) + dy * cos(radians)
            if px < -epsilon || py < -epsilon || px > Double(stack.width) + epsilon || py > Double(stack.height) + epsilon { return true }
        }
        return false
    }

    /// Whether a point of the stack lies in the drawn (rotated) layer.
    static func contains(_ result: Result, _ point: CGPoint) -> Bool {
        let radians = -result.angle * .pi / 180
        let dx = Double(point.x - result.rect.midX)
        let dy = Double(point.y - result.rect.midY)
        let localX = dx * cos(radians) - dy * sin(radians)
        let localY = dx * sin(radians) + dy * cos(radians)
        return abs(localX) <= Double(result.rect.width) / 2 && abs(localY) <= Double(result.rect.height) / 2
    }
}
