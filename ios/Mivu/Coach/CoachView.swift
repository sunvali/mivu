import SwiftUI

struct CoachView: View {
    @Bindable var coach: CoachViewModel
    let openDestination: (CoachDestination) -> Void
    @State private var showPhotos = false
    @State private var preparation = PhotoPreparation()
    @State private var importFailed = false
    @State private var followLatest = true
    @State private var scrollPhase: ScrollPhase = .idle
    @State private var position = ScrollPosition(idType: String.self)
    @State private var hasNewMessage = false
    @State private var nearBottom = true
    @State private var followRequested = false
    @FocusState private var editing: Bool
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    if DiaryLaunch.isCoachInferenceFixture {
                        Text("Native test fixture — no provider request").font(.caption).foregroundStyle(Color.diaryLeaf).accessibilityIdentifier("coachFixtureBanner")
                    }
                    if let snapshot = coach.diary.snapshot {
                        if let day = coach.diary.activeDay {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(day.localDate).font(.subheadline).accessibilityIdentifier("coachDate")
                                    Spacer()
                                    Text(snapshot.totals(dayID: day.id).kcal.map { $0.formatted(.number.precision(.fractionLength(0))) + " kcal recorded" } ?? "Not estimated yet")
                                        .font(.subheadline.weight(.medium)).monospacedDigit()
                                }
                                if let target = snapshot.goal(on: day.localDate)?.targets.kcal {
                                    Text("\(target.formatted(.number.precision(.fractionLength(0)))) kcal goal")
                                        .font(.caption).accessibilityIdentifier("coachGoalSummary")
                                }
                                Divider()
                            }.foregroundStyle(Color.diarySecondary)
                        }
                        if coach.turns.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("What would you like to record?").font(.title2.weight(.semibold))
                                Text("Describe a meal, add a photo, or record a weigh-in or workout. You can review and correct every estimate.")
                                    .foregroundStyle(Color.diarySecondary)
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
                }.scrollTargetLayout().padding(.vertical, 20)
            }
            .padding(.horizontal, 20)
            .scrollPosition($position)
            .defaultScrollAnchor(.bottom, for: .initialOffset)
            .scrollDismissesKeyboard(.interactively)
            .onScrollPhaseChange { oldPhase, phase, context in
                scrollPhase = phase
                if phase == .idle {
                    if oldPhase == .interacting || oldPhase == .decelerating || (oldPhase != .tracking && position.isPositionedByUser) {
                        followLatest = isNearBottom(context.geometry)
                        if followLatest { hasNewMessage = false }
                    }
                    if followLatest && position.isPositionedByUser { followRequested = true }
                    followLatestPosition()
                }
            }
            .onChange(of: position.isPositionedByUser) { _, byUser in
                if byUser && scrollPhase != .tracking { followLatest = nearBottom }
            }
            .onScrollGeometryChange(for: Bool.self) { isNearBottom($0) } action: { _, nearBottom in
                self.nearBottom = nearBottom
                if nearBottom {
                    followLatest = true; hasNewMessage = false
                    if scrollPhase == .idle && position.isPositionedByUser { requestFollow() }
                } else if scrollPhase == .interacting || scrollPhase == .decelerating || (position.isPositionedByUser && scrollPhase != .tracking) {
                    followLatest = false
                }
            }
            .onChange(of: coach.turns) { _, _ in newContent() }
            .onChange(of: coach.activity) { _, _ in newContent() }
            .overlay(alignment: .bottom) {
                if hasNewMessage && !nearBottom && !followLatest {
                    Button {
                        followLatest = true; hasNewMessage = false
                        requestFollow()
                    } label: {
                        Label("New message", systemImage: "arrow.down").frame(minHeight: 44)
                    }
                    .buttonStyle(.bordered).tint(.diaryLeaf)
                    .background(Color.diarySurface, in: Capsule())
                    .accessibilityHint("Jump to the latest message and follow new replies")
                    .accessibilityIdentifier("coachNewMessage")
                    .padding(.bottom, 8)
                }
            }
            if coach.diary.snapshot != nil { composer }
        }
        .background(Color.diaryCanvas)
        .navigationTitle("Coach")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: UUID.self) { MealDetailView(model: coach.diary, mealID: $0) }
        .navigationDestination(for: WorkoutDestination.self) { WorkoutDetailView(model: coach.diary, sessionID: $0.id) }
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
            followLatest = true; hasNewMessage = false
            nearBottom = true; followRequested = false
            position = ScrollPosition(idType: String.self)
            requestFollow()
        }
    }
    private var userScrolling: Bool {
        scrollPhase == .tracking || scrollPhase == .interacting || scrollPhase == .decelerating
    }
    private func isNearBottom(_ geometry: ScrollGeometry) -> Bool {
        geometry.contentSize.height + geometry.contentInsets.bottom - geometry.contentOffset.y - geometry.containerSize.height <= 80
    }
    private func newContent() {
        hasNewMessage = true
        requestFollow()
    }
    private func requestFollow() {
        followRequested = true
        followLatestPosition()
    }
    private func followLatestPosition() {
        guard followRequested, followLatest, !userScrolling else { return }
        Task { @MainActor in
            await Task.yield()
            guard followRequested, followLatest, !userScrolling, let id = conversationRows.last?.id else { return }
            followRequested = false
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                position.scrollTo(id: id, anchor: .bottom)
            }
            hasNewMessage = false
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
        coach.turns.flatMap { turn in
            var rows = [ConversationRow(turn: turn, kind: .input)]
            if turn.assistantText != nil { rows.append(ConversationRow(turn: turn, kind: .reply)) }
            if turn.state != .completed || turn.pendingMealID != nil || turn.receipts.contains(where: { $0.mealID != nil || $0.workoutID != nil || $0.destination != nil }) {
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
            TextField("Message Coach", text: $coach.draft.text, axis: .vertical)
                .lineLimit(1...(typeSize.isAccessibilitySize ? 2 : 5)).focused($editing).accessibilityIdentifier("coachInput")
                .padding(12).background(Color.diarySurface, in: RoundedRectangle(cornerRadius: 16)).overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(Color.diaryRule, lineWidth: 0.5) }
            HStack {
                Button { editing = false; showPhotos = true } label: {
                    if typeSize.isAccessibilitySize { Image(systemName: "camera").font(.title2).frame(minWidth: 44, minHeight: 44) }
                    else { Label("Add photos", systemImage: "camera") }
                }.accessibilityLabel("Add photos").frame(minHeight: 44).accessibilityIdentifier("coachPhotos")
                Spacer(minLength: 8)
                if reduceTransparency { send.buttonStyle(.borderedProminent) }
                else { send.buttonStyle(.glassProminent) }
            }
        }.padding(.horizontal, 20).padding(.vertical, 8).background(Color.diaryCanvas)
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
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(Color.diarySurface, in: RoundedRectangle(cornerRadius: 16))
    }
    private func turnActions(_ turn: CoachTurn) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if turn.state != .completed {
                if let activity = coach.activity, coach.activityTurnID == turn.id {
                    CoachActivityView(activity: activity)
                } else {
                    Label(status(turn.state), systemImage: turn.state == .analyzing ? "hourglass" : "clock").font(.subheadline).foregroundStyle(Color.diarySecondary)
                }
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
                NavigationLink(value: meal.id) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(meal.state == .awaitingReview ? "Needs review" : meal.isSaved ? "Saved meal" : "Captured on this iPhone", systemImage: meal.state == .awaitingReview ? "checkmark.circle.badge.questionmark" : "checkmark.circle")
                            .font(.subheadline.weight(.semibold))
                        MealRow(meal: meal)
                    }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.diarySurface, in: RoundedRectangle(cornerRadius: 12))
                }.accessibilityIdentifier("coachMealLink")
            }
            ForEach(coach.linkedWorkouts(turn)) { workout in
                NavigationLink(value: WorkoutDestination(id: workout.id)) { Label("Open workout and corrections", systemImage: "figure.strengthtraining.traditional").frame(minHeight: 44) }.accessibilityIdentifier("coachWorkoutLink")
            }
            ForEach(CoachDestination.allCases.filter { destination in turn.receipts.contains { $0.destination == destination } }, id: \.self) { destination in
                Button { openDestination(destination) } label: {
                    Label(destination.linkTitle, systemImage: "gearshape").frame(minHeight: 44)
                }
                .accessibilityIdentifier("coachSettingsLink")
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

private extension CoachDestination {
    var linkTitle: String {
        switch self {
        case .settings: "Open Settings"
        case .profiles: "Open local profiles"
        case .connection: "Open ChatGPT connection"
        case .nutritionSource: "Open nutrition source"
        case .backup: "Open backup and Files"
        }
    }
}
