import SwiftUI

struct ManualNutritionDraft: Equatable {
    var itemID = UUID()
    var mealID = UUID()
    var submissionID = UUID()
    var name = ""
    var quantity = "1"
    var unit = "serving"
    var kcal = ""
    var carbs = ""
    var protein = ""
    var fat = ""

    private(set) var frozenPayload: ManualNutritionPayload?
    var isDirty: Bool { !name.isEmpty || quantity != "1" || unit != "serving" || ![kcal, carbs, protein, fat].allSatisfy(\.isEmpty) }
    func item() throws -> FoodItem {
        func number(_ text: String) -> Double? { Double(text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")) }
        let strings = [kcal, carbs, protein, fat]
        guard let amount = number(quantity), amount > 0,
              strings.allSatisfy({ $0.isEmpty || number($0).map { $0.isFinite && $0 >= 0 && $0 <= 10_000_000 } == true }),
              strings.contains(where: { !$0.isEmpty }) else { throw DiaryError.invalidData }
        let values = strings.map(number)
        let sources = Dictionary(uniqueKeysWithValues: zip(["kcal", "carbs", "protein", "fat"], values).compactMap { key, value in
            value == nil ? nil : (key, NutritionProvenance.user)
        })
        let item = FoodItem(id: itemID, name: name.trimmingCharacters(in: .whitespacesAndNewlines), quantity: amount,
            unit: unit.trimmingCharacters(in: .whitespacesAndNewlines), nutrition: NutritionValues(kcal: values[0], carbs: values[1], protein: values[2], fat: values[3]),
            provenance: .user, reference: "Entered manually", uncertain: false, nutrientSources: sources)
        try validateItems([item]); return item
    }
    mutating func freeze(profileID: UUID, target: ManualNutritionTarget, at: Date, appendingTo meal: MealReadModel?) throws -> ManualNutritionPayload {
        let item = try item()
        if let frozenPayload {
            guard frozenPayload.items == [item] else { throw DiaryError.staleRevision }
            return frozenPayload
        }
        let payload = ManualNutritionPayload(profileID: profileID, mealID: meal?.id ?? mealID, submissionID: submissionID,
            operation: meal == nil ? .create : .append, target: target, capturedAt: at, eatenAt: meal?.eatenAt ?? at,
            timePrecision: meal.map { $0.timePrecision ?? .exact } ?? (target.isRecorded ? .dateOnly : .exact),
            expectedMealRevision: meal?.revision, items: [item])
        try validateManualNutritionPayload(payload); frozenPayload = payload; return payload
    }
    mutating func releaseUncommittedIdentity() {
        frozenPayload = nil; itemID = UUID(); mealID = UUID(); submissionID = UUID()
    }
}

private extension ManualNutritionTarget {
    var isRecorded: Bool { if case .recorded = self { true } else { false } }
}

struct ManualNutritionView: View {
    @Bindable var model: DiaryViewModel
    var target: ManualNutritionTarget? = nil
    var appendingTo: MealReadModel? = nil
    var onSaved: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var draft = ManualNutritionDraft()
    @State private var ownership: DiarySelectionOwnership?
    @State private var saving = false
    @State private var showDiscard = false
    @State private var showDayQuestion = false
    @State private var message: String?
    @State private var reconciledMealID: UUID?
    @FocusState private var editingField: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Food") {
                    TextField("Food name", text: $draft.name).font(.title2.weight(.semibold)).padding(.vertical, 8)
                        .focused($editingField, equals: "Name").accessibilityIdentifier("manualFoodName")
                    numberField("Amount", text: $draft.quantity, identifier: "manualAmount")
                    TextField("Unit", text: $draft.unit).focused($editingField, equals: "Unit").frame(minHeight: 44)
                        .accessibilityIdentifier("manualUnit")
                }
                Section {
                    numberField("Energy (kcal)", text: $draft.kcal, identifier: "manualCalories")
                    numberField("Protein (g)", text: $draft.protein, identifier: "manualProtein")
                    numberField("Carbs (g)", text: $draft.carbs, identifier: "manualCarbs")
                    numberField("Fat (g)", text: $draft.fat, identifier: "manualFat")
                } header: { Text("Nutrition for this amount") } footer: {
                    Text("Enter at least one nutrient. Leave unknown values blank; zero means a known zero. Saved as entered manually.")
                }
                if let target {
                    Section { LabeledContent("Recorded day", value: target.day.localDate)
                        Text(appendingTo == nil ? "Time will be unspecified." : "The meal’s original day and time are kept.")
                            .font(.subheadline).foregroundStyle(Color.diarySecondary)
                    }
                }
                if let mealID = reconciledMealID {
                    Section {
                        NavigationLink { MealDetailView(model: model, mealID: mealID) } label: { Label("View previously saved food", systemImage: "checkmark.circle").frame(minHeight: 44) }
                            .accessibilityIdentifier("reconciledManualFood")
                    }
                }
                if let message { Section { Label(message, systemImage: "exclamationmark.circle").foregroundStyle(Color.diaryError) } }
            }
            .disabled(saving)
            .scrollContentBackground(.hidden).background(Color.diaryCanvas)
            .scrollDismissesKeyboard(.interactively).foregroundStyle(Color.diaryText).tint(.diaryAccent)
            .navigationTitle(appendingTo == nil ? "Enter nutrition" : "Add food manually").navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(draft.isDirty || saving)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { editingField = nil }.accessibilityIdentifier("doneManualNutrition") }
                ToolbarItem(placement: .cancellationAction) {
                    Button { editingField = nil; if draft.isDirty { showDiscard = true } else { dismiss() } } label: {
                        Text("Cancel").frame(minWidth: 44, minHeight: 44)
                    }.disabled(saving).accessibilityIdentifier("cancelManualNutrition")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { Task { await save(choice: .current) } } label: {
                        Text("Save").frame(minWidth: 44, minHeight: 44)
                    }
                        .disabled((try? draft.item()) == nil || saving).accessibilityIdentifier("saveManualNutrition")
                }
            }
            .alert("Discard changes?", isPresented: $showDiscard) {
                Button("Discard changes", role: .destructive) { dismiss() }
                Button("Keep editing", role: .cancel) {}
            } message: { Text("Your unsaved food and nutrition will be discarded.") }
            .confirmationDialog("Which waking day?", isPresented: $showDayQuestion, titleVisibility: .visible) {
                Button("Previous day") { Task { await save(choice: .previous) } }
                Button("New day") { Task { await save(choice: .newCurrent) } }
                Button("Keep editing", role: .cancel) {}
            } message: { Text("Your active day began on an earlier date. A late meal can stay in that day.") }
            .task { if ownership == nil { ownership = model.selection } }
        }
        .environment(\.locale, Locale(identifier: "en")).environment(\.layoutDirection, .leftToRight)
    }
    private func numberField(_ title: String, text: Binding<String>, identifier: String) -> some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) { Text(title); input(title, text: text, identifier: identifier) }.padding(.vertical, 8)
            } else { LabeledContent { input(title, text: text, identifier: identifier) } label: { Text(title) } }
        }.frame(minHeight: 44)
    }
    private func input(_ title: String, text: Binding<String>, identifier: String) -> some View {
        TextField("Unknown", text: text).keyboardType(.decimalPad).monospacedDigit()
            .multilineTextAlignment(typeSize.isAccessibilitySize ? .leading : .trailing)
            .focused($editingField, equals: title).accessibilityLabel(title).accessibilityIdentifier(identifier)
    }
    private func save(choice: ManualNutritionDayChoice) async {
        guard !saving, let token = ownership, model.selection == token, !model.isChangingProfile else { return }
        saving = true; defer { saving = false }; editingField = nil; message = nil
        do {
            if let frozen = draft.frozenPayload, frozen.items != [try draft.item()] {
                if let committed = try await model.store.manualNutritionResult(for: frozen, expectedSelection: token, expectedProfileID: token.identity.profileID) {
                    guard model.selection == token else { return }
                    reconciledMealID = committed.meal.id
                    draft.releaseUncommittedIdentity()
                    message = "Your earlier food was saved. These changed values have not been saved."
                    await model.loadMeal(committed.meal.id)
                    return
                }
                draft.releaseUncommittedIdentity()
            }
            let payload: ManualNutritionPayload
            if let frozen = draft.frozenPayload { payload = frozen }
            else {
                let at = Date()
                let resolved: ManualNutritionTarget
                if let target { resolved = target }
                else {
                    var requested = appendingTo.map { ManualNutritionDayChoice.recorded($0.dayID) } ?? choice
                    if appendingTo == nil, choice == .current,
                       try await model.store.dayAssignment(at: at, expectedSelection: token, expectedProfileID: token.identity.profileID) == .newDay {
                        requested = .newCurrent
                    }
                    resolved = try await model.store.prepareManualNutritionTarget(choice: requested, at: at,
                        expectedSelection: token, expectedProfileID: token.identity.profileID)
                }
                guard model.selection == token else { return }
                payload = try draft.freeze(profileID: token.identity.profileID, target: resolved, at: at, appendingTo: appendingTo)
            }
            if let result = await model.saveManualNutrition(payload, expectedSelection: token), model.selection == token {
                onSaved(result.meal.id); dismiss()
            } else if model.selection == token, model.manualDayChoiceNeeded {
                draft.releaseUncommittedIdentity(); showDayQuestion = true // nothing was saved; re-resolve the day
            } else if model.selection == token { message = model.errorMessage ?? "Could not confirm this save. Retry with the same food to check it safely." }
        } catch DiaryError.ambiguousDay { showDayQuestion = true }
        catch { if model.selection == token { message = error.localizedDescription } }
    }
}
