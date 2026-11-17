import Foundation

/// The lenses over the stream. Labels overlap, so one entry can appear under several.
enum EntryFilter: String, CaseIterable, Identifiable {
    case all
    case todos
    case links
    case notes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .todos: return "To-dos"
        case .links: return "Links"
        case .notes: return "Notes"
        }
    }

    func includes(_ entry: Entry) -> Bool {
        switch self {
        case .all: return true
        case .todos: return entry.isTodo
        case .links: return entry.hasLink
        case .notes: return entry.isNote
        }
    }
}
