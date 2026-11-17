import SwiftUI

enum SettingsKey {
    static let startScreen = "startScreen"
    static let appearance = "appearance"
    static let digestEnabled = "digestEnabled"
    static let digestWeekday = "digestWeekday"
    static let digestHour = "digestHour"
    static let linkPreviews = "linkPreviews"
}

/// What the app shows when it opens.
enum StartScreen: String, CaseIterable, Identifiable {
    /// A blank page with the keyboard up. The default.
    case capture
    /// Recent entries with the composer focused above the keyboard.
    case timeline

    var id: String { rawValue }

    var title: String {
        switch self {
        case .capture: return "Blank page"
        case .timeline: return "Timeline"
        }
    }
}

enum AppearanceSetting: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// Typed access to the same values the Settings screen edits through `@AppStorage`.
enum AppSettings {
    private static var defaults: UserDefaults { .standard }

    static func registerDefaults() {
        defaults.register(defaults: [
            SettingsKey.startScreen: StartScreen.capture.rawValue,
            SettingsKey.appearance: AppearanceSetting.system.rawValue,
            SettingsKey.digestEnabled: true,
            SettingsKey.digestWeekday: 1,
            SettingsKey.digestHour: 17,
            SettingsKey.linkPreviews: true,
        ])
    }

    static var startScreen: StartScreen {
        StartScreen(rawValue: defaults.string(forKey: SettingsKey.startScreen) ?? "") ?? .capture
    }

    static var digestEnabled: Bool {
        defaults.bool(forKey: SettingsKey.digestEnabled)
    }

    /// 1 = Sunday … 7 = Saturday.
    static var digestWeekday: Int {
        let value = defaults.integer(forKey: SettingsKey.digestWeekday)
        return (1...7).contains(value) ? value : 1
    }

    static var digestHour: Int {
        let value = defaults.integer(forKey: SettingsKey.digestHour)
        return (0...23).contains(value) ? value : 17
    }

    static var linkPreviews: Bool {
        defaults.bool(forKey: SettingsKey.linkPreviews)
    }
}
