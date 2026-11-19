import SwiftUI

@MainActor @Observable final class FeedbackForm {
    enum Phase: Equatable { case editing, sending, failed, sent, mailUnavailable }
    typealias Send = @MainActor (FeedbackReport, URL) async throws -> Void
    typealias OpenMail = @MainActor (URL) async -> Bool

    /// What the person typed, kept while the app runs so leaving the screen does not lose it.
    private static var draft = (message: "", email: "")

    var kind: FeedbackKind
    var message = FeedbackForm.draft.message { didSet { Self.draft.message = message } }
    var email = FeedbackForm.draft.email { didSet { Self.draft.email = email } }
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
    var emailInvalid: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && FeedbackReport(kind: kind, message: "x", email: email, diagnostics: diagnostics, context: nil) == nil
    }
    /// Shown before anything is typed too, so the list never hides something that will be sent.
    var includedLines: [String] { diagnostics.lines(context) }

    func submit(openMail: OpenMail) async {
        guard let report, phase != .sending else { return }
        guard let endpoint else { return await mail(report, openMail) }
        phase = .sending
        do {
            try await send(report, endpoint)
            phase = .sent; message = ""; email = ""
        } catch { phase = .failed }
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
    @State private var copied = 0
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @FocusState private var typing: Bool

    init(kind: FeedbackKind = .bug, context: FeedbackContext? = nil, endpoint: URL? = Feedback.endpoint,
         diagnostics: FeedbackDiagnostics = .current,
         send: @escaping FeedbackForm.Send = { try await Feedback.send($0, to: $1) }) {
        _form = State(initialValue: FeedbackForm(kind: kind, context: context, endpoint: endpoint, diagnostics: diagnostics, send: send))
    }

    var body: some View {
        Form {
            Section {
                picker.listRowBackground(Color.clear).listRowInsets(EdgeInsets())
            }
            Section {
                TextField(prompt, text: $form.message, axis: .vertical)
                    .lineLimit(typeSize.isAccessibilitySize ? 3...10 : 5...10).focused($typing)
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
                    .submitLabel(.done).onSubmit { typing = false }.focused($typing)
                    .frame(minHeight: 44).accessibilityIdentifier("feedbackEmail")
            } footer: {
                if form.emailInvalid {
                    Text("Enter a valid email address, or leave it empty.").foregroundStyle(Color.diaryError)
                        .accessibilityIdentifier("feedbackEmailHint")
                } else {
                    Text("Add it if you'd like a reply.").foregroundStyle(Color.diarySecondary)
                }
            }
            Section {
                Text(form.includedLines.joined(separator: " · ")).font(.subheadline).foregroundStyle(Color.diarySecondary)
                    .accessibilityIdentifier("feedbackIncluded")
            } header: {
                Text("Included with your report").foregroundStyle(Color.diarySecondary)
            } footer: {
                Text("Your diary is never included.").foregroundStyle(Color.diarySecondary)
            }
        }
        .scrollContentBackground(.hidden).background(Color.diaryCanvas)
        .listSectionSpacing(16)
        .scrollDismissesKeyboard(.immediately)
        .safeAreaInset(edge: .bottom) { actions }
        .navigationTitle("Send feedback").navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { typing = false } } }
        .sensoryFeedback(.success, trigger: form.phase) { _, phase in phase == .sent }
        .sensoryFeedback(.success, trigger: copied)
        .task(id: form.phase) {
            guard form.phase == .sent else { return }
            try? await Task.sleep(for: .seconds(1.5))
            if !Task.isCancelled { dismiss() }
        }
    }

    @ViewBuilder private var picker: some View {
        let picker = Picker("Type", selection: $form.kind) {
            ForEach(FeedbackKind.allCases, id: \.self) { Text($0.title).tag($0) }
        }.accessibilityIdentifier("feedbackKind")
        // A segmented control does not grow with the largest text sizes.
        if typeSize.isAccessibilitySize { picker.pickerStyle(.menu).frame(minHeight: 44) }
        else { picker.pickerStyle(.segmented).frame(minHeight: 44) }
    }

    /// Pinned above the keyboard, so the result of a tap is always visible.
    private var actions: some View {
        VStack(spacing: 8) {
            switch form.phase {
            case .sent:
                Label("Thanks! Your report is on its way.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Color.diarySuccess).frame(minHeight: 50).accessibilityIdentifier("feedbackSent")
            default:
                if form.phase == .failed {
                    Text("Couldn't send. Check your connection and try again.").font(.footnote)
                        .foregroundStyle(Color.diaryError).accessibilityIdentifier("feedbackError")
                }
                if form.phase == .mailUnavailable {
                    Text("Mail isn't set up on this device.").font(.footnote).foregroundStyle(Color.diarySecondary)
                    Text("Email us at \(Feedback.supportAddress)").font(.footnote).textSelection(.enabled)
                        .accessibilityIdentifier("feedbackAddress")
                    Button("Copy address", systemImage: "doc.on.doc") { UIPasteboard.general.string = Feedback.supportAddress; copied += 1 }
                        .frame(minHeight: 44).accessibilityIdentifier("feedbackCopyAddress")
                }
                Button { typing = false; Task { await form.submit(openMail: openMail) } } label: {
                    HStack(spacing: 8) {
                        if form.phase == .sending { ProgressView().tint(.white) }
                        Text(sendTitle).fontWeight(.semibold)
                    }.frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).controlSize(.large).buttonBorderShape(.capsule).tint(Color.diaryAccent)
                .disabled(!form.canSend).accessibilityIdentifier("feedbackSend")
                if form.phase == .failed {
                    Button("Send by email instead") { typing = false; Task { await form.sendByEmail(openMail: openMail) } }
                        .frame(minHeight: 44).accessibilityIdentifier("feedbackEmailFallback")
                }
            }
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 20).padding(.vertical, 12)
        .frame(maxWidth: .infinity).background(Color.diaryCanvas)
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
