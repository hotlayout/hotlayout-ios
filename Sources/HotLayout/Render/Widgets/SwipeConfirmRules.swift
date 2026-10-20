import Foundation

/// «Swipe to confirm» (`Button.confirm: 'swipe'`, `x-swipeConfirm`, `x-swipeConfirmBusy`): the
/// geometry of the track, the progress of a drag, what a release does, how the busy state ends.
enum SwipeConfirmRules {
    static let word = "swipe"
    static let threshold = 0.9
    static let thumbGlyph = "chevron-right"
    /// The thumb stands an `xs` step inside the border.
    static let insetToken = "xs"
    static let busyMaxMs = 8000.0
    static let completeMs = 200.0
    static let returnMs = 250.0
    static let spinnerTurnMs = 800.0

    static func confirmsBySwipe(_ props: JSONObject) -> Bool { props["confirm"]?.stringValue == word }

    struct Track: Equatable {
        var height: Double
        var width: Double
        var border: Double
        var inset: Double
    }

    struct Geometry: Equatable {
        var diameter: Double
        var thumbRoom: Double
        var travel: Double
        var labelStart: Double
        var labelWidth: Double
    }

    static func geometry(_ track: Track) -> Geometry {
        let border = max(0, track.border)
        let inset = max(0, track.inset)
        let diameter = max(0, track.height - 2 * border - 2 * inset)
        let room = border + inset + diameter
        return Geometry(
            diameter: diameter, thumbRoom: room,
            travel: max(0, track.width - 2 * border - 2 * inset - diameter),
            labelStart: room, labelWidth: max(0, track.width - 2 * room)
        )
    }

    /// The label plus the thumb room on both sides; the inline padding of the size is not read.
    static func naturalWidth(label: Double, height: Double, border: Double, inset: Double) -> Double {
        max(0, label) + 2 * geometry(Track(height: height, width: 0, border: border, inset: inset)).thumbRoom
    }

    /// The drag along the inline axis over the travel, clamped to 0…1. `dx` is the movement on
    /// the screen, positive to the right; the end of the line is on the left in right-to-left text.
    static func progress(dx: Double, travel: Double, rightToLeft: Bool) -> Double {
        guard travel > 0, dx.isFinite else { return 0 }
        return min(1, max(0, (rightToLeft ? -dx : dx) / travel))
    }

    enum Release: String, Equatable { case act, `return` }

    static func release(progress: Double, disabled: Bool = false) -> Release {
        !disabled && progress >= threshold ? .act : .return
    }

    /// Where the thumb starts, from the inline start of the track.
    static func thumbStart(_ track: Track, progress: Double) -> Double {
        max(0, track.border) + max(0, track.inset) + min(1, max(0, progress)) * geometry(track).travel
    }

    /// The drag is captured once it goes more along the inline axis than across.
    static func captures(dx: Double, dy: Double) -> Bool { abs(dx) > abs(dy) }

    // MARK: Ways to press

    enum Way: String { case pointerTap, dragPastThreshold, dragShort, enter, space, enterRepeat }
    enum Press: String, Equatable { case act, nothing }

    /// What each way of pressing does (busy: nothing; disabled: nothing).
    static func press(_ way: Way, disabled: Bool, busy: Bool = false) -> Press {
        if disabled || busy { return .nothing }
        switch way {
        case .dragPastThreshold, .enter, .space: return .act
        case .pointerTap, .dragShort, .enterRepeat: return .nothing
        }
    }

    // MARK: The busy state

    enum Runner: String, Equatable { case reader, host, none, invalid }
    enum AfterRelease: String, Equatable { case busy, giveBack = "return" }

    /// Who ran a press, from what it did: an action handed to the host is the host's (an invalid
    /// standard one is `invalid`), `none` is nobody's, everything else the reader did itself
    /// (navigation, also when the host cancelled it, and writes).
    static func runner(type: String?, outcome: PressOutcome) -> Runner {
        if let handed = outcome.handed { return handed.invalid != nil ? .invalid : .host }
        return type == "none" || type == nil ? .none : .reader
    }

    static func afterRelease(_ runner: Runner) -> AfterRelease {
        runner == .none || runner == .invalid ? .giveBack : .busy
    }

    enum BusyEvent: String { case fulfilled, rejected, screenChanged, timeout }
    enum BusyOutcome: String, Equatable { case giveBack = "return", gone, stay }

    /// How the busy state ends. `promise`: the host answered the action with a task.
    static func busyOutcome(_ event: BusyEvent, promise: Bool) -> BusyOutcome {
        if event == .screenChanged { return .gone }
        if event == .timeout { return promise ? .stay : .giveBack }
        return promise ? .giveBack : .stay
    }
}
