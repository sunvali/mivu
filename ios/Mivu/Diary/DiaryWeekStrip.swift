import SwiftUI

/// Calendar math on `yyyy-MM-dd` labels. Labels are formatted in UTC so a date never shifts across zones.
enum DiaryWeek {
    private static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }

    static func date(_ label: String) -> Date? { ProgressDate.date(label, zone: "UTC") }
    static func label(_ date: Date) -> String { ProgressDate.label(date, zone: "UTC") }
    static func adding(_ days: Int, to localDate: String) -> String? {
        date(localDate).flatMap { utc.date(byAdding: .day, value: days, to: $0) }.map { label($0) }
    }

    static func dates(containing localDate: String, calendar: Calendar) -> [String] {
        guard let day = date(localDate) else { return [] }
        let offset = (utc.component(.weekday, from: day) - calendar.firstWeekday + 7) % 7
        return (0..<7).compactMap { adding($0 - offset, to: localDate) }
    }

    /// Every week from the earliest of the records and the selection, through the week holding `today`.
    static func weekStarts(earliest: String?, selected: String, today: String, calendar: Calendar) -> [String] {
        let first = [earliest, selected, today].compactMap { $0 }.min() ?? today
        guard let start = dates(containing: first, calendar: calendar).first,
              let end = dates(containing: max(today, selected), calendar: calendar).first else { return [] }
        return Array(sequence(first: start) { week in week < end ? adding(7, to: week) : nil })
    }

    static func format(_ localDate: String, _ pattern: String) -> String {
        guard let day = date(localDate) else { return localDate }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US"); formatter.timeZone = .gmt; formatter.dateFormat = pattern
        return formatter.string(from: day)
    }

    static func pillLabel(_ localDate: String, summaries: [DiaryDaySummary]) -> String {
        let name = format(localDate, "EEEE d MMMM")
        guard let first = summaries.first else { return "\(name), nothing logged" }
        let meals = summaries.reduce(0) { $0 + $1.mealCount }
        return "\(name), \(first.day.completeness.rawValue), \(meals) \(meals == 1 ? "meal" : "meals")"
    }
}

extension DayCompleteness {
    var color: Color {
        switch self {
        case .complete: .diarySuccess
        case .partial: .diaryWarning
        case .unknown, .untracked: .diarySecondary
        }
    }
}

/// Swipe between weeks, tap a day. Swiping keeps the weekday and never moves past today.
struct DiaryWeekStrip: View {
    @Binding var selected: String
    let today: String
    let earliest: String?
    let summaries: [String: [DiaryDaySummary]]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visibleWeek: String?
    private var calendar: Calendar { .current }

    private var weeks: [String] { DiaryWeek.weekStarts(earliest: earliest, selected: selected, today: today, calendar: calendar) }
    private func weekStart(_ date: String) -> String { DiaryWeek.dates(containing: date, calendar: calendar).first ?? date }

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(weeks, id: \.self) { week in
                    HStack(spacing: 4) {
                        ForEach(DiaryWeek.dates(containing: week, calendar: calendar), id: \.self, content: pill)
                    }
                    .containerRelativeFrame(.horizontal)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollIndicators(.hidden)
        .scrollPosition(id: $visibleWeek)
        .onAppear { visibleWeek = weekStart(selected) }
        .onChange(of: selected) { _, date in
            let week = weekStart(date)
            if week != visibleWeek { withAnimation(reduceMotion ? nil : .snappy) { visibleWeek = week } }
        }
        .onChange(of: visibleWeek) { _, week in
            let current = weekStart(selected)
            guard let week, week != current, let from = DiaryWeek.date(current), let to = DiaryWeek.date(week) else { return }
            let shift = Int((to.timeIntervalSince(from) / 86_400).rounded())
            selected = min(DiaryWeek.adding(shift, to: selected) ?? selected, today)
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .accessibilityIdentifier("diaryWeekStrip")
    }

    private func pill(_ date: String) -> some View {
        let days = summaries[date] ?? [], isSelected = date == selected, isFuture = date > today
        return Button { selected = date } label: {
            VStack(spacing: 4) {
                Text(DiaryWeek.format(date, "EEEEE")).font(.caption2.weight(.semibold))
                    .foregroundStyle(isSelected ? Color.diaryActionText : Color.diarySecondary)
                Text(DiaryWeek.format(date, "d")).font(.headline).monospacedDigit()
                    .foregroundStyle(isSelected ? Color.diaryActionText : date == today ? Color.diaryAccent : Color.diaryText)
                Circle().fill(days.first?.day.completeness.color ?? .clear).frame(width: 6, height: 6)
                    .opacity(days.isEmpty || isSelected ? 0 : 1)
            }
            .frame(maxWidth: .infinity, minHeight: 64)
            .background { if isSelected { Capsule().fill(Color.diaryAccent) } }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isFuture).opacity(isFuture ? 0.35 : 1)
        .accessibilityLabel(DiaryWeek.pillLabel(date, summaries: days))
        .accessibilityValue(date)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityShowsLargeContentViewer()
        .accessibilityIdentifier("diaryDayPill")
    }
}

struct CoverageChip: View {
    let completeness: DayCompleteness
    let set: (DayCompleteness) -> Void
    var body: some View {
        Menu {
            Section("Complete means all intake was recorded.") {
                ForEach(DayCompleteness.allCases, id: \.self) { value in
                    Button { set(value) } label: {
                        if value == completeness { Label { Text(value.title) } icon: { Image(systemName: "checkmark") } } else { Text(value.title) }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Circle().fill(completeness.color).frame(width: 8, height: 8)
                Text(completeness.title).font(.subheadline.weight(.medium))
                Image(systemName: "chevron.up.chevron.down").font(.caption2.weight(.semibold))
            }
            .foregroundStyle(Color.diaryText)
            .padding(.horizontal, 12).frame(minHeight: 44)
            .background(Capsule().fill(Color.diarySummarySurface))
        }
        .accessibilityLabel(Text("Day coverage"))
        .accessibilityValue(Text(completeness.title))
        .accessibilityIdentifier("diaryCoverageChip")
    }
}
