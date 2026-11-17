import SwiftUI
import SwiftData

/// Plain text search over everything saved, including link titles.
struct SearchView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppRouter.self) private var router
    @Query(sort: \Entry.createdAt, order: .reverse) private var entries: [Entry]
    @State private var query = ""

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var results: [Entry] {
        let needle = trimmedQuery
        guard !needle.isEmpty else { return [] }
        return entries.filter { entry in
            entry.rawText.localizedStandardContains(needle)
                || (entry.linkTitle?.localizedStandardContains(needle) ?? false)
        }
    }

    var body: some View {
        NavigationStack {
            List(results) { entry in
                Button {
                    // Show the result in place in the full stream.
                    router.filter = .all
                    router.scrollTarget = entry.id
                    dismiss()
                } label: {
                    SearchResultRow(entry: entry)
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
            .overlay {
                if trimmedQuery.isEmpty {
                    ContentUnavailableView("Search Cubby", systemImage: "magnifyingglass", description: Text("Find anything you've dropped in."))
                } else if results.isEmpty {
                    ContentUnavailableView.search(text: trimmedQuery)
                }
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Notes, links, to-dos")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct SearchResultRow: View {
    let entry: Entry

    private var symbol: String {
        if entry.isTodo { return entry.isCompleted ? "checkmark.circle.fill" : "circle" }
        if entry.hasLink { return "link" }
        return "text.alignleft"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(entry.isTodo ? Theme.accent : Color.secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.bodyText.isEmpty ? (entry.linkTitle ?? entry.rawText) : entry.bodyText)
                    .lineLimit(3)
                Text(entry.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}
