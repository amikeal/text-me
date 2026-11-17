import SwiftUI

/// Sets a deadline by hand, for when Cubby missed one or got it wrong.
struct DeadlineEditor: View {
    let entry: Entry

    @Environment(\.dismiss) private var dismiss
    @State private var date: Date
    @State private var includesTime: Bool

    init(entry: Entry) {
        self.entry = entry
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        _date = State(initialValue: entry.deadline ?? tomorrow)
        _includesTime = State(initialValue: entry.deadline != nil && entry.deadlineHasTime)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker(
                        "Date",
                        selection: $date,
                        displayedComponents: includesTime ? [.date, .hourAndMinute] : [.date]
                    )
                    .datePickerStyle(.graphical)
                    Toggle("Include a time", isOn: $includesTime)
                } footer: {
                    Text(includesTime
                         ? "Cubby reminds you at this time."
                         : "Cubby reminds you at 9:00 that morning.")
                }

                if entry.deadline != nil {
                    Section {
                        Button("Remove Deadline", role: .destructive) {
                            CubbyModel.shared.setDeadline(entry, date: nil, hasTime: false)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Deadline")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let value = includesTime ? date : Calendar.current.startOfDay(for: date)
                        CubbyModel.shared.setDeadline(entry, date: value, hasTime: includesTime)
                        dismiss()
                    }
                }
            }
        }
    }
}
