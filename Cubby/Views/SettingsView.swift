import SwiftUI
import UIKit
import UserNotifications
import CubbyCore

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @AppStorage(SettingsKey.startScreen) private var startScreen = StartScreen.capture.rawValue
    @AppStorage(SettingsKey.appearance) private var appearance = AppearanceSetting.system.rawValue
    @AppStorage(SettingsKey.digestEnabled) private var digestEnabled = true
    @AppStorage(SettingsKey.digestWeekday) private var digestWeekday = 1
    @AppStorage(SettingsKey.digestHour) private var digestHour = 17
    @AppStorage(SettingsKey.linkPreviews) private var linkPreviews = true

    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var isResorting = false

    var body: some View {
        NavigationStack {
            Form {
                openingSection
                appearanceSection
                remindersSection
                linksSection
                sortingSection
                aboutSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                notificationStatus = await CubbyModel.shared.notifications.authorizationStatus()
            }
            .onChange(of: digestEnabled) { CubbyModel.shared.refreshDerived() }
            .onChange(of: digestWeekday) { CubbyModel.shared.refreshDerived() }
            .onChange(of: digestHour) { CubbyModel.shared.refreshDerived() }
        }
    }

    // MARK: - Sections

    private var openingSection: some View {
        Section {
            Picker("Open to", selection: $startScreen) {
                ForEach(StartScreen.allCases) { screen in
                    Text(screen.title).tag(screen.rawValue)
                }
            }
        } footer: {
            Text("A blank page gets you typing fastest. The timeline shows your recent entries above the keyboard.")
        }
    }

    private var appearanceSection: some View {
        Section("Appearance") {
            Picker("Appearance", selection: $appearance) {
                ForEach(AppearanceSetting.allCases) { setting in
                    Text(setting.title).tag(setting.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    private var remindersSection: some View {
        Section {
            notificationRow
            Toggle("Weekly digest", isOn: $digestEnabled)
            if digestEnabled {
                Picker("Day", selection: $digestWeekday) {
                    ForEach(1...7, id: \.self) { weekday in
                        Text(Calendar.current.weekdaySymbols[weekday - 1]).tag(weekday)
                    }
                }
                Picker("Time", selection: $digestHour) {
                    ForEach(6...22, id: \.self) { hour in
                        Text(Self.hourLabel(hour)).tag(hour)
                    }
                }
            }
        } header: {
            Text("Reminders")
        } footer: {
            Text("Cubby reminds you when a to-do with a date comes due, and once a week sums up what's still open.")
        }
    }

    @ViewBuilder
    private var notificationRow: some View {
        switch notificationStatus {
        case .authorized, .provisional, .ephemeral:
            LabeledContent("Notifications", value: "On")
        case .denied:
            Button("Turn On Notifications in Settings") {
                if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                    openURL(url)
                }
            }
        default:
            Button("Turn On Notifications") {
                Task {
                    await CubbyModel.shared.notifications.requestAuthorization()
                    notificationStatus = await CubbyModel.shared.notifications.authorizationStatus()
                    CubbyModel.shared.refreshDerived()
                }
            }
        }
    }

    private var linksSection: some View {
        Section {
            Toggle("Fetch link titles", isOn: $linkPreviews)
        } header: {
            Text("Links")
        } footer: {
            Text("Cubby contacts a linked site once to get its title. Everything else stays on your device and in your iCloud.")
        }
    }

    private var sortingSection: some View {
        Section {
            LabeledContent("Sorted by", value: engineName)
            Button {
                isResorting = true
                Task {
                    await CubbyModel.shared.resortEverything()
                    isResorting = false
                }
            } label: {
                HStack {
                    Text("Sort Everything Again")
                    Spacer()
                    if isResorting { ProgressView() }
                }
            }
            .disabled(isResorting)
        } header: {
            Text("Sorting")
        } footer: {
            Text(engineFootnote)
        }
    }

    private var aboutSection: some View {
        Section {
            LabeledContent("Version", value: Self.version)
        } header: {
            Text("About")
        } footer: {
            Text("Cubby: notes to self, sorted for you.\nDrop it in. Find it later.")
        }
    }

    // MARK: - Values

    private var engineName: String {
        FoundationModelsClassifier.isAvailable ? "Apple Intelligence" : "Built-in rules"
    }

    private var engineFootnote: String {
        switch FoundationModelsClassifier.status {
        case .available:
            return "Entries are sorted on this device by Apple Intelligence. Your corrections are always kept."
        case .unavailable(let reason):
            return "\(reason), so Cubby sorts with built-in rules. Your corrections are always kept."
        }
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "–"
        let build = info?["CFBundleVersion"] as? String ?? "–"
        return "\(short) (\(build))"
    }

    private static func hourLabel(_ hour: Int) -> String {
        let date = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }
}
