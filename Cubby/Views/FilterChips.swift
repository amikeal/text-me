import SwiftUI

/// All · To-dos · Links · Notes, on one piece of Liquid Glass.
struct FilterChips: View {
    @Binding var selection: EntryFilter
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(EntryFilter.allCases) { filter in
                let isSelected = selection == filter
                Button {
                    withAnimation(.snappy(duration: 0.25)) {
                        selection = filter
                    }
                } label: {
                    Text(filter.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .foregroundStyle(isSelected ? Theme.onAccent : Color.primary)
                        .padding(.horizontal, 11)
                        .frame(height: 44)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(Theme.accent)
                                    .matchedGeometryEffect(id: "selection", in: namespace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityIdentifier("filter-\(filter.rawValue)")
            }
        }
        .padding(4)
        .glassEffect(.regular, in: .capsule)
    }
}
