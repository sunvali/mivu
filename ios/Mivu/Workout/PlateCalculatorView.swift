import SwiftUI

/// Mockup 8: the plates for each side of the bar, from the weight wheel. The bar can be changed here
/// for lifts with a different one (trap bar, landmine); the person's own bar and plates live in Settings.
struct PlateCalculatorView: View {
    /// In the shown unit.
    let target: Double
    let unit: String
    private let plates: [Double]
    private let bars: [Double]
    @State private var bar: Double
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize

    init(target: Double, unit: String) {
        self.target = target; self.unit = unit
        plates = WeightStep.plates(unit: unit)
        let own = WeightStep.bar(unit: unit)
        // Their bar, a lighter one, or none.
        bars = [own, unit == "lb" ? 35 : 15, 0].reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
        _bar = State(initialValue: own)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 6) {
                        Text("\(Self.number(target)) \(unit)").font(.largeTitle.weight(.bold)).monospacedDigit()
                        if let side = PlateCalculator.perSide(target: target, bar: bar, plates: plates) {
                            Text("Each side").font(.subheadline).foregroundStyle(Color.diarySecondary)
                            Text(side.isEmpty ? String(localized: "Just the bar") : side.map(Self.number).joined(separator: " + "))
                                .font(.title2.weight(.semibold)).foregroundStyle(Color.diaryWorkout).multilineTextAlignment(.center)
                                .accessibilityIdentifier("platesPerSide")
                        } else {
                            let nearest = PlateCalculator.nearest(target: target, bar: bar, plates: plates)
                            Text("Your plates can't make this").font(.subheadline).foregroundStyle(Color.diarySecondary)
                            Text(nearest.below == nearest.above ? "Closest: \(Self.number(nearest.below)) \(unit)"
                                 : "Closest: \(Self.number(nearest.below)) or \(Self.number(nearest.above)) \(unit)")
                                .font(.title3.weight(.semibold)).multilineTextAlignment(.center)
                                .accessibilityIdentifier("platesPerSide")
                        }
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                }
                Section("Bar") {
                    (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))) {
                        ForEach(bars, id: \.self) { choice in
                            let chosen = choice == bar
                            Button { bar = choice } label: {
                                Text(choice == 0 ? String(localized: "None") : "\(Self.number(choice)) \(unit)")
                                    .font(.subheadline.weight(.semibold)).padding(.horizontal, 16).frame(minHeight: 44)
                                    .foregroundStyle(chosen ? Color.diaryActionText : Color.diaryText)
                                    .background(chosen ? Color.diaryWorkout : Color.diaryCanvas, in: .capsule)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(choice == 0 ? String(localized: "No bar") : "\(Self.number(choice)) \(unit)")
                            .accessibilityAddTraits(chosen ? .isSelected : [])
                        }
                    }
                }
                Section {
                    LabeledContent("My plates", value: plates.map(Self.number).joined(separator: " · "))
                } footer: {
                    Text("Change your bar and plates in Settings › Workouts.")
                }
            }
            .scrollContentBackground(.hidden).background(Color.diaryCanvas)
            .navigationTitle("Plates")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.accessibilityIdentifier("platesDone") } }
        }
        .tint(.diaryAccent)
        .presentationDetents([.medium, .large])
    }

    static func number(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0...2))) }
}
