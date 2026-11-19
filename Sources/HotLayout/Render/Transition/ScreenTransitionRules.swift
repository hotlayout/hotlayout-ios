import Foundation

/// What happened to the stack of screens in one step.
enum StackStep: String, Equatable {
    /// The first show, a new entry, a stack the host built anew: always at once.
    case start
    /// The stack grew by one (`navigate`).
    case push
    /// The stack became shorter by one (`navigate.back`, the scrim, Escape, a drag that closes a sheet).
    case pop
    /// A section was switched (`navigate.section`, an item of a navigation bar).
    case `switch`
}

/// How a screen asks to come and go (`transition` of a screen entry). Only a word of the list
/// counts: anything else is no field.
enum ScreenTransitionWord: String, Equatable {
    /// A cross-dissolve: a page fades out over the new one, a layer changes its opacity only.
    case fade
    /// At once.
    case none

    static func of(_ value: JSONValue?) -> ScreenTransitionWord? {
        value?.stringValue.flatMap(ScreenTransitionWord.init(rawValue:))
    }
}

/// A screen as the transition sees it: three fields of its entry.
struct TransitionScreen: Equatable {
    /// The screen is laid over another one (the EFFECTIVE presentation: the first screen of a stack is a page).
    var modal = false
    /// The `modalPlacement` word, whatever it is (`WideChrome.modalShape` knows what it means).
    var placement: JSONValue?
    var transition: ScreenTransitionWord?
}

/// What the reader plays.
enum TransitionMotion: String, Equatable {
    case none
    case push
    case pop
    case crossfade
    case sheetIn = "sheet-in"
    case sheetOut = "sheet-out"
    case windowIn = "window-in"
    case windowOut = "window-out"
    case layerFadeIn = "layer-fade-in"
    case layerFadeOut = "layer-fade-out"

    /// A layer (a sheet, a window, or only its opacity) comes or goes.
    var isLayer: Bool {
        switch self {
        case .sheetIn, .sheetOut, .windowIn, .windowOut, .layerFadeIn, .layerFadeOut: return true
        default: return false
        }
    }

    var isLayerIn: Bool { self == .sheetIn || self == .windowIn || self == .layerFadeIn }

    /// Two whole stacks change places: the one that goes is kept beside the one that comes.
    var isPage: Bool { self == .push || self == .pop || self == .crossfade }
}

/// Why nothing moves.
enum StillReason: String, Equatable {
    case start
    case reducedMotion = "reduced-motion"
    case covered
    case dragged
    case section
    case fieldNone = "field-none"
}

/// What happens to the scrim (and the blur behind it) under a layer.
enum ScrimMotion: String, Equatable {
    /// It comes and goes with the layer: a page is on the other side.
    case fade
    /// It stays: a layer is on the other side.
    case still
}

/// A planned motion of a step: the motion and its numbers, or nothing and the reason.
struct ScreenTransitionPlan: Equatable {
    var motion: TransitionMotion
    /// Why nothing moves; `nil` when something does.
    var reason: StillReason?
    var durationMs: Double
    var curve: VisibilityFade.Curve
    /// `push` and `pop`: the share of the width the page beneath moves.
    var parallax: Double?
    /// `window-in`: the scale the window grows from.
    var scaleFrom: Double?
    /// A layer's motion: what the scrim does.
    var scrim: ScrimMotion?

    var moves: Bool { motion != .none }

    static func still(_ reason: StillReason) -> ScreenTransitionPlan {
        ScreenTransitionPlan(motion: .none, reason: reason, durationMs: 0, curve: ScreenTransition.linearCurve)
    }
}

/// One layer at a moment of a motion: a shift as a share of the screen width (`x`) or of the layer's
/// own height (`y`), an opacity and a scale.
struct TransitionLayerFrame: Equatable {
    var x = 0.0
    var y = 0.0
    var opacity = 1.0
    var scale = 1.0
}

/// Both screens and the scrim at a moment of a motion.
struct ScreenTransitionFrame: Equatable {
    /// The screen that comes (the new top of the stack).
    var incoming: TransitionLayerFrame
    /// The screen that goes (the old top).
    var outgoing: TransitionLayerFrame
    /// The share of the resting opacity of the scrim under a layer: 1 at rest, 0 not seen.
    var scrim: Double
}

/// Default transitions between screens (`x-screenTransition`): which motion a step of the stack
/// plays, and where both screens stand at a moment of it. The numbers are the contract's, the same
/// on every platform. The views that play it are in `StackTransitionView`.
enum ScreenTransition {
    static let field = "transition"

    static let decelerate = VisibilityFade.Curve(x1: 0.2, y1: 0, x2: 0, y2: 1)
    static let accelerate = VisibilityFade.Curve(x1: 0.4, y1: 0, x2: 1, y2: 1)
    static let standardFade = VisibilityFade.Curve(x1: 0.4, y1: 0, x2: 0.2, y2: 1)
    static let linearCurve = VisibilityFade.Curve(x1: 0, y1: 0, x2: 1, y2: 1)

    static let pageMs = 300.0
    static let pageParallax = 0.3
    static let sheetOpenMs = 280.0
    static let sheetCloseMs = 220.0
    static let windowOpenMs = 200.0
    static let windowCloseMs = 150.0
    static let windowScaleFrom = 0.96
    static let fadeMs = 200.0

    private static func plan(
        _ motion: TransitionMotion, _ ms: Double, _ curve: VisibilityFade.Curve, parallax: Double? = nil, scaleFrom: Double? = nil,
        scrim: ScrimMotion? = nil
    ) -> ScreenTransitionPlan {
        ScreenTransitionPlan(motion: motion, reason: nil, durationMs: ms, curve: curve, parallax: parallax, scaleFrom: scaleFrom, scrim: scrim)
    }

    private static func layerIn(from: TransitionScreen, to: TransitionScreen, word: ScreenTransitionWord?, areaWidth: Double) -> ScreenTransitionPlan {
        let scrim: ScrimMotion = from.modal ? .still : .fade
        if word == .fade { return plan(.layerFadeIn, fadeMs, standardFade, scrim: scrim) }
        if WideChrome.modalShape(placement: to.placement, areaWidth: areaWidth) == .sheet {
            return plan(.sheetIn, sheetOpenMs, decelerate, scrim: scrim)
        }
        return plan(.windowIn, windowOpenMs, decelerate, scaleFrom: windowScaleFrom, scrim: scrim)
    }

    private static func layerOut(
        leaving: TransitionScreen, to: TransitionScreen, word: ScreenTransitionWord?, areaWidth: Double, dragged: Bool
    ) -> ScreenTransitionPlan {
        let scrim: ScrimMotion = to.modal ? .still : .fade
        if word == .fade { return plan(.layerFadeOut, fadeMs, standardFade, scrim: scrim) }
        if WideChrome.modalShape(placement: leaving.placement, areaWidth: areaWidth) == .sheet {
            if dragged { return .still(.dragged) }
            return plan(.sheetOut, sheetCloseMs, accelerate, scrim: scrim)
        }
        return plan(.windowOut, windowCloseMs, accelerate, scrim: scrim)
    }

    private static func page(_ motion: TransitionMotion) -> ScreenTransitionPlan {
        plan(motion, pageMs, decelerate, parallax: pageParallax)
    }

    private static let crossfade = plan(.crossfade, fadeMs, standardFade)

    /// How the reader shows a step of the stack. The order of the checks is part of the rule: `start`,
    /// reduced motion, the fill of a swipe button, the word of the screen that decides, then the shape.
    ///
    /// `from` is the top screen before the step (`nil` at `start`), `to` after it; `areaWidth` is the
    /// width of the area the host gave the stack, which decides between a sheet and a window.
    static func plan(
        step: StackStep, from: TransitionScreen?, to: TransitionScreen, areaWidth: Double, reducedMotion: Bool = false, covered: Bool = false,
        dragged: Bool = false
    ) -> ScreenTransitionPlan {
        guard step != .start, let from else { return .still(.start) }
        if reducedMotion { return .still(.reducedMotion) }
        if covered { return .still(.covered) }
        if step == .pop {
            if from.transition == ScreenTransitionWord.none { return .still(.fieldNone) }
            if from.modal { return layerOut(leaving: from, to: to, word: from.transition, areaWidth: areaWidth, dragged: dragged) }
            return from.transition == .fade ? crossfade : page(.pop)
        }
        let word = to.transition
        if word == ScreenTransitionWord.none { return .still(.fieldNone) }
        if step == .switch {
            guard word == .fade else { return .still(.section) }
            return to.modal ? layerIn(from: from, to: to, word: word, areaWidth: areaWidth) : crossfade
        }
        if to.modal { return layerIn(from: from, to: to, word: word, areaWidth: areaWidth) }
        return word == .fade ? crossfade : page(.push)
    }

    private static let rest = TransitionLayerFrame()

    /// Where both screens stand `elapsedMs` after the motion began. `x` is positive toward the end
    /// edge (the view mirrors the sign in a right-to-left language). Past the duration it is the final state.
    static func frame(_ plan: ScreenTransitionPlan, at elapsedMs: Double) -> ScreenTransitionFrame {
        guard plan.moves else { return ScreenTransitionFrame(incoming: rest, outgoing: TransitionLayerFrame(opacity: 0), scrim: 1) }
        let share = plan.durationMs <= 0 ? 1 : elapsedMs / plan.durationMs
        let e = VisibilityFade.bezier(plan.curve, at: share)
        let fades = plan.scrim == .fade
        let scrimIn = fades ? e : 1
        let scrimOut = fades ? 1 - e : 1
        let parallax = plan.parallax ?? 0
        switch plan.motion {
        case .none:
            return ScreenTransitionFrame(incoming: rest, outgoing: rest, scrim: 1)
        case .push:
            return ScreenTransitionFrame(incoming: TransitionLayerFrame(x: 1 - e), outgoing: TransitionLayerFrame(x: -parallax * e), scrim: 1)
        case .pop:
            return ScreenTransitionFrame(incoming: TransitionLayerFrame(x: -parallax * (1 - e)), outgoing: TransitionLayerFrame(x: e), scrim: 1)
        case .crossfade:
            return ScreenTransitionFrame(incoming: rest, outgoing: TransitionLayerFrame(opacity: 1 - e), scrim: 1)
        case .sheetIn:
            return ScreenTransitionFrame(incoming: TransitionLayerFrame(y: 1 - e), outgoing: rest, scrim: scrimIn)
        case .sheetOut:
            return ScreenTransitionFrame(incoming: rest, outgoing: TransitionLayerFrame(y: e), scrim: scrimOut)
        case .windowIn:
            let from = plan.scaleFrom ?? 1
            return ScreenTransitionFrame(incoming: TransitionLayerFrame(opacity: e, scale: from + (1 - from) * e), outgoing: rest, scrim: scrimIn)
        case .layerFadeIn:
            return ScreenTransitionFrame(incoming: TransitionLayerFrame(opacity: e), outgoing: rest, scrim: scrimIn)
        case .windowOut, .layerFadeOut:
            return ScreenTransitionFrame(incoming: rest, outgoing: TransitionLayerFrame(opacity: 1 - e), scrim: scrimOut)
        }
    }
}
