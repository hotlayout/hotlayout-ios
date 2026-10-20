import SwiftUI

/// `Image`: the width is given by the place, the height by the proportion unless the node names
/// one (`x-style.layout.image`). The file is never asked for its own size. The corner radius of
/// the node box clips the picture; a square with half its side as the radius is a circle.
struct ImageWidget: View {
    let node: DocumentNode
    let context: RenderContext
    let look: BoxLook

    /// The vertical room the padding and the border of the node take from its height.
    private var inset: Double { look.padding.top + look.padding.bottom + 2 * (look.borderWidth ?? 0) }

    var body: some View {
        let fit = node.props["fit"]?.stringValue == "contain" ? "contain" : "cover"
        let placeholder = context.theme.colorValue("muted")?.withOpacity(0.15).color ?? Color.gray.opacity(0.15)
        let source = node.props["source"] ?? ["kind": "asset", "asset": "placeholder"]
        let picture = RemoteImage(url: ImageSource.url(source, context: context), fit: fit, placeholder: placeholder, sink: context.sink)
        Group {
            if look.height != nil {
                // The node box gives the named height (and the limits); the proportion is not read.
                picture.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ImageBoxLayout(
                    aspectRatio: node.props["aspectRatio"],
                    minHeight: look.minHeight.map { max(0, $0 - inset) },
                    maxHeight: look.maxHeight.map { max(0, $0 - inset) }
                ) { picture }
            }
        }
        .clipped()
        .accessibilityElement()
        .accessibilityLabel(altText)
        .accessibilityAddTraits(.isImage)
        .accessibilityHidden(altText.isEmpty)
    }

    /// `alt` is a string or a string of the document (a binding or a template); an empty one
    /// hides the picture from VoiceOver.
    var altText: String {
        guard let alt = node.props["alt"] else { return "" }
        if let literal = alt.stringValue { return ShownText.of(literal) }
        return context.text(node, field: "alt")
    }
}

/// The box of a picture with no named height: as wide as the place offers, as high as the
/// proportion says (held between the limits). With no width on offer the box is empty.
struct ImageBoxLayout: Layout {
    let aspectRatio: JSONValue?
    let minHeight: Double?
    let maxHeight: Double?

    private func box(_ proposal: ProposedViewSize) -> CGSize {
        let width = proposal.width.flatMap { $0.isFinite ? Double($0) : nil } ?? 0
        let box = ImageRules.box(aspectRatio: aspectRatio, width: width, height: nil, minHeight: minHeight, maxHeight: maxHeight)
        return CGSize(width: box.width, height: box.height)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize { box(proposal) }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for view in subviews { view.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size)) }
    }
}
