import CoreText
import HotLayout
import SwiftUI

/// A viewer of the contract's screen fixtures, drawn with the reader through its public API only.
/// The UI tests drive it.
///
/// Launch arguments open one screen directly:
///   -fixture <file name without .json>   -screen <screenId>   -locale <tag>
///   -app obsidian|sunny|orbit   a showcase app on its own, with the window to itself
///   -screen <screenId>   with -app: the screen the app opens on
///   -entry <name>   a named entry point of the app   -scenario <name>   -tab <name>   data of Orbit
///   -contractSamples YES   the samples of the data dictionary and a fixed clock
///   -clock running         with -contractSamples: the clock starts at the samples' moment and runs
///   -showActions YES       what reached the host, as text the UI tests read
///   -fontReport YES        whether the theme's body family is installed
///   -landscape YES         the window turned to the side
@main
struct HotlayoutDemoApp: App {
    init() { DemoFonts.register() }

    var body: some Scene {
        WindowGroup {
            DemoRoot()
        }
    }
}

struct DemoRoot: View {
    private let launch = UserDefaults.standard

    var body: some View {
        if let app = launch.string(forKey: "app").flatMap(ShowcaseApp.init(rawValue:)) {
            ShowcaseScreen(app: app, locale: launch.string(forKey: "locale"), entry: launch.string(forKey: "entry"))
        } else if launch.bool(forKey: "fixtureList") {
            fixtureList
        } else if let fixture = launch.string(forKey: "fixture") {
            FixtureScreen(name: fixture, screenId: launch.string(forKey: "screen"), locale: launch.string(forKey: "locale"))
        } else {
            ShowcaseHome()
        }
    }

    private var fixtureList: some View {
        NavigationStack {
            List(Fixtures.names, id: \.self) { name in
                NavigationLink(name) { ListedFixture(name: name) }
            }
            .navigationTitle("HotLayout fixtures")
        }
    }
}

/// A fixture opened from the list. The document draws its own bar, so the demo's navigation bar is
/// hidden; the arrow of the document, which has nowhere to go back to on its first screen, comes to
/// the host as `navigate.back`, and the host closes the screen.
struct ListedFixture: View {
    let name: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        FixtureScreen(name: name, screenId: nil, locale: nil, onBackAtRoot: { dismiss() })
            .toolbar(.hidden, for: .navigationBar)
            .background(SwipeBackRestorer())
    }
}

/// Hiding the navigation bar turns off the edge swipe that goes back; this gives it back.
private struct SwipeBackRestorer: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ controller: Controller, context: Context) {}

    final class Controller: UIViewController, UIGestureRecognizerDelegate {
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            guard let pop = navigationController?.interactivePopGestureRecognizer else { return }
            pop.delegate = self
            pop.isEnabled = true
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            (navigationController?.viewControllers.count ?? 0) > 1
        }
    }
}

enum Fixtures {
    static var folder: URL? { Bundle.main.url(forResource: "fixtures", withExtension: nil) }

    static var names: [String] {
        guard let folder, let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { return [] }
        return files.filter { $0.pathExtension == "json" }.map { $0.deletingPathExtension().lastPathComponent }.sorted()
    }

    /// The document of a fixture; `screenId` replaces the initial screen.
    static func document(_ name: String, screenId: String?) throws -> HotlayoutDocument {
        guard let url = folder?.appendingPathComponent("\(name).json") else { throw CocoaError(.fileNoSuchFile) }
        var json = try JSONValue.parse(Data(contentsOf: url))
        if let screenId, case .object(var object) = json {
            object["initialScreenId"] = .string(screenId)
            json = .object(object)
        }
        return try HotlayoutDocument.load(json)
    }

    /// The fixture's own theme (`themes/<name>-theme.json` without the `-screens` suffix), if any.
    static func theme(_ name: String) -> HotlayoutThemeSet {
        let base = name.replacingOccurrences(of: "-screens", with: "")
        guard let url = folder?.appendingPathComponent("themes/\(base)-theme.json"),
            let data = try? Data(contentsOf: url), let set = try? HotlayoutThemeSet.load(data)
        else { return .builtIn }
        return set
    }
}

/// The demo has no network: an address of the sample data names a picture bundled with the app.
enum SampleImages {
    static let policy = ImagePolicy(resolve: { address in
        // The samples of the data dictionary carry `data:` pictures.
        if SampleData.useContractSamples, address.hasPrefix("data:image/") { return URL(string: address) }
        guard let url = URL(string: address), url.host == "images.hotlayout.example" else { return ImagePolicy.httpsOnly(address) }
        return Bundle.main.url(forResource: "fixtures/images/" + url.deletingPathExtension().lastPathComponent, withExtension: "png")
    })
}

/// Data for the fixtures that draw lists: the lists are empty without it.
enum SampleData {
    /// `-contractSamples YES`: the samples of the data dictionary (`sample-data/contract-samples.json`,
    /// without `survey.*`) and the moment they were taken, the data the other readers' demos show.
    static var useContractSamples: Bool { UserDefaults.standard.bool(forKey: "contractSamples") }

    static func chosen(for fixture: String) -> DataScope {
        guard useContractSamples,
            let url = Fixtures.folder?.appendingPathComponent("sample-data/contract-samples.json"),
            let data = try? Data(contentsOf: url), case .object(let object)? = try? JSONValue.parse(data)
        else { return scope(for: fixture) }
        return Dictionary(object.map { ($0.key, $0.value) }, uniquingKeysWith: { first, _ in first })
    }

    static var now: Date? {
        useContractSamples ? ISO8601DateFormatter().date(from: "2026-10-10T09:00:00Z") : nil
    }

    static func scope(for fixture: String) -> DataScope {
        let names = ["Backpack", "Bottle", "Headphones", "Notebook", "Mug"]
        let items: [JSONValue] = names.enumerated().map { index, name in
            .object(["id": .string(name.lowercased()), "name": .string(name), "image": .string("https://images.hotlayout.example/\(["wide", "square", "tall"][index % 3]).png"), "selectedId": .string(index < 3 ? "backpack" : "coffee"), "category": .string(index < 3 ? "gear" : "home")])
        }
        let activities: [JSONValue] = [
            ["title": "Coffee week", "day": "Today", "points": 120], ["title": "Movie night", "day": "Today", "points": 80],
            ["title": "Strong week", "day": "Yesterday", "points": 60], ["title": "Weekend trip", "day": "Wed, Oct 14", "points": 250],
        ]
        let tasks: [JSONValue] = (1...5).map { ["title": .string("Challenge \($0)"), "progress": .number(Double($0 * 3)), "target": 20] }
        return ["items": .array(items), "activities": .array(activities), "tasks": .array(tasks), "user.points": 12_400]
    }
}

struct FixtureScreen: View {
    let name: String
    let screenId: String?
    let locale: String?
    /// Called when the document's own «back» has no screen left to return to (`navigate.back` on the
    /// first screen reaches the host). Nil when the demo runs straight on a fixture.
    var onBackAtRoot: (() -> Void)?
    @State private var lastAction = ""
    /// `-showActions YES`: what reached the host, counted, as text the UI tests can read.
    @State private var actionLog: [String] = []
    @State private var clockStart = Date()
    private var showActions: Bool { UserDefaults.standard.bool(forKey: "showActions") }

    var body: some View {
        switch Result(catching: { try Fixtures.document(name, screenId: screenId) }) {
        case .success(let document):
            clocked(document)
            .overlay(alignment: .topLeading) {
                if showActions {
                    Text("actions=\(actionLog.count) " + actionLog.joined(separator: ","))
                        .font(.system(size: 9)).foregroundStyle(.red).allowsHitTesting(false)
                        .accessibilityIdentifier("demo-action-log")
                }
            }
            .overlay(alignment: .bottomLeading) {
                if UserDefaults.standard.bool(forKey: "fontReport") {
                    Text(DemoFonts.report(for: Fixtures.theme(name)))
                        .font(.system(size: 9)).foregroundStyle(.red).allowsHitTesting(false)
                        .accessibilityIdentifier("demo-font-report")
                }
            }
            .onAppear {
                // `-landscape` turns the window to the side: the frames of a tablet that lies down.
                #if os(iOS)
                guard UserDefaults.standard.bool(forKey: "landscape"),
                    let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
                scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscape))
                #endif
            }
        case .failure(let error):
            Text("Could not open \(name): \(String(describing: error))").padding()
        }
    }

    /// `-clock running` (with `-contractSamples`): the host's clock starts at the moment of the samples
    /// and goes on a whole second at a time, as the prototype of the editor runs it. The reader does not
    /// tick under a moment the host gives; the host that owns the clock moves it.
    @ViewBuilder
    private func clocked(_ document: HotlayoutDocument) -> some View {
        if UserDefaults.standard.string(forKey: "clock") == "running", let samples = SampleData.now {
            TimelineView(.periodic(from: clockStart, by: 1)) { timeline in
                reader(document, now: samples.addingTimeInterval(timeline.date.timeIntervalSince(clockStart).rounded(.down)))
            }
        } else {
            reader(document, now: SampleData.now)
        }
    }

    private func reader(_ document: HotlayoutDocument, now: Date?) -> HotlayoutScreen {
        HotlayoutScreen(
            document: document,
            theme: Fixtures.theme(name),
            data: SampleData.chosen(for: name),
            locale: locale ?? Locale.current.identifier,
            now: now,
            images: SampleImages.policy,
            onAction: { action, _ in
                lastAction = action.type
                let verdict = action.standard != nil ? "standard" : (action.invalid.map { "invalid:\($0.param)" } ?? "other")
                actionLog.append("\(action.type)|\(verdict)")
                if action.type == "navigate.back" { onBackAtRoot?() }
            },
            onTrack: { event, _ in actionLog.append("track:\(event.event)") },
            onScreenChange: { event in
                print("shown", event.screenId, event.cause.rawValue)
                actionLog.append("shown:\(event.screenId):\(event.cause.rawValue)")
            },
            onReport: { reports in reports.forEach { print("report", $0) } }
        )
    }
}

/// The theme of the showcase names Inter. The package ships no fonts (the app provides them), so
/// the demo bundles Inter, Geist and Manrope (SIL Open Font License, `Fonts/OFL-*.txt`) and registers it for the
/// process before the first screen is drawn.
enum DemoFonts {
    static func register() {
        let fonts = Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? []
        for url in fonts {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    /// `-fontReport YES`: the family the theme names for the body and whether the reader will use it.
    static func report(for set: HotlayoutThemeSet) -> String {
        let family = set.theme(nil).fontFamilies["body"] ?? "none"
        return "body-family=\(family) installed=\(!UIFont.fontNames(forFamilyName: family).isEmpty)"
    }
}
