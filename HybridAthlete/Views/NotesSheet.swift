import SwiftUI

/// Optional "how was last night?" notes. Nothing is required — they only sharpen the explanation.
struct NotesSheet: View {
    let activity: Activity
    let onSave: (SleepAnswer?, DrinksAnswer?, FuelAnswer?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var sleep: SleepAnswer?
    @State private var drinks: DrinksAnswer?
    @State private var fuel: FuelAnswer?

    init(activity: Activity, onSave: @escaping (SleepAnswer?, DrinksAnswer?, FuelAnswer?) -> Void) {
        self.activity = activity
        self.onSave = onSave
        _sleep = State(initialValue: activity.sleepAnswer)
        _drinks = State(initialValue: activity.drinksAnswer)
        _fuel = State(initialValue: activity.fuelAnswer)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ChipPicker(options: SleepAnswer.allCases, selection: $sleep, title: \.title)
                } header: {
                    Text("How'd you sleep?")
                } footer: {
                    if let hours = activity.recovery?.sleepHours {
                        Text("Your Watch logged \(Format.hoursMinutes(hours * 3600)).")
                    }
                }
                Section("Drinks last night?") {
                    ChipPicker(options: DrinksAnswer.allCases, selection: $drinks, title: \.title)
                }
                Section {
                    ChipPicker(options: FuelAnswer.allCases, selection: $fuel, title: \.title)
                } header: {
                    Text("How'd you eat?")
                } footer: {
                    Text("All optional. It changes the story, not the score.")
                }
            }
            .navigationTitle("Last night")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(sleep, drinks, fuel)
                        dismiss()
                    }
                    .bold()
                }
            }
        }
    }
}

/// Tap-to-select chips; tapping the selected chip clears it.
private struct ChipPicker<Option: Identifiable & Hashable>: View {
    let options: [Option]
    @Binding var selection: Option?
    let title: KeyPath<Option, String>

    var body: some View {
        ViewThatFits {
            HStack(spacing: 8) { chips }
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) { ForEach(options.prefix(2)) { chip($0) } }
                HStack(spacing: 8) { ForEach(options.dropFirst(2)) { chip($0) } }
            }
        }
        .padding(.vertical, 4)
    }

    private var chips: some View { ForEach(options) { chip($0) } }

    private func chip(_ option: Option) -> some View {
        let selected = selection == option
        return Button {
            selection = selected ? nil : option
        } label: {
            Text(option[keyPath: title])
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(selected ? Color.orange : Color(.tertiarySystemFill), in: Capsule())
                .foregroundStyle(selected ? .white : .primary)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
