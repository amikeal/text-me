import Foundation

/// The shared container the app, the share extension and the widget all read and write.
///
/// The identifier comes from the `CubbyAppGroup` key each target's Info.plist carries, so it is
/// set in one place (Config/Cubby.xcconfig) and never hard-coded.
public enum AppGroup {
    public static var identifier: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "CubbyAppGroup") as? String,
              !value.isEmpty else { return nil }
        return value
    }

    /// Nil when the App Group isn't provisioned (for example an unsigned build).
    public static var containerURL: URL? {
        #if canImport(Darwin)
        guard let identifier = identifier else { return nil }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
        #else
        return nil
        #endif
    }

    /// Where the share extension leaves captures for the app to pick up.
    public static var inboxDirectory: URL? {
        containerURL?.appendingPathComponent("Inbox", isDirectory: true)
    }

    /// The small summary the widget reads.
    public static var snapshotURL: URL? {
        containerURL?.appendingPathComponent("widget-snapshot.json", isDirectory: false)
    }
}
