import SwiftUI
import SwiftData

/// The default opening screen: a blank page, keyboard up, nothing to decide.
struct CaptureView: View {
    @Environment(AppRouter.self) private var router
    @Query(filter: #Predicate<Entry> { $0.isTodo && $0.completedAt == nil })
    private var openTodos: [Entry]

    @State private var text = ""
    @State private var lastSaved: String?
    @State private var savedCount = 0
    @State private var showSettings = false
    @FocusState private var isFocused: Bool

    private var canSave: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                timelinePill
                HStack {
                    Spacer()
                    GlassIconButton(systemName: "gearshape", label: "Settings") {
                        showSettings = true
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            ScrollView {
                TextField("Note to self", text: $text, axis: .vertical)
                    .font(.system(size: 28, weight: .medium))
                    .lineLimit(1...)
                    .focused($isFocused)
                    .submitLabel(.send)
                    .onSubmit(save)
                    .padding(.horizontal, 24)
                    .padding(.top, 28)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDismissesKeyboard(.never)
            .contentShape(Rectangle())
            .onTapGesture { isFocused = true }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomBar
        }
        .background(Theme.ground.ignoresSafeArea())
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .onAppear { isFocused = true }
        .onChange(of: router.focusRequest) { isFocused = true }
        .sensoryFeedback(.success, trigger: savedCount)
    }

    /// The way through to everything already saved.
    private var timelinePill: some View {
        Button {
            router.showTimeline()
        } label: {
            HStack(spacing: 8) {
                Text("Timeline")
                    .fontWeight(.semibold)
                if !openTodos.isEmpty {
                    Text(openTodos.count == 1 ? "1 open to-do" : "\(openTodos.count) open to-dos")
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.down")
                    .font(.footnote.weight(.bold))
            }
            .font(.subheadline)
            .padding(.horizontal, 18)
            .frame(height: 44)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .capsule)
    }

    private var bottomBar: some View {
        HStack(alignment: .center, spacing: 12) {
            if let lastSaved {
                Label {
                    Text(lastSaved)
                        .lineLimit(1)
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.accent)
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .accessibilityLabel("Saved: \(lastSaved)")
            }
            Spacer(minLength: 0)
            SendButton(size: 52, isEnabled: canSave, action: save)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    private func save() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Return dismisses the keyboard on a multi-line field; bring it straight back.
        Task { @MainActor in isFocused = true }
        guard !trimmed.isEmpty else { return }

        CubbyModel.shared.capture(trimmed, source: .app)
        text = ""
        savedCount += 1
        withAnimation(.snappy) { lastSaved = trimmed }

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            if lastSaved == trimmed {
                withAnimation(.snappy) { lastSaved = nil }
            }
        }
    }
}
