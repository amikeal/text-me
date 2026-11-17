import Foundation

/// Which engine produced a classification.
public enum ClassifierTier: String, Codable, Sendable {
    /// Apple's on-device language model, on top of the deterministic pass.
    case foundationModels
    /// Deterministic detection plus rules. Works on every device.
    case heuristic
}

/// What Cubby believes an entry is. Labels overlap: an entry can be a to-do and carry a link.
public struct EntryClassification: Equatable, Sendable {
    public var isTodo: Bool
    public var isNote: Bool
    public var urls: [URL]
    /// True when the entry is nothing but links.
    public var isLinkOnly: Bool
    /// Only set for to-dos: a date on a plain note is not something to be reminded about.
    public var deadline: Date?
    public var deadlineHasTime: Bool
    public var shortTitle: String?
    public var isMultiItem: Bool
    public var tier: ClassifierTier

    public init(
        isTodo: Bool,
        isNote: Bool,
        urls: [URL],
        isLinkOnly: Bool,
        deadline: Date?,
        deadlineHasTime: Bool,
        shortTitle: String?,
        isMultiItem: Bool,
        tier: ClassifierTier
    ) {
        self.isTodo = isTodo
        self.isNote = isNote
        self.urls = urls
        self.isLinkOnly = isLinkOnly
        self.deadline = deadline
        self.deadlineHasTime = deadlineHasTime
        self.shortTitle = shortTitle
        self.isMultiItem = isMultiItem
        self.tier = tier
    }

    public var hasLink: Bool { !urls.isEmpty }
}

/// The raw answer from a language model, before it is merged with the deterministic pass.
public struct LLMClassification: Equatable, Sendable {
    public var isTodo: Bool
    public var isNote: Bool
    /// "YYYY-MM-DD" or "YYYY-MM-DDTHH:MM", or empty when there is no date.
    public var deadline: String
    public var isMultiItem: Bool
    public var shortTitle: String

    public init(isTodo: Bool, isNote: Bool, deadline: String, isMultiItem: Bool, shortTitle: String) {
        self.isTodo = isTodo
        self.isNote = isNote
        self.deadline = deadline
        self.isMultiItem = isMultiItem
        self.shortTitle = shortTitle
    }
}
