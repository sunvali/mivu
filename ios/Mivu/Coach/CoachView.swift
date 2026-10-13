import SwiftUI

struct CoachView: View {
    @Bindable var coach: CoachViewModel
    @State private var showPhotos = false
    @State private var preparation = PhotoPreparation()
    @State private var importFailed = false
    @State private var followLatest = true
    @State private var userScrolling = false
    @FocusState private var editing: Bool
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    if DiaryLaunch.isCoachInferenceFixture {
                        Text("Native test fixture — no provider request").font(.caption).foregroundStyle(Color.diaryLeaf).accessibilityIdentifier("coachFixtureBanner")
                    }
                    if let snapshot = coach.diary.snapshot {
                        if let day = coach.diary.activeDay {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(day.localDate).font(.caption).foregroundStyle(Color.diarySecondary)
                                NutritionSummary(totals: snapshot.totals(dayID: day.id))
                                if let goal = snapshot.goal(on: day.localDate) {
                                    let progress = ProgressAnalytics.daily(snapshot: snapshot, localDate: day.localDate)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Your goals").font(.subheadline.weight(.semibold))
                                        if let target = goal.targets.kcal {
                                            Text("\(target.formatted(.number.precision(.fractionLength(0)))) kcal goal")
                                        }
                                        Text("Remaining from recorded food: \(progress.remainingFromRecorded.kcal.map { $0.formatted(.number.precision(.fractionLength(0))) + " kcal" } ?? "unknown")")
                                    }
                                    .font(.subheadline)
                                    .accessibilityIdentifier("coachGoalSummary")
                                }
                            }.padding(16).background(Color.diarySurface, in: RoundedRectangle(cornerRadius: 20))
                        }
                        if coach.turns.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("A little context, a clearer picture.").font(.title2.weight(.semibold))
                                Text("Log meals, morning weigh-ins or workouts, add photos, or ask about your recorded progress. Estimates stay open to correction.").foregroundStyle(Color.diarySecondary)
                            }.padding(.vertical, 24)
                        }
                        ForEach(conversationRows) { row in
                            switch row.kind {
                            case .input: inputBubble(row.turn)
                            case .reply:
                                Text(row.turn.assistantText ?? "").textSelection(.enabled).padding(.horizontal, 8)
                                    .accessibilityIdentifier("coachReply")
                            case .actions: turnActions(row.turn)
                            }
                        }
                    } else { ContentUnavailableView("Choose your diary", systemImage: "person.crop.circle", description: Text("Open Settings to choose a private local profile.")) }
                }.padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .onScrollPhaseChange { _, phase in
                userScrolling = phase == .tracking || phase == .interacting || phase == .decelerating
            }
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentSize.height - geometry.contentOffset.y - geometry.containerSize.height
            } action: { _, remaining in
                let nearBottom = remaining <= 80
                if userScrolling, followLatest != nearBottom { followLatest = nearBottom }
            }
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentSize.height } action: { oldHeight, newHeight in
                guard newHeight > oldHeight, followLatest, !userScrolling,
                      let turn = coach.turns.last, turn.assistantText != nil else { return }
                Task { @MainActor in
                    await Task.yield()
                    if followLatest, !userScrolling { proxy.scrollTo("reply-" + turn.id.uuidString, anchor: .top) }
                }
            }
            .onChange(of: coach.turns.last?.assistantText) { _, _ in
                guard followLatest, let id = coach.turns.last?.id, coach.turns.last?.assistantText != nil else { return }
                Task { @MainActor in
                    await Task.yield()
                    if followLatest, !userScrolling { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { proxy.scrollTo("reply-" + id.uuidString, anchor: .top) } }
                }
            }
            .onChange(of: coach.turns.count) { _, _ in
                followLatest = true
                if let id = coach.turns.last?.id { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { proxy.scrollTo("input-" + id.uuidString, anchor: .bottom) } }
            }
        }
        .background(Color.diaryCanvas)
        .navigationTitle("Coach")
        .navigationDestination(for: UUID.self) { MealDetailView(model: coach.diary, mealID: $0) }
        .navigationDestination(for: WorkoutDestination.self) { WorkoutDetailView(model: coach.diary, sessionID: $0.id) }
        .safeAreaInset(edge: .bottom) { if coach.diary.snapshot != nil { composer } }
        .sheet(isPresented: $showPhotos) {
            NavigationStack {
                Form { PhotoInput(photos: $coach.draft.photos, preparation: preparation, importFailed: $importFailed) }
                    .navigationTitle("Coach photos")
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showPhotos = false }.frame(minHeight: 44) } }
            }.environment(\.locale, Locale(identifier: "en")).environment(\.layoutDirection, .leftToRight)
        }
        .alert("Could not import photo", isPresented: $importFailed) { Button("OK", role: .cancel) {} } message: { Text("Choose a smaller image or another photo. Your other input is preserved.") }
        .sensoryFeedback(.success, trigger: coach.captureReceipt)
        .onChange(of: coach.diary.snapshot?.profile.id) { _, _ in
            preparation.cancel(); preparation = PhotoPreparation()
            showPhotos = false; editing = false
        }
    }
    private struct WorkoutDestination: Hashable { let id: UUID }
    private struct ConversationRow: Identifiable {
        enum Kind: String { case input, reply, actions }
        let turn: CoachTurn
        let kind: Kind
        var id: String { kind.rawValue + "-" + turn.id.uuidString }
    }
    private var conversationRows: [ConversationRow] {
        // Lazy scrolling resolves ForEach element IDs before offscreen views exist.
        coach.turns.flatMap { turn in
            var rows = [ConversationRow(turn: turn, kind: .input)]
            if turn.assistantText != nil { rows.append(ConversationRow(turn: turn, kind: .reply)) }
            if turn.state != .completed || turn.pendingMealID != nil || turn.receipts.contains(where: { $0.mealID != nil || $0.workoutID != nil }) {
                rows.append(ConversationRow(turn: turn, kind: .actions))
            }
            return rows
        }
    }
    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let error = coach.errorMessage { Text(error).font(.caption).foregroundStyle(Color.diarySecondary).accessibilityIdentifier("coachError") }
            if !coach.connection.planAuthorized && !DiaryLaunch.isCoachInferenceFixture { Text("Input saves on this iPhone. Connect ChatGPT in Settings for analysis.").font(.caption).foregroundStyle(Color.diarySecondary) }
            if !coach.draft.photos.isEmpty { Text("\(coach.draft.photos.count) photos attached").font(.caption).foregroundStyle(Color.diarySecondary) }
            TextField("Meals, weigh-ins, workouts or a question?", text: $coach.draft.text, axis: .vertical)
                .lineLimit(1...(typeSize.isAccessibilitySize ? 2 : 5)).focused($editing).accessibilityIdentifier("coachInput")
                .padding(12).background(Color.diarySurface, in: RoundedRectangle(cornerRadius: 16))
            HStack {
                Button { editing = false; showPhotos = true } label: {
                    if typeSize.isAccessibilitySize { Image(systemName: "camera").font(.title2).frame(minWidth: 44, minHeight: 44) }
                    else { Label("Add photos", systemImage: "camera") }
                }.accessibilityLabel("Add photos").frame(minHeight: 44).accessibilityIdentifier("coachPhotos")
                Spacer(minLength: 8)
                if reduceTransparency { send.buttonStyle(.borderedProminent) }
                else { send.buttonStyle(.glassProminent) }
            }
        }.padding(.horizontal, 16).padding(.vertical, 8).background(Color.diaryCanvas)
            .disabled(coach.isSending || coach.diary.isChangingProfile)
    }
    private var send: some View {
        Button { editing = false; Task { _ = await coach.send() } } label: {
            if coach.isSending { ProgressView().frame(minWidth: 60, minHeight: 44) }
            else if typeSize.isAccessibilitySize { Text("Send").font(.headline).fixedSize().frame(minHeight: 44) }
            else { Label("Send", systemImage: "arrow.up").frame(minHeight: 44) }
        }.tint(.diaryAccent).foregroundStyle(Color.diaryActionText).disabled(!coach.canSend || !preparation.canCapture).accessibilityIdentifier("coachSend")
    }
    private func inputBubble(_ turn: CoachTurn) -> some View {
            VStack(alignment: .leading, spacing: 8) {
                if !turn.text.isEmpty { Text(turn.text).textSelection(.enabled) }
                if !turn.photoIDs.isEmpty { Label("\(turn.photoIDs.count) attached photos", systemImage: "photo") .font(.caption) }
                Label("Input saved on this iPhone", systemImage: "internaldrive").font(.caption).foregroundStyle(Color.diarySecondary)
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(Color.diaryLeaf.opacity(0.08), in: RoundedRectangle(cornerRadius: 20))
    }
    private func turnActions(_ turn: CoachTurn) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if turn.state != .completed {
                Label(status(turn.state), systemImage: turn.state == .analyzing ? "hourglass" : "clock").font(.subheadline).foregroundStyle(Color.diarySecondary)
                if turn.needsDayChoice == true {
                    if let date = coach.previousDayDate(turn) {
                        Button("Use previous waking day: " + date) { Task { await coach.chooseDay(turn.id, usePrevious: true) } }.frame(minHeight: 44).disabled(coach.isWorking)
                    }
                    Button("Use capture date: " + coach.captureDate(turn)) { Task { await coach.chooseDay(turn.id, usePrevious: false) } }.frame(minHeight: 44).disabled(coach.isWorking)
                } else if [.waitingForConnection, .waitingForNetwork, .needsRetry, .needsClarification].contains(turn.state) {
                    Button("Retry analysis") { Task { await coach.retry(turn.id) } }.frame(minHeight: 44).disabled(coach.isWorking).accessibilityIdentifier("coachRetry")
                }
            }
            ForEach(coach.linkedMeals(turn)) { meal in
                NavigationLink(value: meal.id) { Label(meal.state == .awaitingReview ? "Review meal estimate" : "Open meal and corrections", systemImage: "fork.knife").frame(minHeight: 44) }.accessibilityIdentifier("coachMealLink")
            }
            ForEach(coach.linkedWorkouts(turn)) { workout in
                NavigationLink(value: WorkoutDestination(id: workout.id)) { Label("Open workout and corrections", systemImage: "figure.strengthtraining.traditional").frame(minHeight: 44) }.accessibilityIdentifier("coachWorkoutLink")
            }
        }
    }
    private func status(_ state: CoachTurnState) -> String {
        switch state {
        case .captured: "Waiting for analysis"
        case .analyzing: "Analyzing saved input"
        case .waitingForConnection: "Waiting for an authorized connection"
        case .waitingForNetwork: "Waiting for the network. Your input is saved."
        case .needsRetry: "Analysis paused. Your input is saved."
        case .needsClarification: "More details are needed. Review the saved record or send a follow-up."
        case .completed: "Completed"
        }
    }
}
