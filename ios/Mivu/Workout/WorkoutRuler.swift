import SwiftUI

/// A big number over a sideways ruler: drag to change it one tick at a time, or tap the number to type.
struct WorkoutRuler: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let majorEvery: Int
    let unit: String
    let format: (Double) -> String
    let label: String

    @State private var position = ScrollPosition(idType: Int.self)
    @State private var phase = ScrollPhase.idle
    @State private var scrolledIndex: Int?
    @State private var width: CGFloat = 0
    @State private var typing = false
    @State private var typed: Double?
    @FocusState private var focused: Bool
    @ScaledMetric(relativeTo: .largeTitle) private var valueSize = 44.0
    private let spacing: CGFloat = 10

    init(value: Binding<Double>, range: ClosedRange<Double>, step: Double, majorEvery: Int, unit: String,
         format: @escaping (Double) -> String, label: String) {
        _value = value; self.range = range; self.step = step; self.majorEvery = majorEvery
        self.unit = unit; self.format = format; self.label = label
    }

    private var count: Int { Int(((range.upperBound - range.lowerBound) / step).rounded()) }
    private var index: Int { min(max(Int(((value - range.lowerBound) / step).rounded()), 0), count) }
    private func snapped(_ index: Int) -> Double { range.lowerBound + Double(min(max(index, 0), count)) * step }

    var body: some View {
        VStack(spacing: 8) {
            number
            ruler
        }
        .accessibilityElement(children: typing ? .contain : .ignore)
        .accessibilityLabel(label)
        .accessibilityValue("\(format(value)) \(unit)")
        .accessibilityAdjustableAction { direction in
            if direction == .increment { value = snapped(index + 1) } else if direction == .decrement { value = snapped(index - 1) }
        }
        .accessibilityAction { startTyping() }
    }

    @ViewBuilder private var number: some View {
        if typing {
            TextField(label, value: $typed, format: .number)
                .keyboardType(.decimalPad).focused($focused)
                .font(.system(size: valueSize, weight: .bold)).monospacedDigit().multilineTextAlignment(.center)
                .frame(minHeight: 44)
                .onAppear { focused = true }
                .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
        } else {
            Button(action: startTyping) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(format(value)).font(.system(size: valueSize, weight: .bold)).monospacedDigit()
                        .contentTransition(.numericText(value: value))
                    Text(unit).font(.headline).foregroundStyle(Color.diarySecondary)
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
    }

    private var ruler: some View {
        GeometryReader { proxy in
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 0) {
                    ForEach(0...count, id: \.self, content: tick)
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            // Half a screen of margin on each side lets the first and last tick reach the needle.
            .contentMargins(.horizontal, proxy.size.width / 2 - spacing / 2, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned(limitBehavior: .never))
            .scrollPosition($position, anchor: .center)
            .onScrollGeometryChange(for: Int.self) { geometry in
                Int(((geometry.contentOffset.x + geometry.contentInsets.leading) / spacing).rounded())
            } action: { _, scrolled in
                scrolledIndex = scrolled
                // Only a finger moves the value; jumping to a typed value must not echo back through here.
                if phase != .idle { value = snapped(scrolled) }
            }
            .onScrollPhaseChange { _, new in
                phase = new
                if new == .idle, let scrolledIndex { value = snapped(scrolledIndex) }
            }
            // The margins depend on the width, so place the value once the width is known.
            .onChange(of: proxy.size.width, initial: true) { _, new in width = new; scroll(to: index) }
        }
        .frame(height: 60)
        .overlay(alignment: .top) { Capsule().fill(Color.diaryAccent).frame(width: 3, height: 36) }
        .mask {
            LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.22),
                                   .init(color: .black, location: 0.78), .init(color: .clear, location: 1)],
                           startPoint: .leading, endPoint: .trailing)
        }
        .sensoryFeedback(.selection, trigger: index)
        // VoiceOver adjusts the number instead; the off-screen ticks would also stretch its focus frame.
        .accessibilityHidden(true)
        .onChange(of: index) { _, new in if new != scrolledIndex { scroll(to: new) } }
    }

    private func tick(_ index: Int) -> some View {
        // Major ticks fall on round values (5, 10, 15 min), whatever the lower bound.
        let major = Int((snapped(index) / step).rounded()) % majorEvery == 0
        return VStack(spacing: 6) {
            Capsule().fill(major ? Color.diarySecondary : Color.diaryRule)
                .frame(width: 2, height: major ? 30 : 16)
                .frame(height: 36, alignment: .center)
            if major {
                Text(format(snapped(index))).font(.caption2).foregroundStyle(Color.diarySecondary)
                    .dynamicTypeSize(...DynamicTypeSize.xxLarge).fixedSize()
            }
        }
        .frame(width: spacing)
    }

    /// Puts tick `index` under the needle; the inverse of the offset-to-index reading above.
    private func scroll(to index: Int) { position.scrollTo(x: CGFloat(index) * spacing - (width / 2 - spacing / 2)) }

    private func startTyping() { typed = value; typing = true }

    private func commit() {
        if let typed, typed.isFinite { value = snapped(Int(((typed - range.lowerBound) / step).rounded())) }
        typing = false
    }
}
