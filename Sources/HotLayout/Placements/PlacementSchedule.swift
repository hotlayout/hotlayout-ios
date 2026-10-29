import Foundation

/// Instants of the schedule: `YYYY-MM-DDTHH:MM:SSZ`, UTC, whole seconds, years 2000 to 2099, real
/// calendar dates only. The shape is checked by hand first and the seconds are counted from the
/// parts, so no platform parser can carry a day that does not exist over to the next month, and
/// an offset, a fraction of a second or a lowercase `z` never passes.
enum PlacementInstant {
    /// Seconds since 1970-01-01T00:00:00Z, or `nil` when the text is not an instant.
    static func seconds(_ text: String) -> Int? {
        let b = Array(text.utf8)
        guard b.count == 20, b[4] == 0x2D, b[7] == 0x2D, b[10] == 0x54, b[13] == 0x3A, b[16] == 0x3A, b[19] == 0x5A else { return nil }
        func number(_ range: Range<Int>) -> Int? {
            var value = 0
            for index in range {
                guard b[index] >= 0x30, b[index] <= 0x39 else { return nil }
                value = value * 10 + Int(b[index] - 0x30)
            }
            return value
        }
        guard let year = number(0..<4), let month = number(5..<7), let day = number(8..<10),
            let hour = number(11..<13), let minute = number(14..<16), let second = number(17..<19),
            (2000...2099).contains(year), (1...12).contains(month), hour < 24, minute < 60, second < 60
        else { return nil }
        let leap = year % 4 == 0
        let lengths = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        guard day >= 1, day <= lengths[month - 1] else { return nil }
        return daysFromCivil(year, month, day) * 86_400 + hour * 3600 + minute * 60 + second
    }

    /// Days since 1970-01-01 of a proleptic Gregorian date.
    private static func daysFromCivil(_ year: Int, _ month: Int, _ day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = y / 400
        let yearOfEra = y - era * 400
        let dayOfYear = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

    static func date(_ text: String) -> Date? { seconds(text).map { Date(timeIntervalSince1970: TimeInterval($0)) } }
}

/// One readable scheduled item of a place: a window `[from, until)` and what stands in it.
struct PlacementWindow {
    let index: Int
    let from: Int
    let until: Int
    let resolution: HotlayoutPlacementResolution

    /// The readable items of `schedule`. A broken item (not an object, no `documentId` key, an id
    /// or an entry of the wrong form, an instant that is not one, `until` not after `from`) is
    /// skipped whole and gives neither a showing nor a boundary. A pause (`documentId: null`) is
    /// an empty place for its window and its `entry` is never read. `schedule` that is not an
    /// array is no schedule.
    static func read(_ place: JSONObject) -> [PlacementWindow] {
        guard let items = place["schedule"]?.arrayValue else { return [] }
        var windows: [PlacementWindow] = []
        for (index, item) in items.enumerated() {
            guard let object = item.objectValue, let documentId = object["documentId"],
                let from = object["from"]?.stringValue.flatMap(PlacementInstant.seconds),
                let until = object["until"]?.stringValue.flatMap(PlacementInstant.seconds), until > from
            else { continue }
            if documentId.isNull {
                windows.append(PlacementWindow(index: index, from: from, until: until, resolution: HotlayoutPlacementResolution(status: .empty)))
                continue
            }
            guard let id = documentId.stringValue, PlacementForms.isDocumentId(id) else { continue }
            var entry: String?
            if let raw = object["entry"], !raw.isNull {
                guard let name = raw.stringValue, PlacementForms.isEntry(name) else { continue }
                entry = name
            }
            windows.append(PlacementWindow(index: index, from: from, until: until, resolution: HotlayoutPlacementResolution(status: .document, documentId: id, entry: entry)))
        }
        return windows
    }

    /// The window in force at `now` (seconds, may be fractional): the one that started last, and
    /// of two that started together the earlier in the array. The order of the array means
    /// nothing otherwise.
    static func active(_ windows: [PlacementWindow], at now: TimeInterval) -> PlacementWindow? {
        var best: PlacementWindow?
        for window in windows where TimeInterval(window.from) <= now && now < TimeInterval(window.until) {
            if let current = best, window.from <= current.from { continue }
            best = window
        }
        return best
    }

    /// The earliest edge of any window that is later than `now`.
    static func nextBoundary(_ windows: [PlacementWindow], after now: TimeInterval) -> Date? {
        var next: Int?
        for window in windows {
            for edge in [window.from, window.until] where TimeInterval(edge) > now {
                if next == nil || edge < next! { next = edge }
            }
        }
        return next.map { Date(timeIntervalSince1970: TimeInterval($0)) }
    }
}

extension HotlayoutPlacementMap {
    /// What stands in the place `name` at the moment `now`: the scheduled item whose window
    /// `[from, until)` lasts, otherwise the permanent content. A pause (an item without a
    /// document) is `empty`. Broken permanent content is `unreadable` even while a window lasts.
    /// The clock is the device's: nothing here asks a network.
    public func resolve(_ name: String, at now: Date) -> HotlayoutPlacementResolution {
        let found = lookup(name)
        guard case .place(let place, let permanent) = found else { return found.resolution }
        guard let window = PlacementWindow.active(PlacementWindow.read(place), at: now.timeIntervalSince1970) else { return permanent }
        return window.resolution
    }

    /// The earliest edge (`from` or `until` of a readable scheduled item) later than `now`;
    /// `nil` when nothing will change any more, and for a place that is unknown or unreadable.
    public func nextBoundary(_ name: String, after now: Date) -> Date? {
        guard case .place(let place, _) = lookup(name) else { return nil }
        return PlacementWindow.nextBoundary(PlacementWindow.read(place), after: now.timeIntervalSince1970)
    }

    /// The ids of the documents the place `name` can show: its permanent content, then every
    /// readable window, each once, in the order of the map. Empty for a place that is unknown or
    /// unreadable.
    func documentIds(of name: String) -> [String] {
        guard case .place(let place, let permanent) = lookup(name) else { return [] }
        var ids: [String] = []
        for id in [permanent.documentId] + PlacementWindow.read(place).map(\.resolution.documentId) {
            if let id, !ids.contains(id) { ids.append(id) }
        }
        return ids
    }

    /// The ids of documents of readable scheduled items of every place (kept for the day they start).
    func scheduledDocumentIds() -> Set<String> {
        guard reading == .map else { return [] }
        var ids: Set<String> = []
        for key in places.keys {
            guard let place = places[key]?.objectValue else { continue }
            for window in PlacementWindow.read(place) { if let id = window.resolution.documentId { ids.insert(id) } }
        }
        return ids
    }
}

enum PlacementTimer {
    /// The longest a single sleep may last: a timer past 2^31 - 1 ms is cut and the place is
    /// computed again at its end.
    static let maxMs = 2_147_483_647

    /// How long to sleep from `now` to `boundary`, in milliseconds, at least 1 and at most `maxMs`.
    static func sleepMs(until boundary: Date, from now: Date) -> Int {
        let ms = (boundary.timeIntervalSince(now) * 1000).rounded(.up)
        if ms >= Double(maxMs) { return maxMs }
        return max(1, Int(ms))
    }
}
