import SwiftUI
import WidgetKit
import CubbyCore

struct CaptureEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

/// Reads the summary the app last wrote. The app reloads the widget whenever entries change,
/// so the timeline has a single entry and no schedule of its own.
struct CaptureProvider: TimelineProvider {
    func placeholder(in context: Context) -> CaptureEntry {
        CaptureEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (CaptureEntry) -> Void) {
        let snapshot = context.isPreview ? WidgetSnapshot.placeholder : (WidgetSnapshot.load() ?? .empty)
        completion(CaptureEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CaptureEntry>) -> Void) {
        let entry = CaptureEntry(date: Date(), snapshot: WidgetSnapshot.load() ?? .empty)
        completion(Timeline(entries: [entry], policy: .never))
    }
}

/// Tap to open Cubby ready to type; shows how many to-dos are still open.
struct CaptureWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CubbyCapture", provider: CaptureProvider()) { entry in
            CaptureWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(URL(string: "cubby://compose"))
        }
        .configurationDisplayName("Cubby")
        .description("Drop it in, and see what's still open.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular])
    }
}

struct CaptureWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CaptureEntry

    private var snapshot: WidgetSnapshot { entry.snapshot }

    private var openText: String {
        switch snapshot.openTodoCount {
        case 0: return "Nothing open"
        case 1: return "1 open to-do"
        default: return "\(snapshot.openTodoCount) open to-dos"
        }
    }

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "square.and.pencil")
                    .font(.title3.weight(.semibold))
            }
            .accessibilityLabel("New Cubby note")

        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Label("Cubby", systemImage: "square.and.pencil")
                    .font(.headline)
                Text(openText)
                if let next = snapshot.nextTitle {
                    Text(next)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        default:
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "square.and.pencil")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.tint)
                Spacer(minLength: 0)
                Text("Drop it in")
                    .font(.headline)
                Text(openText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if let next = snapshot.nextTitle {
                    Text(next)
                        .font(.footnote)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}
