import Foundation

/// What a press hands over, in the order the contract states (`x-haptic.order`): the haptic
/// request, then the analytics event, then the action (or the shown screen). The screen calls
/// `announce` as soon as a press is read (before the host is asked about a navigation) and
/// `hand` once the flow has decided; `deliver` is the two in a row.
enum PressDelivery {
    static func announce(
        _ outcome: PressOutcome, source: ActionSource,
        onHaptic: ((HapticFeedback, ActionSource) -> Void)?, onTrack: ((TrackEvent, ActionSource) -> Void)?
    ) {
        if let haptic = outcome.haptic { onHaptic?(haptic, source) }
        if let track = outcome.track { onTrack?(track, source) }
    }

    /// Hands the action over and returns the task the host answered it with, if any.
    static func hand(
        _ outcome: PressOutcome, source: ActionSource, onAction: ((HotlayoutAction, ActionSource) -> Task<Void, Never>?)?
    ) -> Task<Void, Never>? {
        guard let handed = outcome.handed else { return nil }
        return onAction?(handed, source) ?? nil
    }

    @discardableResult
    static func deliver(
        _ outcome: PressOutcome, source: ActionSource,
        onHaptic: ((HapticFeedback, ActionSource) -> Void)?, onTrack: ((TrackEvent, ActionSource) -> Void)?,
        onAction: ((HotlayoutAction, ActionSource) -> Task<Void, Never>?)?
    ) -> Task<Void, Never>? {
        announce(outcome, source: source, onHaptic: onHaptic, onTrack: onTrack)
        return hand(outcome, source: source, onAction: onAction)
    }
}
