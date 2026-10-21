import Foundation

/// A color with alpha, components 0…1 (sRGB).
public struct RGBA: Equatable, Hashable, Sendable {
    /// Red, 0…1.
    public let red: Double
    /// Green, 0…1.
    public let green: Double
    /// Blue, 0…1.
    public let blue: Double
    /// Opacity, 0…1.
    public let alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// `#rrggbb` or `#rrggbbaa` (`colorAlpha: 'rrggbbaa-alpha-last'`); any other shape is «no
    /// color», never a guess.
    public init?(hex: String) {
        let utf8 = Array(hex.utf8)
        guard utf8.first == UInt8(ascii: "#"), utf8.count == 7 || utf8.count == 9 else { return nil }
        var values: [Double] = []
        var index = 1
        while index < utf8.count {
            guard let pair = UInt8(String(decoding: utf8[index..<index + 2], as: UTF8.self), radix: 16) else { return nil }
            values.append(Double(pair) / 255)
            index += 2
        }
        self.init(red: values[0], green: values[1], blue: values[2], alpha: values.count == 4 ? values[3] : 1)
    }

    /// The color with its alpha multiplied by `opacity`.
    public func withOpacity(_ opacity: Double) -> RGBA {
        RGBA(red: red, green: green, blue: blue, alpha: alpha * opacity)
    }
}

/// A text style of the theme: size and spacing in logical pixels, line height a multiple of
/// the size (`lineHeightUnit: 'font-size-multiple'`), no letter spacing is zero.
public struct TextStyleValue: Equatable, Sendable {
    /// The size in logical pixels.
    public internal(set) var fontSize: Double
    /// The line height as a multiple of the size.
    public internal(set) var lineHeight: Double
    /// The weight, 100…900.
    public internal(set) var fontWeight: Int
    /// The letter spacing in logical pixels.
    public internal(set) var letterSpacing: Double
    /// `heading` or `body`: which font family the style uses.
    public internal(set) var role: String

    public init(fontSize: Double, lineHeight: Double, fontWeight: Int, letterSpacing: Double = 0, role: String = "body") {
        self.fontSize = fontSize
        self.lineHeight = lineHeight
        self.fontWeight = fontWeight
        self.letterSpacing = letterSpacing
        self.role = role
    }
}

/// One layer of a shadow.
public struct ShadowLayer: Equatable, Sendable {
    /// The horizontal offset in logical pixels.
    public internal(set) var offsetX: Double
    /// The vertical offset in logical pixels.
    public internal(set) var offsetY: Double
    /// The blur radius in logical pixels.
    public internal(set) var blur: Double
    /// The spread in logical pixels.
    public internal(set) var spread: Double
    /// The color of the layer.
    public internal(set) var color: RGBA
}

/// A linear gradient of the theme.
public struct GradientValue: Equatable, Sendable {
    /// A color at a position along a gradient.
    public struct Stop: Equatable, Sendable {
        /// The color at this stop.
        public var color: RGBA
        /// The position along the gradient, 0…1.
        public var position: Double
    }

    /// Degrees as CSS reads them: 0 is «to top», 90 «to right».
    public let angle: Double
    /// The stops in order.
    public let stops: [Stop]
}

/// The colors of one role (`roles.buttonVariant.primary`): names of theme colors.
public struct RoleSlots: Equatable, Sendable {
    /// The name of the background color.
    public let background: String?
    /// The name of the text and icon color.
    public let foreground: String?
    /// The name of the border color.
    public let border: String?
}

/// Whether a theme is light or dark.
public enum ThemeBrightness: String, Equatable, Sendable {
    case light
    case dark
}

/// One theme of a theme contract: six dictionaries and the roles.
public struct HotlayoutTheme: Equatable, Sendable {
    /// The identifier of the theme.
    public internal(set) var id: String
    /// `light` or `dark`; see `appearance`.
    public internal(set) var brightness: String
    /// `brightness` as a value; anything but `dark` reads as `light`, as the theme reader does.
    public var appearance: ThemeBrightness { brightness == ThemeBrightness.dark.rawValue ? .dark : .light }
    /// The spacing steps by name, in logical pixels.
    public internal(set) var spacing: [String: Double]
    /// The corner radii by name, in logical pixels.
    public internal(set) var radius: [String: Double]
    /// The colors by name.
    public internal(set) var color: [String: RGBA]
    /// The text styles by name.
    public internal(set) var typography: [String: TextStyleValue]
    /// The shadows by name.
    public internal(set) var elevation: [String: [ShadowLayer]]
    /// The gradients by name.
    public internal(set) var gradient: [String: GradientValue]
    /// The font families by role (`heading`, `body`).
    public internal(set) var fontFamilies: [String: String]
    /// The color slots of the roles of the widgets (a role group, then a variant).
    public internal(set) var roles: [String: [String: RoleSlots]]

    /// The color behind a name, with the optional state colors falling back to the token they
    /// borrowed before they had a name (`x-optionalColors`).
    public func colorValue(_ token: String) -> RGBA? {
        if let value = color[token] { return value }
        if let fallback = Self.optionalColorFallbacks[token] { return color[fallback] }
        return nil
    }

    static let optionalColorFallbacks = ["locked": "muted", "inProgress": "accent", "completed": "success"]

    /// The built-in theme of the same brightness: where a core token the reader needs comes from
    /// when this theme lacks it. A theme read by `loadTheme` is already filled from it.
    private var builtInTwin: HotlayoutTheme {
        let set = HotlayoutThemeSet.builtIn
        return set.themes.values.first { $0.brightness == brightness } ?? set.theme()
    }

    /// A colour of the core of the theme, with the built-in value standing in.
    func coreColor(_ token: String) -> RGBA {
        colorValue(token) ?? builtInTwin.coreColor(token)
    }

    /// A text style of the core of the theme, with the built-in value standing in.
    func coreTypography(_ token: String) -> TextStyleValue {
        typography[token] ?? builtInTwin.typography[token] ?? builtInTwin.typography[NodeStyle.rootTypography]!
    }

    /// A spacing step of the core of the theme, with the built-in value standing in.
    func coreSpacing(_ token: String) -> Double {
        spacing[token] ?? builtInTwin.coreSpacing(token)
    }

    /// A radius of the core of the theme, with the built-in value standing in.
    func coreRadius(_ token: String) -> Double {
        radius[token] ?? builtInTwin.coreRadius(token)
    }
}

/// A theme contract: a set of themes and the one a reader takes by default.
public struct HotlayoutThemeSet: Equatable, Sendable {
    /// The version of the theme contract the set was written for.
    public let themeContractVersion: String
    /// The theme a reader takes when none is asked for.
    public let defaultThemeId: String
    /// The themes by identifier.
    public let themes: [String: HotlayoutTheme]
    /// What the reader skipped or replaced while reading the theme (`loadTheme`); not part of
    /// equality. `HotlayoutScreen` hands these to `onReport` with its own.
    public internal(set) var reports: [HotlayoutReport] = []

    /// The same themes: the version, the default and every theme. The `reports` of the read are not compared.
    public static func == (lhs: HotlayoutThemeSet, rhs: HotlayoutThemeSet) -> Bool {
        lhs.themeContractVersion == rhs.themeContractVersion && lhs.defaultThemeId == rhs.defaultThemeId && lhs.themes == rhs.themes
    }

    /// The theme the reader draws with: the requested one, else the default
    /// (`unknownThemeId: 'use-default'`), else any.
    public func theme(_ id: String? = nil) -> HotlayoutTheme {
        if let id, let theme = themes[id] { return theme }
        if let theme = themes[defaultThemeId] { return theme }
        if let first = themes.keys.sorted().first, let theme = themes[first] { return theme }
        return Self.builtIn.theme()
    }

    /// The theme this reader ships with: the `contract` block of `theme.json`.
    public static let builtIn: HotlayoutThemeSet = {
        guard let url = Bundle.module.url(forResource: "built-in-theme", withExtension: "json"),
            let data = try? Data(contentsOf: url), let json = try? JSONValue.parse(data),
            let set = ThemeReader.read(json, base: nil, sink: ReportSink())
        else { preconditionFailure("HotLayout: the built-in theme is missing from the package resources") }
        return set
    }()

    /// Reads a theme contract. A newer minor's fields are skipped; a missing entry is filled
    /// from the built-in theme of the same brightness (`partialTheme`); a theme that cannot be
    /// read at all gives `nil` (`unreadableTheme: 'fallback-and-report'`).
    static func read(_ json: JSONValue, sink: ReportSink = ReportSink()) -> HotlayoutThemeSet? {
        ThemeReader.read(DocumentReader.withoutForbiddenKeys(json), base: builtIn, sink: sink)
    }
}

extension HotlayoutThemeSet {
    /// Loads a theme contract (`theme/published.json` of a project): JSON, the version gate, then a
    /// tolerant read of every theme. A token of the wrong shape is skipped and listed in `reports`
    /// of the result; the built-in theme of the same brightness fills what is missing.
    ///
    /// - Throws: `HotlayoutLoadError.malformedJSON` for text that is not JSON, and
    ///   `HotlayoutLoadError.notATheme` for JSON that is not a readable theme contract (no `themes`,
    ///   a major version this reader does not read, or no theme that can be read). Draw with
    ///   `HotlayoutThemeSet.builtIn` instead.
    public static func load(_ data: Data) throws -> HotlayoutThemeSet {
        let json: JSONValue
        do {
            json = try JSONValue.parse(data)
        } catch {
            throw HotlayoutLoadError.malformedJSON(String(describing: error))
        }
        return try load(json)
    }

    /// Loads a theme contract from JSON that is already parsed.
    public static func load(_ json: JSONValue) throws -> HotlayoutThemeSet {
        let sink = ReportSink()
        guard var set = HotlayoutThemeSet.read(json, sink: sink) else {
            throw HotlayoutLoadError.notATheme(sink.reports.first?.reason ?? "no theme can be read")
        }
        set.reports = sink.reports
        return set
    }
}

@available(*, deprecated, renamed: "HotlayoutThemeSet.load(_:)")
public func loadTheme(_ data: Data) throws -> HotlayoutThemeSet { try HotlayoutThemeSet.load(data) }

@available(*, deprecated, renamed: "HotlayoutThemeSet.load(_:)")
public func loadTheme(_ json: JSONValue) throws -> HotlayoutThemeSet { try HotlayoutThemeSet.load(json) }

enum ThemeReader {
    static func read(_ json: JSONValue, base: HotlayoutThemeSet?, sink: ReportSink) -> HotlayoutThemeSet? {
        guard let object = json.objectValue, let themesObject = object["themes"]?.objectValue else {
            sink.add(.ignoredInput, "theme", "the theme is not a theme contract; the built-in theme is used")
            return nil
        }
        if let version = object["themeContractVersion"]?.stringValue {
            let verdict = HotlayoutVersions.check(version, readerVersion: HotlayoutVersions.theme)
            guard verdict.isReadable else {
                sink.add(.ignoredInput, "theme", "theme contract \(version) is not readable by this reader; the built-in theme is used")
                return nil
            }
        }
        var themes: [String: HotlayoutTheme] = [:]
        for (id, value) in themesObject {
            guard let theme = value.objectValue else {
                sink.add(.ignoredInput, "theme “\(id)”", "a theme that is not an object is skipped")
                continue
            }
            let brightness = theme["brightness"]?.stringValue == "dark" ? "dark" : "light"
            let fallback = base?.themes.values.first { $0.brightness == brightness } ?? base?.theme()
            themes[id] = readTheme(id: id, theme, brightness: brightness, fallback: fallback, sink: sink)
        }
        guard !themes.isEmpty else { return nil }
        let defaultId = object["defaultThemeId"]?.stringValue.flatMap { themes[$0] != nil ? $0 : nil } ?? themes.keys.sorted().first!
        return HotlayoutThemeSet(
            themeContractVersion: object["themeContractVersion"]?.stringValue ?? HotlayoutVersions.theme, defaultThemeId: defaultId, themes: themes)
    }

    static func readTheme(id: String, _ theme: JSONObject, brightness: String, fallback: HotlayoutTheme?, sink: ReportSink) -> HotlayoutTheme {
        var result =
            fallback
            ?? HotlayoutTheme(
                id: id, brightness: brightness, spacing: [:], radius: [:], color: [:], typography: [:], elevation: [:], gradient: [:], fontFamilies: [:],
                roles: [:])
        result.id = id
        result.brightness = brightness
        let place = "theme “\(id)”"
        func fit(_ value: Double, _ bounds: ThemeNumbers.Bounds, builtIn: Double? = nil, _ where: String) -> Double {
            ThemeNumbers.fit(value, bounds, builtIn: builtIn, place: place, at: `where`, sink: sink)
        }
        for (name, value) in theme["spacing"]?.objectValue ?? JSONObject() {
            if let number = ThemeNumbers.number(value) {
                result.spacing[name] = fit(number, ThemeNumbers.spacing, builtIn: fallback?.spacing[name], "spacing.\(name)")
            } else {
                sink.add(.ignoredInput, "\(place): spacing.\(name)", "not a length")
            }
        }
        for (name, value) in theme["radius"]?.objectValue ?? JSONObject() {
            if let number = ThemeNumbers.number(value) {
                result.radius[name] = fit(number, ThemeNumbers.radius, builtIn: fallback?.radius[name], "radius.\(name)")
            } else {
                sink.add(.ignoredInput, "\(place): radius.\(name)", "not a length")
            }
        }
        for (name, value) in theme["color"]?.objectValue ?? JSONObject() {
            if let color = value.stringValue.flatMap(RGBA.init(hex:)) {
                result.color[name] = color
            } else {
                sink.add(.ignoredInput, "\(place): color.\(name)", "not a color")
            }
        }
        for (name, value) in theme["typography"]?.objectValue ?? JSONObject() {
            guard let style = value.objectValue, let rawSize = ThemeNumbers.number(style["fontSize"]), let rawLine = ThemeNumbers.number(style["lineHeight"])
            else {
                sink.add(.ignoredInput, "\(place): typography.\(name)", "not a text style")
                continue
            }
            let builtIn = fallback?.typography[name]
            let at = "typography.\(name)"
            let size = fit(rawSize, ThemeNumbers.fontSize, builtIn: builtIn?.fontSize, "\(at).fontSize")
            let line = fit(rawLine, ThemeNumbers.lineHeight, builtIn: builtIn?.lineHeight, "\(at).lineHeight")
            let weight = fit(
                ThemeNumbers.number(style["fontWeight"]) ?? 400, ThemeNumbers.fontWeight, builtIn: builtIn.map { Double($0.fontWeight) }, "\(at).fontWeight")
            // The built-in styles carry no letter spacing: one outside the bounds has no built-in value to take.
            let tracking = fit(ThemeNumbers.number(style["letterSpacing"]) ?? 0, ThemeNumbers.letterSpacing, "\(at).letterSpacing")
            result.typography[name] = TextStyleValue(
                fontSize: size, lineHeight: line, fontWeight: SafeInt.clamped(weight), letterSpacing: tracking, role: style["role"]?.stringValue ?? "body"
            )
        }
        for (name, value) in theme["elevation"]?.objectValue ?? JSONObject() {
            guard let layers = value.arrayValue else { continue }
            // A part of a shadow borrowed from another shadow would be a third value nobody wrote: a layer number takes the bound.
            var read: [ShadowLayer] = []
            for (index, layer) in layers.enumerated() {
                guard let layer = layer.objectValue, let color = layer["color"]?.stringValue.flatMap(RGBA.init(hex:)) else { continue }
                let at = "elevation.\(name)[\(index)]"
                read.append(
                    ShadowLayer(
                        offsetX: fit(ThemeNumbers.number(layer["offsetX"]) ?? 0, ThemeNumbers.shadowOffset, "\(at).offsetX"),
                        offsetY: fit(ThemeNumbers.number(layer["offsetY"]) ?? 0, ThemeNumbers.shadowOffset, "\(at).offsetY"),
                        blur: fit(ThemeNumbers.number(layer["blur"]) ?? 0, ThemeNumbers.shadowBlur, "\(at).blur"),
                        spread: fit(ThemeNumbers.number(layer["spread"]) ?? 0, ThemeNumbers.shadowSpread, "\(at).spread"),
                        color: color.withOpacity(fit(ThemeNumbers.number(layer["opacity"]) ?? 1, ThemeNumbers.unit, "\(at).opacity"))
                    ))
            }
            result.elevation[name] = read
        }
        for (name, value) in theme["gradient"]?.objectValue ?? JSONObject() {
            guard let gradient = value.objectValue, let angle = gradient["angle"]?.numberValue else { continue }
            var stops: [GradientValue.Stop] = []
            for (index, stop) in (gradient["stops"]?.arrayValue ?? []).enumerated() {
                guard let stop = stop.objectValue, let color = stop["color"]?.stringValue.flatMap(RGBA.init(hex:)), let position = ThemeNumbers.number(stop["position"])
                else { continue }
                stops.append(GradientValue.Stop(color: color, position: fit(position, ThemeNumbers.unit, "gradient.\(name).stops[\(index)].position")))
            }
            if stops.count >= 2 { result.gradient[name] = GradientValue(angle: angle, stops: stops) }
        }
        for (name, value) in theme["fontFamilies"]?.objectValue ?? JSONObject() {
            if let primary = value["primary"]?.stringValue { result.fontFamilies[name] = primary }
        }
        for (group, value) in theme["roles"]?.objectValue ?? JSONObject() {
            var entries: [String: RoleSlots] = result.roles[group] ?? [:]
            for (name, slots) in value.objectValue ?? JSONObject() {
                entries[name] = RoleSlots(
                    background: slots["background"]?.stringValue, foreground: slots["foreground"]?.stringValue, border: slots["border"]?.stringValue)
            }
            result.roles[group] = entries
        }
        return result
    }
}
