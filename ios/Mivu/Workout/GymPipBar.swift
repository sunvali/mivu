import SwiftUI

/// "Tell Pip" inside the gym: a message goes to the same Coach conversation, Pip's reply shows above the bar,
/// and a change to this workout can be undone here. The camera names a machine, as the exercise picker's does.
struct GymPipBar: View {
    let coach: CoachViewModel
    let model: LiveWorkoutModel
    let onCamera: (() -> Void)?
    @State private var text = ""
    @State private var voice = CoachVoiceInput()
    @State private var working = false
    @State private var reply: Reply?
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Reply: Equatable {
        var id = UUID()
        var text: String
        var undo: [WorkoutExercise]?
    }

    var body: some View {
        VStack(spacing: 8) {
            if let reply { card(reply) }
            HStack(spacing: 4) {
                TextField("Tell Pip… 3 × 10 at 60", text: $text, axis: .vertical)
                    .lineLimit(1...3).submitLabel(.send).focused($focused)
                    .onSubmit(send)
                    .padding(.leading, 16).frame(minHeight: 44)
                    .accessibilityLabel("Tell Pip").accessibilityIdentifier("gymPipInput")
                if working {
                    ProgressView().frame(width: 44, height: 44).accessibilityLabel("Pip is working")
                } else if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    icon("arrow.up.circle.fill", label: "Send", id: "gymPipSend", action: send)
                } else {
                    icon(voice.phase == .idle ? "mic" : "stop.circle.fill", label: voice.phase == .idle ? "Speak to Pip" : "Stop", id: "gymPipMic") {
                        Task {
                            if voice.phase == .idle { await voice.start(appendingTo: text) { text = $0 } } else { await voice.stop() }
                        }
                    }
                    if let onCamera { icon("camera", label: "Photo of a machine", id: "gymPipCamera", action: onCamera) }
                }
            }
            .padding(.trailing, 4)
            .background(Color.diarySurface, in: .capsule)
            .overlay { Capsule().strokeBorder(Color.diaryRule, lineWidth: 1) }
        }
        .animation(reduceMotion ? nil : .snappy, value: reply)
    }

    private func icon(_ symbol: String, label: LocalizedStringKey, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.title3.weight(.semibold)).foregroundStyle(Color.diaryAccent).frame(width: 44, height: 44)
        }
        .buttonStyle(.plain).accessibilityLabel(label).accessibilityIdentifier(id)
    }

    private func card(_ reply: Reply) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "sparkles").foregroundStyle(Color.diaryAccent).accessibilityHidden(true)
            Text(reply.text).font(.subheadline).foregroundStyle(Color.diaryText).frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("gymPipReply")
            if let undo = reply.undo {
                Button("Undo") { Task { await model.restoreExercises(undo); self.reply = nil } }
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Color.diaryAccent).frame(minWidth: 44, minHeight: 44)
                    .accessibilityIdentifier("gymPipUndo")
            }
            Button { self.reply = nil } label: { Image(systemName: "xmark").font(.footnote.weight(.semibold)).foregroundStyle(Color.diarySecondary).frame(width: 44, height: 44) }
                .buttonStyle(.plain).accessibilityLabel("Close")
        }
        .padding(.leading, 14)
        .background(Color.diarySummarySurface, in: .rect(cornerRadius: 18))
        .task(id: reply.id) {
            AccessibilityNotification.Announcement(reply.text).post()
            // Long enough to read and undo; a new message replaces it sooner.
            try? await Task.sleep(for: .seconds(10))
            if self.reply?.id == reply.id { self.reply = nil }
        }
    }

    private func send() {
        let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty, !working, let owner = coach.diary.selection else { return }
        text = ""; focused = false; working = true; reply = nil
        Task {
            defer { working = false }
            if voice.phase != .idle { await voice.stop() }
            let before = model.session.exercises, id = UUID()
            do {
                try await coach.captureExternal(profileID: owner.identity.profileID, message, submissionID: id, capturedAt: Date())
            } catch {
                text = message
                reply = Reply(text: String(localized: "Couldn't send that. Try again."))
                return
            }
            let summary = await finished(id, owner: owner)
            await model.reloadFromStore()
            let changed = model.session.exercises != before
            reply = Reply(text: summary.flatMap(Self.line) ?? String(localized: "Pip will answer in Coach."), undo: changed ? before : nil)
        }
    }

    /// The turn once Pip is done with it, or nil while it still waits (offline, or longer than a minute).
    private func finished(_ id: UUID, owner: DiarySelectionOwnership) async -> CoachExchangeSummary? {
        for _ in 0..<120 {
            if let summary = try? await coach.diary.store.coachExchange(turnID: id, expectedSelection: owner),
               summary.state != .captured, summary.state != .analyzing { return summary }
            try? await Task.sleep(for: .milliseconds(500))
        }
        return nil
    }

    private static func line(_ summary: CoachExchangeSummary) -> String? {
        switch summary.state {
        case .waitingForConnection, .waitingForNetwork: String(localized: "Pip will answer when you're back online.")
        case .needsRetry: String(localized: "Pip couldn't answer. Try again in Coach.")
        default: summary.assistantText.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 }
        }
    }
}
