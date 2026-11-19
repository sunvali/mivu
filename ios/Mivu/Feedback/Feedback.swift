import UIKit

enum FeedbackKind: String, Codable, CaseIterable, Sendable {
    case bug, idea, question
    var title: String {
        switch self {
        case .bug: String(localized: "Bug")
        case .idea: String(localized: "Idea")
        case .question: String(localized: "Question")
        }
    }
}

/// A closed set of codes, so a report never carries raw error text or diary content.
enum FeedbackContext: String, Codable, Sendable, Identifiable {
    var id: String { rawValue }
    case coachNetwork = "coach_network", coachSession = "coach_session", coachOther = "coach_other"
    init(_ state: CoachTurnState) {
        switch state {
        case .waitingForNetwork: self = .coachNetwork
        case .waitingForConnection: self = .coachSession
        default: self = .coachOther
        }
    }
}

struct FeedbackDiagnostics: Equatable, Sendable {
    var appVersion, build, os, device, language: String

    @MainActor static var current: FeedbackDiagnostics {
        var system = utsname(); uname(&system)
        let machine = withUnsafeBytes(of: &system.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        let info = Bundle.main.infoDictionary
        return FeedbackDiagnostics(
            appVersion: info?["CFBundleShortVersionString"] as? String ?? "?",
            build: info?["CFBundleVersion"] as? String ?? "?",
            os: UIDevice.current.systemVersion, device: machine,
            language: Bundle.main.preferredLocalizations.first ?? "en")
    }
    var lines: [String] {
        ["Mivu \(appVersion) (\(build))", "iOS \(os)",
         String(localized: "Device: \(device)"), String(localized: "Language: \(language)")]
    }
}

struct FeedbackReport: Encodable, Equatable, Sendable {
    var kind: FeedbackKind
    var message: String
    var email: String?
    var appVersion, build, os, device, language: String
    var context: FeedbackContext?

    /// Trims message and email; an empty email becomes nil. Nil when the message or email is invalid.
    init?(kind: FeedbackKind, message: String, email: String, diagnostics: FeedbackDiagnostics, context: FeedbackContext?) {
        let message = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty, message.count <= Feedback.messageLimit else { return nil }
        guard email.isEmpty || (email.count <= 254 && email.wholeMatch(of: /[^@\s]+@[^@\s]+\.[^@\s]+/) != nil) else { return nil }
        self.kind = kind; self.message = message; self.email = email.isEmpty ? nil : email
        appVersion = diagnostics.appVersion; build = diagnostics.build; os = diagnostics.os
        device = diagnostics.device; language = diagnostics.language
        self.context = context
    }

    /// Everything sent besides what the person typed; shown on screen and appended to the email.
    var includedLines: [String] {
        FeedbackDiagnostics(appVersion: appVersion, build: build, os: os, device: device, language: language).lines
            + (context.map { [String(localized: "Coach error: \($0.rawValue)")] } ?? [])
    }
}

enum FeedbackError: Error { case rejected }

enum Feedback {
    static let messageLimit = 4000
    static let supportAddress = "support@mivuapp.com"

    /// Nil until a deployed endpoint is configured; the form then sends by email instead.
    static var endpoint: URL? {
        guard let text = Bundle.main.object(forInfoDictionaryKey: "MivuFeedbackEndpoint") as? String,
              let url = URL(string: text), url.scheme == "https", url.host() != nil else { return nil }
        return url
    }

    static func mailto(_ report: FeedbackReport) -> URL {
        var parts = URLComponents()
        parts.scheme = "mailto"
        parts.path = supportAddress
        parts.queryItems = [
            // English on purpose: the inbox sorts on these.
            URLQueryItem(name: "subject", value: "[\(report.kind.rawValue.capitalized)] Mivu \(report.appVersion) (\(report.build)), iOS \(report.os)"),
            URLQueryItem(name: "body", value: "\(report.message)\n\n---\n\(report.includedLines.joined(separator: "\n"))")
        ]
        return parts.url!
    }

    /// Succeeds only on 204: a 200 can be a Wi-Fi login page rather than our server.
    static func send(_ report: FeedbackReport, to endpoint: URL, session: URLSession = .shared) async throws {
        var request = URLRequest(url: endpoint, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(report)
        let (_, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 204 else { throw FeedbackError.rejected }
    }
}
