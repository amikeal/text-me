import Foundation

/// Turns raw text into an `EntryClassification`.
///
/// Two steps, so capture never waits on a model:
/// 1. `quick` runs instantly on every device: deterministic links and dates, plus rules.
/// 2. `merge` folds in the language model's answer when one is available.
///
/// Precedence when sources disagree: deterministic detection, then the model, then the rules.
/// (User corrections sit above all three and are applied by the app, not here.)
public struct ClassificationPipeline: Sendable {
    /// Bump when prompts or rules change, so stored entries can be re-classified.
    public static let version = 1

    public var calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    public func quick(text: String, capturedAt: Date) -> EntryClassification {
        let urls = LinkDetector.urls(in: text)
        let body = LinkDetector.strippingURLs(from: text)
        // Dates are read from the text without links, so "/2026/11/20/" in a URL is not a deadline.
        let parsed = DeadlineParser(calendar: calendar).parse(body, reference: capturedAt)
        let rules = HeuristicClassifier().classify(text: body, hasLinks: !urls.isEmpty, hasDeadline: parsed != nil)

        return EntryClassification(
            isTodo: rules.isTodo,
            isNote: rules.isNote,
            urls: urls,
            isLinkOnly: body.isEmpty && !urls.isEmpty,
            deadline: rules.isTodo ? parsed?.date : nil,
            deadlineHasTime: rules.isTodo ? (parsed?.hasTime ?? false) : false,
            shortTitle: rules.shortTitle ?? urls.first?.host,
            isMultiItem: rules.isMultiItem,
            tier: .heuristic
        )
    }

    public func merge(text: String, capturedAt: Date, llm: LLMClassification) -> EntryClassification {
        let urls = LinkDetector.urls(in: text)
        let body = LinkDetector.strippingURLs(from: text)
        let isLinkOnly = body.isEmpty && !urls.isEmpty

        // A bare link is a link, whatever the model says.
        let isTodo = isLinkOnly ? false : llm.isTodo
        let isNote = isLinkOnly ? false : (llm.isNote || !isTodo)

        var deadline: ParsedDeadline?
        if isTodo {
            deadline = DeadlineParser(calendar: calendar).parse(body, reference: capturedAt)
                ?? modelDeadline(llm.deadline, capturedAt: capturedAt)
        }

        let modelTitle = llm.shortTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = modelTitle.isEmpty ? (HeuristicClassifier.shortTitle(for: body) ?? urls.first?.host) : modelTitle

        return EntryClassification(
            isTodo: isTodo,
            isNote: isNote,
            urls: urls,
            isLinkOnly: isLinkOnly,
            deadline: deadline?.date,
            deadlineHasTime: deadline?.hasTime ?? false,
            shortTitle: title,
            isMultiItem: isLinkOnly ? false : llm.isMultiItem,
            tier: .foundationModels
        )
    }

    private static let modelDateRx = Rx(#"^\s*(\d{4})-(\d{1,2})-(\d{1,2})(?:[T\s]+(\d{1,2}):(\d{2}))?"#)

    /// Reads the model's "YYYY-MM-DD" or "YYYY-MM-DDTHH:MM". Rejects dates that cannot be
    /// deadlines for a note written at `capturedAt` (in the past, or more than two years out).
    func modelDeadline(_ raw: String, capturedAt: Date) -> ParsedDeadline? {
        guard let match = Self.modelDateRx.first(in: raw),
              let year = match.group(1).flatMap({ Int($0) }),
              let month = match.group(2).flatMap({ Int($0) }),
              let day = match.group(3).flatMap({ Int($0) }),
              (1...12).contains(month), (1...31).contains(day) else { return nil }

        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        let hour = match.group(4).flatMap { Int($0) }
        let minute = match.group(5).flatMap { Int($0) }
        if let hour, let minute, (0...23).contains(hour), (0...59).contains(minute) {
            components.hour = hour
            components.minute = minute
        }
        guard let date = calendar.date(from: components),
              calendar.component(.month, from: date) == month else { return nil }

        let earliest = calendar.startOfDay(for: capturedAt)
        guard date >= earliest,
              let latest = calendar.date(byAdding: .year, value: 2, to: capturedAt),
              date <= latest else { return nil }
        return ParsedDeadline(date: date, hasTime: components.hour != nil)
    }
}
