import Foundation

/// Requests made with a person's own key. Failures are `ResponsesClient.Failure`, so Coach treats every service alike.
struct KeyServiceClient: Sendable {
    private let session: URLSession

    init(session: URLSession = .shared) { self.session = session }

    /// Costs nothing and sends no diary data; a 401 here means the key is wrong.
    func models(_ service: KeyService, key: String) async throws -> [AvailableModel] {
        let address = switch service {
        case .claude: "https://api.anthropic.com/v1/models?limit=100"
        case .openAI: "https://api.openai.com/v1/models"
        case .gemini: "https://generativelanguage.googleapis.com/v1beta/openai/models"
        case .openRouter: "https://openrouter.ai/api/v1/key"
        }
        let reply = try await send(request(service, address, key: key))
        if service == .openRouter { return service.shortlist }
        struct Catalog: Decodable {
            struct Model: Decodable { let id: String; let display_name: String? }
            let data: [Model]
        }
        guard let catalog = try? JSONDecoder().decode(Catalog.self, from: reply) else { throw ResponsesClient.Failure.malformedResponse }
        return catalog.data.compactMap {
            // Gemini lists "models/<id>" but takes the bare id in requests.
            let id = $0.id.hasPrefix("models/") ? String($0.id.dropFirst(7)) : $0.id
            return service.lists(id) ? AvailableModel(slug: id, displayName: $0.display_name ?? id) : nil
        }
    }

    // shortcut: not streamed, a reply slower than the 180 s timeout fails; switch to SSE if Coach shows partial text
    func respond(_ service: KeyService, model: String, input: [CoachInferenceInput],
                 toolNamespace: Data?, key: String) async throws -> CoachInferenceResult {
        switch service {
        case .openAI:
            return try await ResponsesClient(session: session).respond(model: model, input: input, toolNamespace: toolNamespace, accessToken: key)
        case .claude:
            var call = try request(service, "https://api.anthropic.com/v1/messages", key: key)
            call.httpBody = try MessagesWire.body(model: model, input: input, toolNamespace: toolNamespace)
            return try MessagesWire.result(await send(call))
        case .gemini, .openRouter:
            let address = service == .gemini ? "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions"
                : "https://openrouter.ai/api/v1/chat/completions"
            var call = try request(service, address, key: key)
            call.httpBody = try ChatCompletionsWire.body(model: model, input: input, toolNamespace: toolNamespace)
            return try ChatCompletionsWire.result(await send(call))
        }
    }

    private func request(_ service: KeyService, _ address: String, key: String) throws -> URLRequest {
        guard !key.isEmpty, !key.contains(where: { $0.isWhitespace }) else { throw ResponsesClient.Failure.invalidInput }
        var request = URLRequest(url: URL(string: address)!)
        request.timeoutInterval = 180
        if service == .claude {
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")
        } else {
            request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
        }
        if service == .openRouter { request.setValue("Mivu", forHTTPHeaderField: "X-Title") }
        return request
    }

    /// The error body is never read: only the status decides the failure, so no service text reaches a log or the screen.
    private func send(_ request: URLRequest) async throws -> Data {
        var request = request
        if request.httpBody != nil {
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await session.data(for: request, delegate: RejectAuthRedirects())
        guard let status = (response as? HTTPURLResponse)?.statusCode else { throw ResponsesClient.Failure.malformedResponse }
        switch status {
        case 200: return data
        case 401: throw ResponsesClient.Failure.unauthorized
        case 403: throw ResponsesClient.Failure.forbidden
        case 402, 429: throw ResponsesClient.Failure.quotaReached
        case 529: throw ResponsesClient.Failure.usageUnavailable
        default: throw ResponsesClient.Failure.http(status: status)
        }
    }
}
