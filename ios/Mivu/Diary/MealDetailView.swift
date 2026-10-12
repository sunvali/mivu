import SwiftUI

struct MealDetailView: View {
    @Bindable var model: DiaryViewModel
    let mealID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var showCorrection = false
    @State private var editedItem: FoodItem?
    @State private var editingRevision: Int?
    @State private var editingSubmissionID: UUID?
    @State private var showDelete = false
    @State private var showMove = false
    @State private var selectedPhoto: UUID?
    var body: some View {
        Group {
            if let meal = model.meal(mealID), let snapshot = model.snapshot {
                List {
                    Section {
                        Label(meal.state.title, systemImage: meal.state == .saved ? "checkmark.circle" : "clock")
                        Text(meal.eatenAt, format: .dateTime.day().month().hour().minute())
                        Text("Apple sample estimate — not food recognition").font(.caption).foregroundStyle(Color.diarySecondary)
                        if meal.isSaved { NutritionSummary(totals: meal.totals) }
                    }
                    if let review = meal.submissions.last(where: { $0.state == .awaitingReview }), let proposal = review.proposal {
                        Section("Review estimate") {
                            Text("This proposal does not count in totals until you save it.").font(.caption).foregroundStyle(Color.diarySecondary)
                            ForEach(proposal.items, id: \.id) { item in itemRow(item, editable: true, reviewSubmissionID: review.id) }
                            Button("Save reviewed meal") { Task { await model.change { try await model.store.acceptReview(mealID: meal.id, submissionID: review.id, expectedProfileID: snapshot.profile.id) } } }.frame(minHeight: 44).accessibilityIdentifier("acceptReview")
                        }
                    }
                    Section("Food items") {
                        if meal.items.isEmpty { Text("No saved items yet").foregroundStyle(Color.diarySecondary) }
                        ForEach(meal.items, id: \.id) { item in itemRow(item, editable: true) }
                    }
                    if !meal.photos.isEmpty {
                        Section("Attached photos") {
                            ForEach(meal.photos, id: \.id) { photo in
                                VStack(alignment: .leading) {
                                    if let image = UIImage(data: photo.data) { Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 240).clipShape(RoundedRectangle(cornerRadius: 12)).accessibilityLabel("Meal photo") }
                                    Text(photo.role == .before ? "Before eating" : photo.role == .after ? "After eating" : "Unspecified").font(.caption).foregroundStyle(Color.diarySecondary)
                                    Button("Delete photo", role: .destructive) { selectedPhoto = photo.id }.frame(minHeight: 44)
                                }
                            }
                        }
                    }
                    Section("Update this meal") {
                        Button("Add message or photo") { showCorrection = true }.frame(minHeight: 44).accessibilityIdentifier("correctMeal")
                        Button("I ate half") { Task { if await model.change({ _ = try await model.store.correctMeal(mealID: mealID, text: "half", expectedProfileID: snapshot.profile.id) }) { model.resumeWorker() } } }.frame(minHeight: 44).disabled(!meal.isSaved || meal.state != .saved).accessibilityIdentifier("halfPortion")
                        Button("Move to another day") { showMove = true }.frame(minHeight: 44)
                        if meal.state == .needsRetry || meal.state == .captured { Button("Retry sample estimate") { model.resumeWorker() }.frame(minHeight: 44) }
                        Button("Delete meal", role: .destructive) { showDelete = true }.frame(minHeight: 44).accessibilityIdentifier("deleteMeal")
                    }
                    Section("Record history") {
                        ForEach(meal.submissions, id: \.id) { submission in
                            VStack(alignment: .leading, spacing: 4) {
                                if !submission.text.isEmpty { Text(submission.text) }
                                Text(submission.state.title).font(.caption).foregroundStyle(Color.diarySecondary)
                            }
                        }
                    }
                }
            } else { ContentUnavailableView("Meal unavailable", systemImage: "fork.knife", description: Text("It may have been deleted or belong to another profile.")) }
        }
        .scrollContentBackground(.hidden).background(Color.diaryCanvas)
        .navigationTitle("Meal")
        .sheet(isPresented: $showCorrection) { MealComposerView(model: model, correctingMealID: mealID) }
        .sheet(item: $editedItem) { item in FoodItemEditor(item: item) { updated in
            guard let owner = model.snapshot?.profile.id else { return false }
            return await model.change { try await model.store.editItem(mealID: mealID, item: updated, reviewSubmissionID: editingSubmissionID, expectedRevision: editingRevision, expectedProfileID: owner) }
        } }
        .confirmationDialog("Delete this meal and its photos?", isPresented: $showDelete, titleVisibility: .visible) {
            Button("Delete meal", role: .destructive) { guard let owner = model.snapshot?.profile.id else { return }; Task { if await model.change({ try await model.store.deleteMeal(mealID, expectedProfileID: owner) }) { dismiss() } } }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete this photo?", isPresented: Binding(get: { selectedPhoto != nil }, set: { if !$0 { selectedPhoto = nil } }), titleVisibility: .visible) {
            Button("Delete photo", role: .destructive) { guard let owner = model.snapshot?.profile.id, let id = selectedPhoto else { return }; Task { await model.change { try await model.store.deletePhoto(mealID: mealID, photoID: id, expectedProfileID: owner) }; selectedPhoto = nil } }
            Button("Cancel", role: .cancel) { selectedPhoto = nil }
        }
        .confirmationDialog("Move to another day", isPresented: $showMove, titleVisibility: .visible) {
            if let snapshot = model.snapshot {
                ForEach(snapshot.days, id: \.id) { day in Button(day.localDate) { Task { await model.change { try await model.store.moveMeal(mealID, to: day.id, expectedProfileID: snapshot.profile.id) } } } }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
    private func itemRow(_ item: FoodItem, editable: Bool, reviewSubmissionID: UUID? = nil) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(item.provenance == .sample ? String(localized: "Apple (sample)") : item.name).font(.headline)
            Text("\(item.quantity.formatted()) \(item.unit)").foregroundStyle(Color.diarySecondary)
            Text(item.provenance == .user ? "Edited by you" : "Synthetic apple estimate").font(.caption).foregroundStyle(Color.diarySecondary)
            if item.uncertain { Text("Portion or nutrients are uncertain").font(.caption).foregroundStyle(Color.diarySecondary) }
            if editable { Button("Edit item") { editingRevision = model.meal(mealID)?.revision; editingSubmissionID = reviewSubmissionID; editedItem = item }.frame(minHeight: 44).accessibilityIdentifier("editItem") }
        }
    }
}


private struct FoodItemEditor: View {
    let item: FoodItem
    let save: (FoodItem) async -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var quantity: String
    @State private var unit: String
    @State private var kcal: String
    @State private var carbs: String
    @State private var protein: String
    @State private var fat: String
    @State private var saving = false
    init(item: FoodItem, save: @escaping (FoodItem) async -> Bool) {
        self.item = item; self.save = save
        _name = State(initialValue: item.name); _quantity = State(initialValue: String(item.quantity)); _unit = State(initialValue: item.unit)
        _kcal = State(initialValue: item.nutrition.kcal.map { String($0) } ?? "")
        _carbs = State(initialValue: item.nutrition.carbs.map { String($0) } ?? "")
        _protein = State(initialValue: item.nutrition.protein.map { String($0) } ?? "")
        _fat = State(initialValue: item.nutrition.fat.map { String($0) } ?? "")
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Item") { TextField("Name", text: $name); TextField("Quantity", text: $quantity).keyboardType(.decimalPad).accessibilityIdentifier("itemQuantity"); TextField("Unit", text: $unit) }
                Section("Consumed nutrients") {
                    TextField("Calories (kcal)", text: $kcal).keyboardType(.decimalPad).accessibilityIdentifier("itemCalories")
                    TextField("Carbs (g)", text: $carbs).keyboardType(.decimalPad)
                    TextField("Protein (g)", text: $protein).keyboardType(.decimalPad)
                    TextField("Fat (g)", text: $fat).keyboardType(.decimalPad)
                    Text("Leave unknown values blank. Changing only quantity scales the recorded nutrients.").font(.caption).foregroundStyle(Color.diarySecondary)
                }
            }.navigationTitle("Edit item")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) { Button("Save") {
                    guard var updated = edited else { return }
                    updated.provenance = .user
                    Task { saving = true; defer { saving = false }; if await save(updated) { dismiss() } }
                }.disabled(edited == nil || saving).accessibilityIdentifier("saveItem") }
            }
        }
    }
    private func number(_ text: String) -> Double? { Double(text.replacingOccurrences(of: ",", with: ".")) }
    private var edited: FoodItem? {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !unit.isEmpty, let amount = number(quantity), amount >= 0, amount.isFinite else { return nil }
        let inputs = [kcal, carbs, protein, fat]
        guard inputs.allSatisfy({ $0.isEmpty || number($0).map { $0 >= 0 && $0.isFinite && $0 <= 100_000 } == true }) else { return nil }
        var updated = item
        updated.name = name; updated.quantity = amount; updated.unit = unit
        let values = inputs.map(number)
        updated.nutrition = NutritionValues(kcal: values[0], carbs: values[1], protein: values[2], fat: values[3])
        return updated
    }
}
