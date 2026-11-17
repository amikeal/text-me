import SwiftUI

/// Colors come from the asset catalog, where each has a light and a dark variant.
enum Theme {
    static let accent = Color("AccentColor")
    /// Text and icons on top of the accent color.
    static let onAccent = Color("OnAccent")
    /// The flat background the stream sits on.
    static let ground = Color("Ground")
    /// Link cards.
    static let card = Color("Card")
    static let deadlineBackground = Color("DeadlineBackground")
    static let deadlineForeground = Color("DeadlineForeground")
}

/// A round Liquid Glass button holding one symbol.
struct GlassIconButton: View {
    let systemName: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.body.weight(.semibold))
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel(label)
    }
}

/// The round send button used by both the blank page and the timeline composer.
struct SendButton: View {
    var size: CGFloat = 44
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.up")
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundStyle(isEnabled ? Theme.onAccent : Color.secondary)
                .frame(width: size, height: size)
                .background(isEnabled ? Theme.accent : Color.secondary.opacity(0.18), in: .circle)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .animation(.snappy(duration: 0.2), value: isEnabled)
        .accessibilityLabel("Save")
    }
}
