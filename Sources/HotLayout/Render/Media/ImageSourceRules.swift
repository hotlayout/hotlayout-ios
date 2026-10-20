import Foundation

/// What the reader says about, and never loads, a picture address (`x-imageSource`).
enum ImageSourceRules {
    /// An address the host's own decision cannot make a picture: its scheme, read as a URL parser
    /// reads it, is one of these.
    static let neverSchemes: Set<String> = ["javascript", "vbscript"]
    /// The document's own address is cut here in a report.
    static let reportDocumentLength = 120

    /// Whether the address is never a picture whatever the host says: leading control characters and
    /// spaces are stripped, tab, line feed and carriage return are removed anywhere, and the scheme is
    /// compared without regard to case.
    static func neverAnImage(_ address: String) -> Bool {
        var scalars = Array(address.unicodeScalars.drop { $0.value <= 0x20 })
        scalars.removeAll { $0 == "\t" || $0 == "\n" || $0 == "\r" }
        guard let colon = scalars.firstIndex(of: ":"), colon > 0 else { return false }
        let scheme = scalars[..<colon]
        guard let first = scheme.first, first.isASCII, CharacterSet.letters.contains(first),
            scheme.allSatisfy({ $0.isASCII && (CharacterSet.alphanumerics.contains($0) || "+.-".unicodeScalars.contains($0)) })
        else { return false }
        return neverSchemes.contains(String(String.UnicodeScalarView(scheme)).lowercased())
    }

    /// The scheme and the host of an address and nothing else: the path and the query of an address
    /// from data may carry a token.
    static func schemeAndHost(_ address: String) -> String {
        guard let colon = address.firstIndex(of: ":"), address.distance(from: address.startIndex, to: colon) > 0,
            address.distance(from: address.startIndex, to: colon) <= 20
        else { return "(not an address)" }
        let scheme = address[..<colon].filter { $0.isLetter || $0.isNumber || "+.-".contains($0) }
        let rest = address[address.index(after: colon)...]
        guard rest.hasPrefix("//") else { return "\(scheme):" }
        let authority = rest.dropFirst(2).prefix { $0 != "/" && $0 != "?" && $0 != "#" }
        let afterUser = authority.split(separator: "@", omittingEmptySubsequences: false).last.map(Substring.init) ?? authority
        // The port is no part of the host.
        let host = afterUser.hasPrefix("[") ? (afterUser.prefix { $0 != "]" } + "]") : String(afterUser.prefix { $0 != ":" })
        return "\(scheme)://\(String(host).prefix(80))"
    }

    /// The address of the document as a report carries it.
    static func documentAddress(_ address: String) -> String {
        address.count <= reportDocumentLength ? address : String(address.prefix(reportDocumentLength)) + "…"
    }

    /// What the report of a refused address says; an address from data never shows its path or query.
    static func refusal(_ address: String, fromData: Bool) -> String {
        let shown = fromData ? schemeAndHost(address) : documentAddress(address)
        return "the address \(shown) is not loaded: the picture is drawn as its placeholder"
    }

    /// What the report of a picture that failed to load says: the scheme and the host only.
    static func failure(_ url: URL) -> String {
        "the picture at \(schemeAndHost(url.absoluteString)) could not be loaded (a failed request, a body over the limit, too many or refused redirects, "
            + "the deadline, or not a picture): it is drawn as its placeholder"
    }
}
