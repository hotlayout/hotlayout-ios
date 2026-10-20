import SwiftUI

/// `Stack`: layers in one point. The kinds of the layers come from the document
/// (`LayerRules`), the places of the overlays from the theme.
struct StackView: View {
    let node: DocumentNode
    let context: RenderContext
    let depth: Int
    let stretch: Bool

    var body: some View {
        let alignH = AlignWord(node.props["alignHorizontal"]) ?? .center
        let alignV = AlignWord(node.props["alignVertical"]) ?? .center
        let kinds = LayerRules.kinds(parentType: node.type, children: node.children.map(\.fields))
        let visible = node.children.map { context.isShown($0) }
        let acting = LayerRules.acting(kinds, visible: visible)
        LayerStackLayout(alignHorizontal: alignH, alignVertical: alignV, stretch: stretch) {
            ForEach(Array(node.children.enumerated()), id: \.offset) { index, child in
                layer(child, kind: acting[index])
                    .layoutValue(key: WidthHungryKey.self, value: Self.takesPlace(child))
            }
        }
    }

    /// Whether a layer has no width of its own and takes the whole width of the stack: a picture, and a
    /// container, column or stack that holds one and names no width itself.
    static func takesPlace(_ node: DocumentNode) -> Bool {
        guard node.fields["style"]?["width"] == nil else { return false }
        switch node.type {
        case "Image": return true
        case "Container", "Column", "Stack":
            let direction = node.props["direction"]?.stringValue
            return direction != "row" && node.children.contains { takesPlace($0) }
        default: return false
        }
    }

    @ViewBuilder
    private func layer(_ child: DocumentNode, kind: LayerKind) -> some View {
        switch kind {
        case .sizing:
            NodeView(node: child, context: context, placement: .natural, depth: depth + 1, parentType: node.type)
        case .fill:
            NodeView(node: child, context: context, placement: .fillingStack, depth: depth + 1, parentType: node.type)
                .layoutValue(key: LayerRoleKey.self, value: .fill)
        case .overlay(let read):
            let place = Self.place(read, stackNode: node, resolver: context.resolver)
            // SwiftUI mirrors the turn of a view in right-to-left text by itself, so the angle
            // handed over is the one of left-to-right text (`LayerGeometry.drawnAngle` is the
            // angle as the contract states it for the mirrored layout).
            // The shift of a moving layer goes along the screen axes, after the turn of the layer.
            NodeView(node: child, context: context, placement: .natural, depth: depth + 1, parentType: node.type, motionOutside: true)
                .rotationEffect(.degrees(Double(read.rotate)))
                .nodeMotion(NodeMotion.read(child.fields["motion"]), rightToLeft: context.rightToLeft)
                .layoutValue(key: LayerRoleKey.self, value: .overlay(place))
        }
    }

    /// The own alignment word or the word of the stack; an offset whose token the theme does not
    /// know is no offset on that axis (`tokenWithoutFieldDefault: 'omit-field'`).
    static func place(_ read: LayerRead, stackNode: DocumentNode, resolver: StyleResolver) -> OverlayPlace {
        func pixels(_ axis: LayerAxisOffset?) -> (toward: String, by: Double)? {
            guard let axis, let by = resolver.spacing(axis.by.json) else { return nil }
            return (axis.toward, by)
        }
        return OverlayPlace(
            alignHorizontal: read.alignHorizontal ?? AlignWord(stackNode.props["alignHorizontal"]) ?? .center,
            alignVertical: read.alignVertical ?? AlignWord(stackNode.props["alignVertical"]) ?? .center,
            offsetX: pixels(read.offsetX), offsetY: pixels(read.offsetY), rotate: read.rotate
        )
    }
}
