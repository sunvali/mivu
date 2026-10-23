import SwiftUI

/// A card's full screen: the same range, paged back a whole window at a time until the diary has no older days.
struct ProgressDetail<Content: View>: View {
    let title: String
    @Bindable var model: DiaryViewModel
    let range: ProgressRange
    let today: String
    var foodLimit = 0
    @ViewBuilder let content: (ProgressSnapshot, [TopFood]) -> Content

    @State private var endingOn: String?
    @State private var snapshot: ProgressSnapshot?
    /// The window `snapshot` belongs to; another window shows loading, never stale numbers.
    @State private var loadedEnd: String?
    @State private var hasEarlier = false
    @State private var foods: [TopFood] = []
    @State private var loadError: String?
    @State private var ownership: DiarySelectionOwnership?
    @Environment(\.dismiss) private var dismiss

    private var zone: String { model.readModel?.profile.timeZoneID ?? TimeZone.current.identifier }
    private var end: String { endingOn ?? today }
    private struct Request: Equatable { let end: String; let generation: UInt64 }

    var body: some View {
        List {
            Section {
                HStack {
                    Button { endingOn = shift(-range.days) } label: { Label("Earlier", systemImage: "chevron.left").frame(minHeight: 44) }
                        .disabled(!hasEarlier || loadedEnd != end)
                        .accessibilityIdentifier("progressDetailEarlier")
                    Spacer()
                    Text(dates).font(.subheadline.weight(.semibold)).foregroundStyle(Color.diarySecondary)
                    Spacer()
                    Button { endingOn = min(today, shift(range.days)) } label: { Label("Later", systemImage: "chevron.right").labelStyle(.titleAndIcon).frame(minHeight: 44) }
                        .disabled(end >= today)
                }
                .buttonStyle(.borderless)
            }
            .listRowBackground(Color.clear)
            if let snapshot, loadedEnd == end {
                content(snapshot, foods)
            } else if let loadError {
                Text(loadError).foregroundStyle(Color.diaryError)
                Button("Retry") { Task { await load() } }.frame(minHeight: 44)
            } else {
                ProgressView("Loading…")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden).background(Color.diaryCanvas)
        .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .task(id: Request(end: end, generation: model.changeGeneration)) { await load() }
        .onAppear { ownership = ownership ?? model.selection }
        .onChange(of: model.selection) { _, selected in if selected != ownership { dismiss() } }
    }

    private var dates: String {
        let start = ProgressDate.date(end, zone: zone).map { ProgressDate.label($0.addingTimeInterval(Double(1 - range.days) * 86_400), zone: zone) } ?? end
        return "\(DiaryWeek.format(start, start.prefix(4) == end.prefix(4) ? "MMM d" : "MMM d, yyyy")) – \(DiaryWeek.format(end, "MMM d, yyyy"))"
    }

    private func shift(_ days: Int) -> String {
        ProgressDate.date(end, zone: zone).map { ProgressDate.label($0.addingTimeInterval(Double(days) * 86_400), zone: zone) } ?? end
    }

    private func load() async {
        guard let owner = model.selection else { return }
        let key = end
        loadError = nil
        do {
            let progress = try await DiaryProgressView.loadProgress(model: model, endingOn: key, days: ProgressSnapshot.loadDays(range))
            let older = try await model.store.hasDays(before: ProgressSnapshot.rangeStart(progress, range), expectedProfileID: owner.identity.profileID)
            let top = foodLimit > 0 ? try await model.store.topFoods(from: ProgressSnapshot.rangeStart(progress, range), through: progress.endLocalDate, limit: foodLimit, expectedProfileID: owner.identity.profileID) : []
            guard !Task.isCancelled, model.selection == owner, key == end else { return }
            snapshot = ProgressSnapshot(progress: progress, range: range, zone: zone, today: today); foods = top
            loadedEnd = key; hasEarlier = older
        } catch {
            guard !Task.isCancelled, key == end else { return }
            loadError = "Could not load this range. Your diary is preserved."
        }
    }
}

/// One row per day or bucket under a detail chart.
struct ProgressDayRow: View {
    let title: String
    let value: String
    var band: ProgressBand?
    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 3).fill(band?.color ?? Color.diaryRule.opacity(0.6)).frame(width: 10, height: 10)
                .accessibilityHidden(true)
            Text(title).foregroundStyle(Color.diaryText)
            Spacer()
            Text(value).monospacedDigit().foregroundStyle(Color.diarySecondary)
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
        .accessibilityValue(band?.title ?? "")
    }
}

extension ProgressSnapshot {
    func dayTitle(_ day: DailyProgress) -> String { DiaryWeek.format(day.localDate, "EEE d MMM") }
    func band(_ day: DailyProgress) -> ProgressBand? { ProgressInsights.band(day) }
}

@MainActor enum ProgressDetails {
    static func calories(_ snapshot: ProgressSnapshot) -> some View {
        Group {
            Section { ProgressCaloriesCard(snapshot: snapshot).listCardRow() }
            Section("Days") {
                ForEach(snapshot.days.reversed(), id: \.localDate) { day in
                    ProgressDayRow(title: snapshot.dayTitle(day), value: ProgressInsights.plainResult(day), band: snapshot.band(day))
                }
            }
        }
    }

    /// Three plain lines: what you eat on an average complete day against each goal.
    static func macros(_ snapshot: ProgressSnapshot) -> some View {
        Group {
            Section { ProgressMacrosCard(snapshot: snapshot).listCardRow() }
            Section {
                let goal = snapshot.goal?.targets, average = snapshot.averages
                ForEach([("Protein", average.protein, goal?.protein), ("Carbs", average.carbs, goal?.carbs), ("Fat", average.fat, goal?.fat)], id: \.0) { name, value, target in
                    ProgressDayRow(title: name, value: ProgressInsights.plainMacro(value, goal: target))
                }
            } footer: {
                Text("Averages use complete days only.")
            }
        }
    }

    static func calendar(_ snapshot: ProgressSnapshot) -> some View {
        Section {
            ForEach(ProgressInsights.calendarRows(snapshot.days, range: snapshot.range, zone: snapshot.zone)) { row in
                ProgressCalendarRow(row: row)
            }
        } footer: {
            Text("Teal: near your target. Orange: further off. Grey: logged, not judged yet. Empty: no log.")
        }
    }

    static func burn(_ snapshot: ProgressSnapshot) -> some View {
        Group {
            Section { ProgressBurnCard(snapshot: snapshot).listCardRow() }
            Section("How it's worked out") {
                let complete = snapshot.loadedDays.filter { $0.status == .closed }.compactMap { $0.foodTotals?.kcal }
                LabeledContent("Complete days", value: complete.count.formatted())
                LabeledContent("Average intake", value: complete.isEmpty ? "—" : kcal(complete.reduce(0, +) / Double(complete.count)))
                LabeledContent("Weigh-ins", value: snapshot.loadedTrend.count.formatted())
                if let slope = ProgressInsights.slopePerDay(snapshot.loadedTrend) {
                    LabeledContent("Weight change", value: "\((slope * 7).formatted(.number.precision(.fractionLength(2)))) kg a week")
                }
                Text("Each kilogram of body weight stores about 7,700 kcal. Burn = average intake minus the energy your trend stored or released per day.")
                    .font(.footnote).foregroundStyle(Color.diarySecondary)
            }
        }
    }

    static func foods(_ foods: [TopFood]) -> some View {
        Section {
            if foods.isEmpty { ProgressPlaceholder(symbol: "fork.knife", text: "No saved foods with known calories in this range.") }
            ForEach(Array(foods.enumerated()), id: \.offset) { _, food in
                ProgressDayRow(title: food.name, value: "\(food.count == 1 ? "once" : "\(food.count) times") · \(kcal(food.kcal))")
            }
        } footer: {
            Text("Foods with unknown calories and meals still being analyzed are left out.")
        }
    }
}

/// A week (Week, Month) as seven dots, or a month (3M, Year) as a share of days logged.
struct ProgressCalendarRow: View {
    let row: ProgressCalendarRowData
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(row.title).foregroundStyle(Color.diaryText)
                Spacer()
                Text("\(row.logged) of \(row.total) logged").monospacedDigit().foregroundStyle(Color.diarySecondary)
            }
            if let dots = row.dots {
                HStack(spacing: 6) {
                    ForEach(dots.indices, id: \.self) { index in
                        switch dots[index] {
                        case .outside: Color.clear.frame(width: 18, height: 18)
                        case .noLog: Circle().strokeBorder(Color.diaryRule, style: StrokeStyle(lineWidth: 1, dash: [2, 2])).frame(width: 18, height: 18)
                        case let .logged(band): Circle().fill(band?.color ?? Color.diarySecondary.opacity(0.45)).frame(width: 18, height: 18)
                        }
                    }
                }
            } else {
                ProgressView(value: Double(row.logged), total: Double(max(row.total, 1))).tint(Color.diaryAccent)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
