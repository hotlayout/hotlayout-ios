import CoreGraphics
import Foundation

/// One drawn element of an icon in the 24×24 grid, with its paint.
struct IconElement: Equatable, Sendable {
    let path: IconPath
    /// `fill='currentColor'`: the element is filled with the foreground color.
    let filled: Bool
    /// `stroke='none'` turns the stroke off; otherwise it is drawn with `strokeWidth`.
    let stroked: Bool
    let strokeWidth: Double
}

/// The icon set the reader ships with (`icons.json`): for every icon name, the inner elements
/// of an SVG on one shared grid. Drawing is done here, from geometry, never by an SVG engine:
/// the body is a closed vocabulary (`format`) and anything outside it is not drawn.
enum IconSet {
    /// Names drawn mirrored in right-to-left text (`x-mirroredIcons`): a direction, not a thing.
    static let mirrored: Set<String> = [
        "chevron", "arrow-left", "arrow-right", "arrow-up-left", "arrow-up-right", "arrow-down-left", "arrow-down-right",
        "chevron-left", "chevron-right", "chevrons-left", "chevrons-right", "circle-arrow-left", "circle-arrow-right",
        "circle-chevron-left", "circle-chevron-right", "log-in", "log-out", "undo", "redo", "undo-2", "redo-2", "reply",
        "forward", "send", "external-link", "trending-up", "trending-down", "list", "list-checks",
    ]

    /// Whether a drawing is flipped: a directional icon of the set in right-to-left text.
    static func isMirrored(_ name: String?, rightToLeft: Bool) -> Bool {
        rightToLeft && name.map(mirrored.contains) == true
    }

    /// The grid of every icon (`grid`): 24 units, stroke 2, round caps and joins.
    static let gridSize = 24.0
    static let defaultStrokeWidth = 2.0

    private static let parsed = LockedValue<[String: [IconElement]]>([:])

    /// The shipped file, parsed once.
    private static let shipped: JSONValue? = {
        guard let url = Bundle.module.url(forResource: "icons", withExtension: "json"),
            let data = try? Data(contentsOf: url)
        else { return nil }
        return try? JSONValue.parse(data)
    }()

    /// The raw bodies by name, loaded once.
    static let bodies: [String: String] = {
        var result: [String: String] = [:]
        for (name, body) in shipped?["icons"]?.objectValue ?? JSONObject() {
            if let body = body.stringValue { result[name] = body }
        }
        return result
    }()

    /// The version of the shipped set (`iconSetVersion`).
    static let shippedVersion: String? = shipped?["iconSetVersion"]?.stringValue

    static var names: [String] { bodies.keys.sorted() }

    /// The elements of an icon, or `nil` for a name the set does not have (`unknownIcon:
    /// 'empty-box-same-size'`: the caller keeps an empty box of the same size).
    static func elements(_ name: String) -> [IconElement]? {
        if let known = parsed.withLock({ $0[name] }) { return known }
        guard let body = bodies[name] else { return nil }
        let elements = IconBody.parse(body)
        parsed.withLock { $0[name] = elements }
        return elements
    }
}

/// The closed vocabulary of an icon body (`format`): self-closing elements with single-quoted
/// attributes. An element or an attribute outside it is skipped.
enum IconBody {
    static let geometry: [String: Set<String>] = [
        "path": ["d"], "circle": ["cx", "cy", "r"], "ellipse": ["cx", "cy", "rx", "ry"],
        "rect": ["x", "y", "width", "height", "rx", "ry"], "line": ["x1", "y1", "x2", "y2"],
        "polyline": ["points"], "polygon": ["points"],
    ]

    static func parse(_ body: String) -> [IconElement] {
        var elements: [IconElement] = []
        var rest = Substring(body)
        while let open = rest.firstIndex(of: "<") {
            guard let close = rest[open...].range(of: "/>") else { break }
            let tag = rest[rest.index(after: open)..<close.lowerBound]
            rest = rest[close.upperBound...]
            let nameEnd = tag.firstIndex(where: { $0 == " " }) ?? tag.endIndex
            let name = String(tag[..<nameEnd])
            guard let allowed = geometry[name] else { continue }
            var attributes: [String: String] = [:]
            var cursor = tag[nameEnd...]
            while let equals = cursor.firstIndex(of: "=") {
                let key = cursor[..<equals].trimmingCharacters(in: .whitespaces)
                let afterEquals = cursor.index(after: equals)
                guard afterEquals < cursor.endIndex, cursor[afterEquals] == "'",
                    let end = cursor[cursor.index(after: afterEquals)...].firstIndex(of: "'")
                else { break }
                attributes[key] = String(cursor[cursor.index(after: afterEquals)..<end])
                cursor = cursor[cursor.index(after: end)...]
            }
            guard let path = shape(name, attributes, allowed: allowed) else { continue }
            let strokeWidth = attributes["stroke-width"].flatMap(Double.init) ?? IconSet.defaultStrokeWidth
            elements.append(
                IconElement(
                    path: path,
                    filled: attributes["fill"] == "currentColor",
                    stroked: attributes["stroke"] != "none",
                    strokeWidth: strokeWidth.isFinite && strokeWidth >= 0 ? strokeWidth : IconSet.defaultStrokeWidth
                ))
        }
        return elements
    }

    static func shape(_ name: String, _ a: [String: String], allowed: Set<String>) -> IconPath? {
        func n(_ key: String) -> Double? { a[key].flatMap(Double.init).flatMap { $0.isFinite ? $0 : nil } }
        var path = IconPath()
        switch name {
        case "path":
            guard let d = a["d"] else { return nil }
            path = SVGPathParser.parse(d)
        case "circle":
            guard let cx = n("cx"), let cy = n("cy"), let r = n("r"), r > 0 else { return nil }
            path.ellipse(CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r))
        case "ellipse":
            guard let cx = n("cx"), let cy = n("cy"), let rx = n("rx"), let ry = n("ry"), rx > 0, ry > 0 else { return nil }
            path.ellipse(CGRect(x: cx - rx, y: cy - ry, width: 2 * rx, height: 2 * ry))
        case "rect":
            guard let width = n("width"), let height = n("height"), width > 0, height > 0 else { return nil }
            let rx = n("rx") ?? n("ry") ?? 0
            let ry = n("ry") ?? rx
            path.roundedRect(CGRect(x: n("x") ?? 0, y: n("y") ?? 0, width: width, height: height), rx: min(rx, width / 2), ry: min(ry, height / 2))
        case "line":
            guard let x1 = n("x1"), let y1 = n("y1"), let x2 = n("x2"), let y2 = n("y2") else { return nil }
            path.move(CGPoint(x: x1, y: y1))
            path.line(CGPoint(x: x2, y: y2))
        case "polyline", "polygon":
            let numbers = SVGPathParser.numbers(a["points"] ?? "")
            guard numbers.count >= 4 else { return nil }
            path.move(CGPoint(x: numbers[0], y: numbers[1]))
            var index = 2
            while index + 1 < numbers.count {
                path.line(CGPoint(x: numbers[index], y: numbers[index + 1]))
                index += 2
            }
            if name == "polygon" { path.close() }
        default:
            return nil
        }
        return path
    }
}

/// A platform-neutral path: a list of drawing commands in grid units. SwiftUI and tests both
/// read it.
struct IconPath: Equatable, Sendable {
    enum Command: Equatable, Sendable {
        case move(CGPoint)
        case line(CGPoint)
        case quad(CGPoint, control: CGPoint)
        case cubic(CGPoint, control1: CGPoint, control2: CGPoint)
        case ellipse(CGRect)
        case roundedRect(CGRect, rx: Double, ry: Double)
        case close
    }

    private(set) var commands: [Command] = []

    mutating func move(_ point: CGPoint) { commands.append(.move(point)) }
    mutating func line(_ point: CGPoint) { commands.append(.line(point)) }
    mutating func quad(_ point: CGPoint, control: CGPoint) { commands.append(.quad(point, control: control)) }
    mutating func cubic(_ point: CGPoint, _ c1: CGPoint, _ c2: CGPoint) { commands.append(.cubic(point, control1: c1, control2: c2)) }
    mutating func ellipse(_ rect: CGRect) { commands.append(.ellipse(rect)) }
    mutating func roundedRect(_ rect: CGRect, rx: Double, ry: Double) { commands.append(.roundedRect(rect, rx: rx, ry: ry)) }
    mutating func close() { commands.append(.close) }

    /// The path as Core Graphics geometry, scaled from the grid to `size` points.
    func cgPath(scale: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let transform = CGAffineTransform(scaleX: scale, y: scale)
        for command in commands {
            switch command {
            case .move(let point): path.move(to: point, transform: transform)
            case .line(let point): path.addLine(to: point, transform: transform)
            case .quad(let point, let control): path.addQuadCurve(to: point, control: control, transform: transform)
            case .cubic(let point, let c1, let c2): path.addCurve(to: point, control1: c1, control2: c2, transform: transform)
            case .ellipse(let rect): path.addEllipse(in: rect, transform: transform)
            case .roundedRect(let rect, let rx, let ry):
                if rx > 0, ry > 0 {
                    path.addRoundedRect(in: rect, cornerWidth: rx, cornerHeight: ry, transform: transform)
                } else {
                    path.addRect(rect, transform: transform)
                }
            case .close: path.closeSubpath()
            }
        }
        return path
    }
}

/// SVG path data (`d`) into commands. Arcs become cubic curves.
enum SVGPathParser {
    static func numbers(_ text: String) -> [Double] {
        var result: [Double] = []
        var scanner = NumberScanner(Array(text.utf8))
        while let value = scanner.next() { result.append(value) }
        return result
    }

    struct NumberScanner {
        let bytes: [UInt8]
        var index = 0
        init(_ bytes: [UInt8]) { self.bytes = bytes }

        mutating func skipSeparators() {
            while index < bytes.count, [0x20, 0x2C, 0x09, 0x0A, 0x0D].contains(bytes[index]) { index += 1 }
        }

        mutating func next() -> Double? {
            skipSeparators()
            guard index < bytes.count else { return nil }
            let start = index
            if bytes[index] == UInt8(ascii: "-") || bytes[index] == UInt8(ascii: "+") { index += 1 }
            var sawDot = false
            var sawDigit = false
            while index < bytes.count {
                let byte = bytes[index]
                if byte >= 0x30, byte <= 0x39 {
                    sawDigit = true
                    index += 1
                } else if byte == UInt8(ascii: "."), !sawDot {
                    sawDot = true
                    index += 1
                } else if byte == UInt8(ascii: "e") || byte == UInt8(ascii: "E"), sawDigit {
                    index += 1
                    if index < bytes.count, bytes[index] == UInt8(ascii: "-") || bytes[index] == UInt8(ascii: "+") { index += 1 }
                } else {
                    break
                }
            }
            guard sawDigit, let value = Double(String(decoding: bytes[start..<index], as: UTF8.self)) else {
                index = start
                return nil
            }
            return value
        }

        /// An arc flag: a single 0 or 1, which may be written without a separator.
        mutating func flag() -> Bool? {
            skipSeparators()
            guard index < bytes.count else { return nil }
            let byte = bytes[index]
            guard byte == UInt8(ascii: "0") || byte == UInt8(ascii: "1") else { return nil }
            index += 1
            return byte == UInt8(ascii: "1")
        }

        mutating func command() -> Character? {
            skipSeparators()
            guard index < bytes.count else { return nil }
            let byte = bytes[index]
            guard (byte >= 0x41 && byte <= 0x5A) || (byte >= 0x61 && byte <= 0x7A), byte != UInt8(ascii: "e"), byte != UInt8(ascii: "E") else { return nil }
            index += 1
            return Character(Unicode.Scalar(byte))
        }

        var atEnd: Bool {
            var probe = self
            probe.skipSeparators()
            return probe.index >= bytes.count
        }
    }

    static func parse(_ d: String) -> IconPath {
        var path = IconPath()
        var scanner = NumberScanner(Array(d.utf8))
        var current = CGPoint.zero
        var subpathStart = CGPoint.zero
        var lastControl: CGPoint?
        var lastCommand: Character = " "
        var command: Character?
        var guardCount = 0

        while !scanner.atEnd, guardCount < 10_000 {
            guardCount += 1
            if let next = scanner.command() {
                command = next
            } else if command == nil {
                break
            }
            guard let op = command else { break }
            let relative = op.isLowercase
            func point(_ x: Double, _ y: Double) -> CGPoint {
                relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
            }
            switch op.uppercased() {
            case "M":
                guard let x = scanner.next(), let y = scanner.next() else { return path }
                current = point(x, y)
                subpathStart = current
                path.move(current)
                // Further pairs after a move are lines.
                command = relative ? "l" : "L"
                lastControl = nil
            case "L":
                guard let x = scanner.next(), let y = scanner.next() else { return path }
                current = point(x, y)
                path.line(current)
                lastControl = nil
            case "H":
                guard let x = scanner.next() else { return path }
                current = CGPoint(x: relative ? current.x + x : x, y: current.y)
                path.line(current)
                lastControl = nil
            case "V":
                guard let y = scanner.next() else { return path }
                current = CGPoint(x: current.x, y: relative ? current.y + y : y)
                path.line(current)
                lastControl = nil
            case "C":
                guard let x1 = scanner.next(), let y1 = scanner.next(), let x2 = scanner.next(), let y2 = scanner.next(), let x = scanner.next(),
                    let y = scanner.next()
                else { return path }
                let c1 = point(x1, y1)
                let c2 = point(x2, y2)
                let end = point(x, y)
                path.cubic(end, c1, c2)
                lastControl = c2
                current = end
            case "S":
                guard let x2 = scanner.next(), let y2 = scanner.next(), let x = scanner.next(), let y = scanner.next() else { return path }
                let reflected =
                    "CS".contains(lastCommand.uppercased()) && lastControl != nil
                    ? CGPoint(x: 2 * current.x - lastControl!.x, y: 2 * current.y - lastControl!.y) : current
                let c2 = point(x2, y2)
                let end = point(x, y)
                path.cubic(end, reflected, c2)
                lastControl = c2
                current = end
            case "Q":
                guard let x1 = scanner.next(), let y1 = scanner.next(), let x = scanner.next(), let y = scanner.next() else { return path }
                let control = point(x1, y1)
                let end = point(x, y)
                path.quad(end, control: control)
                lastControl = control
                current = end
            case "T":
                guard let x = scanner.next(), let y = scanner.next() else { return path }
                let control =
                    "QT".contains(lastCommand.uppercased()) && lastControl != nil
                    ? CGPoint(x: 2 * current.x - lastControl!.x, y: 2 * current.y - lastControl!.y) : current
                let end = point(x, y)
                path.quad(end, control: control)
                lastControl = control
                current = end
            case "A":
                guard let rx = scanner.next(), let ry = scanner.next(), let rotation = scanner.next(),
                    let large = scanner.flag(), let sweep = scanner.flag(), let x = scanner.next(), let y = scanner.next()
                else { return path }
                let end = point(x, y)
                arc(&path, from: current, to: end, rx: abs(rx), ry: abs(ry), rotation: rotation, large: large, sweep: sweep)
                current = end
                lastControl = nil
            case "Z":
                path.close()
                current = subpathStart
                lastControl = nil
                command = nil
            default:
                return path
            }
            lastCommand = op
        }
        return path
    }

    /// An elliptical arc (SVG endpoint form) as cubic curves.
    static func arc(_ path: inout IconPath, from start: CGPoint, to end: CGPoint, rx: Double, ry: Double, rotation: Double, large: Bool, sweep: Bool) {
        guard start != end else { return }
        guard rx > 0, ry > 0 else {
            path.line(end)
            return
        }
        var rx = rx
        var ry = ry
        let phi = rotation * .pi / 180
        let cosPhi = cos(phi)
        let sinPhi = sin(phi)
        let dx = (start.x - end.x) / 2
        let dy = (start.y - end.y) / 2
        let x1p = cosPhi * dx + sinPhi * dy
        let y1p = -sinPhi * dx + cosPhi * dy
        let lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
        if lambda > 1 {
            rx *= sqrt(lambda)
            ry *= sqrt(lambda)
        }
        let numerator = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p
        let denominator = rx * rx * y1p * y1p + ry * ry * x1p * x1p
        var coefficient = denominator == 0 ? 0 : sqrt(max(0, numerator / denominator))
        if large == sweep { coefficient = -coefficient }
        let cxp = coefficient * rx * y1p / ry
        let cyp = -coefficient * ry * x1p / rx
        let cx = cosPhi * cxp - sinPhi * cyp + (start.x + end.x) / 2
        let cy = sinPhi * cxp + cosPhi * cyp + (start.y + end.y) / 2

        func angle(_ ux: Double, _ uy: Double, _ vx: Double, _ vy: Double) -> Double {
            let sign: Double = ux * vy - uy * vx < 0 ? -1 : 1
            let dot = ux * vx + uy * vy
            let length = sqrt(ux * ux + uy * uy) * sqrt(vx * vx + vy * vy)
            return sign * acos(max(-1, min(1, dot / length)))
        }
        let theta1 = angle(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry)
        var delta = angle((x1p - cxp) / rx, (y1p - cyp) / ry, (-x1p - cxp) / rx, (-y1p - cyp) / ry)
        if !sweep, delta > 0 { delta -= 2 * .pi }
        if sweep, delta < 0 { delta += 2 * .pi }

        let segments = max(1, Int((abs(delta) / (.pi / 2)).rounded(.up)))
        let step = delta / Double(segments)
        let k = 4.0 / 3.0 * tan(step / 4)
        var theta = theta1
        func pointAt(_ t: Double) -> CGPoint {
            CGPoint(x: cx + rx * cos(t) * cosPhi - ry * sin(t) * sinPhi, y: cy + rx * cos(t) * sinPhi + ry * sin(t) * cosPhi)
        }
        func derivative(_ t: Double) -> CGPoint {
            CGPoint(x: -rx * sin(t) * cosPhi - ry * cos(t) * sinPhi, y: -rx * sin(t) * sinPhi + ry * cos(t) * cosPhi)
        }
        for _ in 0..<segments {
            let next = theta + step
            let p0 = pointAt(theta)
            let p3 = pointAt(next)
            let d0 = derivative(theta)
            let d3 = derivative(next)
            let c1 = CGPoint(x: p0.x + k * d0.x, y: p0.y + k * d0.y)
            let c2 = CGPoint(x: p3.x - k * d3.x, y: p3.y - k * d3.y)
            path.cubic(p3, c1, c2)
            theta = next
        }
    }
}
