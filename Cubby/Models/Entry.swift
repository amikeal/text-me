import Foundation
import SwiftData
import CubbyCore

/// Where an entry came from.
enum CaptureSource: String, CaseIterable {
    case app
    case shareExtension
    case intent
    case widget
}

/// One thing the user dropped in. `rawText` is kept verbatim and is the source of truth;
/// everything else is derived from it or applied by the user.
///
/// Every property has a default and nothing is unique, as CloudKit sync requires.
@Model
final class Entry {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var rawText: String = ""
    var sourceRaw: String = "app"

    // MARK: What the interface shows (stored, so lists can filter on them)

    var isTodo: Bool = false
    var isLinkOnly: Bool = false
    var hasLink: Bool = false
    var deadline: Date?
    var deadlineHasTime: Bool = false
    /// `rawText` without its links; links are shown as cards instead.
    var bodyText: String = ""

    // MARK: Inferred by the classifier

    var inferredIsTodo: Bool = false
    var inferredDeadline: Date?
    var inferredDeadlineHasTime: Bool = false
    /// Newline-separated absolute URLs.
    var urlsJoined: String = ""
    var shortTitle: String?
    var isMultiItem: Bool = false
    var classifiedAt: Date?
    var classifierVersion: Int = 0
    var classifierTierRaw: String?
    /// The pipeline version the language model last tried, successfully or not.
    var refineAttemptVersion: Int = 0

    // MARK: Link preview

    var linkTitle: String?
    var linkFetchAttemptedAt: Date?

    // MARK: Applied by the user (corrections and completion only)

    var todoOverride: Bool?
    var deadlineOverridden: Bool = false
    var completedAt: Date?

    init(text: String, source: CaptureSource, createdAt: Date = Date()) {
        self.id = UUID()
        self.createdAt = createdAt
        self.rawText = text
        self.bodyText = text
        self.sourceRaw = source.rawValue
    }
}

extension Entry {
    var urls: [URL] {
        urlsJoined.split(separator: "\n").compactMap { URL(string: String($0)) }
    }

    var source: CaptureSource {
        CaptureSource(rawValue: sourceRaw) ?? .app
    }

    var tier: ClassifierTier? {
        classifierTierRaw.flatMap { ClassifierTier(rawValue: $0) }
    }

    /// Anything that is neither a to-do nor a bare link is a note.
    var isNote: Bool {
        !isTodo && !isLinkOnly
    }

    var isCompleted: Bool {
        completedAt != nil
    }

    var isOpenTodo: Bool {
        isTodo && completedAt == nil
    }

    /// A short name for notifications, the widget and the digest.
    var title: String {
        if let shortTitle, !shortTitle.isEmpty { return shortTitle }
        if let linkTitle, !linkTitle.isEmpty { return linkTitle }
        return HeuristicClassifier.shortTitle(for: rawText) ?? rawText
    }

    /// Stores a classifier result, then re-applies the user's corrections on top.
    func apply(_ classification: EntryClassification, version: Int, at date: Date = Date()) {
        inferredIsTodo = classification.isTodo
        inferredDeadline = classification.deadline
        inferredDeadlineHasTime = classification.deadlineHasTime
        urlsJoined = classification.urls.map(\.absoluteString).joined(separator: "\n")
        hasLink = classification.hasLink
        isLinkOnly = classification.isLinkOnly
        bodyText = classification.hasLink ? LinkDetector.strippingURLs(from: rawText) : rawText
        shortTitle = classification.shortTitle
        isMultiItem = classification.isMultiItem
        classifiedAt = date
        classifierVersion = version
        classifierTierRaw = classification.tier.rawValue
        recomputeEffective()
    }

    /// User corrections win over anything inferred.
    func recomputeEffective() {
        isTodo = todoOverride ?? inferredIsTodo
        if !deadlineOverridden {
            deadline = isTodo ? inferredDeadline : nil
            deadlineHasTime = isTodo ? inferredDeadlineHasTime : false
        }
        if !isTodo {
            completedAt = nil
        }
    }
}
