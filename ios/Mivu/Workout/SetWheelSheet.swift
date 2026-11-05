import SwiftUI

/// Two wheels for one set, like the iPhone timer: weight and reps, or minutes and seconds.
/// Tap the centred number to type it. Done also ticks the set.
struct SetWheelSheet: View {
    let number: Int
    let measure: ExerciseMeasure
    let unit: String
    let step: Double
    /// Only the values that changed: weight in the shown unit, reps, seconds.
    let onDone: (Double?, Int?, Int?) -> Void
    private let initial: (weight: Double, reps: Int, seconds: Int)
    @State private var weight: Double
    @State private var reps: Int
    @State private var minutes: Int
    @State private var seconds: Int
    @State private var typing: Field?
    @State private var typed = ""
    @State private var wheelHeight: CGFloat = 216
    @State private var height: CGFloat = 360

    enum Field: String { case weight = "Weight", reps = "Reps", minutes = "Minutes", seconds = "Seconds" }

    init(number: Int, set: WorkoutSet, measure: ExerciseMeasure, unit: String, step: Double, onDone: @escaping (Double?, Int?, Int?) -> Void) {
        self.number = number; self.measure = measure; self.unit = unit; self.step = step; self.onDone = onDone
        let weight = WeightStep.display(kg: set.loadKg ?? 0, unit: unit), total = set.seconds ?? 0
        initial = (weight, max(set.repetitions, 1), total)
        _weight = State(initialValue: weight); _reps = State(initialValue: max(set.repetitions, 1))
        _minutes = State(initialValue: total / 60); _seconds = State(initialValue: total % 60)
    }

    private var timed: Bool { measure == .time || measure == .distanceTime }

    /// Every step from 0 to the top of the range, plus an off-step value someone typed or imported.
    private var weights: [Double] {
        var values = Array(stride(from: 0, through: unit == "lb" ? 1_100 : 500, by: step))
        if !values.contains(weight) { values.append(weight); values.sort() }
        return values
    }

    var body: some View {
        VStack(spacing: 8) {
            Text("Set \(number)").font(.headline).padding(.top, 20)
            HStack(spacing: 0) {
                if timed {
                    wheel(.minutes, selection: $minutes, values: Array(0...300), unit: "min") { "\($0)" }
                    wheel(.seconds, selection: $seconds, values: Array(0...59), unit: "sec") { String(format: "%02d", $0) }
                } else {
                    wheel(.weight, selection: $weight, values: weights, unit: unit) { $0.formatted(.number.precision(.fractionLength(0...2))) }
                    wheel(.reps, selection: $reps, values: Array(1...100), unit: "reps") { "\($0)" }
                }
            }
            Button {
                let total = minutes * 60 + seconds
                onDone(weight == initial.weight ? nil : weight, reps == initial.reps ? nil : reps, !timed || total == initial.seconds ? nil : total)
            } label: {
                Label("Done", systemImage: "checkmark").font(.headline).frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent).buttonBorderShape(.capsule).tint(.diaryAccent)
            .accessibilityIdentifier("wheelDone")
            .padding(.horizontal, 20).padding(.bottom, 12)
        }
        // The sheet fits its content's ideal height at every text size.
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self, of: \.size.height) { height = $0 }
        .presentationDetents([.height(height)])
        .presentationBackground(Color.diarySurface)
        .alert(typing.map { LocalizedStringKey($0.rawValue) } ?? "", isPresented: Binding(get: { typing != nil }, set: { if !$0 { typing = nil } })) {
            TextField(typing?.rawValue ?? "", text: $typed).keyboardType(typing == .weight ? .decimalPad : .numberPad)
            Button("OK", action: applyTyped)
            Button("Cancel", role: .cancel) {}
        }
    }

    private func wheel<Value: Hashable>(_ field: Field, selection: Binding<Value>, values: [Value], unit: String, text: @escaping (Value) -> String) -> some View {
        VStack(spacing: 0) {
            Picker(LocalizedStringKey(field.rawValue), selection: selection) {
                ForEach(values, id: \.self) { Text(text($0)).monospacedDigit().tag($0) }
            }
            .pickerStyle(.wheel)
            .onGeometryChange(for: CGFloat.self, of: \.size.height) { wheelHeight = $0 }
            // Only a tap on the centred row types; other taps turn the wheel.
            .simultaneousGesture(SpatialTapGesture().onEnded { tap in
                if abs(tap.location.y - wheelHeight / 2) < 22 { typed = text(selection.wrappedValue); typing = field }
            })
            .accessibilityIdentifier("wheel\(field.rawValue)")
            Text(unit).font(.subheadline).foregroundStyle(Color.diarySecondary).accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity)
        .clipped()
    }

    /// Typed numbers outside the wheel's range are ignored.
    private func applyTyped() {
        let value = Double(typed.replacingOccurrences(of: ",", with: "."))
        switch typing {
        case .weight: if let value, (0...(unit == "lb" ? 1_100 : 500)).contains(value) { weight = (value * 100).rounded() / 100 }
        case .reps: if let value, (1...100).contains(value) { reps = Int(value) }
        case .minutes: if let value, (0...300).contains(value) { minutes = Int(value) }
        case .seconds: if let value, (0...59).contains(value) { seconds = Int(value) }
        case nil: break
        }
        typing = nil
    }
}
