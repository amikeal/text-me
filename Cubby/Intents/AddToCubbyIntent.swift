import AppIntents

/// "Add to Cubby" for Siri, Shortcuts and the Action button. Saves without opening the app.
struct AddToCubbyIntent: AppIntent {
    static let title: LocalizedStringResource = "Add to Cubby"
    static let description: IntentDescription? = IntentDescription("Drop a note, a link or a to-do into Cubby. It gets sorted for you.")
    static let openAppWhenRun = false

    @Parameter(title: "Text", requestValueDialog: "What do you want to drop in?")
    var text: String

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$text) to Cubby")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw $text.needsValueError("What do you want to drop in?")
        }
        CubbyModel.shared.capture(trimmed, source: .intent)
        return .result(dialog: "Dropped in.")
    }
}

struct CubbyShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddToCubbyIntent(),
            phrases: [
                "Add to \(.applicationName)",
                "Drop it in \(.applicationName)",
                "Note to self in \(.applicationName)",
            ],
            shortTitle: "Add to Cubby",
            systemImageName: "tray.and.arrow.down"
        )
    }
}
