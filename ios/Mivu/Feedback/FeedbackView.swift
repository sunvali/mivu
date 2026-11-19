import SwiftUI

@MainActor @Observable final class FeedbackForm {
    enum Phase: Equatable { case editing, sending, failed, sent, mailUnavailable }
    typealias Send = @MainActor (FeedbackReport, URL) async throws -> Void
    typealias OpenMail = @MainActor (URL) async -> Bool

    var kind: FeedbackKind
    var message = ""
    var email = ""
    private(set) var phase = Phase.editing
    let context: FeedbackContext?
    let endpoint: URL?
    let diagnostics: FeedbackDiagnostics
    private let send: Send

    init(kind: FeedbackKind, context: FeedbackContext?, endpoint: URL?, diagnostics: FeedbackDiagnostics, send: @escaping Send) {
        self.kind = kind; self.context = context; self.endpoint = endpoint; self.diagnostics = diagnostics; self.send = send
    }

    /// Nil while the fields are invalid.
    var report: FeedbackReport? { FeedbackReport(kind: kind, message: message, email: email, diagnostics: diagnostics, context: context) }
    var canSend: Bool { report != nil && phase != .sending }
    var count: Int { message.trimmingCharacters(in: .whitespacesAndNewlines).utf16.count }
    var overLimit: Bool { count > Feedback.messageLimit }

    func submit(openMail: OpenMail) async {
        guard let report, phase != .sending else { return }
        guard let endpoint else { return await mail(report, openMail) }
        phase = .sending
        do { try await send(report, endpoint); phase = .sent } catch { phase = .failed }
    }

    func sendByEmail(openMail: OpenMail) async {
        guard let report, phase != .sending else { return }
        await mail(report, openMail)
    }

    /// Opening a draft is not sending, so this never reaches `.sent`.
    private func mail(_ report: FeedbackReport, _ openMail: OpenMail) async {
        phase = await openMail(Feedback.mailto(report)) ? .editing : .mailUnavailable
    }
}

struct FeedbackView: View {
    @State private var form: FeedbackForm
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @FocusState private var messageFocused: Bool

    init(kind: FeedbackKind = .bug, context: FeedbackContext? = nil, endpoint: URL? = Feedback.endpoint,
         diagnostics: FeedbackDiagnostics = .current,
         send: @escaping FeedbackForm.Send = { try await Feedback.send($0, to: $1) }) {
        _form = State(initialValue: FeedbackForm(kind: kind, context: context, endpoint: endpoint, diagnostics: diagnostics, send: send))
    }

    var body: some View {
        Form {
            Section {
                Picker("Type", selection: $form.kind) {
                    ForEach(FeedbackKind.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented).frame(minHeight: 44).accessibilityIdentifier("feedbackKind")
                TextField(prompt, text: $form.message, axis: .vertical)
                    .lineLimit(5...12).focused($messageFocused)
                    .accessibilityLabel("Message").accessibilityIdentifier("feedbackMessage")
            } footer: {
                if form.count > Feedback.messageLimit - 400 {
                    Text("\(form.count) of \(Feedback.messageLimit) characters")
                        .foregroundStyle(form.overLimit ? Color.diaryError : Color.diarySecondary)
                        .accessibilityIdentifier("feedbackCount")
                }
            }
            Section {
                TextField("Email (optional)", text: $form.email)
                    .textContentType(.emailAddress).keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .frame(minHeight: 44).accessibilityIdentifier("feedbackEmail")
            } footer: { Text("Add it if you'd like a reply.") }
            Section {
                ForEach(form.report?.includedLines ?? form.diagnostics.lines, id: \.self) {
                    Text($0).font(.subheadline).foregroundStyle(Color.diarySecondary)
                }
            } header: { Text("Included with your report") } footer: { Text("Your diary is never included.") }
            Section {
                switch form.phase {
                case .sent:
                    Label("Thanks! Your report is on its way.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Color.diarySuccess).frame(minHeight: 44).accessibilityIdentifier("feedbackSent")
                default:
                    if form.phase == .failed {
                        Text("Couldn't send. Check your connection and try again.")
                            .foregroundStyle(Color.diaryError).accessibilityIdentifier("feedbackError")
                    }
                    Button { Task { await form.submit(openMail: openMail) } } label: {
                        HStack {
                            Text(sendTitle).fontWeight(.semibold)
                            if form.phase == .sending { Spacer(); ProgressView() }
                        }.frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .disabled(!form.canSend).accessibilityIdentifier("feedbackSend")
                    if form.phase == .failed {
                        Button("Send by email instead") { Task { await form.sendByEmail(openMail: openMail) } }
                            .frame(minHeight: 44).accessibilityIdentifier("feedbackEmailFallback")
                    }
                    if form.phase == .mailUnavailable {
                        Text("Email us at \(Feedback.supportAddress)").textSelection(.enabled)
                            .frame(minHeight: 44).accessibilityIdentifier("feedbackAddress")
                    }
                }
            }
        }
        .scrollContentBackground(.hidden).background(Color.diaryCanvas)
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Send feedback").navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .sensoryFeedback(.success, trigger: form.phase) { _, phase in phase == .sent }
        .task(id: form.phase) {
            guard form.phase == .sent else { return }
            messageFocused = false
            try? await Task.sleep(for: .seconds(1.5))
            if !Task.isCancelled { dismiss() }
        }
    }

    private var prompt: String {
        switch form.kind {
        case .bug: String(localized: "What happened, and what did you expect?")
        case .idea: String(localized: "What would make Mivu better?")
        case .question: String(localized: "What would you like to know?")
        }
    }
    private var sendTitle: String {
        if form.endpoint == nil { return String(localized: "Send by email") }
        return form.phase == .failed ? String(localized: "Try Again") : String(localized: "Send")
    }
    private func openMail(_ url: URL) async -> Bool {
        await withCheckedContinuation { done in openURL(url) { done.resume(returning: $0) } }
    }
}
