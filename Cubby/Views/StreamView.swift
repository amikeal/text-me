import SwiftUI
import SwiftData

/// The timeline: everything the user has dropped in, oldest at the top, with filter chips
/// above and the composer below. Filters are views over the stream, never places items move to.
struct StreamView: View {
    @Environment(AppRouter.self) private var router
    @Query(sort: \Entry.createdAt) private var entries: [Entry]

    @State private var draft = ""
    @State private var showCompleted = false
    @State private var showSearch = false
    @State private var showSettings = false
    @State private var editingDeadline: Entry?
    @State private var highlighted: UUID?
    @FocusState private var composerFocused: Bool

    var body: some View {
        @Bindable var router = router

        ScrollViewReader { proxy in
            ScrollView {
                content
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
            }
            // A fresh scroll view per filter, so each one starts at its own anchor.
            .id(router.filter)
            .defaultScrollAnchor(router.filter == .todos ? .top : .bottom)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: entries.count) { old, new in
                guard new > old, router.filter != .todos, let last = visible.last else { return }
                withAnimation(.snappy) {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
            .onChange(of: router.scrollTarget) { _, target in
                guard let target else { return }
                router.scrollTarget = nil
                Task { @MainActor in
                    // Give a just-switched filter time to lay out before scrolling within it.
                    try? await Task.sleep(for: .milliseconds(350))
                    withAnimation(.snappy) {
                        proxy.scrollTo(target, anchor: .center)
                        highlighted = target
                    }
                    try? await Task.sleep(for: .seconds(1.6))
                    withAnimation(.easeOut) {
                        if highlighted == target { highlighted = nil }
                    }
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            topBar(filter: $router.filter)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ComposerBar(text: $draft, isFocused: $composerFocused, onSend: send)
        }
        .background(Theme.ground.ignoresSafeArea())
        .sheet(isPresented: $showSearch) {
            SearchView()
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(item: $editingDeadline) { entry in
            DeadlineEditor(entry: entry)
        }
        .task {
            // Opening straight to the timeline means opening ready to type. As on the blank
            // page, retry briefly: a cold launch can drop the first focus request.
            guard AppSettings.startScreen == .timeline else { return }
            composerFocused = true
            for delay in [150, 350, 800] {
                try? await Task.sleep(for: .milliseconds(delay))
                if composerFocused { break }
                composerFocused = true
            }
        }
        .onChange(of: router.focusRequest) {
            composerFocused = true
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        let visible = self.visible
        if visible.isEmpty {
            EmptyStreamView(filter: router.filter, hasAnyEntries: !entries.isEmpty)
                .frame(maxWidth: .infinity)
                .padding(.top, 72)
        } else if router.filter == .todos {
            LazyVStack(alignment: .leading, spacing: 22) {
                ForEach(visible) { entry in
                    row(for: entry, showsDay: true)
                }
                completedToggle
            }
        } else {
            LazyVStack(alignment: .leading, spacing: 22) {
                ForEach(sections) { section in
                    Text(section.title)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(section.entries) { entry in
                        row(for: entry, showsDay: false)
                    }
                }
            }
        }
    }

    private func row(for entry: Entry, showsDay: Bool) -> some View {
        EntryRow(
            entry: entry,
            showsDay: showsDay,
            isHighlighted: highlighted == entry.id,
            onEditDeadline: { editingDeadline = entry }
        )
        .id(entry.id)
    }

    @ViewBuilder
    private var completedToggle: some View {
        let completedCount = entries.filter { $0.isTodo && $0.completedAt != nil }.count
        if completedCount > 0 {
            Button {
                withAnimation(.snappy) { showCompleted.toggle() }
            } label: {
                Text(showCompleted ? "Hide completed" : "Show \(completedCount) completed")
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.accent)
            .padding(.leading, 36)
        }
    }

    private func topBar(filter: Binding<EntryFilter>) -> some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                FilterChips(selection: filter)
                Spacer(minLength: 0)
                GlassIconButton(systemName: "magnifyingglass", label: "Search") {
                    showSearch = true
                }
                Menu {
                    Button {
                        router.screen = .capture
                        router.focusRequest += 1
                    } label: {
                        Label("Blank Page", systemImage: "square.and.pencil")
                    }
                    Button {
                        showSettings = true
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.body.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .circle)
                .accessibilityLabel("More")
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }

    // MARK: - Data

    /// Entries for the current filter. To-dos are ordered for doing: soonest deadline first,
    /// then the newest undated ones. Every other view keeps the stream's order.
    private var visible: [Entry] {
        guard router.filter == .todos else {
            return entries.filter { router.filter.includes($0) }
        }
        let todos = entries.filter(\.isTodo)
        let open = todos.filter { $0.completedAt == nil }.sorted(by: Self.todoOrder)
        guard showCompleted else { return open }
        let done = todos
            .filter { $0.completedAt != nil }
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
        return open + done
    }

    private static func todoOrder(_ left: Entry, _ right: Entry) -> Bool {
        switch (left.deadline, right.deadline) {
        case let (leftDate?, rightDate?):
            return leftDate < rightDate
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        case (.none, .none):
            return left.createdAt > right.createdAt
        }
    }

    private var sections: [DaySection] {
        let calendar = Calendar.current
        var result: [DaySection] = []
        for entry in visible {
            let day = calendar.startOfDay(for: entry.createdAt)
            if let last = result.indices.last, result[last].day == day {
                result[last].entries.append(entry)
            } else {
                result.append(DaySection(day: day, entries: [entry]))
            }
        }
        return result
    }

    private func send() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        // Return dismisses the keyboard on a multi-line field; bring it straight back.
        Task { @MainActor in composerFocused = true }
        guard !trimmed.isEmpty else { return }
        CubbyModel.shared.capture(trimmed, source: .app)
        draft = ""
    }
}

/// One day's worth of entries in the stream.
private struct DaySection: Identifiable {
    let day: Date
    var entries: [Entry]

    var id: Date { day }

    var title: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        let daysAgo = calendar.dateComponents([.day], from: day, to: calendar.startOfDay(for: Date())).day ?? 0
        if (2...6).contains(daysAgo) {
            return day.formatted(.dateTime.weekday(.wide))
        }
        if calendar.isDate(day, equalTo: Date(), toGranularity: .year) {
            return day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        }
        return day.formatted(.dateTime.month(.abbreviated).day().year())
    }
}

/// What the stream shows before there is anything in it, or when a filter matches nothing.
private struct EmptyStreamView: View {
    let filter: EntryFilter
    let hasAnyEntries: Bool

    var body: some View {
        if !hasAnyEntries {
            ContentUnavailableView {
                Label("Drop it in. Find it later.", systemImage: "tray.and.arrow.down")
            } description: {
                Text("Type anything below: a to-do, a link, a thought. Cubby sorts it for you.")
            }
        } else {
            switch filter {
            case .todos:
                ContentUnavailableView("Nothing to do", systemImage: "checkmark.circle", description: Text("To-dos you drop in show up here."))
            case .links:
                ContentUnavailableView("No links yet", systemImage: "link", description: Text("Links you save show up here."))
            case .notes:
                ContentUnavailableView("No notes yet", systemImage: "note.text", description: Text("Thoughts and ideas show up here."))
            case .all:
                ContentUnavailableView("Nothing here yet", systemImage: "tray")
            }
        }
    }
}
