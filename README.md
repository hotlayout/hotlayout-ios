# HotLayout for iOS

A Swift package that draws screens published by the [HotLayout](https://hotlayout.com)
builder: a JSON document, a theme and your data become a native SwiftUI screen.

It reads the same contract as the React and Flutter readers (document schema **9.28.0**, theme
**4.0.1**, icon set **1.0.0**) and is measured by the same shared case tables. All 28 widgets of
the contract are drawn.

## Requirements

- iOS 16 or later
- Swift 5.9 or later, no third-party dependencies

macOS 13 is declared so that the tests run with `swift test`; it is not a product platform.

## Install

HotLayout is installed with Swift Package Manager.

**In `Package.swift`:**

```swift
dependencies: [
    .package(url: "https://github.com/hotlayout/hotlayout-ios", from: "0.2.2"),
],
targets: [
    .target(name: "MyApp", dependencies: [
        .product(name: "HotLayout", package: "hotlayout-ios"),
    ]),
]
```

**In Xcode:**

1. Choose File > Add Package Dependencies...
2. Paste `https://github.com/hotlayout/hotlayout-ios` into the search field.
3. Set the dependency rule to Up to Next Major Version, from `0.2.2`, and choose Add Package.
4. Add the `HotLayout` library to your app target, then `import HotLayout`.

## Use

```swift
import HotLayout
import SwiftUI

struct RewardsScreen: View {
    /// `published.json` of a document and, optionally, `theme/published.json` of its project.
    let documentData: Data
    let themeData: Data?
    @Environment(\.openURL) private var openURL
    // The JSON is read once, in `.task`, not on every evaluation of `body`.
    @State private var document: HotlayoutDocument?
    @State private var theme = HotlayoutThemeSet.builtIn
    @State private var failure: HotlayoutLoadError?

    var body: some View {
        Group {
            if let document {
                HotlayoutScreen(
                    document: document,
                    theme: theme,
                    data: ["user.name": "Maya", "user.points": 1850],
                    locale: Locale.current.identifier,  // the device locale, as is
                    entry: "promo",                     // a named entry point, optional
                    onAction: { action, _ in
                        // The reader opens nothing itself; a standard action arrives checked.
                        if let url = StandardActions.url(for: action) { openURL(url) }
                    },
                    onTrack: { event, _ in print("analytics", event.event, event.params ?? [:]) },
                    onNavigate: { event in event.to != "admin" },  // `false` cancels a change of screen
                    onScreenChange: { shown in print("shown", shown.screenId, shown.cause) },
                    onReport: { reports in reports.forEach { print($0) } }
                )
            } else if let failure {
                Text("This screen is not available: \(failure.description)")
            } else {
                // Not an empty `Group`: an empty view on the first frame never runs `.task`.
                ProgressView()
            }
        }
        .task {
            do {
                document = try HotlayoutDocument.load(documentData)
                if let themeData, let set = try? HotlayoutThemeSet.load(themeData) { theme = set }
            } catch let error as HotlayoutLoadError {
                failure = error
            } catch {
                failure = .malformedJSON(String(describing: error))
            }
        }
    }
}
```

**Device language.** `Locale.current` gives the language of the device only if the app declares
the languages it is localized for (the app's localizations in the Xcode project, or
`CFBundleLocalizations` in `Info.plist`). Without that iOS reports English, and a document that has an
Arabic translation stays English on an Arabic device. Declare the languages of your documents, or
pass `Locale.preferredLanguages.first` as `locale`.

An `onAction` may be `async`. A button that confirms by a swipe then stays busy until the
handler returns (with a plain handler: until the screen changes, or eight seconds):

```swift
struct CheckoutScreen: View {
    let document: HotlayoutDocument
    let redeem: (String?) async -> Void

    var body: some View {
        // An `async` handler: a button that confirms by a swipe stays busy until it returns.
        HotlayoutScreen(document: document, onAction: { action, source async in
            if action.type == "redeem" { await redeem(source.record?["item.id"]?.stringValue) }
        })
    }
}
```

The module is called `HotLayout` and its types `Hotlayout…`, on purpose: the names match the other readers
of the contract. The global functions `loadDocument`, `loadTheme`, `checkVersion`,
`checkDocumentVersion` and `resolveLocale` still work as deprecated forwards of the members below.

The public API, besides the view:

| | |
|---|---|
| `HotlayoutDocument.load(_:)`, `HotlayoutThemeSet.load(_:)` | read a document or a theme from `Data` or a parsed `JSONValue`; throw `HotlayoutLoadError` |
| `HotlayoutVersions.checkDocument(_:)`, `HotlayoutVersions.check(_:readerVersion:)`, `HotlayoutVersions` | the version rule, without reading the whole document |
| `LocaleResolution.resolve(_:available:source:)` | which translation, number format and direction a device locale gets |
| `HotlayoutAction`, `StandardAction`, `StandardActions.url(for:allowedDeeplinkSchemes:)` | what reaches `onAction`, and a helper for the standard actions |
| `TrackEvent`, `HapticFeedback`, `NavigationEvent`, `ScreenShownEvent`, `ActionSource` | what the other callbacks receive |
| `ImagePolicy`, `WritablePaths`, `ScreenLabels` | decisions of the host: pictures, writable data paths, texts of the reader |
| `HotlayoutReport` | what the reader skipped or replaced; never shown to the person |

## What the reader does and does not do

- **Documents, themes and data are untrusted input.** A piece of the wrong shape is skipped and
  reported (`onReport`), never a crash. A tree deeper than 32 levels is refused. See
  [the security model](docs/security.md).
- **Navigation** inside a document (`navigate`, `navigate.back`, `navigate.section`) is done by
  the reader; `onNavigate` may cancel it. `openUrl`, `deeplink`, `close` and the actions of your app
  go to `onAction`, checked against the forms of the contract. Writes (fields, `setValue`,
  `toggleValue`) go to the session of the screen and to `onWrite`.
- **Images** load only from an address of the form of an `openUrl` address (`https:` and a public
  host name) by default. Pass an `ImagePolicy` to decide yourself (`resolve`; your answer is final,
  except that `javascript:` and `vbscript:` are never a picture), to give URLs for the asset tokens
  (`logo`, `banner`, `placeholder`), and to set `maxDownloadBytes` (10 MiB by default) and
  `maxPixelSide` (4096: a larger picture is made smaller, not refused). A refused address makes no
  request and goes to `onReport`.
- **Lists** draw at most 2550 instances of list templates per screen, nested lists included; what
  is beyond is not drawn and is reported once.
- **Haptic feedback** is asked of the host (`onHaptic`); the reader never vibrates.
- **Fonts** are the app's: the package ships none. A family the theme names that the device lacks
  is drawn with the system font.

Where Apple's platform differs from the other readers is listed in
[the platform notes](docs/platform-notes.md).

## The contract

The contract is a set of JSON artifacts: `screen-schema.json` (the widgets, their fields and the
rules of drawing in its `x-…` blocks), `theme.json`, `data-contract.json` and `icons.json`, with
the shared case tables in `fixtures/`. Comments in this package name the `x-…` blocks they follow.

`scripts/sync-contract.sh <path>` copies a checkout of the contract into the package: the
artifacts and tables the tests read, the fixtures of the demo, the icon set and the built-in theme.
The tests compare every copy the reader ships with the artifacts.

## Run

```sh
swift test                                    # rules, tables and off-screen drawing on macOS

# the same unit tests on iOS: boot a simulator without its window, then test the package scheme
xcrun simctl boot <device-id>
xcodebuild test -scheme HotLayout -destination 'platform=iOS Simulator,id=<device-id>'
xcrun simctl shutdown <device-id>

# the fixture viewer and its UI tests on a simulator
cd Demo
xcodebuild -project HotlayoutDemo.xcodeproj -scheme HotlayoutDemoUITests \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro Max' -derivedDataPath build test
```

The demo (`Demo/`) uses the public API only. Without launch arguments it opens on Obsidian, one of
three showcase apps (Obsidian, Sunny and Orbit; their documents, themes and sample data are in
`Demo/fixtures/apps/`), with a small menu to switch app or to open the fixture list. Their pictures
are loaded from hotlayout.com: the demo resolves the site-relative addresses of the documents itself,
the reader's own rule (https only) is not relaxed. `-app obsidian|sunny|orbit -screen <screenId>
-entry <name> -locale <tag>` opens one app on its own; `-fixtureList YES` lists every fixture of the
contract, and `-fixture <name> -screen <screenId> -locale <tag>` opens one screen of it. What the tests check
is described in [Tests/README.md](Tests/README.md).

## License

Apache License 2.0, see [LICENSE](LICENSE). The icon drawings include icons from Lucide (ISC);
see [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).
