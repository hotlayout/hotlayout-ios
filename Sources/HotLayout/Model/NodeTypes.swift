import Foundation

/// The widgets of the schema (`x-compatibility.widgets`). A document may name a type the reader
/// does not know; `WidgetType(rawValue:)` is `nil` for it, and the node is drawn as its children.
enum WidgetType: String, CaseIterable {
    case screen = "Screen"
    case appBar = "AppBar"
    case column = "Column"
    case row = "Row"
    case container = "Container"
    case grid = "Grid"
    case stack = "Stack"
    case tabs = "Tabs"
    case tab = "Tab"
    case accordion = "Accordion"
    case choiceGroup = "ChoiceGroup"
    case repeater = "Repeater"
    case spacer = "Spacer"
    case divider = "Divider"
    case text = "Text"
    case image = "Image"
    case icon = "Icon"
    case button = "Button"
    case iconButton = "IconButton"
    case listTile = "ListTile"
    case progressBar = "ProgressBar"
    case circularProgress = "CircularProgress"
    case badge = "Badge"
    case navBar = "NavBar"
    case navItem = "NavItem"
    case textField = "TextField"
    case `switch` = "Switch"
    case checkbox = "Checkbox"

    init?(_ type: String?) {
        guard let type else { return nil }
        self.init(rawValue: type)
    }
}

extension Set where Element == WidgetType {
    /// Whether the set holds the widget; a type the reader does not know is in no set.
    func contains(_ widget: WidgetType?) -> Bool { widget.map { contains($0) } ?? false }
}

extension DocumentNode {
    /// The widget of the node, `nil` for a type this reader does not know.
    var widget: WidgetType? { WidgetType(rawValue: type) }
}

/// The actions of the catalog (`x-actions`). The `type` of an action stays an open string: a host
/// may own types the catalog does not name.
enum ActionType: String {
    case none
    case navigate
    case navigateBack = "navigate.back"
    case navigateSection = "navigate.section"
    case openUrl
    case deeplink
    case close
    case setValue
    case toggleValue

    init?(_ type: String?) {
        guard let type else { return nil }
        self.init(rawValue: type)
    }
}
