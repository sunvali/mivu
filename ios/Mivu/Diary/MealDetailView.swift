import SwiftUI

struct MealDetailView: View {
    @Bindable var model: DiaryViewModel
    let mealID: UUID
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openDiaryCoach) private var openChat
    @Environment(ChatGPTConnection.self) private var connection: ChatGPTConnection?
    @State private var showCorrection = false
    @State private var showManualNutrition = false
    @State private var editedItem: FoodItem?
    @State private var editingRevision: Int?
    @State private var editingSubmissionID: UUID?
    private enum Deletion { case meal, photo(UUID), food(FoodItem, revision: Int) }
    @State private var deletion: Deletion?
    @State private var showMove = false
    @State private var showScale = false
    @State private var movedDayID: UUID?
    @State private var viewingPhoto: DiaryPhotoReference?
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        Group {
            if let meal = model.meal(mealID), let snapshot = model.readModel {
                List {
                    if let photo = meal.photos.first {
                        Section {
                            Button { viewingPhoto = photo } label: {
                                DiaryPhotoPreview(model: model, reference: photo, height: 240)
                                    .clipShape(RoundedRectangle(cornerRadius: 24))
                            }
                            .buttonStyle(.plain).accessibilityLabel("Meal photo")
                            .accessibilityHint("Open full-screen photo viewer").accessibilityIdentifier("viewMealPhoto")
                            .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 0, trailing: 20))
                            .listRowSeparator(.hidden).listRowBackground(Color.clear)
                        }
                    }
                    Section { mealSummary(meal, snapshot: snapshot).diarySummaryCard() }
                    if let review = meal.submissions.last(where: { $0.state == .awaitingReview }), let proposal = review.proposal {
                        Section("Review estimate") {
                            Text("Check the portions before marking this reviewed. This proposal does not count in totals until you save it.")
                                .font(.subheadline).foregroundStyle(Color.diarySecondary)
                            NutritionSummary(totals: nutritionTotals(proposal.items), title: "Estimated totals")
                            ForEach(proposal.items, id: \.id) { item in itemRow(item, editable: true, reviewSubmissionID: review.id) }
                        }.listRowBackground(Color.diarySurface)
                    }
                    if meal.photos.count > 1 {
                        Section("Attached photos") {
                            ForEach(meal.photos, id: \.id) { photo in
                                VStack(alignment: .leading, spacing: 8) {
                                    Button { viewingPhoto = photo } label: {
                                        DiaryPhotoPreview(model: model, reference: photo)
                                    }.buttonStyle(.plain).accessibilityLabel("Meal photo")
                                        .accessibilityHint("Open full-screen photo viewer").accessibilityIdentifier("viewMealPhoto")
                                    HStack {
                                        Text(photo.role == .before ? "Before eating" : photo.role == .after ? "After eating" : "Timing unspecified")
                                            .font(.caption).foregroundStyle(Color.diarySecondary)
                                        Spacer()
                                        Button("Delete photo", role: .destructive) { deletion = .photo(photo.photoID) }.frame(minHeight: 44)
                                    }
                                }.padding(.vertical, 4)
                            }
                        }.listRowBackground(Color.clear)
                    }
                    Section {
                        if meal.items.isEmpty { Text("No saved items yet").foregroundStyle(Color.diarySecondary).listRowBackground(Color.clear) }
                        ForEach(meal.items, id: \.id) { item in
                            foodRow(item, meal: meal)
                                .diarySummaryCard()
                                .swipeActions(edge: .trailing) {
                                    if meal.items.count > 1 && meal.state == .saved {
                                        Button("Delete", systemImage: "trash", role: .destructive) { deletion = .food(item, revision: meal.revision) }
                                    }
                                }
                                .swipeActions(edge: .leading) {
                                    Button("Ask Pip", systemImage: "sparkles") { askPip(about: item, in: meal) }.tint(.diaryAccent)
                                }
                        }
                    } header: { Text("Foods").font(.title3.weight(.bold)).foregroundStyle(Color.diaryText).textCase(nil) }
                    Section {
                        Button { if model.sampleMode { showCorrection = true } else { askPip(about: nil, in: meal) } } label: {
                            Label("Add note or photo", systemImage: "note.text.badge.plus").frame(minHeight: 44)
                        }.accessibilityIdentifier("correctMeal")
                        if meal.isSaved && !meal.hasUnresolvedInput {
                            Button("Add food manually", systemImage: "number") { showManualNutrition = true }
                                .frame(minHeight: 44).accessibilityIdentifier("addFoodManually")
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
                                                    Text(item.sourceCaption).font(.caption).foregroundStyle(Color.diarySecondary)
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
                            Button("Add note or photo", systemImage: "note.text.badge.plus") { if model.sampleMode { showCorrection = true } else { askPip(about: nil, in: meal) } }
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
        .task(id: model.changeGeneration) { await model.loadMeal(mealID) }
        .navigationTitle("Meal")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom) {
            if let meal = model.meal(mealID) {
                VStack(alignment: .leading, spacing: 8) {
                    if let movedDayID, let day = model.day(movedDayID) {
                        // The Diary tab shows the destination day; this only confirms the move.
                        Label("Moved to \(DiaryWeek.format(day.localDate, "EEEE, d MMM"))", systemImage: "checkmark.circle")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(Color.diarySuccess)
                            .frame(minHeight: 44).accessibilityIdentifier("movedMealDayReceipt")
                    }
                    // A pending estimate pins its own primary action; Ask Pip shrinks to an icon beside it.
                    let review = meal.submissions.last(where: { $0.state == .awaitingReview && $0.proposal != nil })
                    HStack(spacing: 12) {
                        if let review, let owner = model.readModel?.profile.id {
                            Button { Task { await model.acceptReview(mealID: meal.id, submissionID: review.id, expectedProfileID: owner) } } label: {
                                Label("Mark reviewed", systemImage: "checkmark.circle").font(.headline).frame(maxWidth: .infinity, minHeight: 52)
                            }
                            .buttonStyle(.glassProminent).tint(.diaryAccent).foregroundStyle(Color.diaryActionText)
                            .accessibilityIdentifier("acceptReview")
                        }
                        Button { askPip(about: nil, in: meal) } label: {
                            Group {
                                if review != nil { Image(systemName: "sparkles").frame(width: 52, height: 52).accessibilityLabel("Ask Pip about this meal") }
                                else { Label("Ask Pip about this meal", systemImage: "sparkles").frame(maxWidth: .infinity, minHeight: 52) }
                            }.font(.headline)
                        }
                        .buttonStyle(.glass).tint(.diaryAccent)
                        .disabled(model.selection == nil || model.isChangingProfile || openChat.origin?.selection != model.selection)
                        // Keeps the identifier Coach navigation tests use for the source-conversation route.
                        .accessibilityIdentifier(meal.sourceTurnID != nil ? "mealSourceChat" : "mealAskPip")
                    }
                }
                .padding(.horizontal, 20).padding(.vertical, 12).background(Color.diaryCanvas)
            }
        }
        .fullScreenCover(item: $viewingPhoto) { photo in
            MealPhotoViewer(model: model, photo: photo) {
                guard let owner = model.readModel?.profile.id, model.meal(mealID)?.photos.contains(where: { $0.id == photo.id }) == true else { return false }
                return await model.change { try await model.store.deletePhoto(mealID: mealID, photoID: photo.photoID, expectedProfileID: owner) }
            }
        }
        .onChange(of: model.readModel?.profile.id) { _, _ in viewingPhoto = nil; movedDayID = nil }
        .sheet(isPresented: $showManualNutrition) {
            if let meal = model.meal(mealID), let day = model.day(meal.dayID) {
                ManualNutritionView(model: model, target: .recorded(dayID: day.id, localDate: day.localDate, timeZoneID: day.timeZoneID), appendingTo: meal) { _ in }
            }
        }
        .sheet(isPresented: $showCorrection) { MealComposerView(model: model, correctingMealID: mealID) }
        .sheet(item: $editedItem) { item in
            let meal = model.meal(mealID)
            let saved = editingSubmissionID == nil && meal?.state == .saved
            let several = (meal?.items.count ?? 0) > 1
            FoodItemEditor(item: item, errorMessage: { model.errorMessage },
                           deleteFood: saved && several ? { await deleteFood(item, revision: editingRevision) } : nil,
                           deleteMeal: saved && !several ? { await deleteMeal() } : nil,
                           askPip: meal.map { meal in { askPip(about: item, in: meal) } }) { updated, explicitNutrients in
            guard let owner = model.readModel?.profile.id else { return false }
            return await model.change { try await model.store.editItem(mealID: mealID, item: updated, explicitNutrients: explicitNutrients, reviewSubmissionID: editingSubmissionID, expectedRevision: editingRevision, expectedProfileID: owner) }
        } }
        .alert(deletionTitle, isPresented: Binding(get: { deletion != nil }, set: { if !$0 { deletion = nil } }), presenting: deletion) { target in
            switch target {
            case .meal:
                Button("Delete meal", role: .destructive) { Task { await deleteMeal() } }
            case .food(let item, let revision):
                Button("Delete food", role: .destructive) { Task { await deleteFood(item, revision: revision) } }.accessibilityIdentifier("confirmDeleteFood")
            case .photo(let photoID):
                Button("Delete photo", role: .destructive) {
                    guard let owner = model.readModel?.profile.id else { return }
                    Task { await model.change { try await model.store.deletePhoto(mealID: mealID, photoID: photoID, expectedProfileID: owner) } }
                }
            }
            Button("Cancel", role: .cancel) { deletion = nil }
        } message: { target in
            switch target {
            case .meal: Text("This removes the meal and its attached photos from this diary.")
            case .photo: Text("Only this photo will be removed. The meal and its notes are kept.")
            case .food: Text("Only this food is removed. The meal keeps its other foods.")
            }
        }
        .sheet(isPresented: $showScale) {
            if let meal = model.meal(mealID), let owner = model.readModel?.profile.id { ScaleMealSheet(model: model, meal: meal, ownerID: owner) }
        }
        .sheet(isPresented: $showMove) {
            if let meal = model.meal(mealID), let owner = model.readModel?.profile.id {
                MoveMealSheet(model: model, meal: meal, ownerID: owner) { movedDayID = $0 }
            }
        }
    }
    private var deletionTitle: String {
        if case .some(.photo(_)) = deletion { return "Delete this photo?" }
        if case .some(.food(let item, _)) = deletion { return "Delete \(item.name)?" }
        guard let meal = model.meal(mealID), let day = model.day(meal.dayID) else { return "Delete meal?" }
        return "Delete “\(displayTitle(meal))” on \(day.localDate)?"
    }
    /// `revision` is what the person saw when they chose to delete; a newer meal is refused as stale.
    private func deleteFood(_ item: FoodItem, revision: Int?) async -> Bool {
        guard let owner = model.readModel?.profile.id, let revision else { return false }
        return await model.change { try await model.store.deleteItem(mealID: mealID, itemID: item.id, expectedRevision: revision, expectedProfileID: owner) }
    }
    private func deleteMeal() async -> Bool {
        guard let owner = model.readModel?.profile.id else { return false }
        let deleted = await model.change { try await model.store.deleteMeal(mealID, expectedProfileID: owner) }
        if deleted { dismiss() }
        return deleted
    }
    /// Opens Coach at this meal's conversation (or its day), quoting the meal or food; a specific food also gets an unsent message naming it.
    private func askPip(about item: FoodItem?, in meal: MealReadModel) {
        guard let selection = model.selection else { return }
        let day = model.day(meal.dayID).map { " from \(DiaryWeek.format($0.localDate, "EEE d MMM"))" } ?? ""
        let draft = item.map { "About the \($0.name)\(day): " }
        let target: CoachSeekTarget = meal.sourceTurnID.map { .turn($0) } ?? .day(meal.dayID)
        editedItem = nil
        let reply = CoachReply(target: item.map { .item(mealID: meal.id, itemID: $0.id) } ?? .meal(mealID: meal.id), excerpt: String((item?.name ?? displayTitle(meal)).prefix(280)))
        if openChat(target, draft: draft, reply: reply, expectedSelection: selection) { dismiss() }
    }
    private func foodRow(_ item: FoodItem, meal: MealReadModel) -> some View {
        HStack(spacing: 12) {
            Button {
                editingRevision = meal.revision; editingSubmissionID = nil; editedItem = item
            } label: {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.provenance == .sample ? "Apple (sample)" : item.name).font(.body.weight(.semibold))
                        Text("\(item.quantity.formatted()) \(item.unit)").font(.subheadline).monospacedDigit().foregroundStyle(Color.diarySecondary)
                        if item.uncertain { Text("Portion or nutrients are uncertain").font(.caption).foregroundStyle(Color.diarySecondary) }
                    }
                    Spacer(minLength: 8)
                    Text(item.nutrition.kcal.map { $0.formatted(.number.precision(.fractionLength(0))) + " kcal" } ?? "— kcal")
                        .font(.subheadline.weight(.medium)).monospacedDigit()
                }
                .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading).contentShape(Rectangle())
            }
            .buttonStyle(.plain).accessibilityIdentifier("editItem")
            .accessibilityHint("Edit amount, nutrition or delete")
            Button { askPip(about: item, in: meal) } label: {
                Image(systemName: "sparkles").font(.body.weight(.semibold)).foregroundStyle(Color.diaryAccent)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color.diarySummarySurface))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Ask Pip about \(item.name)")
            .accessibilityIdentifier("askPipFood")
            if meal.state == .saved {
                // The meal's only food deletes the meal, as the food editor does.
                Button { deletion = meal.items.count > 1 ? .food(item, revision: meal.revision) : .meal } label: {
                    Image(systemName: "minus.circle").font(.body.weight(.semibold)).foregroundStyle(.red)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete \(item.name)")
                .accessibilityIdentifier("deleteFoodRow")
            }
        }
    }
    private func displayTitle(_ meal: MealReadModel) -> String {
        if let item = meal.items.first { return item.provenance == .sample ? "Apple (sample)" : item.name }
        let note = meal.submissions.first?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return note.isEmpty ? "Meal" : note
    }
    private func mealSummary(_ meal: MealReadModel, snapshot: DiaryReadModel) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(displayTitle(meal))
                .font(.title.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
            if meal.timePrecision == .dateOnly {
                Text(model.day(meal.dayID)?.localDate ?? "Historical meal")
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
                    Text(meal.state == .cancelled ? "Analysis was cancelled. Your note and photos are kept." : meal.state == .needsRetry ? "Your meal is saved. Retry analysis when you’re ready." : meal.state == .waitingForConnection ? "Connect ChatGPT to analyze this saved meal." : "Your meal is saved. Analysis will resume when available.")
                        .font(.subheadline).foregroundStyle(Color.diarySecondary)
                }
            }
            if meal.state == .saved, (meal.totals.kcal ?? 0) > 0 {
                Button { showScale = true } label: { Label("Adjust total", systemImage: "slider.horizontal.3").frame(maxWidth: .infinity, minHeight: 44) }
                    .buttonStyle(.glass).accessibilityHint("Resizes every food in this meal to reach a calorie total")
                    .accessibilityIdentifier("adjustMealTotal")
            }
            if meal.state == .waitingForConnection, let connection {
                ChatGPTConnectButton(connection: connection, title: "Connect ChatGPT")
                    .frame(minHeight: 44).buttonStyle(.glass)
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
                    Text(item.sourceCaption).font(.caption).foregroundStyle(Color.diarySecondary)
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
    init(model: DiaryViewModel, meal: MealReadModel, ownerID: UUID, onMoved: @escaping (UUID) -> Void) {
        self.model = model; mealID = meal.id; self.onMoved = onMoved
        _ownerID = State(initialValue: ownerID)
        _originalDayID = State(initialValue: meal.dayID)
        _originalRevision = State(initialValue: meal.revision)
        _destination = State(initialValue: meal.dayID)
    }
    @State private var destinations: [TrackingDay] = []
    @State private var historyCursor: DiaryHistoryCursor?
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Destination waking day", selection: $destination) {
                        ForEach(destinations.sorted { $0.startAt > $1.startAt }) { day in
                            Text(day.id == originalDayID ? "\(day.localDate) · Current day" : day.localDate).tag(day.id)
                                .frame(minHeight: 44)
                        }
                    }.pickerStyle(.inline).accessibilityIdentifier("moveMealDestination")
                    if historyCursor != nil { Button("Earlier days") { Task { await loadDestinations() } }.frame(minHeight: 44) }
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
                        .disabled(moving || destination == originalDayID || model.readModel?.profile.id != ownerID)
                        .accessibilityIdentifier("confirmMoveMeal")
                }
            }
            .task { await loadDestinations() }
            .interactiveDismissDisabled(moving)
            .onChange(of: model.readModel?.profile.id) { _, id in if id != ownerID { dismiss() } }
        }
    }
    private func loadDestinations() async {
        do {
            let page = try await model.store.diaryHistory(before: historyCursor, expectedProfileID: ownerID)
            guard model.readModel?.profile.id == ownerID else { return }
            destinations = page.days.map(\.day); historyCursor = page.cursor
            if let original = model.day(originalDayID), !destinations.contains(where: { $0.id == originalDayID }) { destinations.append(original) }
        } catch { model.errorMessage = error.localizedDescription }
    }
    private func move() async {
        guard !moving, destination != originalDayID, model.readModel?.profile.id == ownerID else { return }
        moving = true
        defer { moving = false }
        let selectedDay = destination
        if await model.change({
            try await model.store.moveMeal(mealID, to: selectedDay, expectedRevision: originalRevision,
                                           expectedDayID: originalDayID, expectedProfileID: ownerID)
        }) { onMoved(selectedDay); dismiss() }
    }
}

/// Resizes the whole meal to a calorie total; the revision is captured when the sheet opens.
private struct ScaleMealSheet: View {
    @Bindable var model: DiaryViewModel
    let mealID: UUID
    let ownerID: UUID
    let revision: Int
    let currentKcal: Double
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var target: String
    @State private var saving = false
    @FocusState private var focused: Bool
    init(model: DiaryViewModel, meal: MealReadModel, ownerID: UUID) {
        self.model = model; mealID = meal.id; self.ownerID = ownerID; revision = meal.revision
        currentKcal = meal.totals.kcal ?? 0
        _target = State(initialValue: (meal.totals.kcal ?? 0).formatted(.number.precision(.fractionLength(0)).grouping(.never)))
    }
    private var value: Double? {
        guard let kcal = Double(target.replacingOccurrences(of: ",", with: ".")), kcal.isFinite, (0.1...3).contains(kcal / currentKcal) else { return nil }
        return kcal
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent { TextField("kcal", text: $target).keyboardType(.decimalPad).multilineTextAlignment(.trailing).monospacedDigit()
                        .focused($focused).accessibilityIdentifier("mealTargetKcal") } label: { Text("Total calories") }
                        .frame(minHeight: 44).accessibilityElement(children: .contain)
                } header: { Text("New total") } footer: {
                    Text("Every food in this meal is resized by the same amount. Allowed: 10% to 300% of the current \(currentKcal.formatted(.number.precision(.fractionLength(0)))) kcal.")
                }
                Section("Preview") {
                    let text = value.map { $0.formatted(.number.precision(.fractionLength(0))) } ?? "—"
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(text).font(.largeTitle.weight(.semibold)).monospacedDigit().foregroundStyle(Color.diaryEnergy).contentTransition(.numericText())
                        Text("kcal").foregroundStyle(Color.diarySecondary)
                    }
                    .accessibilityElement(children: .ignore).accessibilityLabel(value == nil ? "No valid total" : "\(text) kcal").accessibilityIdentifier("mealPreviewKcal")
                    if let value { Text("\((value / currentKcal).formatted(.number.precision(.fractionLength(2))))× of the current portions").font(.subheadline).foregroundStyle(Color.diarySecondary) }
                }
                if let message = model.errorMessage {
                    Section { Label(LocalizedStringKey(message), systemImage: "exclamationmark.circle").foregroundStyle(Color.diaryError) }
                }
            }
            .disabled(saving)
            .scrollContentBackground(.hidden).background(Color.diaryCanvas).tint(.diaryAccent)
            .navigationTitle("Adjust total").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { focused = false } }
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(saving || value == nil || model.readModel?.profile.id != ownerID).accessibilityIdentifier("saveMealTotal")
                }
            }
            .interactiveDismissDisabled(saving)
            .onChange(of: model.readModel?.profile.id) { _, id in if id != ownerID { dismiss() } }
        }
        .environment(\.locale, Locale(identifier: "en")).environment(\.layoutDirection, .leftToRight)
    }
    private func save() async {
        guard let kcal = value, !saving else { return }
        saving = true; defer { saving = false }
        if await model.change({ try await model.store.scaleMeal(mealID: mealID, targetKcal: kcal, expectedRevision: revision, expectedProfileID: ownerID) }) { dismiss() }
    }
}

private struct FoodItemEditor: View {
    let item: FoodItem
    let save: (FoodItem, Set<String>) async -> Bool
    let errorMessage: () -> String?
    /// Nil for estimate items under review; set exactly one of the two deletes for saved foods.
    var deleteFood: (() async -> Bool)? = nil
    var deleteMeal: (() async -> Bool)? = nil
    var askPip: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var showDetails = false
    @State private var confirmDelete = false
    @State private var name: String
    @State private var quantity: String
    @State private var unit: String
    @State private var kcal: String
    @State private var carbs: String
    @State private var protein: String
    @State private var fat: String
    @State private var explicitNutrients: Set<String> = []
    @State private var saving = false
    @State private var showDiscard = false
    @FocusState private var editingField: String?
    @Environment(\.dynamicTypeSize) private var typeSize
    init(item: FoodItem, errorMessage: @escaping () -> String?, deleteFood: (() async -> Bool)? = nil, deleteMeal: (() async -> Bool)? = nil,
         askPip: (() -> Void)? = nil, save: @escaping (FoodItem, Set<String>) async -> Bool) {
        self.item = item; self.save = save; self.errorMessage = errorMessage
        self.deleteFood = deleteFood; self.deleteMeal = deleteMeal; self.askPip = askPip
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
                    Text(name.isEmpty ? item.name : name).font(.title2.weight(.semibold)).padding(.vertical, 4)
                    nutrientField("Amount", text: $quantity, identifier: "itemQuantity")
                    LabeledContent("Unit") { TextField("Unit", text: $unit).multilineTextAlignment(.trailing).focused($editingField, equals: "Unit") }
                    portionChips
                } header: { Text("Portion") }
                Section { preview } header: { Text("This food") }
                Section {
                    Button { withAnimation(.snappy) { showDetails.toggle() } } label: {
                        HStack {
                            Text("More details")
                            Spacer()
                            Image(systemName: "chevron.down").rotationEffect(.degrees(showDetails ? 180 : 0)).accessibilityHidden(true)
                        }.frame(minHeight: 44)
                    }
                    .accessibilityValue(showDetails ? "Expanded" : "Collapsed").accessibilityIdentifier("foodMoreDetails")
                    if showDetails {
                        TextField("Name", text: $name).focused($editingField, equals: "Name")
                        nutrientField("Energy (kcal)", text: nutrientBinding("kcal", $kcal), identifier: "itemCalories")
                        nutrientField("Protein (g)", text: nutrientBinding("protein", $protein))
                        nutrientField("Carbs (g)", text: nutrientBinding("carbs", $carbs))
                        nutrientField("Fat (g)", text: nutrientBinding("fat", $fat))
                        Text(item.sourceCaption).foregroundStyle(Color.diarySecondary)
                        if !item.reference.isEmpty { Text(item.reference).font(.subheadline).foregroundStyle(Color.diarySecondary) }
                        if item.uncertain { Label("Portion or nutrients are uncertain", systemImage: "info.circle").font(.subheadline).foregroundStyle(Color.diarySecondary) }
                    }
                } footer: {
                    if showDetails { Text("Leave unknown values blank. Changing only the amount scales the recorded nutrients. Changes update this meal only.") }
                }
                if askPip != nil || deleteFood != nil || deleteMeal != nil {
                    Section {
                        if let askPip {
                            Button { dismiss(); askPip() } label: { Label("Ask Pip to fix this", systemImage: "sparkles").frame(minHeight: 44) }
                                .accessibilityIdentifier("askPipAboutFood")
                        }
                        if deleteFood != nil {
                            Button("Delete food", systemImage: "trash", role: .destructive) { confirmDelete = true }
                                .foregroundStyle(Color.diaryError).frame(minHeight: 44).accessibilityIdentifier("deleteFood")
                        } else if deleteMeal != nil {
                            Button("Delete meal", systemImage: "trash", role: .destructive) { confirmDelete = true }
                                .foregroundStyle(Color.diaryError).frame(minHeight: 44).accessibilityIdentifier("deleteMealFromFood")
                        }
                    } footer: {
                        if deleteFood == nil && deleteMeal != nil { Text("This is the meal’s only food, so deleting it deletes the meal.") }
                    }
                }
                if let message = errorMessage() {
                    Section { Label(LocalizedStringKey(message), systemImage: "exclamationmark.circle").foregroundStyle(Color.diaryError) }
                }
            }
            .confirmationDialog(deleteFood != nil ? "Delete \(item.name)?" : "Delete this meal?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button(deleteFood != nil ? "Delete food" : "Delete meal", role: .destructive) {
                    Task {
                        saving = true; defer { saving = false }
                        if await (deleteFood ?? deleteMeal)?() == true { dismiss() }
                    }
                }.accessibilityIdentifier("confirmDeleteFood")
            } message: {
                Text(deleteFood != nil ? "Only this food is removed. The meal keeps its other foods." : "This removes the meal and its attached photos from this diary.")
            }
            .scrollContentBackground(.hidden).background(Color.diaryCanvas)
            .scrollDismissesKeyboard(.interactively)
            .foregroundStyle(Color.diaryText).tint(.diaryAccent)
            .navigationTitle("Edit food").navigationBarTitleDisplayMode(.inline)
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
                    Task { saving = true; defer { saving = false }; if await save(updated, explicitNutrients) { dismiss() } }
                }.disabled(edited == nil || saving).accessibilityIdentifier("saveItem") }
            }
        }
        .environment(\.locale, Locale(identifier: "en"))
        .environment(\.layoutDirection, .leftToRight)
    }
    private var portionChips: some View {
        HStack(spacing: 8) {
            ForEach([(0.5, "½×", "Half"), (1, "1×", "Original"), (1.5, "1½×", "One and a half"), (2, "2×", "Double")], id: \.0) { factor, title, spoken in
                let value = item.quantity * factor
                let selected = number(quantity) == value
                Button {
                    quantity = String(value)
                } label: {
                    Text(title).font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(selected ? Color.diaryActionText : Color.diaryText)
                        .background(Capsule().fill(selected ? Color.diaryAccent : Color.diarySummarySurface))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(spoken) portion")
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityIdentifier("foodScale" + (factor == 1.5 ? "1.5" : factor == 0.5 ? "0.5" : String(Int(factor))))
            }
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
    }
    /// What saving would record, using the same scaling rule as the store.
    private var preview: some View {
        let result = edited.flatMap { try? diaryCorrectedItem($0, previous: item, explicitNutrients: explicitNutrients) }
        let kcalText = result?.nutrition.kcal.map { $0.formatted(.number.precision(.fractionLength(0))) } ?? "—"
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(kcalText).font(.largeTitle.weight(.semibold)).monospacedDigit().foregroundStyle(Color.diaryEnergy)
                    .contentTransition(.numericText())
                Text("kcal").foregroundStyle(Color.diarySecondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(kcalText) kcal")
            .accessibilityIdentifier("foodPreviewCalories")
            if let result {
                HStack(spacing: 16) {
                    macro("Protein", result.nutrition.protein, .diaryProtein)
                    macro("Carbs", result.nutrition.carbs, .diaryCarbs)
                    macro("Fat", result.nutrition.fat, .diaryFat)
                }
            }
        }
        .padding(.vertical, 4)
    }
    private func macro(_ title: String, _ value: Double?, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(color)
            Text(value.map { $0.formatted(.number.precision(.fractionLength(1))) + " g" } ?? "—").font(.subheadline.weight(.medium)).monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }
    private var hasChanges: Bool {
        !explicitNutrients.isEmpty || name != item.name || quantity != String(item.quantity) || unit != item.unit
            || kcal != (item.nutrition.kcal.map { String($0) } ?? "")
            || carbs != (item.nutrition.carbs.map { String($0) } ?? "")
            || protein != (item.nutrition.protein.map { String($0) } ?? "")
            || fat != (item.nutrition.fat.map { String($0) } ?? "")
    }
    private func nutrientBinding(_ key: String, _ value: Binding<String>) -> Binding<String> {
        Binding(get: { value.wrappedValue }, set: { newValue in
            value.wrappedValue = newValue
            explicitNutrients.insert(key)
        })
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
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !unit.isEmpty, let amount = number(quantity), amount >= 0, amount <= 100_000, amount.isFinite else { return nil }
        let inputs = [kcal, carbs, protein, fat]
        guard inputs.allSatisfy({ $0.isEmpty || number($0).map { $0 >= 0 && $0.isFinite && $0 <= 10_000_000 } == true }) else { return nil }
        var updated = item
        updated.name = name; updated.quantity = amount; updated.unit = unit
        let values = inputs.map(number)
        updated.nutrition = NutritionValues(kcal: values[0], carbs: values[1], protein: values[2], fat: values[3])
        guard (try? validateItems([updated])) != nil else { return nil }
        return updated
    }
}

private struct MealPhotoViewer: View {
    @Bindable var model: DiaryViewModel
    let photo: DiaryPhotoReference
    @State private var original: Data?
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
                if let original, let image = UIImage(data: original) {
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
            .task(id: photo.id) {
                guard let token = model.selection else { return }
                do {
                    let data = try await model.store.photoContent(photo, expectedProfileID: token.identity.profileID)
                    try await model.store.validateSelection(epoch: token.selectionEpoch, expectedProfileID: token.identity.profileID)
                    guard !Task.isCancelled, !model.isChangingProfile, model.selection == token else { return }; original = data
                } catch { original = nil }
            }
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
