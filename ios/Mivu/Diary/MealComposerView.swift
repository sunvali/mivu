import SwiftUI

struct MealComposerView: View {
    @Bindable var model: DiaryViewModel
    var correctingMealID: UUID? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var draft = MealDraft()
    @State private var photoPreparation = PhotoPreparation()
    @State private var photoImportFailed = false
    @State private var ambiguousDay: UUID?
    @State private var showDayQuestion = false
    @State private var photoRole = PhotoRole.unspecified
    @State private var submitting = false
    @FocusState private var editingText: Bool
    var body: some View {
        NavigationStack {
            Form {
                Section { SampleBanner() }
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
                Section(correctingMealID == nil ? "Meal details" : "Correction or extra details") {
                    TextField("Write what you ate or what changed", text: $draft.text, axis: .vertical).lineLimit(4...10).focused($editingText).accessibilityIdentifier("mealText")
                    Toggle("Review before saving totals", isOn: $draft.reviewFirst).accessibilityIdentifier("reviewFirst")
                    Text("Send saves your input on this iPhone first. Pending or unreviewed results do not count in totals.").font(.caption).foregroundStyle(Color.diarySecondary)
                }
                if let message = model.errorMessage { Section { Text(LocalizedStringKey(message)).foregroundStyle(.red) } }
            }
            .onDisappear { photoPreparation.cancel() }
            .scrollContentBackground(.hidden).background(Color.diaryCanvas)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(correctingMealID == nil ? "Log meal" : "Update meal")
            .interactiveDismissDisabled(draft.isValid || submitting || photoPreparation.isPreparing)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { editingText = false }.accessibilityIdentifier("doneMealText") }
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(submitting) }
                ToolbarItem(placement: .confirmationAction) { Button { Task { await send() } } label: { if submitting { ProgressView() } else { Text("Send") } }.disabled(!draft.isValid || submitting || !photoPreparation.canCapture).accessibilityIdentifier("sendMeal") }
            }
            .alert("Could not import photo", isPresented: $photoImportFailed) { Button("OK", role: .cancel) {} } message: { Text("Choose a smaller image or another photo. Your other input is preserved.") }
            .confirmationDialog("Which waking day?", isPresented: $showDayQuestion, titleVisibility: .visible) {
                Button("Previous day") {
                    guard let dayID = ambiguousDay, let owner = model.snapshot?.profile.id else { return }
                    Task {
                        if await model.change({ try await model.store.confirmPreviousDay(expectedProfileID: owner) }) { await save(dayID: dayID) }
                    }
                }
                Button("New day") {
                    guard let owner = model.snapshot?.profile.id else { return }
                    Task {
                        do { let day = try await model.store.startDay(expectedProfileID: owner); await save(dayID: day.id) }
                        catch { _ = await model.change { throw error } }
                    }
                }
                Button("Keep editing", role: .cancel) {}
            } message: { Text("Your active day began on an earlier date. A late meal can stay in that day.") }
        }
    }
    private func send() async {
        guard draft.isValid, photoPreparation.canCapture, !submitting, let owner = model.snapshot?.profile.id else { return }
        if let mealID = correctingMealID {
            submitting = true
            defer { submitting = false }
            if await model.change({
                _ = try await model.store.correctMeal(mealID: mealID, text: draft.text, photos: draft.photos.map { MealPhoto(data: $0, role: photoRole) }, reviewFirst: draft.reviewFirst, submissionID: draft.submissionID, expectedProfileID: owner)
            }) { model.resumeWorker(); dismiss() }
            return
        }
        do {
            switch try await model.store.dayAssignment(expectedProfileID: owner) {
            case .existing(let dayID): await save(dayID: dayID)
            case .newDay: let day = try await model.store.startDay(expectedProfileID: owner); await save(dayID: day.id)
            case .ask(let dayID): ambiguousDay = dayID; showDayQuestion = true
            }
        } catch { _ = await model.change { throw error } }
    }
    private func save(dayID: UUID) async {
        guard photoPreparation.canCapture, !submitting else { return }
        submitting = true
        defer { submitting = false }
        if await model.capture(draft, dayID: dayID, photoPreparation: photoPreparation) { dismiss() }
    }
}
