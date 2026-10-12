import SwiftUI

struct HistoryView: View {
    @Bindable var model: DiaryViewModel
    var body: some View {
        List {
            if let snapshot = model.snapshot {
                Section {
                    NavigationLink {
                        DiaryProgressView(model: model)
                    } label: {
                        Label("Progress", systemImage: "chart.xyaxis.line")
                            .frame(minHeight: 44, alignment: .leading)
                    }
                    .accessibilityIdentifier("openProgress")
                }
                Section("Coverage") {
                    ForEach(DayCompleteness.allCases, id: \.self) { status in
                        HStack { Text(status.title); Spacer(); Text(snapshot.days.filter { $0.completeness == status }.count.formatted()) }
                    }
                    Text("Complete days and partial records are kept separate. Missing logs do not mean zero intake.").font(.caption).foregroundStyle(Color.diarySecondary)
                }
                Section("Tracking days") {
                    if snapshot.days.isEmpty { Text("No tracking days yet").foregroundStyle(Color.diarySecondary) }
                    ForEach(snapshot.days.sorted { $0.startAt > $1.startAt }, id: \.id) { day in
                        NavigationLink(value: HistoryRoute.day(day.id)) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(day.localDate).font(.headline)
                                Text(day.completeness.title).font(.caption).foregroundStyle(Color.diarySecondary)
                                if let weight = snapshot.weights.first(where: { $0.dayID == day.id }) { Text("\(weight.value.formatted()) \(weight.unit)").font(.caption) }
                            }.frame(minHeight: 52)
                        }
                    }
                }
            } else { Text("Choose a private local profile in Settings to open your diary.").foregroundStyle(Color.diarySecondary) }
        }.scrollContentBackground(.hidden).background(Color.diaryCanvas)
        .navigationDestination(for: HistoryRoute.self) { route in
            switch route {
            case .day(let id): DayHistoryView(model: model, dayID: id)
            case .meal(let id): MealDetailView(model: model, mealID: id)
            }
        }
        .navigationTitle("History")
    }
}

private struct DayHistoryView: View {
    @Bindable var model: DiaryViewModel
    let dayID: UUID
    var body: some View {
        List {
            if let snapshot = model.snapshot, let day = snapshot.days.first(where: { $0.id == dayID }) {
                Section { NutritionSummary(totals: snapshot.totals(dayID: dayID)) }
                Section("Day coverage") {
                    Picker("Completeness", selection: Binding(get: { day.completeness }, set: { value in Task { await model.change { try await model.store.setCompleteness(dayID: dayID, value, expectedProfileID: snapshot.profile.id) } } })) {
                        ForEach(DayCompleteness.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    if let weight = snapshot.weights.first(where: { $0.dayID == dayID }) { Text("\(weight.value.formatted()) \(weight.unit)") }
                }
                Section("Meals") {
                    ForEach(snapshot.meals.filter { $0.dayID == dayID }.sorted { $0.eatenAt > $1.eatenAt }, id: \.id) { meal in NavigationLink(value: HistoryRoute.meal(meal.id)) { MealRow(meal: meal) } }
                }
            }
        }.scrollContentBackground(.hidden).background(Color.diaryCanvas).navigationTitle(model.snapshot?.days.first { $0.id == dayID }?.localDate ?? "History")
    }
}

private enum HistoryRoute: Hashable { case day(UUID), meal(UUID) }
