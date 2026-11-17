#if canImport(FoundationModels)
import Foundation
import FoundationModels

/// The shape the on-device model must fill in. Guided generation guarantees valid output.
@Generable
struct GeneratedClassification {
    @Guide(description: "True if the text implies a concrete action the writer intends to take, including terse tasks like 'dentist thurs' or a shopping list. False for vague aspirations, facts, ideas, and bare links.")
    var isTodo: Bool

    @Guide(description: "True if the text is information or an idea worth keeping that is not an action.")
    var isNote: Bool

    @Guide(description: "If the action has a date or time, that date as YYYY-MM-DD, or YYYY-MM-DDTHH:MM when a clock time is given, resolved relative to the 'Sent at' timestamp. Otherwise an empty string.")
    var deadline: String

    @Guide(description: "True if the text holds two or more separate items, such as 'milk, eggs, call mom'.")
    var isMultiItem: Bool

    @Guide(description: "A title of at most six words that summarizes the text.")
    var shortTitle: String
}

/// Classifies an entry with Apple's on-device language model (Foundation Models).
public struct FoundationModelsClassifier: Sendable {
    public enum Variant: String, Sendable {
        /// The general-purpose system model.
        case general
        /// The system model specialized for tagging content.
        case contentTagging
    }

    public enum Status: Equatable, Sendable {
        case available
        case unavailable(reason: String)
    }

    public var variant: Variant

    public init(variant: Variant = .general) {
        self.variant = variant
    }

    /// Whether the model can run right now, and if not, why (device, setting, still downloading).
    public static var status: Status {
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case .unavailable(let reason):
            return .unavailable(reason: describe(reason))
        @unknown default:
            return .unavailable(reason: "Unavailable")
        }
    }

    public static var isAvailable: Bool {
        status == .available
    }

    private static func describe(_ reason: SystemLanguageModel.Availability.UnavailableReason) -> String {
        switch reason {
        case .deviceNotEligible:
            return "This device doesn't support Apple Intelligence"
        case .appleIntelligenceNotEnabled:
            return "Apple Intelligence is turned off in Settings"
        case .modelNotReady:
            return "The model is still downloading"
        @unknown default:
            return "Unavailable"
        }
    }

    private static let instructions = """
    You classify short personal notes that a person sent to themselves. \
    The notes are often terse, lowercase and abbreviated. Classify them; do not rewrite them.
    """

    /// The model's context window is small. Longer notes are judged on their opening.
    private static let maxCharacters = 1_500

    public func classify(text: String, sentAt: Date, calendar: Calendar = .current) async throws -> LLMClassification {
        let model: SystemLanguageModel
        switch variant {
        case .general:
            model = .default
        case .contentTagging:
            model = SystemLanguageModel(useCase: .contentTagging)
        }

        // A fresh session per entry keeps earlier notes from influencing this one.
        let session = LanguageModelSession(model: model, instructions: Self.instructions)
        let prompt = "Sent at: \(Self.stamp(sentAt, calendar: calendar))\nText: \(String(text.prefix(Self.maxCharacters)))"
        let response = try await session.respond(
            to: prompt,
            generating: GeneratedClassification.self,
            options: GenerationOptions(sampling: .greedy)
        )
        let output = response.content
        return LLMClassification(
            isTodo: output.isTodo,
            isNote: output.isNote,
            deadline: output.deadline,
            isMultiItem: output.isMultiItem,
            shortTitle: output.shortTitle
        )
    }

    /// "2026-10-12T09:00 (Monday)". Small models resolve "thurs" better when told the weekday.
    static func stamp(_ date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm (EEEE)"
        return formatter.string(from: date)
    }
}
#endif
