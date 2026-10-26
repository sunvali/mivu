import MessageUI
import SwiftUI

struct CoachReplyReportView: View {
    let report: CoachReplyReport
    @Bindable var diary: DiaryViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var reason: CoachReplyReport.Reason = .unsafeAdvice
    @State private var comment = ""
    @State private var status: String?
    @State private var invalidated = false
    @State private var checking = true
    @State private var mailBody: String?
    @State private var showingMail = false

    private struct ValidationKey: Equatable {
        var owner: DiarySelectionOwnership?
        var generation: UInt64
        var changing: Bool
    }
    private var validationKey: ValidationKey {
        ValidationKey(owner: diary.selection, generation: diary.changeGeneration, changing: diary.isChangingProfile)
    }
    private var ownerIsCurrent: Bool { diary.selection == report.owner && !diary.isChangingProfile }
    private var available: Bool { ownerIsCurrent && !invalidated }
    private var reviewText: String? { try? report.body(reason: reason, comment: comment) }

    var body: some View {
        NavigationStack {
            Group {
                if available { review }
                else {
                    ContentUnavailableView("Reply unavailable", systemImage: "text.bubble",
                        description: Text("The profile or selected reply changed. Close this report and select the reply again."))
                }
            }
            .navigationTitle("Report reply").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() }.frame(minHeight: 44) } }
        }
        .task(id: validationKey) { _ = await validate() }
        .onChange(of: ownerIsCurrent) { _, current in if !current { invalidate() } }
        .sheet(isPresented: $showingMail) {
            if let mailBody {
                CoachReportMailComposer(body: mailBody, isValid: available) { outcome in
                    showingMail = false
                    if available { status = outcome.message }
                }
                .interactiveDismissDisabled()
            }
        }
        .accessibilityIdentifier("coachReportReview")
    }

    private var review: some View {
        Form {
            Section {
                Text("Only this reply and the information below are included. The reply itself may contain personal health information. Review it before sending.")
            }
            Section("Reason") {
                Picker("Reason", selection: $reason) {
                    ForEach(CoachReplyReport.Reason.allCases) { Text($0.rawValue).tag($0) }
                }
                .accessibilityIdentifier("coachReportReason")
            }
            Section("Optional comment") {
                TextField("What should we know?", text: $comment, axis: .vertical).lineLimit(3...6)
                    .accessibilityIdentifier("coachReportComment")
                Text("Up to 1,000 characters. Include only information you want to send to support.")
                    .font(.footnote).foregroundStyle(.secondary)
                if reviewText == nil { Text("Shorten your comment before continuing.").foregroundStyle(Color.diaryError) }
            }
            Section("Outgoing report") {
                Text("To: \(CoachReplyReport.recipient)").textSelection(.enabled)
                Text("Subject: Mivu Coach reply report")
                if let reviewText {
                    Text(reviewText).textSelection(.enabled).accessibilityIdentifier("coachReportPayload")
                }
            }
            Section {
                if MFMailComposeViewController.canSendMail() {
                    Button("Review in Mail", systemImage: "envelope") { prepare(copy: false) }
                        .frame(minHeight: 44).accessibilityIdentifier("coachReportMail")
                    Text("Mail opens for your review. Send the report there when you are ready.").font(.footnote).foregroundStyle(.secondary)
                } else {
                    Text("Mail is not configured. Copy the report and paste it into your own email client addressed to \(CoachReplyReport.recipient). Copying does not send it.")
                    Button("Copy report", systemImage: "doc.on.doc") { prepare(copy: true) }
                        .frame(minHeight: 44).accessibilityIdentifier("coachReportCopy")
                }
            }
            .disabled(checking || reviewText == nil)
            if let status { Section { Text(status).accessibilityIdentifier("coachReportStatus") } }
        }
        .disabled(checking)
    }

    private func prepare(copy: Bool) {
        guard available, !checking, let text = reviewText else { return }
        checking = true
        Task { @MainActor in
            guard await validate(), available else { return }
            if copy {
                UIPasteboard.general.setItems([[UIPasteboard.typeAutomatic: text]], options: [.localOnly: true])
                status = CoachReplyReport.Outcome.copied.message
            } else if MFMailComposeViewController.canSendMail() {
                mailBody = text; showingMail = true
            } else {
                status = "Mail is not configured. Use Copy report to prepare your email."
            }
        }
    }

    @MainActor private func validate() async -> Bool {
        guard available else { invalidate(); return false }
        checking = true
        let key = validationKey
        let exchange = try? await diary.store.coachExchange(turnID: report.id, expectedSelection: report.owner)
        guard !Task.isCancelled else { checking = false; return false }
        guard key == validationKey else { return false }
        guard ownerIsCurrent, report.isAvailable(selection: diary.selection, exchange: exchange) else {
            invalidate(); return false
        }
        checking = false
        return true
    }

    private func invalidate() {
        invalidated = true; showingMail = false; mailBody = nil; status = nil; comment = ""; checking = false
    }
}

private struct CoachReportMailComposer: UIViewControllerRepresentable {
    let body: String
    let isValid: Bool
    let completed: (CoachReplyReport.Outcome) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(completed: completed) }
    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        controller.setToRecipients([CoachReplyReport.recipient])
        controller.setSubject("Mivu Coach reply report")
        controller.setMessageBody(body, isHTML: false)
        return controller
    }
    func updateUIViewController(_ controller: MFMailComposeViewController, context: Context) {
        context.coordinator.completed = completed
        if !isValid { controller.dismiss(animated: false) }
    }

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        var completed: (CoachReplyReport.Outcome) -> Void
        init(completed: @escaping (CoachReplyReport.Outcome) -> Void) { self.completed = completed }
        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: (any Error)?) {
            let outcome: CoachReplyReport.Outcome
            if error != nil { outcome = .failed }
            else {
                switch result {
                case .cancelled: outcome = .cancelled
                case .saved: outcome = .savedDraft
                case .sent: outcome = .queuedInMail
                case .failed: outcome = .failed
                @unknown default: outcome = .failed
                }
            }
            completed(outcome)
        }
    }
}
