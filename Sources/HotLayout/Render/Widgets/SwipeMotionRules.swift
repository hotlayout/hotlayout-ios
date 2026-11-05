import Foundation

/// The motion of «swipe to confirm» (`Button.confirmTransition: 'ripple'`, block `x-swipeConfirmMotion`),
/// as pure functions: nothing here draws.
///
/// While the thumb is dragged a fill of the thumb's colour follows it and the label fades with
/// the travel. Released past the threshold, the button collapses into a circle holding the busy
/// indicator; with `ripple` that circle then grows over the whole screen, the action runs under the
/// fill and the next screen shows from under it.
enum SwipeMotion {
    /// The field of the button and its only word; anything else is no field.
    static let field = "confirmTransition"
    static let rippleWord = "ripple"

    /// The actions whose change of screen the reader performs itself: only they can be led by the fill.
    static let rippleActionTypes = ["navigate", "navigate.back"]

    static let collapseMs = 600.0
    static let collapseCurve = VisibilityFade.Curve(x1: 0.4, y1: 0, x2: 0.2, y2: 1)
    static let rippleMs = 800.0
    static let revealMs = 200.0
    static let haloOpacity = 0.4

    static func readsRipple(_ props: JSONObject) -> Bool { props[field]?.stringValue == rippleWord }

    private static func clamp01(_ value: Double) -> Double { value.isFinite ? min(1, max(0, value)) : 0 }

    // MARK: Dragging

    /// The opacity of the label for a share of the travel.
    static func labelOpacity(_ progress: Double) -> Double { 1 - clamp01(progress) }

    /// A strip from the inline start of the button.
    struct Strip: Equatable {
        var start: Double
        var width: Double
    }

    /// The fill behind the thumb: from the place of rest of the thumb to its far edge. At rest it is exactly the thumb.
    static func trail(_ track: SwipeConfirmRules.Track, progress: Double) -> Strip {
        let geometry = SwipeConfirmRules.geometry(track)
        return Strip(start: max(0, track.border) + max(0, track.inset), width: clamp01(progress) * geometry.travel + geometry.diameter)
    }

    /// The radius of the thumb and of the fill behind it, concentric with the track: the radius of the track
    /// minus the inset, never below zero. `radius` is the real radius of the track (`style.radius`, or the
    /// radius of the theme role of a button without a style); it is capped at half the height first, so a pill
    /// track keeps the thumb a circle. A radius that is not known gives the circle.
    static func thumbRadius(_ track: SwipeConfirmRules.Track, radius: Double?) -> Double {
        let circle = SwipeConfirmRules.geometry(track).diameter / 2
        guard let radius, !radius.isNaN else { return circle }
        let actual = min(max(0, radius), max(0, track.height) / 2)
        return min(circle, max(0, actual - max(0, track.inset)))
    }

    // MARK: The circle

    /// One frame of the collapse: the pill, its ring, and the opacity of the surface of the button and of the halo.
    struct CollapseFrame: Equatable {
        var start: Double
        var width: Double
        var height: Double
        var ring: Double
        var surfaceOpacity: Double
        var haloOpacity: Double
    }

    /// The collapse `elapsed` milliseconds after its start: the pill narrows from the width of the button to a
    /// circle the height of the button, towards the CENTRE of the box.
    static func collapse(_ track: SwipeConfirmRules.Track, elapsed: Double) -> CollapseFrame {
        let eased = VisibilityFade.bezier(collapseCurve, at: clamp01(elapsed / collapseMs))
        let height = max(0, track.height)
        let full = max(height, track.width)
        let width = full - (full - height) * eased
        return CollapseFrame(
            start: (track.width - width) / 2, width: width, height: height, ring: max(0, track.border) + max(0, track.inset),
            surfaceOpacity: 1 - eased, haloOpacity: haloOpacity * eased)
    }

    // MARK: The fill over the screen

    /// The final scale of the circle: its core covers the farthest corner of the screen.
    static func rippleScale(centerX: Double, centerY: Double, screenWidth: Double, screenHeight: Double, core: Double) -> Double {
        let dx = max(centerX, screenWidth - centerX)
        let dy = max(centerY, screenHeight - centerY)
        let radius = core / 2
        guard radius > 0 else { return 1 }
        return max(1, (dx * dx + dy * dy).squareRoot() / radius)
    }

    /// The scale of the circle `elapsed` milliseconds after the fill started: linear.
    static func rippleAt(scale: Double, elapsed: Double) -> Double {
        1 + (max(1, scale) - 1) * clamp01(elapsed / rippleMs)
    }

    /// The opacity of the fill `elapsed` milliseconds after the next screen began to show.
    static func revealAt(_ elapsed: Double) -> Double { 1 - clamp01(elapsed / revealMs) }

    // MARK: Order

    enum Step: String, Equatable { case act, glide, collapse, busy, ripple, reveal, expand, giveBack = "return" }
    enum Way: String { case swipe, keyboard }

    /// Whether the fill plays: after a swipe, on an action the reader performs itself, without «reduce motion».
    static func ripplePlays(runner: SwipeConfirmRules.Runner, actionType: String, ripple: Bool, way: Way, reducedMotion: Bool) -> Bool {
        ripple && way == .swipe && !reducedMotion && runner == .reader && rippleActionTypes.contains(actionType)
    }

    /// The steps after a release. With the fill the action goes AFTER it, so the next screen stands under the fill.
    static func sequence(runner: SwipeConfirmRules.Runner, actionType: String, ripple: Bool, way: Way, reducedMotion: Bool) -> [Step] {
        if runner == .none || runner == .invalid { return [.act, .giveBack] }
        if ripplePlays(runner: runner, actionType: actionType, ripple: ripple, way: way, reducedMotion: reducedMotion) {
            return [.glide, .collapse, .ripple, .act, .reveal]
        }
        return reducedMotion ? [.act, .busy] : [.act, .glide, .collapse, .busy]
    }

    /// How «busy» ends: the circle expands back, then the thumb returns; under «reduce motion» it only returns.
    static func busyReturn(reducedMotion: Bool) -> [Step] { reducedMotion ? [.giveBack] : [.expand, .giveBack] }

    // MARK: The block of the artifact

    /// The block `x-swipeConfirmMotion` of the artifact, whole.
    static let rules: JSONValue = [
        "on": ["Button"],
        "when": "confirm-is-swipe",
        "refines": ["x-swipeConfirm.label", "x-swipeConfirmBusy.busy.thumb", "x-swipeConfirmBusy.release.atOrPastThreshold"],
        "drag": [
            "trail": "from-the-rest-place-of-the-thumb-to-its-far-edge-the-height-radius-and-fill-of-the-thumb-under-the-thumb",
            "labelOpacity": "one-minus-the-progress",
        ],
        "thumbShape": [
            "radius": "the-track-radius-minus-the-inset-never-below-zero-concentric-with-the-track",
            "trackRadius": "the-actual-radius-of-the-button-its-style-radius-or-else-the-radius-of-its-theme-role-capped-at-half-the-height",
            "inset": "x-swipeConfirm.thumb.inset",
            "pill": "a-track-radius-of-half-the-height-or-more-keeps-the-thumb-a-circle",
            "trail": "the-radius-of-the-thumb-on-every-corner-no-corner-sticks-out",
            "unchanged": "the-collapse-circle-the-halo-and-the-ripple-stay-round",
        ],
        "collapse": [
            "durationMs": 600,
            "curve": [0.4, 0, 0.2, 1],
            "after": "the-glide-to-the-end",
            "shape": "a-pill-the-height-of-the-button-narrowing-to-a-circle-at-the-centre-of-the-box",
            "core": "the-fill-of-the-thumb-inset-by-the-border-plus-the-inset-on-every-side",
            "halo": "the-fill-of-the-thumb-at-halo-opacity-between-the-core-and-the-edge",
            "haloOpacity": 0.4,
            "surface": "the-background-border-and-shadow-of-the-button-fade-out",
            "label": "hidden",
            "indicator": "the-busy-indicator-of-x-swipeConfirmBusy-at-the-centre",
            "layout": "unchanged-the-box-keeps-its-size",
        ],
        "busyLook": "the-collapsed-circle",
        "expand": "the-collapse-played-backwards-then-the-thumb-returns",
        "field": "confirmTransition",
        "words": ["ripple"],
        "noField": "the-screen-changes-as-usual",
        "ripple": [
            "durationMs": 800,
            "curve": "linear",
            "plays": "after-a-swipe-on-a-navigate-or-navigate-back-action-without-reduced-motion",
            "actions": ["navigate", "navigate.back"],
            "after": "the-collapse",
            "centre": "the-centre-of-the-collapsed-circle",
            "scaleTo": "until-the-core-covers-the-farthest-corner-of-the-screen",
            "layer": "above-everything-on-the-screen-including-the-zones-and-the-status-bar-area",
            "then": "the-action-and-its-track-run-once-the-next-screen-is-under-the-fill",
        ],
        "reveal": ["durationMs": 200, "curve": "linear", "what": "the-fill-fades-out-over-the-next-screen"],
        "rippleNotPlayed": [
            "keyboardAndAssistive": "the-action-at-once-no-ripple",
            "reducedMotion": "the-action-at-once-no-collapse-no-ripple",
            "otherActions": "not-published-confirm-transition-not-read",
        ],
        "leavesBeforeAct": "nothing-runs-the-fill-goes-with-the-button",
        "reducedMotion": "the-trail-follows-the-finger-no-collapse-no-ripple-the-busy-thumb-jumps-to-the-end-as-in-9-24",
        "editorCanvas": "the-thumb-at-the-start-nothing-plays",
        "olderReader": "the-look-of-9-24-and-the-screen-changes-as-usual",
        "cases": "contract/fixtures/swipe-motion/swipe-motion-cases.json",
    ]
}
