import SwiftUI

/// The one input, present on every timeline view so capture never needs navigation.
struct ComposerBar: View {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    let onSend: () -> Void

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Note to self", text: $text, axis: .vertical)
                .lineLimit(1...6)
                .focused(isFocused)
                .submitLabel(.send)
                .onSubmit(onSend)
                .padding(.leading, 20)
                .padding(.vertical, 16)
            SendButton(isEnabled: canSend, action: onSend)
                .padding(.trailing, 6)
                .padding(.bottom, 6)
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 28))
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 8)
    }
}
