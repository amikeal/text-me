import Foundation

/// Thin wrapper over `NSRegularExpression`, which exists on every platform Foundation runs on.
struct Rx: @unchecked Sendable {
    private let regex: NSRegularExpression

    /// Patterns in this module are compile-time constants, so a bad pattern is a programmer error.
    init(_ pattern: String) {
        regex = try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }

    struct Match {
        let range: NSRange
        /// Group 0 is the whole match. Groups that did not participate are nil.
        let groups: [String?]

        var location: Int { range.location }
        var end: Int { range.location + range.length }

        func group(_ index: Int) -> String? {
            index < groups.count ? groups[index] : nil
        }
    }

    func matches(in text: String) -> [Match] {
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        return regex.matches(in: text, options: [], range: full).map { result in
            var groups: [String?] = []
            for index in 0..<result.numberOfRanges {
                let range = result.range(at: index)
                groups.append(range.location == NSNotFound ? nil : ns.substring(with: range))
            }
            return Match(range: result.range, groups: groups)
        }
    }

    func first(in text: String) -> Match? {
        matches(in: text).first
    }

    func isMatch(_ text: String) -> Bool {
        first(in: text) != nil
    }

    func removingMatches(from text: String, replacement: String = " ") -> String {
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        return regex.stringByReplacingMatches(in: text, options: [], range: full, withTemplate: replacement)
    }
}

extension String {
    /// Text after the given UTF-16 offset, used for look-ahead checks around a match.
    func suffix(fromUTF16 offset: Int) -> String {
        let ns = self as NSString
        guard offset >= 0, offset <= ns.length else { return "" }
        return ns.substring(from: offset)
    }

    /// Text before the given UTF-16 offset, used for look-behind checks around a match.
    func prefix(toUTF16 offset: Int) -> String {
        let ns = self as NSString
        guard offset >= 0, offset <= ns.length else { return "" }
        return ns.substring(to: offset)
    }
}
