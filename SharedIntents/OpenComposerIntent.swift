import AppIntents
import Foundation

/// Opens Cubby ready to type. Compiled into both the app and the widget extension, because the
/// Control Center control lives in the extension but the intent has to run in the app.
struct OpenComposerIntent: AppIntent {
    static let title: LocalizedStringResource = "New Cubby Note"
    static let description: IntentDescription? = IntentDescription("Opens Cubby ready to type.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(URL(string: "cubby://compose")!))
    }
}
