import Foundation
import CubbyCore

/// Runs one of Cubby's classifiers over a file of notes and writes its predictions.
///
/// Uses the same `CubbyCore` code the app ships, so the numbers describe the real product.
///
///     swift run cubby-eval <heur|fm|fm-tag> <entries.jsonl> <predictions.jsonl>
@main
struct CubbyEval {
    struct InputEntry: Decodable {
        let id: String
        let sent_at: String
        let text: String
    }

    struct Prediction: Encodable {
        let id: String
        let classifier: String
        let pipelineVersion: Int
        let os: String
        let isTodo: Bool
        let isNote: Bool
        let hasLink: Bool
        let deadline: String?
        let isMultiItem: Bool
        let shortTitle: String?
        let latency_ms: Double
        let error: String?
    }

    enum EvalError: Error, CustomStringConvertible {
        case usage
        case unknownClassifier(String)
        case badDate(id: String, value: String)
        case modelUnavailable(String)

        var description: String {
            switch self {
            case .usage:
                return "usage: cubby-eval <heur|fm|fm-tag> <entries.jsonl> <predictions.jsonl>"
            case .unknownClassifier(let name):
                return "unknown classifier '\(name)'. Use heur, fm or fm-tag."
            case .badDate(let id, let value):
                return "entry \(id): can't read sent_at '\(value)'. Use 2026-10-14T19:32:00."
            case .modelUnavailable(let reason):
                return "the on-device model can't run here: \(reason)"
            }
        }
    }

    static func main() async {
        do {
            try await run()
        } catch {
            FileHandle.standardError.write(Data("cubby-eval: \(error)\n".utf8))
            exit(1)
        }
    }

    static func run() async throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard arguments.count == 3 else { throw EvalError.usage }
        let classifier = arguments[0]
        let inputURL = URL(fileURLWithPath: arguments[1])
        let outputURL = URL(fileURLWithPath: arguments[2])

        guard ["heur", "fm", "fm-tag"].contains(classifier) else {
            throw EvalError.unknownClassifier(classifier)
        }
        if classifier != "heur" {
            try checkModel()
        }

        let calendar = Calendar.current
        let pipeline = ClassificationPipeline(calendar: calendar)
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        let decoder = JSONDecoder()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]

        let lines = try String(contentsOf: inputURL, encoding: .utf8)
            .split(whereSeparator: \.isNewline)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        var output = ""
        for (index, line) in lines.enumerated() {
            let entry = try decoder.decode(InputEntry.self, from: Data(line.utf8))
            guard let sentAt = parseDate(entry.sent_at) else {
                throw EvalError.badDate(id: entry.id, value: entry.sent_at)
            }

            let started = Date()
            var failure: String?
            var result = pipeline.quick(text: entry.text, capturedAt: sentAt)
            if classifier != "heur" {
                do {
                    result = try await refine(entry.text, sentAt: sentAt, classifier: classifier, pipeline: pipeline, calendar: calendar)
                } catch {
                    // The app keeps the rule-based answer when the model fails, so the eval does too.
                    failure = String(describing: error)
                }
            }
            let latency = Date().timeIntervalSince(started) * 1000

            let prediction = Prediction(
                id: entry.id,
                classifier: classifier,
                pipelineVersion: ClassificationPipeline.version,
                os: os,
                isTodo: result.isTodo,
                isNote: result.isNote,
                hasLink: result.hasLink,
                deadline: result.deadline.map { format($0, hasTime: result.deadlineHasTime, calendar: calendar) },
                isMultiItem: result.isMultiItem,
                shortTitle: result.shortTitle,
                latency_ms: (latency * 100).rounded() / 100,
                error: failure
            )
            output += String(decoding: try encoder.encode(prediction), as: UTF8.self) + "\n"
            FileHandle.standardError.write(Data("\r\(index + 1)/\(lines.count)".utf8))
        }

        try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try output.write(to: outputURL, atomically: true, encoding: .utf8)
        FileHandle.standardError.write(Data("\nWrote \(lines.count) predictions to \(outputURL.path)\n".utf8))
    }

    static func checkModel() throws {
        #if canImport(FoundationModels)
        if case .unavailable(let reason) = FoundationModelsClassifier.status {
            throw EvalError.modelUnavailable(reason)
        }
        #else
        throw EvalError.modelUnavailable("this platform has no Foundation Models framework")
        #endif
    }

    static func refine(
        _ text: String,
        sentAt: Date,
        classifier: String,
        pipeline: ClassificationPipeline,
        calendar: Calendar
    ) async throws -> EntryClassification {
        #if canImport(FoundationModels)
        let variant: FoundationModelsClassifier.Variant = classifier == "fm-tag" ? .contentTagging : .general
        let answer = try await FoundationModelsClassifier(variant: variant).classify(text: text, sentAt: sentAt, calendar: calendar)
        return pipeline.merge(text: text, capturedAt: sentAt, llm: answer)
        #else
        throw EvalError.modelUnavailable("this platform has no Foundation Models framework")
        #endif
    }

    /// Reads "2026-10-14T19:32:00" (local time), with or without seconds, or a full ISO 8601 stamp.
    static func parseDate(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        for pattern in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm"] {
            formatter.dateFormat = pattern
            if let date = formatter.date(from: value) { return date }
        }
        return ISO8601DateFormatter().date(from: value)
    }

    static func format(_ date: Date, hasTime: Bool, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = hasTime ? "yyyy-MM-dd'T'HH:mm" : "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
