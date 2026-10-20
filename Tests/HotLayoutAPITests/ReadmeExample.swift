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

    var body: some View {
        if let document = try? loadDocument(documentData) {
            HotlayoutScreen(
                document: document,
                theme: themeData.flatMap { try? loadTheme($0) } ?? .builtIn,
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
        } else {
            Text("This screen is not available.")
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
