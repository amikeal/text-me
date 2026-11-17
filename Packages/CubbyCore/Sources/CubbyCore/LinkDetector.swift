import Foundation

/// Finds web links in free text. Deterministic: this never depends on a language model.
public enum LinkDetector {
    private static let fallback = Rx(#"(?:https?://|www\.)[^\s<>"'\)\]]+"#)

    /// Web URLs (http/https) found in the text, in order, without duplicates.
    public static func urls(in text: String) -> [URL] {
        var seen = Set<String>()
        var result: [URL] = []
        for match in matches(in: text) {
            guard let url = match.url else { continue }
            let key = url.absoluteString
            if seen.insert(key).inserted {
                result.append(url)
            }
        }
        return result
    }

    /// The text with every detected link removed and whitespace tidied.
    public static func strippingURLs(from text: String) -> String {
        let ns = text as NSString
        var output = text
        // Remove from the end so earlier ranges stay valid.
        for match in matches(in: text).sorted(by: { $0.range.location > $1.range.location }) {
            guard match.range.location + match.range.length <= ns.length else { continue }
            output = (output as NSString).replacingCharacters(in: match.range, with: " ")
        }
        let lines = output
            .components(separatedBy: .newlines)
            .map { line in
                line.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
            }
            .filter { !$0.isEmpty }
        return lines.joined(separator: "\n")
    }

    /// True when the text is nothing but one or more links.
    public static func isLinkOnly(_ text: String) -> Bool {
        !urls(in: text).isEmpty && strippingURLs(from: text).isEmpty
    }

    private struct LinkMatch {
        let range: NSRange
        let url: URL?
    }

    private static func matches(in text: String) -> [LinkMatch] {
        #if canImport(Darwin)
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            let ns = text as NSString
            let found = detector.matches(in: text, options: [], range: NSRange(location: 0, length: ns.length))
            return found.compactMap { result in
                guard let url = result.url, isWeb(url) else { return nil }
                return LinkMatch(range: result.range, url: url)
            }
        }
        #endif
        return fallback.matches(in: text).map { match in
            var raw = match.group(0) ?? ""
            var range = match.range
            // Trailing punctuation belongs to the sentence, not the link.
            while let last = raw.last, ".,;:!?".contains(last) {
                raw.removeLast()
                range.length -= 1
            }
            let withScheme = raw.lowercased().hasPrefix("http") ? raw : "https://" + raw
            return LinkMatch(range: range, url: URL(string: withScheme))
        }
    }

    private static func isWeb(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }
}
