import SwiftUI

struct CoachView: View {
    @Bindable var coach: CoachViewModel
    let companionOutput: CompanionOutput
    let companionRuntime: CompanionRuntime
    let onCompanionContextChanged: (CompanionContext) -> Void
    var navigationRequest: CoachNavigationRequest? = nil
    var onNavigationConsumed: (UUID) -> Void = { _ in }
    var openHistory: () -> Void = {}
    let openDestination: (CoachDestination) -> Void
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var surfaceVisible = false
    @State private var showingDetail = false
    @State private var showPhotos = false
    @State private var cameraPresentationID: UUID?
    @State private var retakingPhotoID: UUID?
    @State private var restoreKeyboard = false
    @State private var refreshViewport: (@MainActor () -> Void)?
    @State private var diagnostics = CoachTimelineDiagnostics()
    @State private var selectedRecord: RecordDestination?
    @FocusState private var editing: Bool
    private enum RecordDestination: Hashable, Identifiable {
        case meal(UUID), workout(UUID)
        var id: Self { self }
    }

    private struct ReceiptRefreshKey: Equatable {
        var selection: DiarySelectionOwnership?
        var timelineRevision: Int?
        var diaryGeneration: UInt64
    }
    private var receiptRefreshKey: ReceiptRefreshKey {
        ReceiptRefreshKey(selection: coach.diary.selection, timelineRevision: coach.timeline?.revision,
            diaryGeneration: coach.diary.changeGeneration)
    }

    var body: some View {
        VStack(spacing: 0) {
            if let timeline = coach.timeline, coach.diary.readModel != nil {
                #if DEBUG
                if DiaryLaunch.isCoachHistoryFixture { diagnosticControls }
                #endif
                edge(.earlier, timeline: timeline)
                CoachTimelineView(timeline: timeline, rows: timelineRows(timeline), diagnostics: fixtureDiagnostics,
                    jumpToLatest: jumpToLatestAction(timeline), onViewportRefreshReady: { refreshViewport = $0 }) { row in
                    AnyView(timelineContent(row))
                }
                .dynamicTypeSize(diagnostics.largeText ? .accessibility2 : typeSize)
                .overlay {
                    if timeline.exchanges.isEmpty, timeline.error == nil {
                        ContentUnavailableView("What would you like to record?", systemImage: "text.bubble",
                            description: Text("Describe a meal, add a photo, or record a weigh-in or workout. You can review and correct every estimate."))
                            .allowsHitTesting(false)
                    }
                }
                edge(.later, timeline: timeline)
                if timeline.error != nil {
                    HStack {
                        Text(navigationError(timeline.queryError)).font(.caption).foregroundStyle(Color.diaryError)
                            .accessibilityIdentifier("coachTimelineError")
                        if timeline.queryError == nil {
                            Button("Try again") { Task { await timeline.jumpToLatest() } }.frame(minWidth: 44, minHeight: 44)
                        }
                    }.padding(.horizontal, 20)
                }
            } else if coach.diary.readModel == nil {
                ContentUnavailableView("Choose your diary", systemImage: "person.crop.circle", description: Text("Open Settings to choose a private local profile."))
            } else { ProgressView("Loading conversation").frame(maxWidth: .infinity, maxHeight: .infinity) }
            if coach.diary.readModel != nil { companionStrip; composer }
        }
        .background(Color.diaryCanvas)
        .navigationTitle("Coach").toolbarTitleDisplayMode(.inlineLarge)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Chat history", systemImage: "clock.arrow.circlepath", action: openHistory)
                    .frame(minWidth: 44, minHeight: 44).accessibilityIdentifier("coachHistory")
            }
        }
        .navigationDestination(item: $selectedRecord) { record in
            Group {
                switch record {
                case .meal(let id): MealDetailView(model: coach.diary, mealID: id)
                case .workout(let id): WorkoutDetailView(model: coach.diary, sessionID: id)
                }
            }
            .onAppear { showingDetail = true; reportCompanionContext() }
            .onDisappear { showingDetail = false; reportCompanionContext() }
        }
        .fullScreenCover(isPresented: $showPhotos, onDismiss: {
            if let id = cameraPresentationID { Task { try? await coach.attachmentDraft.endPresentation(id) } }
            cameraPresentationID = nil; retakingPhotoID = nil
            if restoreKeyboard, coach.diary.selection == coach.attachmentDraft.ownership { editing = true }
            restoreKeyboard = false
        }) {
            if let id = cameraPresentationID {
                CoachCameraView(draft: coach.attachmentDraft, presentationID: id, retaking: retakingPhotoID)
                    .environment(\.locale, Locale(identifier: "en")).environment(\.layoutDirection, .leftToRight)
            }
        }
        .sensoryFeedback(.success, trigger: coach.captureReceipt)
        .onAppear {
            surfaceVisible = true; coach.synchronizeDraftOwnership(); reportCompanionContext()
            #if DEBUG
            if DiaryLaunch.isCoachHistoryFixture {
                let diagnosticCoach = coach
                diagnostics.navigationSnapshot = { [weak diagnosticCoach] in diagnosticCoach?.historyNavigationSnapshot ?? [:] }
                diagnostics.focusReplyAction = {
                    guard let owner = coach.diary.selection else { return nil }
                    let reply = "Off-viewport asynchronous reply completed."
                    do {
                        try await coach.diary.store.completeCoachTurn(turnID: CoachUITestInference.historyID(140), assistantText: reply, expectedProfileID: owner.identity.profileID)
                        return reply
                    } catch { return nil }
                }
            }
            #endif
        }
        .task(id: coach.diary.selection) { await coach.connectTimeline() }
        .task(id: receiptRefreshKey) { await coach.refreshLinks() }
        .task(id: navigationRequest?.requestID) {
            guard let request = navigationRequest else { return }
            _ = await coach.seek(request)
            guard !Task.isCancelled, navigationRequest?.requestID == request.requestID else { return }
            onNavigationConsumed(request.requestID)
        }
        .onDisappear { surfaceVisible = false; diagnostics.stop(); reportCompanionContext() }
        .onChange(of: coach.captureReceipt) { _, id in
            if let id, fixtureDiagnostics != nil { diagnostics.expectReply(id, alreadyCompleted: coach.historyFixtureLatest?.id == id && coach.historyFixtureLatest?.state == .completed && coach.historyFixtureLatest?.assistantText != nil) }
        }
        .onChange(of: coach.historyFixtureLatest) { _, turn in
            if let turn, turn.state == .completed, turn.assistantText != nil { diagnostics.replyDidComplete(turn.id) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .coachThumbnailDidPublish)) { event in
            if let id = event.userInfo?["photoID"] as? UUID { diagnostics.thumbnailDidPublish(id) }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIAccessibility.elementFocusedNotification)) { event in
            diagnostics.observeFocusNotification(event)
        }
        .onChange(of: [editing, showPhotos, showingDetail, companionProcessing, companionRecovery]) { _, _ in reportCompanionContext() }
        .onChange(of: coach.diary.selection) { _, _ in
            coach.synchronizeDraftOwnership(); restoreKeyboard = false; showPhotos = false; editing = false; selectedRecord = nil
        }
    }

    private func jumpToLatestAction(_ timeline: CoachTimelineViewModel) -> (@MainActor @Sendable () -> Void)? {
        guard showsLatestAction(timeline) else { return nil }
        let action: @MainActor @Sendable () -> Void = { _ = Task { await timeline.jumpToLatest() } }
        return action
    }
    private func showsLatestAction(_ timeline: CoachTimelineViewModel) -> Bool {
        if case .latest = timeline.window.viewport { return timeline.window.pages.last?.hasLater == true }
        return true
    }
    private var fixtureDiagnostics: CoachTimelineDiagnostics? {
        #if DEBUG
        DiaryLaunch.isCoachHistoryFixture ? diagnostics : nil
        #else
        nil
        #endif
    }
    #if DEBUG
    private var diagnosticControls: some View {
        VStack(spacing: 0) {
            if CoachCorrectionUITestFixture.isEnabled { CoachCorrectionFixtureControls(coach: coach) }
            HStack {
                Button("Earlier", action: diagnostics.earlier).accessibilityIdentifier("historyMeasureEarlier")
                Button("Later", action: diagnostics.later).accessibilityIdentifier("historyMeasureLater")
                Button("Start") { diagnostics.reveal(false) }.accessibilityIdentifier("historyMeasureStart")
                Button("End") { diagnostics.reveal(true) }.accessibilityIdentifier("historyMeasureEnd")
                Button("Text", action: diagnostics.reflow).accessibilityIdentifier("historyMeasureType")
                Button("Photo row", action: diagnostics.revealPhoto).accessibilityIdentifier("historyMeasurePhotoRow")
                Button("Photo") { diagnostics.beginPhoto(); Task { await CoachHistoryPhotoGate.shared.release() } }
                    .accessibilityIdentifier("historyMeasurePhoto")
                Button("Focus", action: diagnostics.armFocus).accessibilityIdentifier("historyMeasureFocus")
            }.buttonStyle(.borderless).font(.caption).frame(minHeight: 44)
            Text("Fixture facts").font(.caption2).accessibilityIdentifier("historyFixtureFacts").accessibilityValue(coach.historyFixtureFacts)
            Text("Measurements").font(.caption2).accessibilityIdentifier("historyMetrics").accessibilityValue(diagnostics.metrics)
        }
    }
    #endif
    private func navigationError(_ value: CoachQueryError?) -> String {
        switch value {
        case .noChatForDay: "No conversation for this diary day."
        case .missingTurn: "This source message is unavailable."
        default: "Could not load this conversation. Try again."
        }
    }
    @ViewBuilder private func edge(_ direction: CoachPageDirection, timeline: CoachTimelineViewModel) -> some View {
        HStack {
            switch timeline.window.edgeState(direction) {
            case .loading: ProgressView(direction == .earlier ? "Loading earlier messages" : "Loading later messages")
            case .available, .failed:
                let failed = if case .failed = timeline.window.edgeState(direction) { true } else { false }
                Button(failed ? "Retry conversation page" : direction == .earlier ? "Load earlier" : "Load later") {
                    refreshViewport?()
                    if direction == .earlier { timeline.loadEarlier(anchor: timeline.window.viewportAnchor) }
                    else { timeline.loadLater(anchor: timeline.window.viewportAnchor) }
                }
                .frame(minHeight: 44)
                .accessibilityIdentifier(failed ? "coachPageRetry" : direction == .earlier ? "coachEarlierMessages" : "coachLaterMessages")
            case .exhausted: Color.clear.accessibilityHidden(true)
            }
        }.font(.subheadline).frame(minHeight: 44, maxHeight: 44)
    }
    private func timelineRows(_ timeline: CoachTimelineViewModel) -> [CoachTimelineRow] {
        var result: [CoachTimelineRow] = []
        var segment = timeline.window.pages.first?.earlierSegment?.segmentID
        for turn in timeline.exchanges {
            if segment != turn.segmentID {
                result.append(CoachTimelineRow(id: .segment(turn.segmentID), date: turn.displayLocalDate))
                segment = turn.segmentID
            }
            result.append(CoachTimelineRow(id: .exchange(turn.id), exchange: turn,
                targets: turn.receipts.map(coach.receiptTarget), activity: coach.activityTurnID == turn.id ? coach.activity : nil,
                fixtureBanner: DiaryLaunch.isCoachInferenceFixture && turn.id == timeline.exchanges.first?.id,
                isHighlighted: coach.highlightedTurnID == turn.id))
        }
        if let empty = timeline.window.latestEmptySegment {
            result.append(CoachTimelineRow(id: .segment(empty.segmentID), date: empty.displayLocalDate))
        }
        return result
    }
    @ViewBuilder private func timelineContent(_ row: CoachTimelineRow) -> some View {
        if let turn = row.exchange {
            VStack(alignment: .leading, spacing: 16) {
                if row.fixtureBanner { Text("Native test fixture — no provider request").font(.caption).foregroundStyle(Color.diaryLeaf).accessibilityIdentifier("coachFixtureBanner") }
                inputBubble(turn)
                if let reply = turn.assistantText {
                    Text(reply).textSelection(.enabled).padding(16)
                        .background(Color.diarySurface, in: RoundedRectangle(cornerRadius: 16))
                        .frame(maxWidth: .infinity, alignment: .leading).accessibilityIdentifier("coachReply")
                }
                turnActions(turn)
            }
            .padding(row.isHighlighted ? 8 : 0)
            .overlay {
                if row.isHighlighted {
                    RoundedRectangle(cornerRadius: 12).stroke(Color.diaryAccent, lineWidth: 2)
                        .allowsHitTesting(false)
                }
            }
            .accessibilityElement(children: .contain).accessibilityIdentifier("coachExchange-" + turn.id.uuidString)
            .accessibilityValue(row.isHighlighted ? "Selected source message" : "")
        } else if let date = row.date {
            HStack { Rectangle().frame(height: 0.5); Text(date).font(.subheadline).fixedSize(); Rectangle().frame(height: 0.5) }
                .foregroundStyle(Color.diarySecondary).padding(.vertical, 8)
                .accessibilityElement(children: .ignore).accessibilityLabel(date).accessibilityAddTraits(.isHeader)
        }
    }
    private var companionRecovery: Bool { coach.companionNeedsRecovery }
    private var companionProcessing: Bool { coach.companionIsProcessing }
    private func reportCompanionContext() {
        onCompanionContextChanged(CompanionContext(surface: .coach, isTyping: editing && !coach.isSending,
            isProcessing: companionProcessing, needsRecovery: companionRecovery,
            playback: surfaceVisible && !showPhotos && !showingDetail ? .animated : .hidden))
    }
    private var companionStrip: some View {
        HStack(alignment: .bottom, spacing: 8) {
            CompanionView(presentation: companionOutput, darkMode: colorScheme == .dark,
                          size: editing || typeSize.isAccessibilitySize ? 88 : 148, runtime: companionRuntime, surface: .coach)
                .frame(width: editing || typeSize.isAccessibilitySize ? 76 : 120,
                       height: editing || typeSize.isAccessibilitySize ? 66 : 108, alignment: .top)
                .clipped()
            VStack(alignment: .leading, spacing: 4) {
                if let error = coach.errorMessage, companionRecovery {
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
            .transaction { $0.animation = nil }
        }
        .padding(.horizontal, 20)
        .animation(reduceMotion ? nil : .easeOut(duration: MivuMotion.status), value: coach.errorMessage)
        .animation(reduceMotion ? nil : .easeInOut(duration: MivuMotion.companionTransition), value: editing)
    }
    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let day = coach.diary.activeDay {
                Text("Logging to " + day.localDate).font(.caption).foregroundStyle(Color.diarySecondary).accessibilityIdentifier("coachDate")
            }
            if let target = coach.diary.readModel?.activeGoal?.targets.kcal {
                Text("\(target.formatted(.number.precision(.fractionLength(0)))) kcal goal").font(.caption)
                    .foregroundStyle(Color.diarySecondary).accessibilityIdentifier("coachGoalSummary")
            }
            if !coach.attachmentDraft.attachments.isEmpty { draftPhotos }
            if coach.attachmentDraft.isPreparing { ProgressView("Preparing photos").font(.caption) }
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
        TextField("Message Coach", text: Binding(get: { coach.attachmentDraft.text }, set: { coach.attachmentDraft.text = $0 }), axis: .vertical)
            .lineLimit(1...(typeSize.isAccessibilitySize ? 2 : 5)).focused($editing)
            .accessibilityIdentifier("coachInput")
            .padding(.horizontal, 16).padding(.vertical, 10)
            .frame(minHeight: 48)
            .background(Color.diarySurface, in: RoundedRectangle(cornerRadius: 24))
            .overlay { RoundedRectangle(cornerRadius: 24).strokeBorder(Color.diaryRule.opacity(0.5), lineWidth: 0.5) }
    }
    private var photoAction: some View {
        Button { openCamera() } label: {
            Image(systemName: "camera.fill").font(.system(size: 19, weight: .medium))
                .frame(width: 48, height: 48)
                .foregroundStyle(Color.diaryText)
                .background(Color.diarySurface, in: Circle())
        }.accessibilityLabel("Add photos").accessibilityIdentifier("coachPhotos")
            .disabled(coach.attachmentDraft.attachments.count + coach.attachmentDraft.reservedAttachmentCount >= 8)
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
            .background(coach.canSend ? Color.diaryAccent : Color.diaryRule, in: Capsule())
        }
        .foregroundStyle(coach.canSend ? Color.diaryActionText : Color.diarySecondary)
        .disabled(!coach.canSend)
        .accessibilityLabel("Send").accessibilityIdentifier("coachSend")
    }
    private var draftPhotos: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 12) {
                ForEach(Array(coach.attachmentDraft.attachments.enumerated()), id: \.element.id) { index, photo in
                    VStack(spacing: 0) {
                        if let image = UIImage(data: photo.data) {
                            Image(uiImage: image).resizable().scaledToFill().frame(width: 88, height: 88).clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 12)).accessibilityLabel("Attached photo \(index + 1)")
                        }
                        HStack {
                            Button("Retake") { openCamera(replacing: photo.id) }.frame(minWidth: 44, minHeight: 44)
                                .accessibilityLabel("Retake photo \(index + 1)")
                            Button("Remove", role: .destructive) { Task { try? await coach.attachmentDraft.remove(photo.id) } }
                                .frame(minWidth: 44, minHeight: 44).accessibilityLabel("Remove photo \(index + 1)")
                        }.font(.caption)
                    }
                }
            }
        }
    }
    private func openCamera(replacing id: UUID? = nil) {
        coach.synchronizeDraftOwnership()
        do {
            cameraPresentationID = try coach.attachmentDraft.beginPresentation()
            retakingPhotoID = id; restoreKeyboard = editing; editing = false; showPhotos = true
        } catch { coach.errorMessage = "Choose your diary before adding photos." }
    }
    private func inputBubble(_ turn: CoachExchangeSummary) -> some View {
        VStack(alignment: .trailing, spacing: 8) {
            VStack(alignment: .leading, spacing: 8) {
                if !turn.text.isEmpty { Text(turn.text).textSelection(.enabled).accessibilityIdentifier("coachText-" + turn.id.uuidString) }
                if !turn.photos.isEmpty {
                    Label("\(turn.photos.count) attached photos", systemImage: "photo").font(.caption)
                    ForEach(turn.photos) { photo in DiaryPhotoPreview(model: coach.diary, reference: photo, height: 140) }
                }
            }
            .padding(16).foregroundStyle(Color.white)
            .background(Color.diaryMessage, in: RoundedRectangle(cornerRadius: 20))
            Label("Input saved on this iPhone", systemImage: "internaldrive")
                .font(.caption).foregroundStyle(Color.diarySecondary)
        }.frame(maxWidth: .infinity, alignment: .trailing)
    }
    private func turnActions(_ turn: CoachExchangeSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if turn.state != .completed {
                if let activity = coach.activity, coach.activityTurnID == turn.id, turn.receipts.isEmpty {
                    CoachActivityView(activity: activity)
                } else {
                    Label(status(turn.state), systemImage: turn.state == .analyzing ? "hourglass" : "clock").font(.subheadline).foregroundStyle(turn.state == .needsRetry ? Color.diaryError : turn.state == .analyzing ? Color.diaryAccent : Color.diaryWarning)
                }
                if turn.needsDayChoice {
                    if let date = coach.previousDayDate(turn) {
                        Button("Use previous waking day: " + date) { Task { await coach.chooseDay(turn.id, usePrevious: true) } }.frame(minHeight: 44).disabled(coach.isWorking)
                    }
                    Button("Use capture date: " + coach.captureDate(turn)) { Task { await coach.chooseDay(turn.id, usePrevious: false) } }.frame(minHeight: 44).disabled(coach.isWorking)
                } else if [.waitingForConnection, .waitingForNetwork, .needsRetry, .needsClarification].contains(turn.state) {
                    Button("Retry analysis") { Task { await coach.retry(turn.id) } }.frame(minHeight: 44).disabled(coach.isWorking).accessibilityIdentifier("coachRetry")
                }
            }
            ForEach(turn.receipts.filter { $0.mealID != nil || $0.workoutID != nil }, id: \.operationKey) { receipt in
                CoachReceiptView(receipt: receipt, target: coach.receiptTarget(receipt)) {
                    if let id = receipt.mealID { selectedRecord = .meal(id) }
                    else if let id = receipt.workoutID { selectedRecord = .workout(id) }
                }
            }
            if let pendingID = turn.pendingMealID, !turn.receipts.contains(where: { $0.mealID == pendingID }),
               let meal = coach.linkedMeals(turn).first(where: { $0.id == pendingID }) {
                Button { selectedRecord = .meal(meal.id) } label: {
                    Label(meal.state == .awaitingReview ? "Needs review" : "Review captured meal", systemImage: "square.and.pencil").frame(minHeight: 44)
                }.accessibilityIdentifier("coachMealLink")
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
