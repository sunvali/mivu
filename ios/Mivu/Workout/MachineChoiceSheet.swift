import SwiftUI

/// "Which one?" for a machine with several uses. The best guess is already in the workout; picking another swaps it.
struct MachineChoiceSheet: View {
    let options: [String]
    let current: String?
    let onChoose: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(options, id: \.self) { id in
                Button {
                    onChoose(id); dismiss()
                } label: {
                    HStack {
                        Text(WorkoutCatalog.exercise(id)?.name ?? id).foregroundStyle(Color.diaryText)
                        Spacer(minLength: 8)
                        if id == current { Image(systemName: "checkmark").foregroundStyle(Color.diaryAccent).accessibilityHidden(true) }
                    }
                    .frame(minHeight: 44).contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(id == current ? .isSelected : [])
                .accessibilityIdentifier("machineOption")
            }
            .scrollContentBackground(.hidden).background(Color.diaryCanvas)
            .navigationTitle("Which one?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(role: .close) { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
        .tint(.diaryAccent)
    }
}
