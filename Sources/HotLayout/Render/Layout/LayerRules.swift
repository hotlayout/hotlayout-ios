import Foundation

/// What each layer of a `Stack` is, decided by the DOCUMENT and never by visibility
/// (`x-style.layout.layer`, `x-style.fillScope`).
enum LayerKind: Equatable {
    /// An ordinary layer: it takes its own size and measures the stack.
    case sizing
    /// A layer on the whole stack (`fill: true`): it takes the size of the stack.
    case fill
    /// An overlay (`layer`): it stands against the box of the stack and never changes it.
    case overlay(LayerRead)

    var sizesStack: Bool { self == .sizing }
    var isOverlay: Bool {
        if case .overlay = self { return true }
        return false
    }
}

enum LayerRules {
    /// The kind of every child of a parent. Outside a `Stack` neither field is read. `fill`
    /// wins over `layer`. An overlay is read only when the stack has a layer that is neither
    /// stretched nor an overlay — otherwise there is no box to stand against, and the field is
    /// read on none of them (`noSizingLayer: 'ignore-layer'`).
    static func kinds(parentType: String, children: [JSONObject]) -> [LayerKind] {
        guard parentType == "Stack" else { return children.map { _ in .sizing } }
        let fills = children.map { $0["fill"]?.boolValue == true }
        let reads: [LayerRead?] = zip(children, fills).map { fields, fill in fill ? nil : LayerRead.read(fields["layer"]) }
        let sized = zip(fills, reads).contains { !$0 && $1 == nil }
        return zip(fills, reads).map { fill, read in
            if fill { return .fill }
            if sized, let read { return .overlay(read) }
            return .sizing
        }
    }

    /// The kinds as they act NOW. `visible[i]` says whether child `i` is drawn. A stack whose
    /// DRAWN layers are all stretched has nothing to measure it by, so the stretch is not
    /// applied and the layers take their own size (`allLayersFilled: 'ignore-fill'`); in every
    /// other case the kinds stand, so an overlay never turns into a sizing layer because the
    /// sizing layer under it is hidden.
    static func acting(_ kinds: [LayerKind], visible: [Bool]) -> [LayerKind] {
        let someDrawnNotStretched = zip(kinds, visible).contains { $1 && $0 != .fill }
        guard !someDrawnNotStretched else { return kinds }
        return kinds.map { $0 == .fill ? .sizing : $0 }
    }
}
