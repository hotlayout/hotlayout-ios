import SwiftUI

/// Which column of a list row a subview is; a subview that names none takes no part.
enum ListTileColumn { case leading, body, trailing, none }

struct ListTileColumnKey: LayoutValueKey {
    static let defaultValue = ListTileColumn.none
}

/// The three columns of a list row, placed by `ListTileRules.rowRects`: the leading and the
/// trailing column take their own size, the texts the rest of the width, each centred on the
/// height of the row. The rectangles are left-to-right; SwiftUI mirrors a custom layout in
/// right-to-left text.
struct ListTileRowLayout: Layout {
    let gap: Double

    private struct Measured {
        var rects: ListTileRules.RowRects
        var leading: LayoutSubview?
        var body: LayoutSubview?
        var trailing: LayoutSubview?
    }

    private func measure(_ width: Double?, _ subviews: Subviews) -> Measured {
        func column(_ which: ListTileColumn) -> LayoutSubview? { subviews.first { $0[ListTileColumnKey.self] == which } }
        func own(_ subview: LayoutSubview?) -> (inline: Double, block: Double)? {
            subview.map {
                let size = $0.sizeThatFits(.unspecified)
                return (Double(size.width), Double(size.height))
            }
        }
        let leading = column(.leading)
        let body = column(.body)
        let trailing = column(.trailing)
        let leadingSize = own(leading)
        let trailingSize = own(trailing)
        let natural = body.map { Double($0.sizeThatFits(.unspecified).width) } ?? 0
        let rowInline = width ?? ((leadingSize.map { $0.inline + gap } ?? 0) + natural + (trailingSize.map { $0.inline + gap } ?? 0))
        // The width of the texts comes first; their height at that width is the body's block.
        let first = ListTileRules.rowRects(rowInline: rowInline, gap: gap, leading: leadingSize, trailing: trailingSize, bodyBlock: 0, rightToLeft: false)
        let bodyBlock = body.map { Double($0.sizeThatFits(ProposedViewSize(width: CGFloat(first.body.width), height: nil)).height) } ?? 0
        let rects = ListTileRules.rowRects(
            rowInline: rowInline, gap: gap, leading: leadingSize, trailing: trailingSize, bodyBlock: bodyBlock, rightToLeft: false)
        return Measured(rects: rects, leading: leading, body: body, trailing: trailing)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let measured = measure(proposal.width.map(Double.init), subviews)
        let width = proposal.width ?? CGFloat(measured.rects.body.x + measured.rects.body.width + (measured.rects.trailing.map { gap + $0.width } ?? 0))
        return CGSize(width: width, height: CGFloat(measured.rects.block))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let measured = measure(Double(bounds.width), subviews)
        func place(_ subview: LayoutSubview?, _ rect: ListTileRules.Rect?) {
            guard let subview, let rect else { return }
            subview.place(
                at: CGPoint(x: bounds.minX + CGFloat(rect.x), y: bounds.minY + CGFloat(rect.y)),
                proposal: ProposedViewSize(width: CGFloat(rect.width), height: CGFloat(rect.height))
            )
        }
        place(measured.leading, measured.rects.leading)
        place(measured.body, measured.rects.body)
        place(measured.trailing, measured.rects.trailing)
    }
}

/// The trailing text over its caption, both pushed to the end (`ListTileRules.trailingColumn`).
/// The first subview is the text line, the second, if any, the caption.
struct ListTileTrailingLayout: Layout {
    private func column(_ subviews: Subviews) -> (ListTileRules.TrailingColumn, [CGSize]) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let text = sizes.first ?? .zero
        let caption = sizes.count > 1 ? (inline: Double(sizes[1].width), line: Double(sizes[1].height)) : nil
        return (ListTileRules.trailingColumn(textInline: Double(text.width), textLine: Double(text.height), caption: caption), sizes)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let (column, _) = column(subviews)
        return CGSize(width: column.inline, height: column.block)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let (column, sizes) = column(subviews)
        guard let text = subviews.first else { return }
        text.place(at: CGPoint(x: bounds.minX + CGFloat(column.textStart), y: bounds.minY), proposal: ProposedViewSize(sizes[0]))
        if subviews.count > 1, let start = column.captionStart {
            subviews[1].place(at: CGPoint(x: bounds.minX + CGFloat(start), y: bounds.minY + sizes[0].height), proposal: ProposedViewSize(sizes[1]))
        }
    }
}
