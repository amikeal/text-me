import Foundation

/// The numbers behind the weekly digest.
public struct DigestStats: Equatable, Sendable {
    public var openTodos: Int
    public var dueThisWeek: Int
    public var overdue: Int
    public var linksThisWeek: Int
    public var notesThisWeek: Int

    public init(openTodos: Int = 0, dueThisWeek: Int = 0, overdue: Int = 0, linksThisWeek: Int = 0, notesThisWeek: Int = 0) {
        self.openTodos = openTodos
        self.dueThisWeek = dueThisWeek
        self.overdue = overdue
        self.linksThisWeek = linksThisWeek
        self.notesThisWeek = notesThisWeek
    }
}

/// Writes the weekly digest notification. Plain counting, so it works without a language model.
public enum DigestComposer {
    public struct Digest: Equatable, Sendable {
        public var title: String
        public var body: String
    }

    /// Nil when there is nothing worth a notification.
    public static func compose(_ stats: DigestStats) -> Digest? {
        var parts: [String] = []
        if stats.openTodos > 0 {
            parts.append(count(stats.openTodos, "open to-do", "open to-dos"))
        }
        if stats.overdue > 0 {
            parts.append("\(stats.overdue) overdue")
        }
        if stats.dueThisWeek > 0 {
            parts.append("\(stats.dueThisWeek) due this week")
        }
        if stats.linksThisWeek > 0 {
            parts.append(count(stats.linksThisWeek, "link saved", "links saved"))
        }
        if stats.notesThisWeek > 0 {
            parts.append(count(stats.notesThisWeek, "new note", "new notes"))
        }
        guard !parts.isEmpty else { return nil }
        return Digest(title: "Your week in Cubby", body: parts.joined(separator: " · "))
    }

    private static func count(_ value: Int, _ singular: String, _ plural: String) -> String {
        "\(value) \(value == 1 ? singular : plural)"
    }
}
