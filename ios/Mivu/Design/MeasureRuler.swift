import SwiftUI

/// A large number over a horizontal ruler that snaps to `step`, for height and weight.
/// The number is a text field, so an exact value can always be typed; the ruler follows it.
struct MeasureRuler<Field: Hashable>: View {
    let title: String
    @Binding var text: String
    let range: ClosedRange<Double>
    let step: Double
    let unit: String
    /// Where the ruler rests while the text is empty.
    var placeholder: Double
    var fieldID: String
    var focus: FocusState<Field?>.Binding
    var field: Field
    /// Replaces the text field with a read-only label, for values like 5′ 7″ that don't type as one number.
    var formatted: ((Double) -> String)? = nil
    /// Steps between labelled marks; by default every whole unit for 0.1 steps, else every 10.
    var majorEvery: Int? = nil

    @State private var index: Int?
    @State private var selection: TextSelection?
    @State private var dragging = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var numberSize = 64.0
    private static var spacing: CGFloat { 10 }

    private var count: Int { Int(((range.upperBound - range.lowerBound) / step).rounded()) + 1 }
    private var number: Double? { ProgressDate.number(text) }
    private func value(at index: Int) -> Double { range.lowerBound + Double(index) * step }
    private func index(of value: Double) -> Int { min(count - 1, max(0, Int(((value - range.lowerBound) / step).rounded()))) }
    private func write(_ value: Double) { text = value.formatted(.number.precision(.fractionLength(step < 1 ? 1 : 0)).grouping(.never)) }
    private var major: Int { majorEvery ?? (step < 1 ? Int((1 / step).rounded()) : 10) }

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if let formatted {
                    Text(formatted(number ?? placeholder))
                } else {
                    TextField(String(placeholder.formatted()), text: $text, selection: $selection)
                        .keyboardType(step < 1 ? .decimalPad : .numberPad)
                        .focused(focus, equals: field)
                        .fixedSize()
                        .frame(minWidth: 44, minHeight: 44)
                        // Selecting the whole number on focus lets typing replace it, like a scale's display.
                        .onChange(of: focus.wrappedValue == field) { _, focused in
                            guard focused else { return }
                            Task { selection = TextSelection(range: text.startIndex..<text.endIndex) }
                        }
                        .accessibilityLabel("\(title), \(unit)")
                        .accessibilityIdentifier(fieldID)
                }
                Text(unit).font(.title2.weight(.medium)).foregroundStyle(Color.diarySecondary)
            }
            .font(.system(size: numberSize, weight: .semibold, design: .rounded).monospacedDigit())
            .foregroundStyle(Color.diaryText)
            .minimumScaleFactor(0.5).lineLimit(1)
            ruler
        }
        .onAppear { index = index(of: number ?? placeholder) }
        // Typing moves the ruler; the ruler never rewrites what is being typed.
        .onChange(of: text) { _, _ in
            guard !dragging, let number, index != index(of: number) else { return }
            withAnimation(reduceMotion ? nil : .snappy) { index = index(of: number) }
        }
    }

    private var ruler: some View {
        GeometryReader { geometry in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(0..<count, id: \.self) { tick($0) }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .contentMargins(.horizontal, (geometry.size.width - Self.spacing) / 2, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned(limitBehavior: .never))
            .scrollPosition(id: $index, anchor: .center)
            .onScrollPhaseChange { _, phase in
                if phase == .interacting { dragging = true; focus.wrappedValue = nil }
                if phase == .idle { dragging = false }
            }
            .onChange(of: index) { _, index in
                if dragging, let index { write(value(at: index)) }
            }
            .sensoryFeedback(.selection, trigger: index) { _, _ in dragging }
        }
        .frame(height: 64)
        // Numbers grow to the right on a scale in every language.
        .environment(\.layoutDirection, .leftToRight)
        .overlay(alignment: .top) {
            Capsule().fill(Color.diaryAccent).frame(width: 3, height: 40).allowsHitTesting(false)
        }
        .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.2),
                                     .init(color: .black, location: 0.8), .init(color: .clear, location: 1)],
                             startPoint: .leading, endPoint: .trailing))
        .accessibilityElement()
        .accessibilityLabel(title)
        .accessibilityValue(formatted.map { $0(number ?? placeholder) } ?? "\((number ?? placeholder).formatted()) \(unit)")
        .accessibilityAdjustableAction { direction in
            // One whole unit per swipe; the number field types anything finer.
            let stepped = (number ?? placeholder).rounded() + (direction == .increment ? 1 : -1)
            write(min(range.upperBound, max(range.lowerBound, stepped)))
        }
        .accessibilityIdentifier(fieldID + "Ruler")
    }

    private func tick(_ i: Int) -> some View {
        let isMajor = i % major == 0, isHalf = major % 2 == 0 && i % (major / 2) == 0
        return VStack(spacing: 6) {
            Capsule().fill(Color.diaryText.opacity(isMajor ? 0.8 : isHalf ? 0.45 : 0.25))
                .frame(width: isMajor ? 2 : 1.5, height: isMajor ? 32 : isHalf ? 22 : 14)
            if isMajor {
                Text(formatted.map { $0(value(at: i)) } ?? value(at: i).formatted(.number.grouping(.never)))
                    .font(.caption.monospacedDigit()).foregroundStyle(Color.diarySecondary)
                    .fixedSize()
                    // The marks are a visual guide inside a fixed-height ruler; the number above scales fully.
                    .dynamicTypeSize(...DynamicTypeSize.xLarge)
            }
        }
        .frame(width: Self.spacing, height: 64, alignment: .top)
    }
}
