import Foundation

/// A value that changes from data (`animateChanges`, `x-valueTransition`) or grows from zero
/// when its node is shown (`animateIn`, `x-valueAppear`): the curve, the step, the decisions and
/// the numbers a node leads. Pure functions; the clock lives in `ValueTransitionEngine`.
enum ValueTransition {
    static let durationMs = 700.0
    static let precision = 6.0
    static let maxFractionDigits = 3
    /// The key of the literal `value` of a scale among the numbers that appear.
    static let literalKey = "#value"
    static let appearFrom = 0.0

    /// `e = 1 − (1 − p)³`, `p` clamped to 0…1.
    static func ease(_ progress: Double) -> Double {
        let p = Swift.min(1, Swift.max(0, progress))
        return 1 - pow(1 - p, 3)
    }

    /// Whole when both ends are whole; otherwise the digits of the currency, else three.
    static func digits(from: Double, to: Double, format: String?, currency: String?) -> Int {
        if from == from.rounded(), to == to.rounded() { return 0 }
        if format == "currency", let currency, BindingFormat.isCurrencyCode(.string(currency)) {
            return NumberText.currencyFractionDigits(currency)
        }
        return maxFractionDigits
    }

    /// JavaScript `Math.round`: halves go up.
    private static func jsRound(_ value: Double) -> Double { (value + 0.5).rounded(.down) }

    private static func rounded(_ value: Double, digits: Int) -> Double {
        let scale = pow(10, Double(digits))
        return jsRound(value * scale) / scale
    }

    /// The value shown `t` ms after the transition began. A scale (`digits == nil`) has no step;
    /// a number moves in steps cut towards the OLD value, on a rounded product so that
    /// `0.3 × 0.875` is not cut a step lower.
    static func value(from: Double, to: Double, t: Double, digits: Int?) -> Double {
        if !t.isFinite || t >= durationMs { return to }
        let delta = (to - from) * ease(t / durationMs)
        guard let digits else { return from + delta }
        let scale = pow(10, Double(digits))
        let steps = (jsRound(delta * scale * pow(10, precision)) / pow(10, precision)).rounded(.towardZero)
        return rounded(from + steps / scale, digits: digits + Int(precision))
    }

    // MARK: Decisions

    enum NoTransition: String, Equatable {
        case noField, firstShow, sameValue, notANumber, localeChanged, reducedMotion
    }

    enum Decision: Equatable {
        case leads
        case atOnce(NoTransition)
    }

    struct Change {
        var animates: Bool
        var shownBefore: Bool
        var from: JSONValue?
        var to: JSONValue?
        var localeChanged = false
        var reducedMotion = false
    }

    /// The first reason in the contract order wins: no field, first show, reduced motion, a
    /// changed language, a value that is not a number, the same value.
    static func decision(_ change: Change) -> Decision {
        if !change.animates { return .atOnce(.noField) }
        if !change.shownBefore { return .atOnce(.firstShow) }
        if change.reducedMotion { return .atOnce(.reducedMotion) }
        if change.localeChanged { return .atOnce(.localeChanged) }
        guard let from = change.from?.numberValue, let to = change.to?.numberValue else { return .atOnce(.notANumber) }
        if from == to { return .atOnce(.sameValue) }
        return .leads
    }

    enum AppearNo: String, Equatable { case noField, reducedMotion, notANumber, zero }

    enum AppearDecision: Equatable {
        case grows
        case atOnce(AppearNo)
    }

    static func appearDecision(animates: Bool, to: JSONValue?, reducedMotion: Bool) -> AppearDecision {
        if !animates { return .atOnce(.noField) }
        if reducedMotion { return .atOnce(.reducedMotion) }
        guard let number = to?.numberValue else { return .atOnce(.notANumber) }
        if number == 0 { return .atOnce(.zero) }
        return .grows
    }

    enum Moment: String {
        case firstShow, forward, back, `switch`, modalClosed, conditionMet, dataChanged
        case dataChangedDuringAppearWithAnimateChanges, dataChangedDuringAppear
    }

    enum OnMoment: String, Equatable { case appear, none, transition, atOnce }

    static func appear(on moment: Moment) -> OnMoment {
        switch moment {
        case .firstShow, .forward, .back, .switch, .conditionMet: return .appear
        case .modalClosed, .dataChanged: return .none
        case .dataChangedDuringAppearWithAnimateChanges: return .transition
        case .dataChangedDuringAppear: return .atOnce
        }
    }

    // MARK: Targets

    struct Target: Equatable {
        var path: String
        var scale: Bool
        var format: String?
        var currency: String?
    }

    static func animatesChanges(_ props: JSONObject) -> Bool { props["animateChanges"]?.boolValue == true }
    static func animatesIn(_ props: JSONObject) -> Bool { props["animateIn"]?.boolValue == true }

    /// Text formats counted through: none, `number` and `currency`. A date, `daysUntil` and a
    /// countdown part are not.
    private static func transitionsInText(_ format: String?) -> Bool {
        format == nil || format == "number" || format == "currency"
    }

    private static func bindingTarget(_ value: JSONValue?, scale: Bool) -> Target? {
        guard let record = value?.objectValue, record["kind"]?.stringValue == "binding", let path = record["path"]?.stringValue else { return nil }
        let format = record["format"]?.stringValue
        if !scale, !transitionsInText(format) { return nil }
        let currency = BindingFormat.isCurrencyCode(record["currency"]) ? record["currency"]?.stringValue : nil
        return Target(path: path, scale: scale, format: format, currency: currency)
    }

    /// The numbers of a node that transition: the `value` and `max` of a scale, each its own
    /// run; the bindings of a text, alone or inside a template.
    static func targets(_ props: JSONObject) -> [Target] {
        var result: [Target?] = [bindingTarget(props["value"], scale: true), bindingTarget(props["max"], scale: true)]
        if let content = props["content"]?.objectValue, content["kind"]?.stringValue == "template", let values = content["values"]?.objectValue {
            result += values.keys.map { bindingTarget(values[$0], scale: false) }
        } else {
            result.append(bindingTarget(props["content"], scale: false))
        }
        return result.compactMap { $0 }
    }

    /// The numbers that appear: the VALUE of a scale (a literal one is `#value`), the numbers of
    /// a text. The `max` of a scale stands at once.
    static func appearTargets(_ props: JSONObject) -> [Target] {
        var literalScale: [Target] = []
        if props["value"]?["kind"]?.stringValue == "literal" { literalScale = [Target(path: literalKey, scale: true)] }
        let valuePath = props["value"]?["kind"]?.stringValue == "binding" ? props["value"]?["path"]?.stringValue : nil
        let counted = targets(props).filter { !($0.scale && $0.path != valuePath) }
        return literalScale + counted
    }
}
