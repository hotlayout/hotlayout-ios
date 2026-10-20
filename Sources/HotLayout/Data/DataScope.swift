import Foundation

/// Values available to a node: a flat map from a data PATH to a value.
///
/// Flat on purpose. A path in the contract is a string (`task.title`), not a walk through
/// nested objects; splitting it would raise questions the contract does not answer.
public typealias DataScope = [String: JSONValue]

/// The four data layers of a screen, strongest first (`x-dataScope.layers`):
/// the record of the row or of the opened screen, the session (what the person chose or
/// typed), what the host addressed to this screen, and the host data.
enum DataLayer: String, CaseIterable, Sendable {
    case record, session, host, data
}

struct DataLayers: Sendable {
    var record: DataScope?
    var session: DataScope?
    var host: DataScope?
    var data: DataScope?

    init(record: DataScope? = nil, session: DataScope? = nil, host: DataScope? = nil, data: DataScope? = nil) {
        self.record = record
        self.session = session
        self.host = host
        self.data = data
    }

    subscript(layer: DataLayer) -> DataScope? {
        switch layer {
        case .record: return record
        case .session: return session
        case .host: return host
        case .data: return data
        }
    }
}

enum RecordScope {
    /// Absence: a missing key or `null` (`x-dataScope.absent`). Neither shadows a weaker layer
    /// (`absentInDataLayer: 'read-next-layer'`).
    static func isAbsent(_ value: JSONValue?) -> Bool {
        value == nil || value == .null
    }

    /// Reads a path through the layers: the first layer with a present value answers.
    static func read(_ layers: DataLayers, path: String) -> (layer: DataLayer, value: JSONValue)? {
        for layer in DataLayer.allCases {
            if let value = layers[layer]?[path], !isAbsent(value) { return (layer, value) }
        }
        return nil
    }

    /// The layers flattened into one scope, strongest on top.
    static func merge(_ layers: DataLayers) -> DataScope {
        var merged: DataScope = [:]
        for layer in DataLayer.allCases.reversed() {
            for (path, value) in layers[layer] ?? [:] where !isAbsent(value) { merged[path] = value }
        }
        return merged
    }

    /// The fields of one collection record under the entity prefix: `title` of a `task`
    /// record becomes `task.title`. A field that already carries the prefix stays as it is.
    static func instanceRecord(item prefix: String, fields: JSONObject) -> DataScope {
        var record: DataScope = [:]
        for (field, value) in fields where !isAbsent(value) {
            record[field.hasPrefix("\(prefix).") ? field : "\(prefix).\(field)"] = value
        }
        return record
    }

    /// `inner` laid over `outer`: an absent value of the inner scope does not hide the outer one.
    static func overlay(_ outer: DataScope?, _ inner: DataScope?) -> DataScope? {
        guard let inner else { return outer }
        guard var merged = outer else { return inner }
        for (path, value) in inner where !isAbsent(value) { merged[path] = value }
        return merged
    }

    /// Whether a screen opened by `navigate` gets the record of the pressed node
    /// (`navigateFromListItem`, `navigateOutsideListItem`, `carryRecord`): a list row, a modal
    /// layer, or an explicit `carryRecord` hands it over; a page opened elsewhere gets none.
    static func carriesRecord(insideListItem: Bool, presentation: ScreenPresentation, carryRecord: Bool) -> Bool {
        insideListItem || presentation == .modal || carryRecord
    }
}
