import SwiftUI

extension StackStep {
    /// The step a shown screen came by.
    init(_ cause: ScreenShownCause?) {
        switch cause {
        case .forward?: self = .push
        case .back?: self = .pop
        case .switch?: self = .switch
        case .entry?, nil: self = .start
        }
    }
}

private struct StackTransitionFreezeKey: EnvironmentKey {
    static let defaultValue: Double? = nil
}

extension EnvironmentValues {
    /// A fixed moment (ms after the step began) at which every step of the stack stays, instead of playing;
    /// the tests use it to read the real screen in the middle of a motion.
    var stackTransitionFreezeMs: Double? {
        get { self[StackTransitionFreezeKey.self] }
        set { self[StackTransitionFreezeKey.self] = newValue }
    }
}

/// A step of the stack that is being played: the plan, the stack before the step, and the generation of
/// the stack that goes (when two whole stacks change places).
struct RunningTransition: Equatable {
    let id: Int
    let plan: ScreenTransitionPlan
    let outgoing: Flow
    let ghostGeneration: Int
}

/// The width of the area the host gave the stack, as of the last draw.
final class AreaWidth {
    var width = 0.0
}

/// What the stack is drawn in: the width and the insets of the area and the language.
struct StackSpace {
    let width: Double
    let insets: ScreenInsets
    let place: HotlayoutScreen.ScreenPlace
}

/// A stack that is on the screen: the current one, or the one that goes while a page motion plays.
struct StackSlot: Identifiable {
    let id: Int
    let frames: [FlowFrame]
    let isGhost: Bool
}

/// The layer that has left the stack and goes while its motion plays.
struct GhostLayer {
    let frame: FlowFrame
    let screen: ScreenEntry
    let index: Int
}

extension HotlayoutScreen {
    /// The screen on top of a stack as the transition sees it: a modal layer only when it is not the first screen.
    func transitionScreen(of flow: Flow) -> TransitionScreen? {
        guard let top = flow.top, let screen = document.screen(top.screenId) else { return nil }
        return TransitionScreen(
            modal: flow.stack.count > 1 && screen.presentation == .modal, placement: screen.placement.map { .string($0.rawValue) },
            transition: screen.transition)
    }

    func stackSlots(_ flow: Flow) -> [StackSlot] {
        var slots = [StackSlot(id: generation, frames: flow.stack, isGhost: false)]
        if let running, running.plan.motion.isPage {
            slots.insert(StackSlot(id: running.ghostGeneration, frames: running.outgoing.stack, isGhost: true), at: 0)
        }
        return slots
    }

    /// The layer that goes with the motion of a step that closed it.
    func ghostLayer(of running: RunningTransition, space: StackSpace) -> GhostLayer? {
        let plan = running.plan.motion
        guard plan.isLayer, !plan.isLayerIn, let frame = running.outgoing.stack.last, let screen = document.screen(frame.screenId) else { return nil }
        return GhostLayer(frame: frame, screen: screen, index: running.outgoing.stack.count - 1)
    }

    /// The page and the layers over it for a stack of frames.
    func stack(_ frames: [FlowFrame], space: StackSpace, motion: StackMotion? = nil, ghostLayer: GhostLayer? = nil, gone: Bool = false) -> some View {
        let pageIndex =
            frames.lastIndex { frame in
                frame == frames.first || document.screen(frame.screenId)?.presentation != .modal
            } ?? 0
        let pageScreen = frames.indices.contains(pageIndex) ? document.screen(frames[pageIndex].screenId) : nil
        let layerScreens = Dictionary(
            uniqueKeysWithValues: frames.indices.filter { $0 > pageIndex }.compactMap { index in document.screen(frames[index].screenId).map { (index, $0) } })
        func entry(_ id: Int, _ screen: ScreenEntry, ghost: Bool) -> ModalStackLayer {
            let placement = screen.placement.map { JSONValue.string($0.rawValue) }
            return ModalStackLayer(
                id: id, shape: WideChrome.modalShape(placement: placement, areaWidth: space.width), placement: placement, blur: screen.backdropBlur,
                dismissible: screen.dismissible, ghost: ghost)
        }
        var layers = layerScreens.keys.sorted().compactMap { index in layerScreens[index].map { entry(index, $0, ghost: false) } }
        if let ghostLayer { layers.append(entry(ghostLayer.index, ghostLayer.screen, ghost: true)) }
        return ModalStack(
            layers: layers,
            margin: StyleResolver(theme: themeSet.theme(themeId)).spacing(.string("xl")) ?? ModalRules.defaultMargin,
            insets: space.insets,
            motion: motion,
            gone: gone,
            dismiss: dismissLayer,
            page: {
                if let pageScreen {
                    screenView(pageScreen, frame: frames[pageIndex], index: pageIndex, place: space.place, insets: space.insets, asLayer: false)
                        // Keyed by the place in the stack and the screen, as in the other readers: the page that
                        // replaces another is a new view, so it starts at its top instead of inheriting the
                        // scroll of the screen it replaced (SwiftUI would reuse the same scroll view).
                        .id("\(pageIndex)/\(pageScreen.screenId)")
                } else {
                    Color.clear
                }
            },
            layer: { layer in
                let shown = layer.ghost ? ghostLayer.map { ($0.screen, $0.frame) } : layerScreens[layer.id].map { ($0, frames[layer.id]) }
                if let (screen, frame) = shown {
                    // A layer holds no top inset; a sheet holds the bottom one under its content, a window none.
                    screenView(
                        screen, frame: frame, index: layer.id, place: space.place,
                        insets: ScreenInsets(top: 0, bottom: layer.shape == .sheet ? space.insets.bottom : 0), asLayer: true,
                        sheetWindow: layer.shape == .sheetWindow)
                }
            }
        )
    }

    /// Puts a new stack on the screen and plays the step that made it, as the plan of the contract says. A
    /// new step finishes the one before it at once: the stack is then the one that came.
    func show(_ updated: Flow, step: StackStep, dragged: Bool = false) {
        let before = currentFlow
        carousels.prune(frames: updated.stack.map(\.screenId))
        let plan = ScreenTransition.plan(
            step: step, from: transitionScreen(of: before), to: transitionScreen(of: updated) ?? TransitionScreen(), areaWidth: area.width,
            reducedMotion: reduceMotion, covered: ripples.covers, dragged: dragged)
        var transaction = Transaction()
        transaction.disablesAnimations = true
        let id = (running?.id ?? 0) + 1
        withTransaction(transaction) {
            self.flow = updated
            elapsedMs = 0
            guard plan.moves else {
                running = nil
                return
            }
            running = RunningTransition(id: id, plan: plan, outgoing: before, ghostGeneration: generation)
            if plan.motion.isPage { generation += 1 }
            if let freezeMs { elapsedMs = min(max(0, freezeMs), plan.durationMs) }
        }
        guard plan.moves, freezeMs == nil else { return }
        let seconds = plan.durationMs / 1000
        // After the first frame, which stands at the start of the motion.
        DispatchQueue.main.async {
            guard running?.id == id else { return }
            withAnimation(.linear(duration: seconds)) { elapsedMs = plan.durationMs }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds + 0.05) {
            if running?.id == id { running = nil }
        }
    }
}
