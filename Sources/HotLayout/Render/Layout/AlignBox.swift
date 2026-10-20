import Foundation

/// A child of a host with its own margins included. `stretch` is a child a column stretches
/// (its `width` is then not read); a row does not read it.
struct AlignedChild: Equatable {
    var width: Double
    var height: Double
    var stretch = false
}

struct AlignedRect: Equatable {
    /// From the LEFT edge of the content box, in both directions of the script.
    var x: Double
    var y: Double
    var width: Double
    var height: Double
}

struct AlignedBoxInput {
    var axis: MainAxis
    /// The width of the content box of the host.
    var inline: Double
    /// The named height of the content box (`style.height`, a layer with `fill`).
    var block: Double?
    /// `style.minHeight` of the content box; read only on the block axis — a row gets no cross
    /// room from it.
    var minBlock: Double?
    var gap: Double
    var align: AlignWord
    var justify: JustifyWord
    var rightToLeft: Bool
    var children: [AlignedChild]
}

struct AlignedBox: Equatable {
    var block: Double
    var free: Double
    var rects: [AlignedRect]
}

extension AlignRules {
    /// Where the children of a host stand in its content box. Numbers are not rounded; a child
    /// taller or wider than the box keeps its size.
    static func alignedChildRects(_ input: AlignedBoxInput) -> AlignedBox {
        let children = input.children
        let inline = input.inline
        let gaps = input.gap * Double(max(0, children.count - 1))
        func fromLeft(_ start: Double, _ width: Double) -> Double { input.rightToLeft ? inline - start - width : start }
        if input.axis == .block {
            let content = children.reduce(0) { $0 + $1.height } + gaps
            let block = input.block ?? max(input.minBlock ?? 0, content)
            let free = max(0, block - content)
            let shifts = Self.shifts(free: free, count: children.count, justify: input.justify)
            var cursor = 0.0
            let rects = children.enumerated().map { index, child -> AlignedRect in
                let width = child.stretch ? inline : min(child.width, inline)
                let y = cursor + shifts[index]
                cursor += child.height + input.gap
                return AlignedRect(
                    x: fromLeft(crossOffset(available: inline, size: width, align: input.align), width), y: y, width: width, height: child.height)
            }
            return AlignedBox(block: block, free: free, rects: rects)
        }
        let content = children.reduce(0) { $0 + $1.width } + gaps
        let tallest = children.reduce(0) { max($0, $1.height) }
        let block = input.block ?? tallest
        let free = max(0, inline - content)
        let shifts = Self.shifts(free: free, count: children.count, justify: input.justify)
        var cursor = 0.0
        let rects = children.enumerated().map { index, child -> AlignedRect in
            let start = cursor + shifts[index]
            cursor += child.width + input.gap
            return AlignedRect(
                x: fromLeft(start, child.width), y: crossOffset(available: block, size: child.height, align: input.align), width: child.width,
                height: child.height)
        }
        return AlignedBox(block: block, free: free, rects: rects)
    }
}
