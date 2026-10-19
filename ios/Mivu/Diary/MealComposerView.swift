import SwiftUI

struct MealComposerView: View {
    @Bindable var model: DiaryViewModel
    var correctingMealID: UUID? = nil
    var dayID: UUID? = nil
    var onSaved: ((UUID) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var draft = MealDraft()
    @State private var ownership: DiarySelectionOwnership?
    @State private var photoPreparation = PhotoPreparation()
    @State private var photoImportFailed = false
    @State private var ambiguousDay: UUID?
    @State private var showDayQuestion = false
    @State private var photoRole = PhotoRole.unspecified
    @State private var submitting = false
    @State private var showDiscard = false
    @State private var showManualNutrition = false
    @State private var manuallySavedMealID: UUID?
    @FocusState private var editingText: Bool
    var body: some View {
        NavigationStack {
            Form {
                if model.sampleMode { Section { SampleBanner() } }
                Section {
                    TextField("Write what you ate or what changed", text: $draft.text, axis: .vertical)
                        .lineLimit(4...10).focused($editingText).accessibilityIdentifier("mealText")
                        .padding(.vertical, 8)
                } header: {
                    Text(correctingMealID == nil ? "Meal details" : "Correction or extra details")
                } footer: {
                    Text("Add a note, a photo, or both.")
                }
                Section("Photos") {
                    PhotoInput(photos: $draft.photos, preparation: photoPreparation, importFailed: $photoImportFailed).disabled(submitting)
                    if correctingMealID != nil {
                        Picker("Photo timing", selection: $photoRole) {
                            Text("Unspecified").tag(PhotoRole.unspecified)
                            Text("Before eating").tag(PhotoRole.before)
                            Text("After eating").tag(PhotoRole.after)
                        }
                    }
                }
                Section {
                    if let mealID = correctingMealID, let meal = model.meal(mealID) {
                        LabeledContent("Waking day", value: model.day(meal.dayID)?.localDate ?? "Original meal day")
                    } else if let dayID, let day = model.day(dayID) {
                        LabeledContent("Waking day", value: day.localDate)
                        Text("The meal will be recorded on this day. Time will be unspecified.").font(.subheadline).foregroundStyle(Color.diarySecondary)
                    } else if let snapshot = model.readModel, let day = snapshot.activeDay {
                        LabeledContent("Waking day", value: day.localDate)
                    } else {
                        Label("A waking day will be started when you save.", systemImage: "sun.horizon")
                            .foregroundStyle(Color.diarySecondary)
                    }
                    Toggle("Review before saving totals", isOn: $draft.reviewFirst).accessibilityIdentifier("reviewFirst")
                } header: {
                    Text(correctingMealID == nil ? "Waking day" : "This meal")
                } footer: {
                    Text("Saved on this iPhone before analysis. Pending or unreviewed results do not count in totals. We’ll ask if the waking day needs confirming.")
                }
                if correctingMealID == nil {
                    Section {
                        Button("Enter nutrition manually", systemImage: "number") { showManualNutrition = true }
                            .frame(minHeight: 44).accessibilityIdentifier("enterNutritionManually")
                    } footer: { Text("Save known nutrition directly, including when offline.") }
                }
                if let mealID = manuallySavedMealID {
                    Section {
                        NavigationLink { MealDetailView(model: model, mealID: mealID) } label: { Label("View saved food", systemImage: "checkmark.circle").frame(minHeight: 44) }
                            .accessibilityIdentifier("manualSavedFood")
                        Text("Your note and photos are still here and have not been sent.").font(.subheadline).foregroundStyle(Color.diarySecondary)
                    }
                }
                if let message = model.errorMessage { Section { Text(LocalizedStringKey(message)).foregroundStyle(.red) } }
            }
            .onDisappear { photoPreparation.cancel() }
            .task(id: model.changeGeneration) { if ownership == nil { ownership = model.selection }; photoPreparation.use(limiter: model.photoWorkLimiter); if let id = correctingMealID { await model.loadMeal(id) }; if let dayID { await model.loadDay(dayID) } }
            .scrollContentBackground(.hidden).background(Color.diaryCanvas)
            .scrollDismissesKeyboard(.interactively)
            .foregroundStyle(Color.diaryText)
            .tint(.diaryAccent)
            .navigationTitle(correctingMealID == nil ? "Log meal" : "Add to meal")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(draft.isValid || submitting || photoPreparation.isPreparing)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { editingText = false }.accessibilityIdentifier("doneMealText") }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        editingText = false
                        if draft.isValid || photoPreparation.isPreparing { showDiscard = true } else { dismiss() }
                    }
                    .disabled(submitting)
                    .alert("Discard changes?", isPresented: $showDiscard) {
                        Button("Discard changes", role: .destructive) { photoPreparation.cancel(); dismiss() }
                        Button("Keep editing", role: .cancel) {}
                    } message: { Text("Your unsaved note and photos will be discarded.") }
                }
                ToolbarItem(placement: .confirmationAction) { Button { Task { await send() } } label: { if submitting { ProgressView() } else { Text("Save") } }.disabled(!draft.isValid || submitting || !photoPreparation.canCapture).accessibilityIdentifier("sendMeal") }
            }
            .alert("Could not import photo", isPresented: $photoImportFailed) { Button("OK", role: .cancel) {} } message: { Text("Choose a smaller image or another photo. Your other input is preserved.") }
            .confirmationDialog("Which waking day?", isPresented: $showDayQuestion, titleVisibility: .visible) {
                Button("Previous day") {
                    guard let dayID = ambiguousDay, let token = ownership, model.selection == token else { return }
                    let owner = token.identity.profileID
                    Task {
                        if await model.change({ try await model.store.confirmPreviousDay(expectedSelection: token, expectedProfileID: owner) }) { await save(dayID: dayID) }
                    }
                }
                Button("New day") {
                    guard let token = ownership, model.selection == token else { return }
                    let owner = token.identity.profileID
                    Task {
                        do { let day = try await model.store.startDay(expectedSelection: token, expectedProfileID: owner); await save(dayID: day.id) }
                        catch { _ = await model.change { throw error } }
                    }
                }
                Button("Keep editing", role: .cancel) {}
            } message: { Text("Your active day began on an earlier date. A late meal can stay in that day.") }
        }
        .sheet(isPresented: $showManualNutrition) {
            let target = dayID.flatMap { model.day($0) }.map { ManualNutritionTarget.recorded(dayID: $0.id, localDate: $0.localDate, timeZoneID: $0.timeZoneID) }
            ManualNutritionView(model: model, target: target) { mealID in
                if draft.isValid || photoPreparation.isPreparing { manuallySavedMealID = mealID }
                else { onSaved?(mealID); dismiss() }
            }
        }
        .onChange(of: model.selection) { _, selection in
            if let ownership, selection != ownership { photoPreparation.cancel(); dismiss() }
        }
        .environment(\.locale, Locale(identifier: "en"))
        .environment(\.layoutDirection, .leftToRight)
    }
    private func send() async {
        guard draft.isValid, photoPreparation.canCapture, !submitting, let token = ownership, model.selection == token else { return }
        let owner = token.identity.profileID
        if let mealID = correctingMealID {
            submitting = true
            defer { submitting = false }
            if await model.change({
                _ = try await model.store.correctMealProjection(mealID: mealID, text: draft.text, photos: draft.photos.map { MealPhoto(data: $0, role: photoRole) }, reviewFirst: draft.reviewFirst, submissionID: draft.submissionID, forCoach: !model.sampleMode, expectedSelection: token, expectedProfileID: owner)
            }) { model.resumeWorker(); onSaved?(mealID); dismiss() }
            return
        }
        if let dayID { await save(dayID: dayID); return }
        do {
            switch try await model.store.dayAssignment(expectedSelection: token, expectedProfileID: owner) {
            case .existing(let dayID): await save(dayID: dayID)
            case .newDay: let day = try await model.store.startDay(expectedSelection: token, expectedProfileID: owner); await save(dayID: day.id)
            case .ask(let dayID): ambiguousDay = dayID; showDayQuestion = true
            }
        } catch { _ = await model.change { throw error } }
    }
    private func save(dayID: UUID) async {
        guard photoPreparation.canCapture, !submitting, let token = ownership, model.selection == token else { return }
        submitting = true
        defer { submitting = false }
        if await model.capture(draft, dayID: dayID, dateOnly: self.dayID != nil, photoPreparation: photoPreparation, expectedSelection: token) {
            if let mealID = model.savedMealID {
                onSaved?(mealID)
            }
            dismiss()
        }
    }
}
