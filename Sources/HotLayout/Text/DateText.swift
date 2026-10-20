import Foundation

/// Dates of the contract: what counts as a date, and how it is written.
enum DateText {
    /// `x-template.dateTimePattern`: ISO 8601 with time and zone. `1850`, `2026-10-14` and a
    /// numeric timestamp are NOT dates (`dateValueForm`), whatever a platform parser accepts.
    static let pattern = "^(\\d{4})-(\\d{2})-(\\d{2})T(\\d{2}):(\\d{2})(?::(\\d{2})(?:\\.(\\d{1,9}))?)?(Z|([+-])(\\d{2}):(\\d{2}))$"
    private static let expression = try! NSRegularExpression(pattern: pattern)
    /// The longest string the expression accepts is 35 characters; a longer one is not run.
    static let maxLength = 40

    /// The instant of an ISO 8601 string in epoch milliseconds, or `nil` if it is not a date.
    ///
    /// The calendar is checked by code over the groups (`dateValueValidity:
    /// 'calendar-checked-by-reader-code'`): platforms disagree about February 30.
    static func moment(_ value: JSONValue?) -> Double? {
        guard let text = value?.stringValue, text.utf16.count <= maxLength, text.allSatisfy(\.isASCII) else { return nil }
        let whole = NSRange(text.startIndex..., in: text)
        guard let match = expression.firstMatch(in: text, range: whole), match.range == whole else { return nil }
        func group(_ index: Int) -> String? {
            guard let range = Range(match.range(at: index), in: text) else { return nil }
            return String(text[range])
        }
        func number(_ index: Int) -> Int { group(index).flatMap { Int($0) } ?? 0 }
        let year = number(1)
        let month = number(2)
        let day = number(3)
        let hour = number(4)
        let minute = number(5)
        let second = number(6)
        let offsetHour = number(10)
        let offsetMinute = number(11)
        guard (1...12).contains(month), day >= 1, day <= daysInMonth(year: year, month: month),
            hour <= 23, minute <= 59, second <= 59, offsetHour <= 23, offsetMinute <= 59
        else { return nil }
        // Milliseconds: the first three fraction digits, as JavaScript reads them.
        let fraction = group(7) ?? ""
        let millis = Int((fraction + "000").prefix(3)) ?? 0
        let sign = group(9) == "-" ? -1 : 1
        let offset = sign * (offsetHour * 60 + offsetMinute)
        let days = daysFromCivil(year: year, month: month, day: day)
        let seconds = Double(days) * 86_400 + Double(hour * 3600 + minute * 60 + second) - Double(offset * 60)
        return seconds * 1000 + Double(millis)
    }

    static func daysInMonth(year: Int, month: Int) -> Int {
        if month == 2 { return (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 ? 29 : 28 }
        return [4, 6, 9, 11].contains(month) ? 30 : 31
    }

    /// Days from 1970-01-01 in the proleptic Gregorian calendar.
    static func daysFromCivil(year: Int, month: Int, day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = (month + 9) % 12
        let doy = (153 * mp + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    /// CLDR skeletons of the formats (`x-dateParts`; the date without the field is `yMMMd`).
    static func skeleton(format: String, dateParts: String?) -> String? {
        switch format {
        case "date":
            switch dateParts {
            case "dayMonth": return "MMMMd"
            case "weekdayDayMonth": return "MMMMEEEEd"
            case "dayMonthYear": return "yMMMMd"
            default: return "yMMMd"
            }
        case "time": return "jmm"
        default: return nil
        }
    }

    private static let lock = NSLock()
    private static var formatters: [String: DateFormatter] = [:]

    private static func formatter(skeleton: String, locale: String?, timeZone: TimeZone?) -> DateFormatter {
        let key = "\(skeleton)|\(locale ?? "")|\(timeZone?.identifier ?? "")"
        lock.lock()
        defer { lock.unlock() }
        if let known = formatters[key] { return known }
        let formatter = DateFormatter()
        let resolved = locale.map { Locale(identifier: $0) } ?? Locale.current
        formatter.locale = resolved
        // `x-template.dateCalendar`: Gregorian in every locale (otherwise Thai would write 2569).
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = resolved
        formatter.calendar = calendar
        formatter.timeZone = timeZone ?? TimeZone.current
        formatter.setLocalizedDateFormatFromTemplate(skeleton)
        if formatters.count >= 64 { formatters.removeAll() }
        formatters[key] = formatter
        return formatter
    }

    /// A date, a time or both in a locale, or `nil` when the format does not apply.
    static func format(_ moment: Double, format: String, dateParts: String?, locale: String?, timeZone: TimeZone?) -> String? {
        let date = Date(timeIntervalSince1970: moment / 1000)
        if format == "dateTime" {
            // Date and time are joined by the LANGUAGE's pattern (CLDR, the medium joiner):
            // «Oct 31, 2026, 2:05 PM», not a space and not the «at» variant.
            let datePart = formatter(skeleton: "yMMMd", locale: locale, timeZone: timeZone).string(from: date)
            let timePart = formatter(skeleton: "jmm", locale: locale, timeZone: timeZone).string(from: date)
            return glue(for: locale).replacingOccurrences(of: "{1}", with: datePart).replacingOccurrences(of: "{0}", with: timePart)
        }
        guard let skeleton = skeleton(format: format, dateParts: dateParts) else { return nil }
        return formatter(skeleton: skeleton, locale: locale, timeZone: timeZone).string(from: date)
    }

    /// The CLDR medium date-time joiner of a language (`{1}` is the date, `{0}` the time).
    static func glue(for locale: String?) -> String {
        let tag = locale.flatMap(LocaleTags.normalize) ?? Locale.current.identifier.replacingOccurrences(of: "_", with: "-")
        for candidate in LocaleTags.lookupChain(tag) {
            if let glue = dateTimeGlue[candidate] { return glue }
        }
        return "{1}, {0}"
    }

    /// CLDR `dateTimeFormats/medium` (the non-«at» form) where it is not `{1}, {0}`.
    static let dateTimeGlue: [String: String] = [
        "af": "{1} {0}", "am": "{1} {0}", "ar": "{1}\u{060C} {0}", "ar-DZ": "{1}\u{060C} {0}", "ar-EG": "{1}\u{060C} {0}",
        "as": "{1} {0}", "az": "{1} {0}", "bm": "{1} {0}", "bn": "{1} {0}", "bs": "{1} {0}", "cs": "{1} {0}",
        "cy": "{1} {0}", "da": "{1} {0}", "et": "{1} {0}", "eu": "{1} ({0})", "fa": "{1}\u{060C}\u{200F} {0}",
        "fi": "{1} {0}", "fur": "{1} {0}", "ga": "{1} {0}", "gsw": "{1} {0}", "gu": "{1} {0}", "haw": "{1} {0}",
        "hr": "{1} {0}", "hu": "{1} {0}", "id": "{1} {0}", "in": "{1} {0}", "ja": "{1} {0}", "kn": "{1} {0}",
        "ko": "{1} {0}", "ky": "{1} {0}", "ln": "{1} {0}", "lt": "{1} {0}", "lv": "{1} {0}", "mg": "{1} {0}",
        "mn": "{1} {0}", "mt": "{1} {0}", "my": "{1} {0}", "nyn": "{1} {0}", "ps": "{1} {0}", "pt": "{1} {0}",
        "pt-BR": "{1} {0}", "si": "{1} {0}", "sr": "{1} {0}", "sr-Latn": "{1} {0}", "sv": "{1} {0}", "sw": "{1} {0}",
        "te": "{1} {0}", "th": "{1} {0}", "tr": "{1} {0}", "ur": "{1} {0}", "vi": "{0} {1}", "zh": "{1} {0}",
        "zh-CN": "{1} {0}", "zh-HK": "{1}{0}", "zh-TW": "{1}{0}", "zu": "{1} {0}",
    ]
}
