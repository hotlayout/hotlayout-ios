import HotLayout
import SwiftUI

/// The three showcase apps — Obsidian, Sunny and Orbit — drawn by the reader from their own documents.
/// Each app is a folder of `fixtures/apps/<id>/`: the document, the theme and the answer of a backend.
enum ShowcaseApp: String, CaseIterable, Identifiable {
    case obsidian, sunny, orbit

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    private var folder: URL? { Fixtures.folder?.appendingPathComponent("apps/\(rawValue)") }

    private func json(_ name: String) throws -> JSONValue {
        guard let url = folder?.appendingPathComponent(name) else { throw CocoaError(.fileNoSuchFile) }
        return try JSONValue.parse(Data(contentsOf: url))
    }

    /// The document; `screenId` replaces the initial screen.
    func document(screenId: String? = nil) throws -> HotlayoutDocument {
        var root = try json("document.json")
        if let screenId, case .object(var object) = root {
            object["initialScreenId"] = .string(screenId)
            root = .object(object)
        }
        return try HotlayoutDocument.load(root)
    }

    /// The theme names variable fonts by the name of the web's font file («Geist Variable»); the family the
    /// system knows the bundled file by is «Geist».
    func theme() -> HotlayoutThemeSet {
        guard let url = folder?.appendingPathComponent("theme.json"),
            var text = try? String(contentsOf: url, encoding: .utf8)
        else { return .builtIn }
        text = text.replacingOccurrences(of: "Geist Variable", with: "Geist")
        return (try? HotlayoutThemeSet.load(Data(text.utf8))) ?? .builtIn
    }

    /// The moment the sample data was taken and the data of the app in the language of the screen.
    func hostData(locale: String, scenario: String?, tab: String?) -> (data: DataScope, now: Date?) {
        guard let root = try? json(self == .orbit ? "sample-data.json" : "data.json"), case .object(let object) = root else { return ([:], nil) }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let now = object["now"]?.stringValue.flatMap { formatter.date(from: $0) }
        let answer: JSONValue?
        if self == .orbit {
            let scenarios = object["scenarios"]?.objectValue
            answer = scenarios?[scenario ?? "default"] ?? scenarios?["default"]
        } else {
            let short = locale.split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map(String.init) ?? "en"
            answer = object[short] ?? object["en"]
        }
        var scope = DataScope()
        for (key, value) in answer?["data"]?.objectValue ?? [:] { scope[key] = value }
        for (key, value) in answer?["collections"]?.objectValue ?? [:] { scope[key] = value }
        if let tab { scope["ui.missionsTab"] = .string(tab) }
        return (scope, now)
    }

    /// The pictures of the apps live on the site: an address of Obsidian and Sunny names a path of it.
    /// This is the host's decision; the reader's own rule (https only) is left as it is.
    static let images = ImagePolicy(resolve: { address in
        if address.hasPrefix("/landing/demo/") { return URL(string: "https://hotlayout.com" + address) }
        return ImagePolicy.httpsOnly(address)
    })
}

struct ShowcaseScreen: View {
    let app: ShowcaseApp
    let locale: String?
    let entry: String?

    /// What the app is drawn from, read once per app and language, not on every evaluation of `body`.
    private struct Loaded {
        let document: Result<HotlayoutDocument, Error>
        let theme: HotlayoutThemeSet
        let host: (data: DataScope, now: Date?)
    }

    @State private var loaded: Loaded?

    var body: some View {
        Group {
            switch loaded?.document {
            case .success(let document)?:
                if let loaded {
                    HotlayoutScreen(
                        document: document, theme: loaded.theme, data: loaded.host.data, locale: locale ?? "en", entry: entry,
                        timeZone: TimeZone(identifier: "UTC"), now: loaded.host.now, images: ShowcaseApp.images,
                        onAction: { action, _ in NSLog("action %@", action.type) },
                        onReport: { reports in reports.forEach { NSLog("report %@", String(describing: $0)) } }
                    )
                    .id(app.rawValue + (locale ?? ""))
                }
            case .failure(let error)?:
                Text("Could not open \(app.title): \(String(describing: error))").padding()
            case nil:
                Color.clear
            }
        }
        .task(id: app.rawValue + (locale ?? "")) {
            let defaults = UserDefaults.standard
            loaded = Loaded(
                document: Result { try app.document(screenId: defaults.string(forKey: "screen")) },
                theme: app.theme(),
                host: app.hostData(locale: locale ?? "en", scenario: defaults.string(forKey: "scenario"), tab: defaults.string(forKey: "tab"))
            )
        }
    }
}

/// The first screen of the demo: Obsidian, with a small menu to switch to another app or to the fixtures.
struct ShowcaseHome: View {
    @State private var app: ShowcaseApp = .obsidian
    @State private var showFixtures = false

    var body: some View {
        ShowcaseScreen(app: app, locale: nil, entry: nil)
            .id(app)
            .overlay(alignment: .topTrailing) {
                Menu {
                    ForEach(ShowcaseApp.allCases) { item in
                        Button(item.title) { app = item }
                    }
                    Button("Fixtures") { showFixtures = true }
                } label: {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(8)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .padding(.trailing, 76)
                .padding(.top, 2)
                .accessibilityIdentifier("demo-app-menu")
            }
            .sheet(isPresented: $showFixtures) {
                NavigationStack {
                    List(Fixtures.names, id: \.self) { name in
                        NavigationLink(name) { FixtureScreen(name: name, screenId: nil, locale: nil) }
                    }
                    .navigationTitle("HotLayout fixtures")
                }
            }
    }
}
