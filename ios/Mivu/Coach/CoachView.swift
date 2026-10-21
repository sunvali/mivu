import AVFoundation
import SwiftUI

struct CoachView: View {
    @Bindable var coach: CoachViewModel
    let companionOutput: CompanionOutput
    let companionRuntime: CompanionRuntime
    let onCompanionContextChanged: (CompanionContext) -> Void
    var onCompanionTouch: (CompanionTouch) -> Void = { _ in }
    var navigationRequest: CoachNavigationRequest? = nil
    var onNavigationConsumed: (UUID) -> Void = { _ in }
    var openHistory: () -> Void = {}
    let openDestination: (CoachDestination) -> Void
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var surfaceVisible = false
    @State private var showingDetail = false
    @State private var showPhotos = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var voice = CoachVoiceInput()
    @State private var cameraPresentationID: UUID?
    @State private var retakingPhotoID: UUID?
    @State private var restoreKeyboard = false
    @State private var refreshViewport: (@MainActor () -> Void)?
    @State private var requestAccessibilityPage: CoachTimelineView.AccessibilityPageRequest?
    @State private var diagnostics = CoachTimelineDiagnostics()
    @State private var selectedRecord: RecordDestination?
    @AppStorage("morningCardDismissedDay") private var dismissedMorningDay = ""
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
                CoachTimelineView(timeline: timeline, rows: timelineRows(timeline), diagnostics: fixtureDiagnostics,
                    jumpToLatest: jumpToLatestAction(timeline), onViewportRefreshReady: { refreshViewport = $0 },
                    onAccessibilityPageRequestReady: { requestAccessibilityPage = $0 },
                    onReply: { turn in reply(to: turn, fromPip: turn.assistantText != nil) }) { row in
                    AnyView(timelineContent(row))
                }
                .dynamicTypeSize(diagnostics.largeText ? .accessibility2 : typeSize)
                .overlay {
                    if timeline.exchanges.isEmpty, timeline.error == nil {
                        ContentUnavailableView("What would you like to record?", systemImage: "text.bubble",
                            description: Text("Describe a meal, add a photo, or record a weigh-in or workout. You can review and correct every estimate. Coach gives estimates, not medical advice."))
                            .allowsHitTesting(false)
                    }
                }
                .overlay(alignment: .top) { edge(.earlier, timeline: timeline) }
                .overlay(alignment: .bottom) { edge(.later, timeline: timeline) }
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
            // The composer takes its full height first (up to four lines); the timeline above gives way.
            if coach.diary.readModel != nil { composer.fixedSize(horizontal: false, vertical: true) }
        }
        .background(Color.diaryCanvas)
        .navigationTitle("Coach").toolbarTitleDisplayMode(.inlineLarge)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Chat history", systemImage: "clock.arrow.circlepath", action: openHistory)
                    .frame(minWidth: 44, minHeight: 44).accessibilityIdentifier("coachHistory")
                    .accessibilityActions {
                        if let timeline = coach.timeline {
                            accessibilityPageAction(.earlier, timeline: timeline)
                            accessibilityPageAction(.later, timeline: timeline)
                        }
                    }
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
            if request.target != nil { _ = await coach.seek(request) }
            if let draft = request.draft, !Task.isCancelled { coach.prefill(draft) }
            if let reply = request.reply, !Task.isCancelled, coach.startReply(reply) { editing = true }
            guard !Task.isCancelled, navigationRequest?.requestID == request.requestID else { return }
            onNavigationConsumed(request.requestID)
        }
        .onDisappear { surfaceVisible = false; diagnostics.stop(); stopListening(); reportCompanionContext() }
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
        .onChange(of: [editing, showPhotos, showingDetail, companionProcessing, companionRecovery, listening]) { _, _ in reportCompanionContext() }
        .onChange(of: editing) { _, typing in if typing { stopListening() } } // typed edits must not be overwritten by later speech
        // Only background stops listening: permission alerts briefly make the scene inactive.
        .onChange(of: scenePhase) { _, phase in if phase == .background { stopListening() } }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { _ in stopListening() }
        // A route change (headphones, Bluetooth) stops the audio engine underneath us.
        .onReceive(NotificationCenter.default.publisher(for: .AVAudioEngineConfigurationChange)) { _ in stopListening() }
        .sensoryFeedback(trigger: listening) { _, on in on ? .start : .stop }
        .onChange(of: CompanionContext.draftSignal(coach.attachmentDraft.text.count)) { _, _ in reportCompanionContext() }
        .onChange(of: coach.diary.selection) { _, _ in
            coach.synchronizeDraftOwnership(); restoreKeyboard = false; showPhotos = false; editing = false; selectedRecord = nil
            stopListening()
        }
    }

    @ViewBuilder private func accessibilityPageAction(_ direction: CoachPageDirection, timeline: CoachTimelineViewModel) -> some View {
        switch timeline.window.edgeState(direction) {
        case .available:
            Button(direction == .earlier ? "Load earlier messages" : "Load later messages") {
                _ = requestAccessibilityPage?(direction)
            }
        case .failed:
            Button(direction == .earlier ? "Retry earlier messages" : "Retry later messages") {
                _ = requestAccessibilityPage?(direction)
            }
        case .loading, .exhausted: EmptyView()
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
        switch timeline.window.edgeState(direction) {
        case .loading:
            ProgressView(direction == .earlier ? "Loading earlier messages" : "Loading later messages")
                .font(.subheadline).padding(.vertical, 4).allowsHitTesting(false)
        case .failed:
            Button(direction == .earlier ? "Retry earlier messages" : "Retry later messages") {
                refreshViewport?()
                if direction == .earlier { timeline.loadEarlier(anchor: timeline.window.viewportAnchor) }
                else { timeline.loadLater(anchor: timeline.window.viewportAnchor) }
            }
            .font(.subheadline).frame(minHeight: 44).buttonStyle(.glass)
            .accessibilityIdentifier("coachPageRetry")
        case .available, .exhausted: EmptyView()
        }
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
                targets: turn.receipts.map(coach.receiptTarget), questionMeals: coach.linkedMeals(turn), activity: coach.activityTurnID == turn.id ? coach.activity : nil,
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
            VStack(alignment: .leading, spacing: 20) {
                if row.fixtureBanner { Text("Native test fixture — no provider request").font(.caption).foregroundStyle(Color.diaryLeaf).accessibilityIdentifier("coachFixtureBanner") }
                inputBubble(turn)
                VStack(alignment: .leading, spacing: 12) {
                    if let answer = turn.assistantText {
                        Text(answer).font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 12))
                            .contextMenu { messageActions(turn, fromPip: true) }
                            .accessibilityAction(named: "Reply") { reply(to: turn, fromPip: true) }
                            .accessibilityIdentifier("coachReply")
                    }
                    turnActions(turn)
                }
            }
            .padding(.vertical, 12)
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
        onCompanionContextChanged(CompanionContext(surface: .coach, isTyping: (editing || listening) && !coach.isSending,
            isProcessing: companionProcessing, needsRecovery: companionRecovery,
            playback: surfaceVisible && !showPhotos && !showingDetail ? .animated : .hidden,
            draftLength: coach.attachmentDraft.text.count))
    }
    private var companionStrip: some View {
        HStack(alignment: .center, spacing: 12) {
            // Character sheet: the crop's bottom is the bar line his paws rest on, here the field's top edge.
            CompanionView(presentation: companionOutput, darkMode: colorScheme == .dark,
                          size: typeSize.isAccessibilitySize ? 76 : 112, runtime: companionRuntime, surface: .coach,
                          onTouch: onCompanionTouch)
            VStack(alignment: .leading, spacing: 4) {
                if let day = coach.diary.activeDay {
                    Text("Logging to " + day.localDate).font(.caption).foregroundStyle(Color.diarySecondary)
                        .accessibilityIdentifier("coachDate")
                }
                if let target = coach.diary.readModel?.activeGoal?.targets.kcal {
                    Text("\(target.formatted(.number.precision(.fractionLength(0)))) kcal goal").font(.caption)
                        .foregroundStyle(Color.diarySecondary).accessibilityIdentifier("coachGoalSummary")
                }
                if let error = coach.errorMessage, companionRecovery {
                    Text(error).foregroundStyle(Color.diaryError).accessibilityIdentifier("coachError")
                } else if companionRecovery || companionProcessing {
                    Text(companionRecovery ? "Your input is safe here" : "Working on your request…")
                        .foregroundStyle(Color.diaryText)
                }
            }
            .font(.subheadline).fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .transaction { $0.animation = nil }
        }
        .accessibilityElement(children: .contain).accessibilityIdentifier("coachCompanionStrip")
    }
    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !editing, let day = coach.diary.activeDay, let recap = coach.diary.morningRecap, coach.diary.todaysMeals.isEmpty,
               dismissedMorningDay != day.id.uuidString {
                MorningCheckInCard(model: coach.diary, day: day, previous: recap.previous, previousTarget: recap.target,
                                   todayWeight: coach.diary.readModel?.weight, compact: true,
                                   onTellCoach: { coach.attachmentDraft.text = "My weight this morning is "; editing = true }) {
                    withAnimation(.snappy) { dismissedMorningDay = day.id.uuidString }
                }.transition(.opacity)
            }
            if showsStarters { starters }
            if !coach.attachmentDraft.attachments.isEmpty { draftPhotos }
            if coach.attachmentDraft.isPreparing { ProgressView("Preparing photos").font(.caption) }
            HStack(alignment: .bottom, spacing: 8) {
                // Pip stands on the left of the field's flat top edge, never on the round camera.
                VStack(alignment: .leading, spacing: 0) {
                    companionStrip
                    composerInput
                }
                photoAction
            }
            if let note = voice.note {
                Text(note).font(.caption).foregroundStyle(Color.diarySecondary).accessibilityIdentifier("coachVoiceNote")
            }
            if !coach.connection.planAuthorized && !DiaryLaunch.isCoachInferenceFixture {
                HStack(spacing: 4) {
                    Text("Input saves on this iPhone.").foregroundStyle(Color.diarySecondary)
                    ChatGPTConnectButton(connection: coach.connection, title: "Connect ChatGPT for analysis")
                        .fontWeight(.semibold).foregroundStyle(Color.diaryAccent).frame(minHeight: 44)
                }
                .font(.caption)
            }
        }
        .padding(.horizontal, 20).padding(.top, 4).padding(.bottom, 8)
        .animation(reduceMotion ? nil : .snappy, value: coach.attachmentDraft.reply)
        .sensoryFeedback(.selection, trigger: coach.attachmentDraft.reply) { $1 != nil }
        .disabled(coach.isSending || coach.diary.isChangingProfile)
        .animation(reduceMotion ? nil : .snappy, value: showsStarters)
    }
    private var composerInput: some View {
        // A reply quote sits inside the field's top, as in Messages. Below it, one trailing slot:
        // mic while empty, Send once there is something to send.
        VStack(alignment: .leading, spacing: 0) {
            if let reply = coach.attachmentDraft.reply { replyBar(reply) }
            HStack(alignment: .bottom, spacing: 0) {
                // Stacked, not overlaid, so the field grows to fit the words plus the wave while listening.
                ZStack(alignment: .leading) {
                    TextField("Describe a meal…", text: Binding(get: { coach.attachmentDraft.text }, set: { coach.attachmentDraft.text = $0 }),
                              prompt: Text(listening ? "" : "Describe a meal…"), axis: .vertical)
                        // Grows to four lines (three at accessibility sizes), then scrolls inside the field.
                        .lineLimit(1...(typeSize.isAccessibilitySize ? 3 : 4)).focused($editing)
                        .accessibilityIdentifier("coachInput")
                        .padding(.leading, 16).padding(.vertical, 10)
                        // Hide only the text while listening; a transparent field would stop receiving the tap that switches to typing.
                        .foregroundStyle(listening ? Color.clear : Color.primary)
                    if listening { listeningText }
                }
                .frame(minHeight: 48)
                Group { if showsSend { send } else { voiceAction } }
                    .transition(.opacity).padding(.trailing, 2)
            }
            .animation(reduceMotion ? nil : .snappy, value: showsSend)
        }
        .background(Color.diarySurface, in: RoundedRectangle(cornerRadius: 24))
        .overlay { RoundedRectangle(cornerRadius: 24).strokeBorder(Color.diaryRule.opacity(0.5), lineWidth: 0.5) }
    }
    private var photoAction: some View {
        Button { openCamera() } label: {
            Image(systemName: "camera.fill").font(.system(size: 19, weight: .medium))
                .frame(minWidth: 44, minHeight: 44)
        }.accessibilityLabel("Add photos").accessibilityIdentifier("coachPhotos")
            .buttonStyle(.glass).buttonBorderShape(.circle)
            .disabled(coach.attachmentDraft.attachments.count + coach.attachmentDraft.reservedAttachmentCount >= 8)
    }
    private var listening: Bool { voice.phase == .listening }
    private var showsSend: Bool { voice.phase == .idle && (coach.isSending || coach.attachmentDraft.isValid) }
    private var showsStarters: Bool {
        coach.timeline?.exchanges.isEmpty == true && !coach.attachmentDraft.isValid && !editing && voice.phase == .idle
    }
    private var starters: some View {
        // Each starter fills the draft for review; nothing is sent until the user taps Send.
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach([("Log breakfast", "For breakfast I had "), ("Log my weight", "My weight this morning is "),
                         ("How am I doing today?", "How am I doing today?")], id: \.0) { title, draft in
                    Button(title) { coach.attachmentDraft.text = draft; editing = true }
                        .font(.subheadline).controlSize(.large)
                        .buttonStyle(.glass).accessibilityIdentifier("coachStarter")
                }
            }
        }
        // Scrolls under the composer's side margins so the last chip reads as more, not as clipped.
        .contentMargins(.horizontal, 20, for: .scrollContent).padding(.horizontal, -20)
        .scrollIndicators(.hidden).transition(.opacity)
    }
    /// While listening, the words stream in with a three-line sound wave as their cursor.
    /// Taps fall through to the hidden field, so tapping to type stops listening.
    private var listeningText: some View {
        // The wave sits below the baseline so its middle lines up with the middle of the letters.
        Text("\(coach.attachmentDraft.text) \(Text(waveImage(voice.levels)).baselineOffset(-3))")
            .lineLimit(typeSize.isAccessibilitySize ? 3 : 4).truncationMode(.head)
            .padding(.leading, 16).padding(.vertical, 10)
            .allowsHitTesting(false).accessibilityHidden(true)
    }
    private func waveImage(_ levels: [Float]) -> Image {
        let size = CGSize(width: 15, height: 16)
        let image = UIGraphicsImageRenderer(size: size).image { _ in
            UIColor(Color.diaryAccent).resolvedColor(with: UITraitCollection(userInterfaceStyle: colorScheme == .dark ? .dark : .light)).setFill()
            for (index, level) in levels.enumerated() {
                let height = 4 + CGFloat(reduceMotion ? 0.5 : level) * (size.height - 4)
                UIBezierPath(roundedRect: CGRect(x: CGFloat(index) * 6, y: (size.height - height) / 2, width: 3, height: height),
                             cornerRadius: 1.5).fill()
            }
        }
        return Image(decorative: image.cgImage!, scale: image.scale)
    }
    private var voiceAction: some View {
        Button {
            if voice.phase == .idle {
                coach.synchronizeDraftOwnership(); editing = false
                let owner = coach.attachmentDraft.ownership
                Task {
                    await voice.start(appendingTo: coach.attachmentDraft.text) { text in
                        // Final words can arrive after a profile switch; they belong only to the draft they started in.
                        // Once the person is typing, late final words must not overwrite what they type.
                        if coach.attachmentDraft.ownership == owner, !editing { coach.attachmentDraft.text = text }
                    }
                }
            } else { stopListening() }
        } label: {
            Group {
                if voice.phase == .preparing { ProgressView() }
                else {
                    Image(systemName: listening ? "stop.fill" : "mic.fill").font(.system(size: 19, weight: .medium))
                        .symbolEffect(.pulse, isActive: listening && !reduceMotion)
                }
            }.frame(minWidth: 44, minHeight: 48).contentShape(Rectangle())
        }
        .accessibilityLabel(voice.phase == .idle ? "Speak your meal" : "Stop listening").accessibilityIdentifier("coachVoice")
        .buttonStyle(.plain).foregroundStyle(listening ? Color.diaryError : Color.diaryAccent)
    }
    private func stopListening() { Task { await voice.stop() } }
    private var send: some View {
        Button { editing = false; Task { await voice.stop(); _ = await coach.send() } } label: {
            Group {
                if coach.isSending { ProgressView() }
                else {
                    Image(systemName: "arrow.up").font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 34, height: 34).background(Color.diaryAccent, in: Circle())
                }
            }
            .frame(minWidth: 44, minHeight: 48).contentShape(Rectangle())
        }
        .buttonStyle(.plain).opacity(coach.canSend || coach.isSending ? 1 : 0.4)
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
    @ViewBuilder private func messageActions(_ turn: CoachExchangeSummary, fromPip: Bool) -> some View {
        Button("Reply", systemImage: "arrowshape.turn.up.left") { reply(to: turn, fromPip: fromPip) }
        let text = fromPip ? turn.assistantText ?? "" : turn.text
        if !text.isEmpty { Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = text } }
    }
    private func reply(to turn: CoachExchangeSummary, fromPip: Bool) {
        coach.reply(to: turn, fromPip: fromPip); editing = true
    }
    private func replyBar(_ reply: CoachReply) -> some View {
        HStack(spacing: 4) {
            CoachReplyQuote(reply: reply, title: reply.composerTitle)
            Button { coach.attachmentDraft.reply = nil } label: {
                Image(systemName: "xmark.circle.fill").font(.title3).symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.diarySecondary)
                    .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.borderless).accessibilityLabel("Cancel reply").accessibilityIdentifier("coachReplyCancel")
        }
        .padding(.leading, 10).padding(.vertical, 2)
        .background(Color.diaryAccent.opacity(0.07), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding([.horizontal, .top], 5)
        .accessibilityElement(children: .contain).accessibilityIdentifier("coachReplyBar")
        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
    }
    private func openQuote(_ reply: CoachReply) {
        let target: CoachSeekTarget
        switch reply.target {
        case .meal(let id), .item(let id, _): selectedRecord = .meal(id); return
        case .message(let id, _): target = .turn(id)
        case .day(let id): target = .day(id)
        }
        guard let identity = coach.diary.selection?.identity else { return }
        Task { _ = await coach.seek(CoachNavigationRequest(identity: identity, target: target, requestID: UUID())) }
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
                if let reply = turn.reply {
                    Button { openQuote(reply) } label: {
                        CoachReplyQuote(reply: reply, title: reply.author, inMessage: true)
                            .padding(.horizontal, 10).padding(.vertical, 7).frame(minHeight: 44)
                            .background(Color.black.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain).accessibilityHint("Shows the original")
                    .accessibilityIdentifier("coachQuote-" + turn.id.uuidString)
                }
                if !turn.text.isEmpty { Text(turn.text).font(.body).accessibilityIdentifier("coachText-" + turn.id.uuidString) }
                if !turn.photos.isEmpty {
                    Label("\(turn.photos.count) attached photos", systemImage: "photo").font(.caption)
                    ForEach(turn.photos) { photo in DiaryPhotoPreview(model: coach.diary, reference: photo, height: 140) }
                }
            }
            .padding(16).foregroundStyle(Color.white)
            .background(Color.diaryMessage, in: RoundedRectangle(cornerRadius: 20))
            .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 20))
            .contextMenu { messageActions(turn, fromPip: false) }
            .accessibilityAction(named: "Reply") { reply(to: turn, fromPip: false) }
            Label("Input saved on this iPhone", systemImage: "internaldrive")
                .font(.caption).foregroundStyle(Color.diarySecondary)
        }.frame(maxWidth: .infinity, alignment: .trailing)
    }
    private func turnActions(_ turn: CoachExchangeSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let question = turn.question, !question.candidates.isEmpty, turn.id == coach.timeline?.exchanges.last?.id {
                CoachQuestionChips(question: question, meals: coach.linkedMeals(turn), model: coach.diary) { target, label in
                    Task { await coach.answer(target, label: label) }
                }.disabled(coach.isWorking)
            }
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
            if turn.incomplete == true {
                Text("Couldn't finish the rest").font(.subheadline).foregroundStyle(Color.diarySecondary)
                Button("Retry") { Task { await coach.finishRest(of: turn) } }.frame(minHeight: 44).disabled(coach.isWorking).accessibilityIdentifier("coachFinishRest")
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
