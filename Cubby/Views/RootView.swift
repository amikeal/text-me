import SwiftUI

/// Switches between the blank capture page and the timeline.
struct RootView: View {
    @Environment(AppRouter.self) private var router
    @AppStorage(SettingsKey.appearance) private var appearance = AppearanceSetting.system.rawValue

    var body: some View {
        ZStack {
            Theme.ground.ignoresSafeArea()
            switch router.screen {
            case .capture:
                CaptureView()
                    .transition(.move(edge: .top).combined(with: .opacity))
            case .timeline:
                StreamView()
                    .transition(.opacity)
            }
        }
        .animation(.snappy(duration: 0.3), value: router.screen)
        .preferredColorScheme(AppearanceSetting(rawValue: appearance)?.colorScheme)
        .onOpenURL { url in
            router.handle(url: url)
        }
        .task {
            CubbyModel.shared.importInbox()
            await CubbyModel.shared.classifyBacklog()
        }
    }
}
