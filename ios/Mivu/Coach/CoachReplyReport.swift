import Foundation

/// A frozen selection; its owner stays private and is never part of the email.
struct CoachReplyReport: Equatable, Identifiable, Sendable {
    static let recipient = "support@mivuapp.com"
    static let maximumReplyBytes = 32_768
    static let maximumCommentCharacters = 1_000
    let owner: DiarySelectionOwnership
    let id: UUID
    let replyText: String
    private let appVersion: String
    private let appBuild: String
    private let provider: String
    private let model: String

    enum Reason: String, CaseIterable, Identifiable, Sendable {
        case unsafeAdvice = "Unsafe advice"
        case offensiveContent = "Offensive content"
        case inaccurateAnswer = "Inaccurate answer"
        case other = "Other"
        var id: Self { self }
    }
    enum ValidationError: Error, Equatable { case commentTooLong }
    enum Outcome: Sendable {
        case cancelled, savedDraft, queuedInMail, failed, copied
        var message: String {
            switch self {
            case .cancelled: "Report not sent."
            case .savedDraft: "Draft saved in Mail. Report not sent."
            case .queuedInMail: "Report queued in Mail. Delivery is not confirmed."
            case .failed: "Mail could not send the report. Your review text is still available."
            case .copied: "Report copied. Paste it into your email client and send it yourself. Copying does not send a report."
            }
        }
    }

    init?(owner: DiarySelectionOwnership, exchange: CoachExchangeSummary, appVersion: String, appBuild: String,
          provider: String? = nil, model: String? = nil) {
        guard let reply = exchange.assistantText, !reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              reply.utf8.count <= Self.maximumReplyBytes else { return nil }
        self.owner = owner; id = exchange.id; replyText = reply
        self.appVersion = Self.metadata(appVersion); self.appBuild = Self.metadata(appBuild)
        self.provider = Self.metadata(provider); self.model = Self.metadata(model)
    }

    func isAvailable(selection: DiarySelectionOwnership?, exchange: CoachExchangeSummary?) -> Bool {
        selection == owner && exchange?.id == id && exchange?.assistantText == replyText
    }

    func body(reason: Reason, comment: String) throws -> String {
        guard comment.count <= Self.maximumCommentCharacters, comment.utf8.count <= 4_000 else {
            throw ValidationError.commentTooLong
        }
        let trimmed = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        return """
        Coach reply report
        Reason: \(reason.rawValue)
        App: \(appVersion) (\(appBuild))
        Provider: \(provider)
        Model: \(model)
        Reply reference: \(id.uuidString)
        \(trimmed.isEmpty ? "" : "\nComment:\n\(trimmed)\n")
        Selected reply:
        \(replyText)
        """
    }

    private static func metadata(_ value: String?) -> String {
        let clean = (value ?? "").components(separatedBy: .controlCharacters).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? "Unknown" : String(clean.prefix(128))
    }
}
