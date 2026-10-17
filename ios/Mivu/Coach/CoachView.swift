import SwiftUI

struct CoachView: View {
    @Bindable var coach: CoachViewModel
    let companionOutput: CompanionOutput
    let companionRuntime: CompanionRuntime
    let onCompanionContextChanged: (CompanionContext) -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var surfaceVisible = false
    @State private var showingDetail = false
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
    @State private var history = CoachHistoryWindow()
    @FocusState private var editing: Bool
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                if let snapshot = coach.diary.snapshot {
                    // Eager pages keep restored rows in the native accessibility tree.
                    VStack(alignment: .leading, spacing: 24) {
                        if DiaryLaunch.isCoachInferenceFixture {
                            Text("Native test fixture — no provider request").font(.caption).foregroundStyle(Color.diaryLeaf).accessibilityIdentifier("coachFixtureBanner")
                        }
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
                                .accessibilityElement(children: .contain)
                        }
                        if coach.turns.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("What would you like to record?").font(.title2.weight(.semibold))
                                Text("Describe a meal, add a photo, or record a weigh-in or workout. You can review and correct every estimate.")
                                    .foregroundStyle(Color.diarySecondary)
                            }.padding(.vertical, 24)
                        }
                        if history.startIndex(in: turnIDs) > 0 {
                            Button("Show earlier messages") {
                                guard let first = history.showEarlier(ids: turnIDs) else { return }
                                followLatest = false; followRequested = false
                                position.scrollTo(id: "input-" + first.uuidString, anchor: .top)
                            }
                            .frame(minHeight: 44)
                            .accessibilityIdentifier("coachEarlierMessages")
                        }
                        ForEach(conversationRows) { row in
                            VStack(alignment: .leading, spacing: 0) {
                                switch row.kind {
                                case .input: inputBubble(row.turn)
                                case .reply:
                                    Text(row.turn.assistantText ?? "").textSelection(.enabled).padding(16)
                                        .background(Color.diarySurface, in: RoundedRectangle(cornerRadius: 20))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .accessibilityIdentifier("coachReply")
                                case .actions: turnActions(row.turn)
                                }
                            }
                            .id(row.id)
                            .accessibilityElement(children: .contain)
                        }
                    }.scrollTargetLayout().padding(.vertical, 20)
                } else { ContentUnavailableView("Choose your diary", systemImage: "person.crop.circle", description: Text("Open Settings to choose a private local profile.")) }
            }
            .padding(.horizontal, 20)
            .scrollPosition($position)
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
                if nearBottom && (followLatest || position.isPositionedByUser) {
                    followLatest = true; hasNewMessage = false
                    if scrollPhase == .idle && position.isPositionedByUser { requestFollow() }
                } else if scrollPhase == .interacting || scrollPhase == .decelerating || (position.isPositionedByUser && scrollPhase != .tracking) {
                    followLatest = false
                }
            }
            .onChange(of: coach.turns) { _, _ in newContent() }
            .onChange(of: coach.activity) { _, _ in newContent() }
            .overlay(alignment: .bottom) {
                if hasNewMessage && !followLatest {
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
            if coach.diary.snapshot != nil { companionStrip; composer }
        }
        .background(Color.diaryCanvas)
        .navigationTitle("Coach")
        .toolbarTitleDisplayMode(.inlineLarge)
        .navigationDestination(for: UUID.self) {
            MealDetailView(model: coach.diary, mealID: $0)
                .onAppear { showingDetail = true; reportCompanionContext() }
                .onDisappear { showingDetail = false; reportCompanionContext() }
        }
        .navigationDestination(for: WorkoutDestination.self) {
            WorkoutDetailView(model: coach.diary, sessionID: $0.id)
                .onAppear { showingDetail = true; reportCompanionContext() }
                .onDisappear { showingDetail = false; reportCompanionContext() }
        }
        .sheet(isPresented: $showPhotos) {
            NavigationStack {
                Form { PhotoInput(photos: $coach.draft.photos, preparation: preparation, importFailed: $importFailed) }
                    .navigationTitle("Coach photos")
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showPhotos = false }.frame(minHeight: 44) } }
            }.environment(\.locale, Locale(identifier: "en")).environment(\.layoutDirection, .leftToRight)
        }
        .alert("Could not import photo", isPresented: $importFailed) { Button("OK", role: .cancel) {} } message: { Text("Choose a smaller image or another photo. Your other input is preserved.") }
        .sensoryFeedback(.success, trigger: coach.captureReceipt)
        .onAppear { surfaceVisible = true; reportCompanionContext() }
        .onDisappear { surfaceVisible = false; reportCompanionContext() }
        .onChange(of: [editing, showPhotos, importFailed, showingDetail, companionProcessing, companionRecovery]) { _, _ in reportCompanionContext() }
        .onChange(of: coach.diary.snapshot?.profile.id, initial: true) { _, _ in
            history.reset(ids: turnIDs)
            preparation.cancel(); preparation = PhotoPreparation()
            showPhotos = false; editing = false
            followLatest = true; hasNewMessage = false
            followRequested = false
            position = ScrollPosition(idType: String.self)
            requestFollow()
        }
    }
    private var companionTurn: CoachTurn? {
        coach.turns.first { $0.id == coach.activityTurnID } ?? coach.turns.last
    }
    private var companionRecovery: Bool {
        coach.errorMessage != nil || companionTurn.map {
            [.waitingForConnection, .waitingForNetwork, .needsRetry, .needsClarification].contains($0.state)
        } == true
    }
    private var companionProcessing: Bool {
        !companionRecovery && (coach.isSending || (coach.isWorking &&
            (coach.activity != nil || companionTurn?.state == .analyzing || companionTurn?.state == .captured)))
    }
    private func reportCompanionContext() {
        onCompanionContextChanged(CompanionContext(surface: .coach, isTyping: editing,
            isProcessing: companionProcessing, needsRecovery: companionRecovery,
            playback: surfaceVisible && !showPhotos && !importFailed && !showingDetail ? .animated : .hidden))
    }
    private var companionStrip: some View {
        HStack(alignment: .bottom, spacing: 8) {
            CompanionView(presentation: companionOutput, darkMode: colorScheme == .dark,
                          size: editing || typeSize.isAccessibilitySize ? 88 : 148, runtime: companionRuntime, surface: .coach)
                .frame(width: editing || typeSize.isAccessibilitySize ? 76 : 120,
                       height: editing || typeSize.isAccessibilitySize ? 66 : 108, alignment: .top)
                .clipped()
            VStack(alignment: .leading, spacing: 4) {
                if let error = coach.errorMessage {
                    Text(error).foregroundStyle(Color.diaryError).accessibilityIdentifier("coachError")
                } else {
                    Text(typeSize.isAccessibilitySize ? (companionRecovery ? "Input saved" : companionProcessing ? "Working…" : "Ready") : (companionRecovery ? "Your input is safe here" : companionProcessing ? "Working on your request…" : editing ? "Take your time" : "Ready when you are"))
                        .foregroundStyle(Color.diaryText)
                }
            }
            .font(typeSize.isAccessibilitySize ? .caption : .subheadline)
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(Color.diarySurface, in: RoundedRectangle(cornerRadius: 20))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 14)
        }
        .padding(.horizontal, 20)
        .animation(reduceMotion ? nil : .easeOut(duration: MivuMotion.status), value: coach.errorMessage)
        .animation(reduceMotion ? nil : .easeOut(duration: MivuMotion.status), value: editing)
    }
    private var userScrolling: Bool {
        scrollPhase == .tracking || scrollPhase == .interacting || scrollPhase == .decelerating
    }
    private func isNearBottom(_ geometry: ScrollGeometry) -> Bool {
        geometry.contentSize.height + geometry.contentInsets.bottom - geometry.contentOffset.y - geometry.containerSize.height <= 80
    }
    private func newContent() {
        history.reconcile(ids: turnIDs)
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
            // At large text sizes the linked actions can exceed the viewport; begin at the reply.
            let replyID = typeSize.isAccessibilitySize && coach.turns.last?.assistantText != nil
                ? coach.turns.last.map { "reply-" + $0.id.uuidString } : nil
            withAnimation(reduceMotion ? nil : .easeOut(duration: MivuMotion.coachFollow)) {
                position.scrollTo(id: replyID ?? id, anchor: replyID == nil ? .bottom : .top)
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
    private var turnIDs: [UUID] { coach.turns.map(\.id) }
    private var conversationRows: [ConversationRow] {
        coach.turns.dropFirst(history.startIndex(in: turnIDs)).flatMap { turn in
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
            if !coach.draft.photos.isEmpty { Text("\(coach.draft.photos.count) photos attached").font(.caption).foregroundStyle(Color.diarySecondary) }
            if typeSize.isAccessibilitySize {
                composerInput
                HStack {
                    photoAction
                    Spacer(minLength: 8)
                    send
                }
            } else {
                HStack(alignment: .bottom, spacing: 8) {
                    composerInput
                    photoAction
                    send
                }
            }
            if !coach.connection.planAuthorized && !DiaryLaunch.isCoachInferenceFixture {
                Text("Input saves on this iPhone. Connect ChatGPT in Settings for analysis.")
                    .font(.caption).foregroundStyle(Color.diarySecondary)
            }
        }
        .padding(12)
        .background {
            if reduceTransparency { RoundedRectangle(cornerRadius: 28).fill(Color.diarySurface) }
            else { RoundedRectangle(cornerRadius: 28).fill(.ultraThinMaterial) }
        }
        .overlay { RoundedRectangle(cornerRadius: 28).strokeBorder(Color.diaryRule.opacity(0.5), lineWidth: 0.5) }
        .padding(.horizontal, 16).padding(.bottom, 8)
        .disabled(coach.isSending || coach.diary.isChangingProfile)
    }
    private var composerInput: some View {
        TextField("Message Coach", text: $coach.draft.text, axis: .vertical)
            .lineLimit(1...(typeSize.isAccessibilitySize ? 2 : 5)).focused($editing)
            .accessibilityIdentifier("coachInput")
            .padding(.horizontal, 16).padding(.vertical, 10)
            .frame(minHeight: 48)
            .background(Color.diarySurface, in: RoundedRectangle(cornerRadius: 24))
            .overlay { RoundedRectangle(cornerRadius: 24).strokeBorder(Color.diaryRule.opacity(0.5), lineWidth: 0.5) }
    }
    private var photoAction: some View {
        Button { editing = false; showPhotos = true } label: {
            Image(systemName: "camera.fill").font(.system(size: 19, weight: .medium))
                .frame(width: 48, height: 48)
                .foregroundStyle(Color.diaryText)
                .background(Color.diarySurface, in: Circle())
        }.accessibilityLabel("Add photos").accessibilityIdentifier("coachPhotos")
    }
    private var send: some View {
        Button { editing = false; Task { _ = await coach.send() } } label: {
            Group {
                if coach.isSending { ProgressView() }
                else if typeSize.isAccessibilitySize { Text("Send").font(.headline).fixedSize() }
                else { Image(systemName: "arrow.up").font(.system(size: 22, weight: .semibold)) }
            }
            .frame(minWidth: 48, minHeight: 48)
            .padding(.horizontal, typeSize.isAccessibilitySize ? 12 : 0)
            .background(coach.canSend && preparation.canCapture ? Color.diaryAccent : Color.diaryRule, in: Capsule())
        }
        .foregroundStyle(coach.canSend && preparation.canCapture ? Color.diaryActionText : Color.diarySecondary)
        .disabled(!coach.canSend || !preparation.canCapture)
        .accessibilityLabel("Send").accessibilityIdentifier("coachSend")
    }
    private func inputBubble(_ turn: CoachTurn) -> some View {
        VStack(alignment: .trailing, spacing: 8) {
            VStack(alignment: .leading, spacing: 8) {
                if !turn.text.isEmpty { Text(turn.text).textSelection(.enabled) }
                if !turn.photoIDs.isEmpty { Label("\(turn.photoIDs.count) attached photos", systemImage: "photo").font(.caption) }
            }
            .padding(16).foregroundStyle(Color.white)
            .background(Color.diaryMessage, in: RoundedRectangle(cornerRadius: 20))
            Label("Input saved on this iPhone", systemImage: "internaldrive")
                .font(.caption).foregroundStyle(Color.diarySecondary)
        }.frame(maxWidth: .infinity, alignment: .trailing)
    }
    private func turnActions(_ turn: CoachTurn) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if turn.state != .completed {
                if let activity = coach.activity, coach.activityTurnID == turn.id {
                    CoachActivityView(activity: activity)
                } else {
                    Label(status(turn.state), systemImage: turn.state == .analyzing ? "hourglass" : "clock").font(.subheadline).foregroundStyle(turn.state == .needsRetry ? Color.diaryError : turn.state == .analyzing ? Color.diaryAccent : Color.diaryWarning)
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
                            .font(.subheadline.weight(.semibold)).foregroundStyle(meal.state.color)
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
