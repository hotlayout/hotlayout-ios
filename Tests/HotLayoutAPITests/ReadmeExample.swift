// The example of the README, compiled against the public API only (no `@testable`).
// `ReadmeExampleTests` checks that the README carries the region below word for word.

// #region readme
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
// #endregion readme

// #region readme-async
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
// #endregion readme-async
