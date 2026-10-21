import SwiftUI

/// What every node of a screen needs to draw: the theme, the data, the language and the way
/// back to the screen for presses. Passed down explicitly, one value per node.
///
/// Three groups and the values that change from node to node: `screen` is the same for every
/// node of one screen, `list` says where a node stands in lists from data, `bar` is what the
/// chrome zones (app bar, bar of navigation) hand to their content. The flat properties below
/// read and write those groups.
struct RenderContext {
    /// The same for every node of one screen.
    struct ScreenEnv {
        let resolver: StyleResolver
        let screenId: String
        let localization: DocumentLocalization?
        let locale: LocaleResolution
        let timeZone: TimeZone?
        let rightToLeft: Bool
        let sink: ReportSink
        let images: ImagePolicy
        /// Hands a press to the screen together with the list instances the node is drawn inside,
        /// and says who ran it and which task the host answered with, when it gave one.
        let pressHandler: (JSONObject, DocumentNode, [ListInstance]) -> PressRun
        /// The word of the reader for the back arrow of an app bar (`ScreenLabels.back`).
        var backLabel: String
        /// Writes a value under a data path: into the session of the screen and to the host at the same
        /// moment (inputs, choices, write actions). `nil` where nobody owns a session.
        var write: ((String, JSONValue) -> Void)?
        /// The form of the screen.
        var form: ScreenForm?
        /// What the carousels of the stack remember, and the frame of the stack this screen is.
        var carousels: CarouselMemory?
        var frameIndex = 0
        /// The list budget of the screen (`x-listBudget`); `nil` outside a screen, where a list draws every record it would.
        var listBudget: ListBudget.Plan?
        /// The width class of the box this screen is drawn in; one class for the whole screen.
        var widthClass = WidthClass.compact
    }

    /// Where a node stands in lists from data and among its siblings.
    struct ListEnv {
        /// Repeater instances this node is drawn inside, outer first (empty outside a list).
        var instances: [ListInstance] = []
        /// The indexes of those instances (the key of a carousel's state).
        var instancePath: [Int] = []
        /// Where this node stands among its siblings, set by the parent that lays them out and read
        /// by a list item (`Text.marker`); descendants of the node do not inherit it.
        var position: ListPosition?
        /// The place of the node in a numbered list from data (`Text.marker: number` as the template
        /// of a `Repeater`): its number among the drawn instances and how many records were drawn.
        var number: ListNumber?
        /// The choice of the nearest `ChoiceGroup` above the node.
        var choice: ChoiceScope?
    }

    /// What the chrome zones of the screen hand to their content.
    struct BarEnv {
        /// The body of the screen is scrolled far enough for the app bar to change (`styleScrolled`).
        var scrolled = false
        /// The top safe inset the app bar zone holds inside its box, above its content.
        var inset = 0.0
        /// The bottom safe inset the navigation bar holds under its items (zero when it floats: the
        /// inset then lies under its box).
        var navInset = 0.0
        /// The width of the built-in top line of the navigation bar the item belongs to; the item
        /// takes it into its touch area.
        var navLine = 0.0
        /// The widest content of the screen (`Screen.contentMaxWidth`) for the zones that draw their own
        /// column: the app bar and the bar of navigation. `nil` elsewhere.
        var contentMaxWidth: Double?
        /// The bar of navigation whose items stand in the app bar this context draws (`NavBar.widePlacement`).
        var nav: DocumentNode?
        /// The nav item stands at the top: in the app bar or in a bar of its own.
        var navAtTop = false
    }

    var screen: ScreenEnv
    var list = ListEnv()
    var bar = BarEnv()
    /// The data the node reads: the host's data under the session and the record.
    var scope: DataScope
    /// The moment countdowns and «days until» count from, in milliseconds since 1970.
    var now: Double
    /// What the node inherits from its ancestors (colour, text style, emphasis).
    var inherited: InheritedLook

    init(
        resolver: StyleResolver, screenId: String, localization: DocumentLocalization?, locale: LocaleResolution, scope: DataScope,
        timeZone: TimeZone?, now: Double, rightToLeft: Bool, inherited: InheritedLook, sink: ReportSink, images: ImagePolicy,
        pressHandler: @escaping (JSONObject, DocumentNode, [ListInstance]) -> PressRun, backLabel: String = ScreenLabels().back,
        write: ((String, JSONValue) -> Void)? = nil, carousels: CarouselMemory? = nil, frameIndex: Int = 0
    ) {
        screen = ScreenEnv(
            resolver: resolver, screenId: screenId, localization: localization, locale: locale, timeZone: timeZone, rightToLeft: rightToLeft,
            sink: sink, images: images, pressHandler: pressHandler, backLabel: backLabel, write: write, carousels: carousels, frameIndex: frameIndex)
        self.scope = scope
        self.now = now
        self.inherited = inherited
    }

    // MARK: The groups, read flat

    var resolver: StyleResolver { screen.resolver }
    var screenId: String { screen.screenId }
    var localization: DocumentLocalization? { screen.localization }
    var locale: LocaleResolution { screen.locale }
    var timeZone: TimeZone? { screen.timeZone }
    var rightToLeft: Bool { screen.rightToLeft }
    var sink: ReportSink { screen.sink }
    var images: ImagePolicy { screen.images }
    var pressHandler: (JSONObject, DocumentNode, [ListInstance]) -> PressRun { screen.pressHandler }
    var backLabel: String { screen.backLabel }
    var write: ((String, JSONValue) -> Void)? { screen.write }
    var form: ScreenForm? {
        get { screen.form }
        set { screen.form = newValue }
    }
    var carousels: CarouselMemory? { screen.carousels }
    var frameIndex: Int { screen.frameIndex }
    var listBudget: ListBudget.Plan? {
        get { screen.listBudget }
        set { screen.listBudget = newValue }
    }
    var widthClass: WidthClass {
        get { screen.widthClass }
        set { screen.widthClass = newValue }
    }

    var instances: [ListInstance] {
        get { list.instances }
        set { list.instances = newValue }
    }
    var instancePath: [Int] {
        get { list.instancePath }
        set { list.instancePath = newValue }
    }
    var listPosition: ListPosition? {
        get { list.position }
        set { list.position = newValue }
    }
    var listNumber: ListNumber? {
        get { list.number }
        set { list.number = newValue }
    }
    var choice: ChoiceScope? {
        get { list.choice }
        set { list.choice = newValue }
    }

    var barScrolled: Bool {
        get { bar.scrolled }
        set { bar.scrolled = newValue }
    }
    var barInset: Double {
        get { bar.inset }
        set { bar.inset = newValue }
    }
    var navInset: Double {
        get { bar.navInset }
        set { bar.navInset = newValue }
    }
    var navLine: Double {
        get { bar.navLine }
        set { bar.navLine = newValue }
    }
    var contentMaxWidth: Double? {
        get { bar.contentMaxWidth }
        set { bar.contentMaxWidth = newValue }
    }
    var barNav: DocumentNode? {
        get { bar.nav }
        set { bar.nav = newValue }
    }
    var navAtTop: Bool {
        get { bar.navAtTop }
        set { bar.navAtTop = newValue }
    }

    var theme: HotlayoutTheme { resolver.theme }

    /// Whether a node is shown: its class is listed and its condition holds (`WidthRules.isShown`).
    /// `scope` is the data of another record when the node is a list template.
    func isShown(_ node: DocumentNode, scope other: DataScope? = nil) -> Bool {
        WidthRules.isShown(node, widthClass, scope: other ?? scope)
    }

    func press(_ action: JSONObject, _ node: DocumentNode) {
        _ = pressHandler(action, node, instances)
    }

    /// A press whose outcome the caller waits for (`Button.confirm: 'swipe'`).
    func run(_ action: JSONObject, _ node: DocumentNode) -> PressRun {
        pressHandler(action, node, instances)
    }

    func with(inherited look: InheritedLook) -> RenderContext {
        var copy = self
        copy.inherited = look
        return copy
    }

    var textEnvironment: TextEnvironment {
        TextEnvironment(
            scope: scope,
            formattingLocale: locale.formatting,
            fallbackLocale: locale.translation ?? locale.directionLocale,
            timeZone: timeZone,
            now: now,
            rightToLeft: rightToLeft
        )
    }

    /// The language of one string field of a node: translations live under
    /// `<screenId>/<nodeId>/<field>` and, inside a template, `<key>.<path>`.
    func language(node: DocumentNode, field: String) -> TemplateLanguage {
        let key = Localization.key(screenId: screenId, nodeId: node.id, field: field)
        let localization = self.localization
        let translation = locale.translation
        return TemplateLanguage(
            translationLocale: translation,
            sourceLocale: localization?.defaultLocale,
            translated: { sub in
                Localization.translate(localization, translation: translation, key: sub.isEmpty ? key : "\(key).\(sub)")
            }
        )
    }

    /// The SHOWN text of a string field (`x-style.layout.shownText`).
    func text(_ node: DocumentNode, field: String) -> String {
        ShownText.of(
            BindableText.text(
                node.props[field], language: language(node: node, field: field), environment: textEnvironment, sink: sink,
                location: "screen “\(screenId)”: node “\(node.id)”: \(field)"))
    }
}

/// Who ran an action and, for a host action the host answered with a task, that task
/// (`HotlayoutScreen`'s `onAction` of the `async` form).
struct PressRun {
    var runner: SwipeConfirmRules.Runner
    var task: Task<Void, Never>?
}

/// Which image addresses the reader may load, and how much it may take for one picture.
///
/// The host decides the address: `resolve` turns an address of the document into a URL, or `nil`
/// for the placeholder. By default (`httpsOnly`) the address must have exactly the form of the
/// contract's `openUrl` address: `https:`, a host name with an alphabetic top-level domain, no
/// user information; IP literals in any base, IPv6, `localhost` and single-label names are
/// refused. A host that needs an internal or numeric address passes its own `resolve`, and its
/// answer is final, except that an address with the scheme `javascript:` or `vbscript:` is never
/// loaded. A refused address makes no request and goes to `onReport`.
///
/// The same `resolve` is asked again for every redirect a server answers with (at most three are
/// followed); a target it refuses is not followed. Pictures are fetched with a private session that
/// has no cookie storage, no shared cache, no credentials of the host app and no `Referer`, and
/// one picture, redirects included, has 30 seconds.
public struct ImagePolicy: Sendable {
    /// The default for `maxDownloadBytes`: 10 MiB (10 485 760 bytes) for one picture.
    public static let defaultMaxDownloadBytes = 10 * 1024 * 1024
    /// The default for `maxPixelSide`: the longer side of a decoded picture, 4096 pixels.
    public static let defaultMaxPixelSide = 4096

    /// Turns an address of the document into a URL to load, or `nil` to draw the placeholder.
    public var resolve: @Sendable (String) -> URL? {
        get {
            let inner = Self.judged(rawResolve)
            let limits = limits
            return { address in
                guard let url = inner(address) else { return nil }
                ImageSources.shared.register(url, resolve: inner, limits: limits)
                return url
            }
        }
        set { rawResolve = newValue }
    }
    /// URLs of the host's asset tokens (`logo`, `banner`, `placeholder`).
    public var assets: [String: URL]
    /// The most bytes of one picture the reader accepts (checked against `Content-Length` and
    /// while reading); a larger one is the placeholder.
    public var maxDownloadBytes: Int {
        get { limits.maxBytes }
        set { limits.maxBytes = Swift.max(1, newValue) }
    }
    /// The longest side, in pixels, a picture is decoded at. A larger one is made smaller, its
    /// proportion kept; it is not refused.
    public var maxPixelSide: Int {
        get { limits.maxSide }
        set { limits.maxSide = Swift.max(1, newValue) }
    }

    private var rawResolve: @Sendable (String) -> URL?
    private var limits: ImageLimits

    public init(
        assets: [String: URL] = [:],
        maxDownloadBytes: Int = ImagePolicy.defaultMaxDownloadBytes,
        maxPixelSide: Int = ImagePolicy.defaultMaxPixelSide,
        resolve: @escaping @Sendable (String) -> URL? = ImagePolicy.httpsOnly
    ) {
        self.assets = assets
        self.rawResolve = resolve
        self.limits = ImageLimits(maxBytes: Swift.max(1, maxDownloadBytes), maxSide: Swift.max(1, maxPixelSide))
    }

    /// The host's answer, except that a script address is never a picture whatever the host says.
    private static func judged(_ inner: @escaping @Sendable (String) -> URL?) -> @Sendable (String) -> URL? {
        { address in
            guard let url = inner(address), !ImageSourceRules.neverAnImage(url.absoluteString) else { return nil }
            return url
        }
    }

    /// The default: the address has the form of an `openUrl` address of the contract
    /// (`ActionCatalog.formProblem("httpsUrl", …)`), so a numeric or IPv6 host, `localhost` and
    /// user information are refused.
    public static let httpsOnly: @Sendable (String) -> URL? = { address in
        guard ActionCatalog.formProblem("httpsUrl", address) == nil, let url = URL(string: address), url.scheme == "https",
            url.host != nil, url.user == nil, url.password == nil
        else { return nil }
        return url
    }
}

extension RGBA {
    var color: Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha) }
}

extension TextStyleValue {
    /// The SwiftUI font of a theme text style. The theme names a family the device may not
    /// have; the system font stands in for it (the family's own fallback list ends there too).
    func font(family: String?, italic: Bool = false) -> Font {
        let weight = Font.Weight(cssWeight: fontWeight)
        var font: Font
        if let family, Self.isInstalled(family) {
            font = .custom(family, fixedSize: fontSize).weight(weight)
        } else {
            font = .system(size: fontSize, weight: weight)
        }
        if italic { font = font.italic() }
        return font
    }

    /// The natural line height of the font at this size, in points.
    var naturalLineHeight: Double {
        #if canImport(UIKit)
        return Double(UIFont.systemFont(ofSize: fontSize).lineHeight)
        #else
        let font = NSFont.systemFont(ofSize: fontSize)
        return Double(font.ascender - font.descender + font.leading)
        #endif
    }

    /// The natural line height of the font the style is drawn in: the installed family of the theme for
    /// its role, else the system font the reader falls back to.
    func naturalLineHeight(in theme: HotlayoutTheme) -> Double {
        #if canImport(UIKit)
        if let family = theme.fontFamilies[role == "heading" ? "heading" : "body"], let name = UIFont.fontNames(forFamilyName: family).first,
            let font = UIFont(name: name, size: fontSize)
        {
            return Double(font.lineHeight)
        }
        #else
        if let family = theme.fontFamilies[role == "heading" ? "heading" : "body"],
            let member = NSFontManager.shared.availableMembers(ofFontFamily: family)?.first, let name = member.first as? String,
            let font = NSFont(name: name, size: fontSize)
        {
            return Double(font.ascender - font.descender + font.leading)
        }
        #endif
        return naturalLineHeight
    }

    /// The line box the contract asks for (`lineHeight` × size).
    var lineBox: Double { fontSize * lineHeight }

    static func isInstalled(_ family: String) -> Bool {
        #if canImport(UIKit)
        return !UIFont.fontNames(forFamilyName: family).isEmpty
        #else
        return NSFontManager.shared.availableMembers(ofFontFamily: family) != nil
        #endif
    }
}

extension Font.Weight {
    init(cssWeight: Int) {
        switch cssWeight {
        case ..<150: self = .ultraLight
        case ..<250: self = .thin
        case ..<350: self = .light
        case ..<450: self = .regular
        case ..<550: self = .medium
        case ..<650: self = .semibold
        case ..<750: self = .bold
        case ..<850: self = .heavy
        default: self = .black
        }
    }
}

extension RenderContext {
    /// The context of one record of a list from data: its scope over the outer one, and the
    /// instance added to the ones the node is drawn inside (so that a press carries the record).
    func inListInstance(scope itemScope: DataScope, instance: ListInstance, number: ListNumber?, index: Int? = nil) -> RenderContext {
        var copy = self
        if let index { copy.instancePath = instancePath + [index] }
        copy.scope = itemScope
        copy.instances = instances + [instance]
        copy.listNumber = number
        return copy
    }
}
