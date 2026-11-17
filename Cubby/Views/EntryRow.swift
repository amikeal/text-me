import SwiftUI
import UIKit
import CubbyCore

/// One entry in the stream: a small marker showing what Cubby thinks it is, the text as written,
/// a card for any link, and when it was saved. Long-press to correct the sorting.
struct EntryRow: View {
    let entry: Entry
    var showsDay = false
    var isHighlighted = false
    var onEditDeadline: () -> Void = {}

    @Environment(\.openURL) private var openURL

    var body: some View {
        // A deleted entry can be asked to draw once more before the list catches up.
        if entry.isDeleted || entry.modelContext == nil {
            EmptyView()
        } else {
            HStack(alignment: .top, spacing: 12) {
                marker
                VStack(alignment: .leading, spacing: 6) {
                    if !entry.bodyText.isEmpty {
                        Text(entry.bodyText)
                            .font(.body)
                            .foregroundStyle(entry.isCompleted ? Color.secondary : Color.primary)
                            .strikethrough(entry.isCompleted)
                    }
                    if let url = entry.urls.first {
                        LinkCard(url: url, title: entry.linkTitle)
                    }
                    meta
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background {
                if isHighlighted {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Theme.accent.opacity(0.14))
                        .padding(-8)
                }
            }
            .contentShape(Rectangle())
            .contextMenu { menu }
            .sensoryFeedback(.success, trigger: entry.isCompleted)
        }
    }

    // MARK: - Marker

    @ViewBuilder
    private var marker: some View {
        if entry.isTodo {
            Button {
                withAnimation(.snappy) {
                    CubbyModel.shared.toggleDone(entry)
                }
            } label: {
                Image(systemName: entry.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 24, height: 24)
                    .padding(10)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // The tap target is 44 points; the negative padding keeps the layout at 24.
            .padding(-10)
            .accessibilityLabel(entry.isCompleted ? "Mark not done" : "Mark done")
        } else if entry.hasLink {
            Image(systemName: "link")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)
        } else {
            Circle()
                .fill(.tertiary)
                .frame(width: 6, height: 6)
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)
        }
    }

    // MARK: - Meta line

    private var meta: some View {
        HStack(spacing: 8) {
            if entry.isOpenTodo, let deadline = entry.deadline {
                DeadlineChip(date: deadline, hasTime: entry.deadlineHasTime)
            }
            Text(timeText)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var timeText: String {
        if let completedAt = entry.completedAt {
            return "Done " + completedAt.formatted(.relative(presentation: .named))
        }
        if showsDay {
            return entry.createdAt.formatted(.dateTime.month(.abbreviated).day().hour().minute())
        }
        return entry.createdAt.formatted(date: .omitted, time: .shortened)
    }

    // MARK: - Corrections

    @ViewBuilder
    private var menu: some View {
        Button {
            UIPasteboard.general.string = entry.rawText
        } label: {
            Label("Copy", systemImage: "doc.on.doc")
        }
        if let url = entry.urls.first {
            Button {
                openURL(url)
            } label: {
                Label("Open Link", systemImage: "safari")
            }
        }

        Divider()

        if entry.isTodo {
            Button {
                CubbyModel.shared.setTodo(entry, false)
            } label: {
                Label("Not a To-do", systemImage: "circle.slash")
            }
            Button(action: onEditDeadline) {
                Label(entry.deadline == nil ? "Add Deadline" : "Change Deadline", systemImage: "calendar")
            }
            if entry.deadline != nil {
                Button {
                    CubbyModel.shared.setDeadline(entry, date: nil, hasTime: false)
                } label: {
                    Label("Remove Deadline", systemImage: "calendar.badge.minus")
                }
            }
        } else {
            Button {
                CubbyModel.shared.setTodo(entry, true)
            } label: {
                Label("Make It a To-do", systemImage: "checkmark.circle")
            }
        }

        Divider()

        Button(role: .destructive) {
            withAnimation(.snappy) {
                CubbyModel.shared.delete(entry)
            }
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }
}

/// "Thu 3:00 PM". Turns red once the deadline has passed.
struct DeadlineChip: View {
    let date: Date
    let hasTime: Bool

    var body: some View {
        let overdue = DeadlineLabel.isOverdue(date, hasTime: hasTime)
        Text(DeadlineLabel.text(for: date, hasTime: hasTime))
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .foregroundStyle(overdue ? Color.red : Theme.deadlineForeground)
            .background(overdue ? Color.red.opacity(0.14) : Theme.deadlineBackground, in: .capsule)
            .accessibilityLabel((overdue ? "Overdue, was due " : "Due ") + DeadlineLabel.text(for: date, hasTime: hasTime))
    }
}

/// A saved link, shown as its page title and site instead of a raw URL.
struct LinkCard: View {
    let url: URL
    let title: String?

    @Environment(\.openURL) private var openURL

    private var host: String {
        let host = url.host ?? url.absoluteString
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    var body: some View {
        Button {
            openURL(url)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title ?? host)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(title == nil ? url.absoluteString : host)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Theme.card, in: .rect(cornerRadius: 14))
            .contentShape(.rect(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the link")
    }
}
