import Foundation

/// One link of the record a screen holds: the `Repeater` instance a record came from. The
/// collection the list read (`source`), the entity (`item`, the list's prefix) and the fields
/// of the record as the host gave them.
struct RecordLink: Equatable, Sendable {
    let source: String
    let item: String
    let fields: JSONObject

    init(source: String, item: String, fields: JSONObject) {
        self.source = source
        self.item = item
        self.fields = fields
    }
}

/// The collections of each entity, as the DOCUMENT names them (`entity` → `source` of every
/// `Repeater` with that `item`): screens in document order, depth first, each collection once.
typealias EntitySources = [String: [String]]

/// The live record of a page (`x-liveRecord`).
///
/// The record a frame of the stack holds is a CHAIN of links, outer first; the record itself is
/// the overlay of the links, the inner one stronger. When the host gives new collections, every
/// link is searched for by its key (`<item>.id`): first in its own collection, then in the other
/// collections of the same entity; a link found takes the new record whole, a link not found
/// keeps the last record it had. Nothing here is a show of a screen: the stack does not move.
enum LiveRecord {
    /// The name of the key field of a record: `task.id` for `task`.
    static let keyField = "id"

    /// The record of a chain: the links laid over each other, the inner one stronger.
    static func record(of chain: [RecordLink]) -> DataScope? {
        var record: DataScope?
        for link in chain {
            record = RecordScope.overlay(record, RecordScope.instanceRecord(item: link.item, fields: link.fields))
        }
        return record
    }

    /// The chain of a node: the links of its frame, then the instances it is drawn inside.
    static func chain(frame: [RecordLink], instances: [ListInstance]) -> [RecordLink] {
        frame + instances.map { RecordLink(source: $0.source, item: $0.item, fields: $0.fields) }
    }

    /// The value of the key field the way `instanceRecord` would write it: the short name and
    /// the full path are one field, an absent one overrides nothing, and when both are present
    /// the one later in the order of keys wins.
    static func keyFieldValue(item: String, fields: JSONObject) -> JSONValue? {
        let full = "\(item).\(keyField)"
        let short = fields[keyField].flatMap { RecordScope.isAbsent($0) ? nil : $0 }
        let long = fields[full].flatMap { RecordScope.isAbsent($0) ? nil : $0 }
        switch (short, long) {
        case (nil, nil): return nil
        case (let value?, nil), (nil, let value?): return value
        case (let a?, let b?):
            let keys = fields.keys
            return (keys.firstIndex(of: keyField) ?? 0) > (keys.firstIndex(of: full) ?? 0) ? a : b
        }
    }

    /// The key of a record: a non-empty string or a finite number. Anything else — no field,
    /// `null`, a flag, an object — and the record is not live.
    static func key(item: String, fields: JSONObject) -> JSONValue? {
        switch keyFieldValue(item: item, fields: fields) {
        case .string(let text)?: return text.isEmpty ? nil : .string(text)
        case .number(let number)?: return number.isFinite ? .number(number) : nil
        default: return nil
        }
    }

    /// The collections of each entity named by the document, from the roots of its screens.
    static func entitySources(roots: [DocumentNode]) -> EntitySources {
        var found: EntitySources = [:]
        func walk(_ node: DocumentNode, _ depth: Int) {
            guard depth <= 64 else { return }
            if node.widget == .repeater, let source = node.props["source"]?.stringValue, !source.isEmpty,
                let item = node.props["item"]?.stringValue, !item.isEmpty
            {
                var list = found[item] ?? []
                if !list.contains(source) { list.append(source) }
                found[item] = list
            }
            for child in node.children { walk(child, depth + 1) }
        }
        for root in roots { walk(root, 0) }
        return found
    }

    /// The same from the plain list of `Repeater`s a table gives (document order).
    static func entitySources(lists: [(source: String, item: String)]) -> EntitySources {
        var found: EntitySources = [:]
        for list in lists where !list.source.isEmpty && !list.item.isEmpty {
            var sources = found[list.item] ?? []
            if !sources.contains(list.source) { sources.append(list.source) }
            found[list.item] = sources
        }
        return found
    }

    /// Where to look for a link: its own collection first, then the other collections of the
    /// same entity.
    static func searchOrder(of link: RecordLink, sources: EntitySources) -> [String] {
        [link.source] + (sources[link.item] ?? []).filter { $0 != link.source }
    }

    /// The record of a link in the collections the host gives now; the first record with the
    /// key, the same JSON type and equal without conversion (`7` and `"7"` are two records).
    static func find(_ link: RecordLink, collections: (String) -> JSONValue?, sources: EntitySources) -> JSONObject? {
        guard let wanted = key(item: link.item, fields: link.fields) else { return nil }
        for source in searchOrder(of: link, sources: sources) {
            guard let listed = collections(source)?.arrayValue else { continue }
            for candidate in listed {
                if let fields = candidate.objectValue, key(item: link.item, fields: fields) == wanted { return fields }
            }
        }
        return nil
    }

    /// The chain after the host gave new collections. A link that was found takes the new
    /// record whole, one that was not keeps the last record it had; nothing changed — the same
    /// chain (`==`), and the reader keeps the frame as it was.
    static func refresh(_ chain: [RecordLink], collections: (String) -> JSONValue?, sources: EntitySources) -> [RecordLink] {
        chain.map { link in
            guard let found = find(link, collections: collections, sources: sources),
                RecordScope.instanceRecord(item: link.item, fields: found) != RecordScope.instanceRecord(item: link.item, fields: link.fields)
            else { return link }
            return RecordLink(source: link.source, item: link.item, fields: found)
        }
    }
}
