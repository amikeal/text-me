import Foundation

/// Rule-based classification for devices without Apple Intelligence, and the instant first
/// answer on every device before the language model refines it.
public struct HeuristicClassifier: Sendable {
    public struct Result: Equatable, Sendable {
        public var isTodo: Bool
        public var isNote: Bool
        public var isMultiItem: Bool
        public var shortTitle: String?
    }

    public init() {}

    /// - Parameters:
    ///   - text: The entry with links already removed.
    ///   - hasLinks: Whether the original entry contained links.
    ///   - hasDeadline: Whether the deterministic pass found a date.
    public func classify(text: String, hasLinks: Bool, hasDeadline: Bool) -> Result {
        let body = Self.leadingMarkerRx.removingMatches(from: text, replacement: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = body.lowercased()
        let words = Self.words(in: lower)
        let isLinkOnly = body.isEmpty && hasLinks

        let segments = Self.segments(of: body)
        let isMultiItem = Self.isMultiItem(body: body, segments: segments)

        var isTodo = false
        if Self.explicitTodoRx.isMatch(text) {
            isTodo = true
        } else if isLinkOnly || body.isEmpty || Self.notePrefixRx.isMatch(lower) {
            isTodo = false
        } else if Self.startsWithAction(lower), !body.hasSuffix("?") {
            isTodo = true
        } else if Self.triggerRx.isMatch(lower) {
            isTodo = true
        } else if hasDeadline, words.count <= 12 {
            isTodo = true
        } else if isMultiItem {
            // "milk, eggs, call mom": one action makes the whole line a list of things to do.
            // Three or more very short items is nearly always a shopping or packing list.
            let anyAction = segments.contains { Self.startsWithAction($0.lowercased()) }
            let shortList = segments.count >= 3 && segments.allSatisfy { Self.words(in: $0).count <= 3 }
            isTodo = anyAction || shortList
        }

        return Result(
            isTodo: isTodo,
            isNote: !isTodo && !isLinkOnly && !body.isEmpty,
            isMultiItem: isMultiItem,
            shortTitle: Self.shortTitle(for: body)
        )
    }

    /// The first few words, for digests and notifications.
    public static func shortTitle(for text: String, maxWords: Int = 6) -> String? {
        let firstLine = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let words = firstLine.split(separator: " ", omittingEmptySubsequences: true)
        guard !words.isEmpty else { return nil }
        let title = words.prefix(maxWords).joined(separator: " ")
        return words.count > maxWords ? title + "…" : title
    }

    // MARK: - Rules

    /// Bullets, checkboxes and numbering at the start of an entry.
    private static let leadingMarkerRx = Rx(#"^\s*(?:[-*•]\s+|\[\s?\]\s*|\d{1,2}[.)]\s+)"#)

    /// The writer said outright that this is a to-do.
    private static let explicitTodoRx = Rx(#"^\s*(?:\[\s?\]|to-?\s?do\s*[:\-–—]|task\s*[:\-–—])"#)

    /// Labels people put in front of things they want to keep, not do.
    private static let notePrefixRx = Rx(
        #"^(?:(?:[a-z]+\s+)?ideas?|notes?|quote|thought|fyi|book|movie|film|show|song|album|podcast|recipe|gift(?:\s+ideas?)?(?:\s+for\s+[a-z]+)?|password|wifi|code|address)\s*[:\-–—]"#
    )

    private static let triggerRx = Rx(
        #"\b(?:needs?\s+to|remember\s+to|don['’]?t\s+forget|do\s+not\s+forget|have\s+to|has\s+to|got\s+to|gotta|must(?!-)|make\s+sure|remind\s+me|reminder\s+to|todo|to-do)\b"#
    )

    private static let actionVerbs: Set<String> = [
        "add", "apply", "ask", "backup", "book", "bring", "buy", "call", "cancel", "change", "charge",
        "check", "clean", "confirm", "deposit", "do", "donate", "download", "drop", "email", "feed",
        "file", "find", "finish", "fix", "follow", "get", "go", "grab", "install", "invite", "mail",
        "make", "measure", "meet", "message", "move", "order", "organize", "pack", "pay", "pick",
        "pickup", "plan", "post", "practice", "prepare", "print", "read", "refill", "register", "remove",
        "renew", "repair", "replace", "reply", "research", "reschedule", "respond", "return", "review",
        "rsvp", "schedule", "send", "set", "ship", "sign", "sort", "start", "stop", "study", "submit",
        "take", "tell", "text", "thank", "tip", "transfer", "try", "update", "upload", "venmo", "visit",
        "walk", "wash", "watch", "water", "withdraw", "write", "listen",
    ]

    /// Words after an action verb that show it is a question or an observation, not an instruction.
    private static let nonActionFollowers: Set<String> = ["you", "we", "they", "i", "he", "she", "it", "this", "that"]

    private static func startsWithAction(_ lower: String) -> Bool {
        let words = Self.words(in: lower)
        guard let first = words.first, actionVerbs.contains(first) else { return false }
        if words.count > 1, nonActionFollowers.contains(words[1]) { return false }
        return true
    }

    private static func words(in text: String) -> [String] {
        text.split(whereSeparator: { !($0.isLetter || $0.isNumber || $0 == "'" || $0 == "’") }).map(String.init)
    }

    /// Lines if there are several; otherwise comma- or semicolon-separated parts.
    private static func segments(of body: String) -> [String] {
        let lines = body.split(whereSeparator: \.isNewline)
            .map { leadingMarkerRx.removingMatches(from: String($0), replacement: "").trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if lines.count >= 2 { return lines }
        return body.split(whereSeparator: { $0 == "," || $0 == ";" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Several lines, three or more short comma-separated parts ("milk, eggs, call mom"),
    /// or two tiny ones ("milk, eggs"). Two longer parts are usually one thought with a pause:
    /// "dentist thurs 3pm, ask about retainer".
    private static func isMultiItem(body: String, segments: [String]) -> Bool {
        guard segments.count >= 2 else { return false }
        if body.contains(where: \.isNewline) { return true }
        if segments.count == 2 {
            return segments.allSatisfy { words(in: $0).count <= 2 }
        }
        return segments.allSatisfy { words(in: $0).count <= 4 }
    }
}
