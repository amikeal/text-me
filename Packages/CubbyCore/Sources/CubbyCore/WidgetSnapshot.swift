import Foundation

/// The little the widget needs to know, written by the app whenever entries change.
public struct WidgetSnapshot: Codable, Equatable, Sendable {
    public var openTodoCount: Int
    /// The to-do with the nearest deadline, if any.
    public var nextTitle: String?
    public var nextDeadline: Date?
    public var nextDeadlineHasTime: Bool
    public var updatedAt: Date

    public init(
        openTodoCount: Int,
        nextTitle: String? = nil,
        nextDeadline: Date? = nil,
        nextDeadlineHasTime: Bool = false,
        updatedAt: Date = Date()
    ) {
        self.openTodoCount = openTodoCount
        self.nextTitle = nextTitle
        self.nextDeadline = nextDeadline
        self.nextDeadlineHasTime = nextDeadlineHasTime
        self.updatedAt = updatedAt
    }

    public static let empty = WidgetSnapshot(openTodoCount: 0)

    /// Shown in the widget gallery before real data exists.
    public static let placeholder = WidgetSnapshot(openTodoCount: 3, nextTitle: "Call the dentist")

    public static func load(from url: URL? = AppGroup.snapshotURL) -> WidgetSnapshot? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    @discardableResult
    public func save(to url: URL? = AppGroup.snapshotURL) -> Bool {
        guard let url, let data = try? JSONEncoder().encode(self) else { return false }
        do {
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }
}
