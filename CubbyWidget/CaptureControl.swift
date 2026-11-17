import AppIntents
import SwiftUI
import WidgetKit

/// A Control Center, Lock Screen and Action button control that opens Cubby ready to type.
struct CaptureControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "CubbyCaptureControl") {
            ControlWidgetButton(action: OpenComposerIntent()) {
                Label("New Note", systemImage: "square.and.pencil")
            }
        }
        .displayName("New Cubby Note")
        .description("Open Cubby ready to type.")
    }
}
