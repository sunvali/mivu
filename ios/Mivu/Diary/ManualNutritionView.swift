import SwiftUI

struct ManualNutritionDraft: Equatable {
    var itemID = UUID()
    var mealID = UUID()
    var submissionID = UUID()
    var name = ""
    var quantity = "100"
    /// A canonical unit key such as "g"; screens show it with `FoodItem.shownUnit`.
    var unit = "g"
    var kcal = ""
    var carbs = ""
    var protein = ""
    var fat = ""
    /// Nutrients per one unit; amount changes scale from here so dragging never compounds rounding.
    private var perUnit: [Double?] = [nil, nil, nil, nil]
    /// The recent food the values were copied from; each value keeps its source until it is edited.
    private var origin: FoodItem?
    private var fromOrigin: Set<Int> = []
    /// The amount the nutrient texts currently hold for; it stays put while the amount field is mid-edit.
    private var basisAmount: Double? = 100

    private(set) var frozenPayload: ManualNutritionPayload?
    static let units = ["g", "ml", "serving", "piece"]
    private static let keys = ["kcal", "carbs", "protein", "fat"]
    private static var fields: [WritableKeyPath<Self, String>] { [\.kcal, \.carbs, \.protein, \.fat] }
    var usesRecentFood: Bool { origin != nil }
    var isDirty: Bool { !name.isEmpty || quantity != "100" || unit != "g" || ![kcal, carbs, protein, fat].allSatisfy(\.isEmpty) }
    var amount: Double? { Self.number(quantity).flatMap { $0 > 0 && $0.isFinite ? $0 : nil } }

    static func number(_ text: String) -> Double? { Double(text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")) }
    private static func text(_ value: Double, digits: Int) -> String { value.formatted(.number.precision(.fractionLength(0...digits)).grouping(.never)) }
    /// Energy shows whole kcal and macros one decimal, so scaled values stay readable.
    private static func shown(_ value: Double, field: Int) -> String { text(value, digits: field == 0 ? 0 : 1) }
    private func scaled(_ field: Int, at amount: Double?) -> String? { amount.flatMap { a in perUnit[field].map { Self.shown($0 * a, field: field) } } }

    /// A typed value holds for the amount it was typed at, so re-base any value that no longer matches.
    private mutating func syncBasis() {
        guard let basisAmount else { return }
        for (i, field) in Self.fields.enumerated() where scaled(i, at: basisAmount) != self[keyPath: field] {
            perUnit[i] = Self.number(self[keyPath: field]).map { $0 / basisAmount }; fromOrigin.remove(i)
        }
    }
    mutating func setAmount(_ text: String) {
        syncBasis(); quantity = text
        guard let amount else { return }
        for (i, field) in Self.fields.enumerated() { if let value = scaled(i, at: amount) { self[keyPath: field] = value } }
        basisAmount = amount
    }
    /// Grams can't become pieces without knowing the food, so totals stay and the new amount becomes the base.
    mutating func setUnit(_ newUnit: String) {
        syncBasis(); let old = basisAmount
        unit = newUnit; quantity = ["g", "ml"].contains(newUnit) ? "100" : "1"; basisAmount = amount
        guard let old, let amount else { return }
        perUnit = perUnit.map { $0.map { $0 * old / amount } }
    }
    mutating func use(_ food: FoodItem) {
        name = food.name; unit = food.unit; quantity = Self.text(food.quantity, digits: 2); origin = food; basisAmount = amount
        let values = [food.nutrition.kcal, food.nutrition.carbs, food.nutrition.protein, food.nutrition.fat], base = amount ?? food.quantity
        for (i, field) in Self.fields.enumerated() {
            perUnit[i] = values[i].map { $0 / base }; self[keyPath: field] = values[i].map { Self.shown($0, field: i) } ?? ""
        }
        fromOrigin = Set(values.indices.filter { values[$0] != nil })
    }
    func item() throws -> FoodItem {
        let strings = [kcal, carbs, protein, fat]
        guard let amount, strings.allSatisfy({ $0.isEmpty || Self.number($0).map { $0.isFinite && $0 >= 0 && $0 <= 10_000_000 } == true }),
              strings.contains(where: { !$0.isEmpty }) else { throw DiaryError.invalidData }
        let values = strings.map(Self.number)
        let sources = Dictionary(uniqueKeysWithValues: Self.keys.indices.compactMap { i -> (String, NutritionProvenance)? in
            guard values[i] != nil else { return nil }
            let copied = origin.flatMap { food in fromOrigin.contains(i) && scaled(i, at: basisAmount) == strings[i] ? food.nutrientSources[Self.keys[i]] ?? food.provenance : nil }
            return (Self.keys[i], copied ?? .user)
        })
        let manual = origin == nil || sources.values.allSatisfy { $0 == .user }
        let item = FoodItem(id: itemID, name: name.trimmingCharacters(in: .whitespacesAndNewlines), quantity: amount,
            unit: unit.trimmingCharacters(in: .whitespacesAndNewlines), nutrition: NutritionValues(kcal: values[0], carbs: values[1], protein: values[2], fat: values[3]),
            provenance: manual ? .user : origin!.provenance, reference: manual ? "Entered manually" : origin!.reference,
            uncertain: manual ? false : origin!.uncertain, nutrientSources: sources)
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
    /// Offered above the numbers so describing stays the easy path; nil hides it.
    var askPip: ((String, UUID) async -> Bool)? = nil
    var onSnapIt: (() -> Void)? = nil
    var onSaved: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var draft = ManualNutritionDraft()
    @State private var ownership: DiarySelectionOwnership?
    @State private var saving = false
    @State private var showDiscard = false
    @State private var message: String?
    @State private var reconciledMealID: UUID?
    @State private var recentFoods: [FoodItem] = []
    @State private var chipTaps = 0
    @State private var description = ""
    @State private var askID = UUID()
    @State private var asking = false
    @State private var askFailed = false
    @State private var snapAfterDiscard = false
    @FocusState private var editingField: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            Form {
                if let askPip { describeSection(askPip) }
                Section("Food") {
                    TextField("Food name", text: $draft.name).font(.title2.weight(.semibold)).padding(.vertical, 8)
                        .focused($editingField, equals: "Name").accessibilityIdentifier("manualFoodName")
                    if !recentFoods.isEmpty { recentRow }
                }
                Section {
                    MeasureRuler(title: String(localized: "Amount"), text: Binding(get: { draft.quantity }, set: { draft.setAmount($0) }),
                                 range: rulerRange, step: rulerStep, unit: FoodItem.shownUnit(draft.unit), placeholder: isMass ? 100 : 1,
                                 fieldID: "manualAmount", focus: $editingField, field: "Amount", feedbackEvery: isMass ? 10 : 2)
                        .id(draft.unit) // a fresh ruler per unit, so its marks and number width start clean
                        .padding(.vertical, 8).listRowSeparator(.hidden)
                    Picker("Unit", selection: Binding(get: { draft.unit }, set: { draft.setUnit($0); editingField = nil })) {
                        ForEach(ManualNutritionDraft.units + (ManualNutritionDraft.units.contains(draft.unit) ? [] : [draft.unit]), id: \.self) {
                            Text(FoodItem.shownUnit($0)).tag($0)
                        }
                    }
                    .pickerStyle(.segmented).frame(minHeight: 44).accessibilityLabel(String(localized: "Unit")).accessibilityIdentifier("manualUnit").listRowSeparator(.hidden)
                    presetRow.listRowSeparator(.hidden)
                    if ![draft.kcal, draft.protein, draft.carbs, draft.fat].allSatisfy(\.isEmpty) { liveSummary }
                }
                Section {
                    numberField(String(localized: "Energy (kcal)"), text: $draft.kcal, identifier: "manualCalories")
                    numberField(String(localized: "Protein (g)"), text: $draft.protein, identifier: "manualProtein")
                    numberField(String(localized: "Carbs (g)"), text: $draft.carbs, identifier: "manualCarbs")
                    numberField(String(localized: "Fat (g)"), text: $draft.fat, identifier: "manualFat")
                } header: { Text("Nutrition for this amount") } footer: {
                    if draft.usesRecentFood {
                        Text("Values from your earlier log keep their source until you change them. Leave unknown values blank; zero means a known zero.")
                    } else {
                        Text("Enter at least one nutrient. Leave unknown values blank; zero means a known zero. Saved as entered manually.")
                    }
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
            .disabled(saving || asking)
            .onChange(of: description) { _, _ in askID = UUID(); askFailed = false }
            .scrollContentBackground(.hidden).background(Color.diaryCanvas)
            .scrollDismissesKeyboard(.interactively).foregroundStyle(Color.diaryText).tint(.diaryAccent)
            .navigationTitle(appendingTo == nil ? "Enter nutrition" : "Add food manually").navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(draft.isDirty || !description.isEmpty || saving || asking)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { editingField = nil }.accessibilityIdentifier("doneManualNutrition") }
                ToolbarItem(placement: .cancellationAction) {
                    Button { editingField = nil; if draft.isDirty || !description.isEmpty { showDiscard = true } else { dismiss() } } label: {
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
                Button("Discard changes", role: .destructive) { if snapAfterDiscard { onSnapIt?() } else { dismiss() } }
                Button("Keep editing", role: .cancel) { snapAfterDiscard = false }
            } message: { Text("Your unsaved food and nutrition will be discarded.") }
            .sensoryFeedback(.impact(weight: .light), trigger: chipTaps)
            .sensoryFeedback(.selection, trigger: draft.unit)
            .task {
                if ownership == nil { ownership = model.selection }
                if let token = ownership, recentFoods.isEmpty {
                    recentFoods = (try? await model.store.recentFoods(expectedSelection: token, expectedProfileID: token.identity.profileID)) ?? []
                }
            }
        }
    }
    private var isMass: Bool { ["g", "ml"].contains(draft.unit) }
    private var rulerStep: Double { isMass ? 5 : 0.5 }
    /// The ruler grows to fit a typed amount up to five times its usual end; larger typed amounts still save.
    private var rulerRange: ClosedRange<Double> {
        let top = isMass ? 1000.0 : 10.0
        // Zero keeps labelled marks on round numbers; a zero amount only disables Save.
        return 0...min(top * 5, max(top, ((draft.amount ?? 0) / top).rounded(.up) * top))
    }
    private var recentRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Recent foods", comment: "Label above chips of recently logged foods on the manual food entry screen").font(.footnote.weight(.medium)).foregroundStyle(Color.diarySecondary)
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(recentFoods) { food in
                        let current = food.name == draft.name
                        Button { draft.use(food); editingField = nil; chipTaps += 1 } label: { chip(food.name, selected: current).frame(maxWidth: 220) }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(String(localized: "Recent foods", comment: "Label above chips of recently logged foods on the manual food entry screen")), \(food.name)")
                            .accessibilityAddTraits(current ? .isSelected : [])
                            .accessibilityIdentifier("recentFood")
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .padding(.vertical, 4)
    }
    private var presetRow: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(isMass ? [50, 100, 150, 200, 300] : [0.5, 1, 1.5, 2], id: \.self) { (value: Double) in
                    let label = value == 0.5 ? "½" : value == 1.5 ? "1½" : value.formatted(.number.grouping(.never))
                    Button {
                        draft.setAmount(value.formatted(.number.precision(.fractionLength(0...2)).grouping(.never))); editingField = nil; chipTaps += 1
                    } label: { chip(label, selected: draft.amount == value).monospacedDigit() }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(value.formatted()) \(FoodItem.shownUnit(draft.unit))")
                        .accessibilityAddTraits(draft.amount == value ? .isSelected : [])
                        .accessibilityIdentifier("manualPreset")
                }
            }
        }
        .scrollIndicators(.hidden)
    }
    private func chip(_ text: String, selected: Bool) -> some View {
        Text(text).font(.subheadline.weight(.semibold)).lineLimit(1)
            .padding(.horizontal, 16).frame(minWidth: 44, minHeight: 44)
            .foregroundStyle(selected ? Color.diaryCanvas : Color.diaryAccent)
            .background(Capsule().fill(selected ? Color.diaryAccent : Color.diaryAccent.opacity(0.08)))
            .contentShape(Capsule())
    }
    /// Energy and the macro split follow the ruler live, so the effect of an amount is visible while dragging.
    private var liveSummary: some View {
        let grams = [draft.protein, draft.carbs, draft.fat].map { ManualNutritionDraft.number($0) }
        let energy = [grams[0].map { $0 * 4 }, grams[1].map { $0 * 4 }, grams[2].map { $0 * 9 }].map { $0 ?? 0 }
        let total = energy.reduce(0, +)
        let titles = [String(localized: "Energy (kcal)"), String(localized: "Protein (g)"), String(localized: "Carbs (g)"), String(localized: "Fat (g)")]
        let spoken = zip(titles, [draft.kcal, draft.protein, draft.carbs, draft.fat]).filter { !$1.isEmpty }.map { "\($0) \($1)" }
        return VStack(alignment: .leading, spacing: 8) {
            if !draft.kcal.isEmpty { HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(draft.kcal).font(.largeTitle.weight(.semibold)).fontDesign(.rounded).monospacedDigit()
                    .foregroundStyle(Color.diaryEnergy).contentTransition(reduceMotion ? .identity : .numericText())
                Text("kcal").font(.headline).foregroundStyle(Color.diarySecondary)
            } }
            // The split only adds up when every macro is known; unknown is not zero.
            if total > 0, !grams.contains(nil) {
                Canvas { context, size in
                    var x = 0.0
                    for (part, color) in [(energy[0], Color.diaryProtein), (energy[1], Color.diaryCarbs), (energy[2], Color.diaryFat)] {
                        let width = max(0, size.width * part / total - 2)
                        context.fill(Capsule().path(in: CGRect(x: x, y: 0, width: width, height: size.height)), with: .color(color))
                        x += width + 2
                    }
                }
                .frame(maxWidth: .infinity).frame(height: 8)
            }
            if grams.contains(where: { $0 != nil }) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { legend(grams) }
                    VStack(alignment: .leading, spacing: 2) { legend(grams) }
                }
                .font(.caption.weight(.medium)).monospacedDigit()
            }
        }
        .padding(.vertical, 8)
        .animation(reduceMotion ? nil : .snappy, value: draft.kcal)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.updatesFrequently)
        .accessibilityLabel(spoken.isEmpty ? String(localized: "Unknown") : spoken.joined(separator: ", "))
        .accessibilityIdentifier("manualLiveSummary")
    }
    @ViewBuilder private func legend(_ grams: [Double?]) -> some View {
        let text = { (value: Double) in String(localized: "\(value.formatted(.number.precision(.fractionLength(0...1)))) g") }
        let dot = { (color: Color) in Circle().fill(color).frame(width: 8, height: 8) }
        if let protein = grams[0] { HStack(spacing: 4) { dot(.diaryProtein); Text("Protein \(text(protein))") } }
        if let carbs = grams[1] { HStack(spacing: 4) { dot(.diaryCarbs); Text("Carbs \(text(carbs))") } }
        if let fat = grams[2] { HStack(spacing: 4) { dot(.diaryFat); Text("Fat \(text(fat))") } }
    }
    private var trimmedDescription: String { description.trimmingCharacters(in: .whitespacesAndNewlines) }
    private func describeSection(_ askPip: @escaping (String, UUID) async -> Bool) -> some View {
        // At accessibility sizes the two buttons stack so their labels never break mid-word.
        let row = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout())
        return Section {
            TextField("2 eggs and toast", text: $description, axis: .vertical).lineLimit(1...4)
                .focused($editingField, equals: "Describe").frame(minHeight: 44).accessibilityLabel("Describe what you ate")
                .accessibilityIdentifier("manualDescribe")
            row {
                if let onSnapIt {
                    Button("Photo", systemImage: "camera") {
                        if draft.isDirty || !description.isEmpty { snapAfterDiscard = true; showDiscard = true } else { onSnapIt() }
                    }
                    .buttonStyle(.borderless).foregroundStyle(Color.diaryAccent)
                    .frame(minHeight: 44).accessibilityHint("Closes this form and opens Snap It.").accessibilityIdentifier("manualSnapIt")
                }
                Spacer(minLength: 0)
                Button {
                    Task {
                        asking = true; askFailed = false
                        if await askPip(trimmedDescription, askID) { dismiss() } else { askFailed = true }
                        asking = false
                    }
                } label: { Label("Ask Pip", systemImage: "sparkles").foregroundStyle(Color.diaryActionText) }
                    .buttonStyle(.borderedProminent).controlSize(.large).disabled(trimmedDescription.isEmpty || asking)
                    .accessibilityIdentifier("manualAskPip")
            }
            .accessibilityElement(children: .contain)
            if askFailed {
                Label("Could not send to Pip. Your text is still here.", systemImage: "exclamationmark.circle").foregroundStyle(Color.diaryError)
            }
        } header: { Text("Easier: just describe it") } footer: { Text("Pip works out the nutrition. Know the exact numbers? Type them below.") }
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
                    message = String(localized: "Your earlier food was saved. These changed values have not been saved.")
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
            } else if model.selection == token, model.manualDayChanged {
                draft.releaseUncommittedIdentity(); message = DiaryError.ambiguousDay.localizedDescription // nothing was saved; the next Save re-resolves the day
            } else if model.selection == token { message = model.errorMessage ?? String(localized: "Could not confirm this save. Retry with the same food to check it safely.") }
        } catch DiaryError.ambiguousDay { draft.releaseUncommittedIdentity(); message = DiaryError.ambiguousDay.localizedDescription }
        catch { if model.selection == token { message = error.localizedDescription } }
    }
}
