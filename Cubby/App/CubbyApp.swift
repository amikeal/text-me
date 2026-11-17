import SwiftUI
import SwiftData

@main
struct CubbyApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var router = AppRouter.shared
    @State private var backgroundedAt: Date?

    /// Away longer than this and the app reopens ready to capture, as if freshly launched.
    private static let resetAfter: TimeInterval = 60

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(router)
                .modelContainer(CubbyModel.shared.container)
                .tint(Theme.accent)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                CubbyModel.shared.importInbox()
                Task { await CubbyModel.shared.classifyBacklog() }
                if let backgroundedAt, Date().timeIntervalSince(backgroundedAt) > Self.resetAfter {
                    router.resetToStart()
                }
                backgroundedAt = nil
            case .background:
                backgroundedAt = Date()
                CubbyModel.shared.refreshDerived(immediately: true)
                BackgroundRefresh.schedule()
            default:
                break
            }
        }
        .backgroundTask(.appRefresh(BackgroundRefresh.identifier)) {
            await CubbyModel.shared.backgroundRefresh()
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // The notification delegate has to be in place before launch finishes, or a tap on a
        // reminder that launched the app is lost.
        CubbyModel.shared.notifications.configure()
        return true
    }
}
