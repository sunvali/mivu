import SwiftUI

struct MealDetailView: View {
    @Bindable var model: DiaryViewModel
    let mealID: UUID
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openDiaryConnection) private var openConnection
    @State private var showCorrection = false
    @State private var editedItem: FoodItem?
    @State private var editingRevision: Int?
    @State private var editingSubmissionID: UUID?
    private enum Deletion { case meal, photo(UUID) }
    @State private var deletion: Deletion?
    @State private var showMove = false
    @State private var movedDayID: UUID?
    @State private var viewingPhoto: MealPhoto?
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        Group {
            if let meal = model.meal(mealID), let snapshot = model.snapshot {
                List {
                    Section {
                        mealSummary(meal, snapshot: snapshot).listRowBackground(Color.diarySummarySurface)
                    }.listRowBackground(Color.clear)
                    if let review = meal.submissions.last(where: { $0.state == .awaitingReview }), let proposal = review.proposal {
                        Section("Review estimate") {
                            Text("Check the portions before marking this reviewed. This proposal does not count in totals until you save it.")
                                .font(.subheadline).foregroundStyle(Color.diarySecondary)
                            NutritionSummary(totals: nutritionTotals(proposal.items), title: "Estimated totals")
                            ForEach(proposal.items, id: \.id) { item in itemRow(item, editable: true, reviewSubmissionID: review.id) }
                            Button { Task { await model.change { try await model.store.acceptReview(mealID: meal.id, submissionID: review.id, expectedProfileID: snapshot.profile.id) } } } label: {
                                Label("Mark reviewed", systemImage: "checkmark.circle").frame(maxWidth: .infinity, minHeight: 52)
                            }
                            .buttonStyle(.glassProminent).tint(.diaryAccent).foregroundStyle(Color.diaryActionText)
                            .accessibilityIdentifier("acceptReview")
                        }.listRowBackground(Color.diarySurface)
                    }
                    if !meal.photos.isEmpty {
                        Section("Attached photos") {
                            ForEach(meal.photos, id: \.id) { photo in
                                VStack(alignment: .leading, spacing: 8) {
                                    if let image = UIImage(data: photo.data) {
                                        Button { viewingPhoto = photo } label: {
                                            Image(uiImage: image).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: 260)
                                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                        }
                                        .buttonStyle(.plain).accessibilityLabel("Meal photo")
                                        .accessibilityHint("Open full-screen photo viewer").accessibilityIdentifier("viewMealPhoto")
                                    }
                                    HStack {
                                        Text(photo.role == .before ? "Before eating" : photo.role == .after ? "After eating" : "Timing unspecified")
                                            .font(.caption).foregroundStyle(Color.diarySecondary)
                                        Spacer()
                                        Button("Delete photo", role: .destructive) { deletion = .photo(photo.id) }.frame(minHeight: 44)
                                    }
                                }.padding(.vertical, 4)
                            }
                        }.listRowBackground(Color.clear)
                    }
                    Section("Ingredients") {
                        if meal.items.isEmpty { Text("No saved items yet").foregroundStyle(Color.diarySecondary) }
                        ForEach(meal.items, id: \.id) { item in itemRow(item, editable: true) }
                    }.listRowBackground(Color.clear)
                    Section {
                        Button { showCorrection = true } label: {
                            Label("Add note or photo", systemImage: "note.text.badge.plus").frame(minHeight: 44)
                        }.accessibilityIdentifier("correctMeal")
                        if meal.isSaved && meal.state == .saved {
                            Button("I ate half") { Task { if await model.change({ _ = try await model.store.correctMeal(mealID: mealID, text: "half", forCoach: !model.sampleMode, expectedProfileID: snapshot.profile.id) }) { model.resumeWorker() } } }
                                .frame(minHeight: 44).accessibilityIdentifier("halfPortion")
                        }
                    }.listRowBackground(Color.clear)
                    Section {
                        DisclosureGroup {
                            LabeledContent("Captured on this iPhone") {
                                Text(meal.capturedAt, format: .dateTime.day().month().year().hour().minute())
                            }
                            LabeledContent("Current revision", value: meal.revision.formatted()).monospacedDigit()
                            Text("Saved submissions are shown below. Individual change times and before-and-after values are not recorded.")
                                .font(.subheadline).foregroundStyle(Color.diarySecondary)
                            if meal.submissions.isEmpty {
                                Text("No saved submissions.").foregroundStyle(Color.diarySecondary)
                            }
                            ForEach(Array(meal.submissions.enumerated()), id: \.element.id) { index, submission in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Submission \(index + 1)").font(.subheadline.weight(.semibold))
                                    if !submission.text.isEmpty { Text(submission.text) }
                                    LabeledContent("Based on revision", value: submission.baseRevision.formatted()).monospacedDigit()
                                    Text(submission.state.title).font(.subheadline).foregroundStyle(submission.state.color)
                                    if let proposal = submission.proposal {
                                        DisclosureGroup("Stored proposal") {
                                            ForEach(proposal.items) { item in
                                                VStack(alignment: .leading, spacing: 4) {
                                                    Text(item.name).font(.subheadline.weight(.medium))
                                                    Text("\(item.quantity.formatted()) \(item.unit)").font(.subheadline).monospacedDigit()
                                                    Text(item.provenance.description).font(.caption).foregroundStyle(Color.diarySecondary)
                                                }.padding(.vertical, 4)
                                            }
                                        }
                                    }
                                }.padding(.vertical, 8)
                            }
                        } label: {
                            Label("Record history", systemImage: "clock.arrow.circlepath").frame(minHeight: 44)
                        }
                    }.listRowBackground(Color.clear)
                    if let message = model.errorMessage {
                        Section { Label(LocalizedStringKey(message), systemImage: "exclamationmark.circle").foregroundStyle(Color.diaryError) }
                            .listRowBackground(Color.clear)
                    }
                }
                .listStyle(.plain)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button("Add note or photo", systemImage: "note.text.badge.plus") { showCorrection = true }
                            Button("Move to another day", systemImage: "calendar") { showMove = true }
                            if meal.state == .needsRetry || meal.state == .captured {
                                Button("Retry analysis", systemImage: "arrow.clockwise") { if model.sampleMode { model.resumeWorker() } else { model.retryCoachMeal?(mealID) } }
                            }
                            Divider()
                            Button("Delete meal", systemImage: "trash", role: .destructive) { deletion = .meal }.accessibilityIdentifier("deleteMeal")
                        } label: { Label("Meal actions", systemImage: "ellipsis") }
                    }
                }
            } else { ContentUnavailableView("Meal unavailable", systemImage: "fork.knife", description: Text("It may have been deleted or belong to another profile.")) }
        }
        .scrollContentBackground(.hidden).background(Color.diaryCanvas)
        .foregroundStyle(Color.diaryText).tint(.diaryAccent)
        .navigationTitle("Meal")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom) {
            if let movedDayID, let day = model.snapshot?.days.first(where: { $0.id == movedDayID }) {
                NavigationLink { DayHistoryView(model: model, dayID: day.id) } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Moved to \(day.localDate)").font(.subheadline)
                            Text("View day").font(.body.weight(.semibold))
                        }
                    } icon: { Image(systemName: "checkmark.circle") }
                    .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                }
                .buttonStyle(.glass).tint(.diaryAccent).accessibilityIdentifier("movedMealDayReceipt")
                .padding(20).background(Color.diaryCanvas)
            }
        }
        .fullScreenCover(item: $viewingPhoto) { photo in
            MealPhotoViewer(photo: photo) {
                guard let owner = model.snapshot?.profile.id, model.meal(mealID)?.photos.contains(where: { $0.id == photo.id }) == true else { return false }
                return await model.change { try await model.store.deletePhoto(mealID: mealID, photoID: photo.id, expectedProfileID: owner) }
            }
        }
        .onChange(of: model.snapshot?.profile.id) { _, _ in viewingPhoto = nil; movedDayID = nil }
        .sheet(isPresented: $showCorrection) { MealComposerView(model: model, correctingMealID: mealID) }
        .sheet(item: $editedItem) { item in FoodItemEditor(item: item, errorMessage: { model.errorMessage }) { updated in
            guard let owner = model.snapshot?.profile.id else { return false }
            return await model.change { try await model.store.editItem(mealID: mealID, item: updated, reviewSubmissionID: editingSubmissionID, expectedRevision: editingRevision, expectedProfileID: owner) }
        } }
        .alert(deletionTitle, isPresented: Binding(get: { deletion != nil }, set: { if !$0 { deletion = nil } }), presenting: deletion) { target in
            switch target {
            case .meal:
                Button("Delete meal", role: .destructive) {
                    guard let owner = model.snapshot?.profile.id else { return }
                    Task { if await model.change({ try await model.store.deleteMeal(mealID, expectedProfileID: owner) }) { dismiss() } }
                }
            case .photo(let photoID):
                Button("Delete photo", role: .destructive) {
                    guard let owner = model.snapshot?.profile.id else { return }
                    Task { await model.change { try await model.store.deletePhoto(mealID: mealID, photoID: photoID, expectedProfileID: owner) } }
                }
            }
            Button("Cancel", role: .cancel) { deletion = nil }
        } message: { target in
            switch target {
            case .meal: Text("This removes the meal and its attached photos from this diary.")
            case .photo: Text("Only this photo will be removed. The meal and its notes are kept.")
            }
        }
        .sheet(isPresented: $showMove) {
            if let meal = model.meal(mealID), let owner = model.snapshot?.profile.id {
                MoveMealSheet(model: model, meal: meal, ownerID: owner) { movedDayID = $0 }
            }
        }
    }
    private var deletionTitle: String {
        if case .some(.photo(_)) = deletion { return "Delete this photo?" }
        guard let meal = model.meal(mealID), let day = model.snapshot?.days.first(where: { $0.id == meal.dayID }) else { return "Delete meal?" }
        return "Delete “\(displayTitle(meal))” on \(day.localDate)?"
    }
    private func displayTitle(_ meal: DiaryMeal) -> String {
        if let item = meal.items.first { return item.provenance == .sample ? "Apple (sample)" : item.name }
        let note = meal.submissions.first?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return note.isEmpty ? "Meal" : note
    }
    private func mealSummary(_ meal: DiaryMeal, snapshot: DiarySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(displayTitle(meal))
                .font(.title.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
            if meal.timePrecision == .dateOnly {
                Text(snapshot.days.first(where: { $0.id == meal.dayID })?.localDate ?? "Historical meal")
                    .font(.subheadline).foregroundStyle(Color.diarySecondary)
                Text("Time unspecified").font(.subheadline).foregroundStyle(Color.diarySecondary)
            } else {
                Text(meal.eatenAt, format: .dateTime.day().month().hour().minute()).font(.subheadline).foregroundStyle(Color.diarySecondary)
            }
            Label("Saved on this iPhone", systemImage: "checkmark.circle.fill")
                .font(.subheadline).foregroundStyle(Color.diarySuccess)
            if meal.state != .saved {
                Label(meal.state.title, systemImage: meal.state == .needsRetry ? "exclamationmark.circle" : "clock")
                    .font(.subheadline).foregroundStyle(meal.state.color)
            }
            if model.sampleMode { Text("Apple sample estimate — not food recognition").font(.caption).foregroundStyle(Color.diarySecondary) }
            if meal.isSaved { NutritionSummary(totals: meal.totals) }
            else if meal.state != .awaitingReview {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Nutrition").font(.headline)
                    Text("— kcal").font(.largeTitle.weight(.semibold)).monospacedDigit()
                    Text("Not estimated yet").font(.subheadline).foregroundStyle(Color.diarySecondary)
                    Text(meal.state == .cancelled ? "Analysis was cancelled. Your note and photos are kept." : meal.state == .needsRetry ? "Your meal is saved. Retry analysis when you’re ready." : meal.state == .waitingForConnection ? "Connect ChatGPT in Settings to analyze this saved meal." : "Your meal is saved. Analysis will resume when available.")
                        .font(.subheadline).foregroundStyle(Color.diarySecondary)
                }
            }
            if meal.state == .waitingForConnection {
                Button("Open connection settings", systemImage: "link") { openConnection() }
                    .frame(minHeight: 44).buttonStyle(.glass).accessibilityIdentifier("openMealConnection")
            }
        }.padding(.vertical, 12)
    }
    private func itemRow(_ item: FoodItem, editable: Bool, reviewSubmissionID: UUID? = nil) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                editingRevision = model.meal(mealID)?.revision; editingSubmissionID = reviewSubmissionID; editedItem = item
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    if typeSize.isAccessibilitySize {
                        Text(item.provenance == .sample ? "Apple (sample)" : item.name).font(.body.weight(.medium))
                        Text("\(item.quantity.formatted()) \(item.unit)").monospacedDigit().foregroundStyle(Color.diarySecondary)
                    } else {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(item.provenance == .sample ? "Apple (sample)" : item.name).font(.body.weight(.medium))
                            Spacer(minLength: 8)
                            Text("\(item.quantity.formatted()) \(item.unit)").monospacedDigit().foregroundStyle(Color.diarySecondary)
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Color.diarySecondary).accessibilityHidden(true)
                        }
                    }
                    Text(item.provenance.description).font(.caption).foregroundStyle(Color.diarySecondary)
                    if item.uncertain { Text("Portion or nutrients are uncertain").font(.caption).foregroundStyle(Color.diarySecondary) }
                }.frame(maxWidth: .infinity, minHeight: 56, alignment: .leading).contentShape(Rectangle())
            }
            .buttonStyle(.plain).disabled(!editable).accessibilityIdentifier("editItem")
            .accessibilityHint("Edit ingredient amount and nutrition")
            if !item.reference.isEmpty {
                DisclosureGroup("Source details") { Text(item.reference).font(.subheadline).foregroundStyle(Color.diarySecondary).padding(.vertical, 8) }
                    .font(.subheadline).frame(minHeight: 44)
            }
        }.padding(.vertical, 4)
    }

}


private struct MoveMealSheet: View {
    @Bindable var model: DiaryViewModel
    let mealID: UUID
    let onMoved: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var ownerID: UUID
    @State private var originalDayID: UUID
    @State private var originalRevision: Int
    @State private var destination: UUID
    @State private var moving = false
    init(model: DiaryViewModel, meal: DiaryMeal, ownerID: UUID, onMoved: @escaping (UUID) -> Void) {
        self.model = model; mealID = meal.id; self.onMoved = onMoved
        _ownerID = State(initialValue: ownerID)
        _originalDayID = State(initialValue: meal.dayID)
        _originalRevision = State(initialValue: meal.revision)
        _destination = State(initialValue: meal.dayID)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Destination waking day", selection: $destination) {
                        ForEach((model.snapshot?.days ?? []).sorted { $0.startAt > $1.startAt }) { day in
                            Text(day.id == originalDayID ? "\(day.localDate) · Current day" : day.localDate).tag(day.id)
                                .frame(minHeight: 44)
                        }
                    }.pickerStyle(.inline).accessibilityIdentifier("moveMealDestination")
                } footer: {
                    Text("Only this meal will move. The destination changes when you tap Move.")
                }
                if let message = model.errorMessage {
                    Section { Label(LocalizedStringKey(message), systemImage: "exclamationmark.circle").foregroundStyle(Color.diaryError) }
                }
            }
            .disabled(moving)
            .scrollContentBackground(.hidden).background(Color.diaryCanvas).tint(.diaryAccent)
            .navigationTitle("Move meal").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(moving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Move") { Task { await move() } }
                        .disabled(moving || destination == originalDayID || model.snapshot?.profile.id != ownerID)
                        .accessibilityIdentifier("confirmMoveMeal")
                }
            }
            .interactiveDismissDisabled(moving)
            .onChange(of: model.snapshot?.profile.id) { _, id in if id != ownerID { dismiss() } }
        }
    }
    private func move() async {
        guard !moving, destination != originalDayID, model.snapshot?.profile.id == ownerID else { return }
        moving = true
        defer { moving = false }
        let selectedDay = destination
        if await model.change({
            try await model.store.moveMeal(mealID, to: selectedDay, expectedRevision: originalRevision,
                                           expectedDayID: originalDayID, expectedProfileID: ownerID)
        }) { onMoved(selectedDay); dismiss() }
    }
}

private struct FoodItemEditor: View {
    let item: FoodItem
    let save: (FoodItem) async -> Bool
    let errorMessage: () -> String?
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var quantity: String
    @State private var unit: String
    @State private var kcal: String
    @State private var carbs: String
    @State private var protein: String
    @State private var fat: String
    @State private var saving = false
    @State private var showDiscard = false
    @FocusState private var editingField: String?
    @Environment(\.dynamicTypeSize) private var typeSize
    init(item: FoodItem, errorMessage: @escaping () -> String?, save: @escaping (FoodItem) async -> Bool) {
        self.item = item; self.save = save; self.errorMessage = errorMessage
        _name = State(initialValue: item.name); _quantity = State(initialValue: String(item.quantity)); _unit = State(initialValue: item.unit)
        _kcal = State(initialValue: item.nutrition.kcal.map { String($0) } ?? "")
        _carbs = State(initialValue: item.nutrition.carbs.map { String($0) } ?? "")
        _protein = State(initialValue: item.nutrition.protein.map { String($0) } ?? "")
        _fat = State(initialValue: item.nutrition.fat.map { String($0) } ?? "")
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name).focused($editingField, equals: "Name")
                        .font(.title2.weight(.semibold)).padding(.vertical, 8)
                    nutrientField("Amount", text: $quantity, identifier: "itemQuantity")
                    LabeledContent("Unit") { TextField("Unit", text: $unit).multilineTextAlignment(.trailing).focused($editingField, equals: "Unit") }
                } header: { Text("Ingredient") }
                Section {
                    nutrientField("Energy (kcal)", text: $kcal, identifier: "itemCalories")
                    nutrientField("Protein (g)", text: $protein)
                    nutrientField("Carbs (g)", text: $carbs)
                    nutrientField("Fat (g)", text: $fat)
                } header: { Text("Nutrition for this amount") } footer: {
                    Text("Leave unknown values blank. Changing only quantity scales the recorded nutrients. Changes update this meal only.")
                }
                Section("Source") {
                    Text(item.provenance.description).foregroundStyle(Color.diarySecondary)
                    if !item.reference.isEmpty {
                        DisclosureGroup("View source details") { Text(item.reference).font(.subheadline).padding(.vertical, 8) }
                    }
                    if item.uncertain { Label("Portion or nutrients are uncertain", systemImage: "info.circle").font(.subheadline).foregroundStyle(Color.diarySecondary) }
                }
                if let message = errorMessage() {
                    Section { Label(LocalizedStringKey(message), systemImage: "exclamationmark.circle").foregroundStyle(Color.diaryError) }
                }
            }
            .scrollContentBackground(.hidden).background(Color.diaryCanvas)
            .scrollDismissesKeyboard(.interactively)
            .foregroundStyle(Color.diaryText).tint(.diaryAccent)
            .navigationTitle("Edit ingredient").navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(hasChanges || saving)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { editingField = nil } }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        editingField = nil
                        if hasChanges { showDiscard = true } else { dismiss() }
                    }
                    .disabled(saving)
                    .alert("Discard changes?", isPresented: $showDiscard) {
                        Button("Discard changes", role: .destructive) { dismiss() }
                        Button("Keep editing", role: .cancel) {}
                    } message: { Text("The saved ingredient will keep its original values.") }
                }
                ToolbarItem(placement: .confirmationAction) { Button("Save") {
                    guard var updated = edited else { return }
                    updated.provenance = .user
                    Task { saving = true; defer { saving = false }; if await save(updated) { dismiss() } }
                }.disabled(edited == nil || saving).accessibilityIdentifier("saveItem") }
            }
        }
        .environment(\.locale, Locale(identifier: "en"))
        .environment(\.layoutDirection, .leftToRight)
    }
    private var hasChanges: Bool {
        name != item.name || quantity != String(item.quantity) || unit != item.unit
            || kcal != (item.nutrition.kcal.map { String($0) } ?? "")
            || carbs != (item.nutrition.carbs.map { String($0) } ?? "")
            || protein != (item.nutrition.protein.map { String($0) } ?? "")
            || fat != (item.nutrition.fat.map { String($0) } ?? "")
    }
    private func nutrientField(_ title: String, text: Binding<String>, identifier: String = "") -> some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                    numericInput(title, text: text, identifier: identifier)
                }.padding(.vertical, 8)
            } else {
                LabeledContent { numericInput(title, text: text, identifier: identifier) } label: { Text(title) }
            }
        }.frame(minHeight: 44)
    }
    private func numericInput(_ title: String, text: Binding<String>, identifier: String) -> some View {
        TextField("Unknown", text: text).keyboardType(.decimalPad)
            .multilineTextAlignment(typeSize.isAccessibilitySize ? .leading : .trailing)
            .monospacedDigit().focused($editingField, equals: title).accessibilityIdentifier(identifier)
            .accessibilityLabel(title)
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

private struct MealPhotoViewer: View {
    let photo: MealPhoto
    let delete: () async -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var zoom: CGFloat = 1
    @GestureState private var magnification: CGFloat = 1
    @State private var showDelete = false
    @State private var deleting = false
    private var scale: CGFloat { min(5, max(1, zoom * magnification)) }
    private var timing: String { photo.role == .before ? "Before eating" : photo.role == .after ? "After eating" : "Unspecified" }
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if let image = UIImage(data: photo.data) {
                    GeometryReader { geometry in
                        ScrollView([.horizontal, .vertical]) {
                            Image(uiImage: image).resizable().scaledToFit()
                                .frame(width: geometry.size.width * scale, height: geometry.size.height * scale)
                                .accessibilityLabel("Meal photo")
                                .accessibilityValue("Zoom \(Int(scale * 100)) percent")
                        }
                        .accessibilityIdentifier("mealPhotoZoom")
                        .simultaneousGesture(MagnifyGesture().updating($magnification) { value, state, _ in state = value.magnification }
                            .onEnded { value in zoom = min(5, max(1, zoom * value.magnification)) })
                        .onTapGesture(count: 2) { zoom = zoom > 1 ? 1 : 2 }
                    }
                } else {
                    ContentUnavailableView("Photo unavailable", systemImage: "photo", description: Text("The saved attachment could not be displayed."))
                }
                VStack(spacing: 8) {
                    Text("Photo timing: \(timing)").font(.subheadline).foregroundStyle(Color.diarySecondary)
                    HStack(spacing: 20) {
                        Button { zoom = max(1, zoom - 1) } label: { Image(systemName: "minus.magnifyingglass").frame(minWidth: 44, minHeight: 44) }
                            .accessibilityLabel("Zoom out").accessibilityIdentifier("zoomOutPhoto").disabled(zoom <= 1)
                        Text("\(Int(scale * 100))%").monospacedDigit().accessibilityIdentifier("photoZoomLevel")
                        Button { zoom = min(5, zoom + 1) } label: { Image(systemName: "plus.magnifyingglass").frame(minWidth: 44, minHeight: 44) }
                            .accessibilityLabel("Zoom in").accessibilityIdentifier("zoomInPhoto").disabled(zoom >= 5)
                    }.buttonStyle(.glass)
                }.padding(.horizontal, 20).padding(.bottom, 12)
            }
            .background(Color.diaryCanvas).foregroundStyle(Color.diaryText).tint(.diaryAccent)
            .navigationTitle("Meal photo").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() }.disabled(deleting).accessibilityIdentifier("closeMealPhoto") }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Delete photo", systemImage: "trash", role: .destructive) { showDelete = true }
                        .disabled(deleting).accessibilityIdentifier("deleteViewedPhoto")
                }
            }
            .alert("Delete this photo?", isPresented: $showDelete) {
                Button("Delete photo", role: .destructive) {
                    Task { deleting = true; defer { deleting = false }; if await delete() { dismiss() } }
                }
                Button("Cancel", role: .cancel) {}
            } message: { Text("Only this photo will be removed. The meal and its notes are kept.") }
            .interactiveDismissDisabled(deleting)
        }
    }
}
