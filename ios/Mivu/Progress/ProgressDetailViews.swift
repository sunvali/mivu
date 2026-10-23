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
                        .disabled(snapshot.map { $0.bands.isEmpty && $0.trend.isEmpty } ?? true)
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
            if let snapshot {
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
            let progress = try await DiaryProgressView.loadProgress(model: model, endingOn: key, days: range.days)
            let top = foodLimit > 0 ? try await model.store.topFoods(from: progress.startLocalDate, through: progress.endLocalDate, limit: foodLimit, expectedProfileID: owner.identity.profileID) : []
            guard !Task.isCancelled, model.selection == owner, key == end else { return }
            snapshot = ProgressSnapshot(progress: progress, range: range, zone: zone); foods = top
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
    func band(_ day: DailyProgress) -> ProgressBand? { ProgressBand.of(kcal: day.foodTotals?.kcal, target: day.goal?.targets.kcal) }
}

@MainActor enum ProgressDetails {
    static func calories(_ snapshot: ProgressSnapshot) -> some View {
        Group {
            Section { ProgressCaloriesCard(snapshot: snapshot).listCardRow() }
            Section("Days") {
                ForEach(snapshot.days.reversed(), id: \.localDate) { day in
                    ProgressDayRow(title: snapshot.dayTitle(day), value: day.foodTotals?.kcal.map(kcal) ?? "No log", band: snapshot.band(day))
                }
            }
        }
    }

    static func macros(_ snapshot: ProgressSnapshot) -> some View {
        Group {
            Section { ProgressMacrosCard(snapshot: snapshot).listCardRow() }
            Section("Days") {
                ForEach(snapshot.days.reversed().filter { $0.foodTotals?.kcal != nil }, id: \.localDate) { day in
                    let totals = day.foodTotals
                    ProgressDayRow(title: snapshot.dayTitle(day),
                                   value: [("P", totals?.protein), ("C", totals?.carbs), ("F", totals?.fat)]
                                       .map { "\($0.0) \($0.1.map { Int($0.rounded()).formatted() } ?? "—")" }.joined(separator: " · "))
                }
            }
        }
    }

    static func calendar(_ snapshot: ProgressSnapshot, openDiary: @escaping () -> Void) -> some View {
        Group {
            Section { ProgressCalendarCard(snapshot: snapshot, openDiary: openDiary).listCardRow() }
            Section { ProgressBandKey() }
            Section("Days") {
                ForEach(snapshot.days.reversed(), id: \.localDate) { day in
                    ProgressDayRow(title: snapshot.dayTitle(day), value: snapshot.band(day)?.title ?? "No log", band: snapshot.band(day))
                }
            }
        }
    }

    static func burn(_ snapshot: ProgressSnapshot) -> some View {
        Group {
            Section { ProgressBurnCard(snapshot: snapshot).listCardRow() }
            Section("How it's worked out") {
                let complete = snapshot.days.filter { $0.completeness == .complete && !$0.hasPending }.compactMap { $0.foodTotals?.kcal }
                LabeledContent("Complete days", value: complete.count.formatted())
                LabeledContent("Average intake", value: complete.isEmpty ? "—" : kcal(complete.reduce(0, +) / Double(complete.count)))
                LabeledContent("Weigh-ins", value: snapshot.trend.count.formatted())
                if let first = snapshot.trend.first, let last = snapshot.trend.last {
                    LabeledContent("Trend change", value: "\((last.trend - first.trend).formatted(.number.precision(.fractionLength(1)))) kg")
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
                ProgressDayRow(title: food.name, value: "\(kcal(food.kcal)) · \(food.count)×")
            }
        } footer: {
            Text("Foods with unknown calories and meals still being analyzed are left out.")
        }
    }
}
