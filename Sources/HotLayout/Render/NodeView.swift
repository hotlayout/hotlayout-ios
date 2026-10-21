import SwiftUI

/// One node of a screen: visibility, effective style, the inherited text look, the box, and
/// the widget itself.
struct NodeView: View {
    let node: DocumentNode
    let context: RenderContext
    var placement: Placement = .stretched
    var depth: Int = 0
    /// The type of the parent (`fill` is read only on a direct child of a `Stack`).
    var parentType: String?
    /// The parent paints the motion itself, outside the turn of a layer (`Stack`).
    var motionOutside = false

    var body: some View {
        if depth > DocumentReader.maxParseDepth || !context.isShown(node) {
            EmptyView()
        } else {
            let style = effectiveStyle()
            let inner = context.with(inherited: NodeStyle.inherited(context.inherited, style: style, resolver: context.resolver)).withoutPosition()
            let look = context.resolver.box(style, scope: context.scope)
            // The padding of a carousel lies inside its scroll: the first card stands a padding
            // from the edge and the last one scrolls past it.
            let carousel = CarouselRules.of(node) != nil
            let shaped = boxLook(look, carousel: carousel)
            let box = widget(inner, style: style, space: hostSpace(look), carouselPadding: carousel ? look.padding : nil)
                .modifier(WriteControlTraits(node: node, context: inner))
                .modifier(NodeBoxModifier(look: shaped.withoutMargin, placement: placementWithMainAxis, context: inner))
            // The press target is the box of the node without its margin; the motion moves that box.
            pressable(box, inner)
                .nodeMotion(motionOutside || node.widget == .screen ? nil : NodeMotion.read(node.fields["motion"]), rightToLeft: context.rightToLeft)
                .padding(shaped.margin.edgeInsets)
        }
    }

    /// The effective style; an app bar that is the zone of its screen lays its scrolled style over
    /// it while the body is scrolled.
    private func effectiveStyle() -> JSONObject {
        let style = NodeStyle.effective(node, scope: context.scope)
        guard node.widget == .appBar, context.barScrolled else { return style }
        return AppBarRules.withScrolledLayer(style, scrolled: AppBarRules.scrolledStyle(node), resolver: context.resolver)
    }

    /// A ring stands in the centre of its box; every other node keeps the placement it was given.
    private var placementWithMainAxis: Placement {
        guard node.widget == .circularProgress else { return placement }
        var centered = placement
        centered.contentAlignment = .center
        return centered
    }

    /// The heights a host can distribute along its main axis, in its content box: the box of a
    /// node includes its padding and border (`sizeIncludes`). Only the source the contract names
    /// gives free space (`AlignRules.heightSource`): a layer that fills its stack, else
    /// `style.height`, else `style.minHeight`.
    private func hostSpace(_ look: BoxLook) -> HostSpace {
        let inset = look.padding.top + look.padding.bottom + 2 * (look.borderWidth ?? 0)
        let source = AlignRules.heightSource(fields: node.fields, parent: parentType, ownHeight: look.height != nil, ownMinHeight: look.minHeight != nil)
        func content(_ value: Double?) -> CGFloat? { value.map { CGFloat(max(0, $0 - inset)) } }
        return HostSpace(
            block: source == .height ? content(look.height) : nil,
            minBlock: source == .minHeight ? content(look.minHeight) : nil,
            fills: source == .fill
        )
    }

    /// A role widget (`Button`) draws its own surface: its style lands on the button itself.
    private func boxLook(_ look: BoxLook, carousel: Bool) -> BoxLook {
        var look = look
        if carousel { look.padding = .zero }
        // The inset of the status bar lies inside the box of the app bar, above its padding.
        if node.widget == .appBar, context.barInset > 0 { look.padding.top += context.barInset }
        guard let widget = node.widget, [.button, .iconButton, .badge].contains(widget) else { return look }
        var outer = BoxLook()
        outer.surfaceDrawnByWidget = true
        outer.margin = look.margin
        outer.width = look.width
        outer.height = look.height
        outer.minWidth = look.minWidth
        outer.maxWidth = look.maxWidth
        outer.minHeight = look.minHeight
        outer.maxHeight = look.maxHeight
        outer.opacity = look.opacity
        return outer
    }

    /// Containers with an action are pressable as a whole.
    @ViewBuilder
    private func pressable(_ content: some View, _ context: RenderContext) -> some View {
        if PressTarget.containerTypes.contains(node.widget) {
            PressableCard(node: node, context: context, content: content)
        } else {
            content
        }
    }

    @ViewBuilder
    private func widget(_ context: RenderContext, style: JSONObject, space: HostSpace, carouselPadding: Sides?) -> some View {
        switch node.widget {
        case .screen, .column:
            ColumnView(
                children: node.children, gap: context.resolver.spacing(node.props["gap"] ?? "sm") ?? 0, node: node, space: space, context: context, depth: depth
            )
        case .row:
            RowView(node: node, space: space, context: context, depth: depth, carouselPadding: carouselPadding)
        case .container:
            if node.props["direction"]?.stringValue == "row" {
                RowView(node: node, space: space, context: context, depth: depth)
            } else {
                ColumnView(
                    children: node.children, gap: context.resolver.spacing(node.props["gap"] ?? "none") ?? 0, node: node, space: space, context: context,
                    depth: depth)
            }
        case .stack:
            StackView(node: node, context: context, depth: depth, stretch: placement.stretchWidth)
        case .text:
            TextRichWidget(node: node, context: context, position: self.context.listPosition)
        case .image:
            ImageWidget(node: node, context: context, look: context.resolver.box(style, scope: self.context.scope))
        case .icon:
            IconWidget(node: node, context: context, look: self.context.resolver.box(style, scope: self.context.scope))
        case .button:
            ButtonWidget(node: node, style: style, context: context)
        case .repeater:
            RepeaterWidget(node: node, context: context, depth: depth, carouselPadding: carouselPadding)
        case .grid:
            GridWidget(node: node, context: context, depth: depth)
        case .iconButton:
            IconButtonWidget(node: node, style: style, context: context)
        case .badge:
            BadgeWidget(node: node, style: style, context: context)
        case .listTile:
            ListTileWidget(node: node, context: context)
        case .accordion:
            AccordionWidget(node: node, context: context, depth: depth)
        case .tabs:
            TabsWidget(node: node, context: context, depth: depth)
        case .tab:
            // The panel is the node itself: its children in a column, `md` apart.
            ColumnView(
                children: node.children, gap: context.resolver.spacing(.string(TabsRules.panelGapToken)) ?? 12, node: nil, context: context, depth: depth)
        case .appBar:
            AppBarWidget(node: node, context: context, depth: depth)
        case .navBar:
            NavBarWidget(node: node, style: style, context: context, depth: depth)
        case .navItem:
            NavItemWidget(node: node, context: context)
        case .textField:
            InputTextFieldWidget(node: node, context: context)
        case .switch:
            InputToggleWidget(node: node, context: context, kind: .toggle)
        case .checkbox:
            InputToggleWidget(node: node, context: context, kind: .checkbox)
        case .choiceGroup:
            ChoiceGroupWidget(node: node, context: context, depth: depth)
        case .spacer:
            SpacerWidget(node: node, context: context)
        case .divider:
            DividerWidget(node: node, context: context)
        case .progressBar:
            ProgressBarWidget(node: node, context: context)
        case .circularProgress:
            // Under a row weight the width fields of the style do not name the diameter.
            CircularProgressWidget(node: node, context: context, style: style, widthApplies: !placement.stretchWidth)
        default:
            // A widget this reader does not know (`unknownWidget: 'render-children'`): its children are drawn.
            ColumnView(children: node.children, gap: 0, node: nil, space: HostSpace(), context: context, depth: depth)
                .onAppear {
                    context.sink.add(
                        .unknownWidget, "screen “\(context.screenId)”: node “\(node.id)”",
                        "“\(node.type)” is not a widget this reader knows; its children are drawn")
                }
        }
    }
}

/// Whether a child of a column keeps its natural width (`x-style.layout.column.naturalWidth`)
/// instead of stretching to the column.
func takesNaturalWidth(_ node: DocumentNode) -> Bool {
    if node.style?["width"] != nil { return true }
    switch node.widget {
    case .button: return node.props["fullWidth"]?.boolValue == false
    case .iconButton, .badge, .icon, .circularProgress: return true
    case .divider, .spacer: return node.props["orientation"]?.stringValue == "vertical"
    default: return false
    }
}

func horizontalAlignment(_ word: String?) -> Alignment {
    switch word {
    case "center": return .center
    case "end": return .trailing
    default: return .leading
    }
}

/// The heights a host can distribute along its main axis, in its content box.
struct HostSpace: Equatable {
    /// `style.height`, less padding and border.
    var block: CGFloat?
    /// `style.minHeight`, less padding and border; for the body of a screen, the visible body.
    var minBlock: CGFloat?
    /// A layer that fills its stack.
    var fills = false
}

extension ColumnView {
    static func columnPlacement(natural: Bool) -> Placement {
        var placement: Placement = natural ? .natural : .stretched
        placement.clampsWidth = true
        return placement
    }
}

/// A column: children stretch to its width, except those of natural width, which stand where
/// `align` puts them (`column.naturalWidthAlign`); `justify` distributes the free height when the
/// column has a source of it (`x-style.layout.alignment`). A child with `pull` is drawn earlier
/// by that much and the ones after it follow (`FlowPull`).
struct ColumnView: View {
    let children: [DocumentNode]
    let gap: Double
    /// The node whose `align` and `justify` act; `nil` for a stand-in column (no fields).
    let node: DocumentNode?
    var space = HostSpace()
    let context: RenderContext
    let depth: Int
    /// The first child pulls nothing (the nodes of the top zone: there is nothing above them).
    var ignoresFirstPull = false

    /// How far a child is pulled toward the start of the column (`pull`).
    private func pull(of child: DocumentNode) -> CGFloat {
        if ignoresFirstPull, child.id == children.first?.id { return 0 }
        guard let node, let read = FlowPull.read(node: child, parentType: node.type, parentProps: node.props), read.axis == .column,
            context.isShown(child)
        else { return 0 }
        return CGFloat(context.resolver.spacing(read.by.json) ?? 0)
    }

    var body: some View {
        let siblings = ListSiblings(children: children, context: context)
        let read = node.flatMap { AlignRules.read(type: $0.type, props: $0.props) }
        ColumnLayout(
            gap: CGFloat(gap), align: read?.align ?? .start, justify: read?.justify ?? .start,
            block: space.block, minBlock: space.minBlock, fillsProposal: space.fills
        ) {
            ForEach(Array(children.enumerated()), id: \.offset) { index, child in
                NodeView(
                    node: child, context: context.at(siblings, index), placement: Self.columnPlacement(natural: takesNaturalWidth(child)), depth: depth + 1,
                    parentType: node?.type
                )
                .layoutValue(key: FlowPullAmount.self, value: pull(of: child))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A row (or a container with `direction: row`).
struct RowView: View {
    let node: DocumentNode
    var space = HostSpace()
    let context: RenderContext
    let depth: Int
    /// The padding of the node when it is a carousel (drawn inside the scroll).
    var carouselPadding: Sides?

    var body: some View {
        let isContainer = node.widget == .container
        let gap = context.resolver.spacing(node.props["gap"] ?? (isContainer ? "none" : "sm")) ?? 0
        // An unknown word acts as without the field: `start` on the main axis, `center` across.
        let justify = node.props["justify"]?.stringValue.flatMap(JustifyWord.init(rawValue:)) ?? .start
        let align = node.props["align"]?.stringValue.flatMap(AlignWord.init(rawValue:)) ?? .center
        let vertical: VerticalAlignment = align == .start ? .top : align == .end ? .bottom : .center
        let siblings = ListSiblings(children: node.children, context: context)
        if let spec = CarouselRules.of(node) {
            CarouselView(
                setup: CarouselSetup.make(spec: spec, node: node, gap: gap, padding: carouselPadding ?? .zero, vertical: vertical, context: context),
                count: node.children.count
            ) { index, width in
                NodeView(
                    node: node.children[index], context: context.at(siblings, index), placement: Self.cardPlacement(width: width), depth: depth + 1,
                    parentType: node.type)
            }
        } else if node.props["scrollable"]?.boolValue == true {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: vertical, spacing: gap) {
                    ForEach(Array(node.children.enumerated()), id: \.offset) { index, child in
                        NodeView(node: child, context: context.at(siblings, index), placement: .natural, depth: depth + 1, parentType: node.type)
                    }
                }
            }
        } else {
            RowLayout(gap: gap, justify: justify, align: align, block: space.block, fillsProposal: space.fills) {
                ForEach(Array(node.children.enumerated()), id: \.offset) { index, child in
                    let weight = Self.weight(of: child)
                    NodeView(
                        node: child, context: context.at(siblings, index), placement: weight == nil ? .natural : .stretched, depth: depth + 1,
                        parentType: node.type
                    )
                    .layoutValue(key: RowWeight.self, value: weight)
                    .layoutValue(key: FlowPullAmount.self, value: pull(of: child))
                }
            }
        }
    }

    /// How far a child is pulled toward the start of the row (`pull`); a weight that acts wins.
    private func pull(of child: DocumentNode) -> CGFloat {
        guard let read = FlowPull.read(node: child, parentType: node.type, parentProps: node.props), read.axis == .row,
            context.isShown(child)
        else { return 0 }
        return CGFloat(context.resolver.spacing(read.by.json) ?? 0)
    }

    /// The weight of a child: a positive whole number (`invalidWeight: 'no-weight'`); a child
    /// that stretches without one takes a share of one (`unweightedStretchInRow`).
    static func weight(of child: DocumentNode) -> Double? {
        if let weight = child.fields["weight"]?.numberValue, weight >= 1, weight == weight.rounded() { return weight }
        if child.style?["width"] != nil { return nil }
        switch child.widget {
        case .button where child.props["fullWidth"]?.boolValue != false: return 1
        case .divider, .spacer: return child.props["orientation"]?.stringValue == "vertical" ? nil : 1
        case .progressBar: return 1
        default: return nil
        }
    }
}
