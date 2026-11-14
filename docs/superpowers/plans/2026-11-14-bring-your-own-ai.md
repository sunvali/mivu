# Bring Your Own AI (iOS) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a person power the iOS Coach with their own Claude, OpenAI, Gemini or OpenRouter credential, next to ChatGPT sign-in and the on-device model.

**Architecture:** `ChatGPTConnection.inference()` already hands Coach, setup and Siri one closure. Four new `Provider` cases return that same closure, backed by a small `KeyServiceClient`. Two pure translators (`MessagesWire` for Claude, `ChatCompletionsWire` for Gemini and OpenRouter) turn `CoachInferenceInput` into a request and a JSON reply into `CoachInferenceResult`. An OpenAI key reuses `ResponsesClient` unchanged.

**Tech Stack:** Swift, SwiftUI, URLSession, Security (Keychain), Swift Testing, XCUITest. No new dependency.

**Spec:** `docs/superpowers/specs/2026-11-14-bring-your-own-ai-design.md`

## Global Constraints

- One active AI at a time. Nothing switches provider by itself.
- A key lives only in the Keychain (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`). Never in `UserDefaults`, the diary database, `DiaryArchive`, a `ProbeJob`, a log line or a diagnostic string.
- No data goes to a service before the person agreed to share with that service. `openAISharingConsent` keeps its name and covers ChatGPT sign-in and an OpenAI key.
- A request is bound to the provider, key and model it started with. Any change ends it as `SessionError.sessionChanged`.
- Adapters throw `ResponsesClient.Failure`, so `CoachEngine`'s existing error-to-state mapping keeps working.
- New requests are **not streamed**. Coach never shows partial text, so a whole JSON reply is equivalent. Mark it in code: `// shortcut: not streamed, a reply slower than the 180 s timeout fails; switch to SSE if Coach shows partial text`.
- Claude: `POST https://api.anthropic.com/v1/messages`, headers `x-api-key` and `anthropic-version: 2026-10-21`. Never send `temperature`, `top_p`, `top_k`, `thinking` or `budget_tokens`.
- Tests and diagnostics use synthetic inputs and fixture keys such as `"fixture-key"` only.
- English only. Dynamic Type, VoiceOver labels, reduced motion and 44-point targets on every new control.
- No real key exists yet. Do not add workarounds for behaviour that is only suspected. Every service ships as "built, not verified live".
- Commits and the pull request use Conventional Commit titles and name no tool or assistant.
- Run tests with XcodeBuildMCP: `xcodebuildmcp simulator test --project-path "$PWD/ios/Mivu.xcodeproj" --scheme Mivu --simulator-id <reserved-UUID> --json '{"extraArgs":["-testPlan","Mivu","-only-testing:MivuTests/<Suite>","-parallel-testing-enabled","NO"]}'`. Reserve a simulator first, as `docs/development/ci-cd.md` describes. The project uses synchronized folders, so new files need no project-file edit.

## Review Focus

1. **A pasted key with stray whitespace or a trailing newline.** Expected: outer whitespace is trimmed and the key works; inner whitespace is rejected with a clear message. Test in Task 1 and Task 4.
2. **A valid key with no credit.** The key check lists models and costs nothing, so the first real request is where this shows. Expected: the turn stays saved, Pip names the service and points to its usage page. Test in Task 3 (402 and 429 map to `.quotaReached`) and Task 7 (copy).
3. **The active key is replaced or removed while a reply is in flight.** Expected: the request ends as `sessionChanged`, never completes on the new key. Test in Task 4.
4. **A reply with no text and no tool call, or cut off by the length limit.** Expected: `.malformedResponse` or `.incompleteResponse`, both already handled by Coach. Test in Task 2.
5. **A saved model that is no longer in the service's list.** Expected: the service default if listed, else the first listed model. Test in Task 4.

---

### Task 1: Key services and their Keychain store

**Files:**
- Create: `ios/Mivu/Connection/KeyService.swift`
- Test: `ios/MivuTests/KeyServiceTests.swift`

**Interfaces:**
- Produces:

```swift
enum KeyService: String, CaseIterable, Sendable {
    case claude, openAI, gemini, openRouter
    var name: String              // "Claude", "OpenAI", "Gemini", "OpenRouter"
    var company: String           // "Anthropic", "OpenAI", "Google", "OpenRouter"
    var caption: String           // list subtitle, see Step 3
    var keyPage: URL              // where the person creates a key
    var usagePage: URL
    var defaultModel: String
    var shortlist: [AvailableModel]   // non-empty only for .openRouter
    var consentKey: String        // .openAI -> "openAISharingConsent"; others -> rawValue + "SharingConsent"
    var connectsBySignIn: Bool    // true only for .openRouter
    func lists(_ modelID: String) -> Bool   // true for chat models worth showing in the picker
}

struct AIKeyStore: Sendable {
    enum Failure: Error, Equatable { case invalidKey, unavailable }
    init(service: String = "Mivu.AIKeys")
    @MainActor static var local: AIKeyStore   // test-scoped service name, as NutritionAPIKeyStore.local
    func load(_ service: KeyService) throws -> String?
    func save(_ key: String, for service: KeyService) throws
    func remove(_ service: KeyService) throws
}
```

- [ ] **Step 1: Write the failing tests**

```swift
@Suite struct KeyServiceTests {
    let store = AIKeyStore(service: "Mivu.AIKeysTest." + UUID().uuidString)

    @Test func keysAreStoredPerService() throws {
        try store.save("fixture-claude", for: .claude)
        try store.save("fixture-gemini", for: .gemini)
        #expect(try store.load(.claude) == "fixture-claude")
        #expect(try store.load(.openAI) == nil)
        try store.remove(.claude)
        #expect(try store.load(.claude) == nil)
        #expect(try store.load(.gemini) == "fixture-gemini")
        try store.remove(.gemini)
    }

    @Test(arguments: ["", "has space", "line\nbreak", String(repeating: "k", count: 513)])
    func rejectsUnusableKeys(_ key: String) {
        #expect(throws: AIKeyStore.Failure.invalidKey) { try store.save(key, for: .openAI) }
    }

    @Test func openAIKeySharesTheExistingOpenAIConsent() {
        #expect(KeyService.openAI.consentKey == "openAISharingConsent")
        #expect(Set(KeyService.allCases.map(\.consentKey)).count == 4)
    }

    @Test func pickerHidesModelsThatCannotChat() {
        #expect(KeyService.claude.lists("claude-haiku-5-5"))
        #expect(!KeyService.openAI.lists("text-embedding-3-small"))
        #expect(!KeyService.gemini.lists("models/gemini-embedding-2"))
        #expect(KeyService.allCases.allSatisfy { $0.lists($0.defaultModel) })
    }
}
```

- [ ] **Step 2: Run to verify it fails** — `-only-testing:MivuTests/KeyServiceTests`. Expected: build fails, `KeyService` not found.

- [ ] **Step 3: Implement `KeyService` and `AIKeyStore`**

`AIKeyStore` copies `NutritionAPIKeyStore`'s Keychain calls with `kSecAttrAccount` set to the service's raw value and a 512-byte limit. Leave `NutritionAPIKeyStore` untouched.

Fixed values:

| Service | caption | keyPage | usagePage |
|---|---|---|---|
| claude | `Paste a key · pay per use` | `https://platform.claude.com/settings/keys` | `https://platform.claude.com/usage` |
| openAI | `Paste a key · pay per use` | `https://platform.openai.com/api-keys` | `https://platform.openai.com/usage` |
| gemini | `Paste a key · has a free tier` | `https://aistudio.google.com/apikey` | `https://aistudio.google.com/usage` |
| openRouter | `Sign in · one account, many models` | `https://openrouter.ai/settings/keys` | `https://openrouter.ai/activity` |

Open each of the eight pages once and correct any that no longer resolve.

`defaultModel`: Claude is `claude-haiku-5-5`. For OpenAI and Gemini, read the provider's current models page and pin its cheapest image-capable chat model. For OpenRouter, read the public `GET https://openrouter.ai/api/v1/models` (no key needed) and pin a default plus a `shortlist` of at most six image-capable models that include one Claude, one GPT and one Gemini model. Put the lookup date in a one-line comment above the constants.

`lists(_:)`: Claude accepts ids starting `claude-`. OpenAI accepts ids starting `gpt-` that contain none of `audio`, `realtime`, `tts`, `transcribe`, `image`, `search`, `embedding`, `instruct`. Gemini accepts ids containing `gemini-` that contain none of `embedding`, `image`, `tts`, `audio`, `live`. OpenRouter accepts ids in its shortlist.

- [ ] **Step 4: Run to verify it passes** — same command. Expected: 4 tests pass (7 cases).

- [ ] **Step 5: Commit** — `git commit -m "feat(connection): key services and a per-service key store"`

---

### Task 2: Claude and Chat Completions translators

**Files:**
- Create: `ios/Mivu/Analysis/MessagesWire.swift`
- Create: `ios/Mivu/Analysis/ChatCompletionsWire.swift`
- Test: `ios/MivuTests/KeyServiceWireTests.swift`

**Interfaces:**
- Consumes: `CoachInferenceInput`, `CoachInferenceResult`, `CoachToolCall`, `CoachTools.namespace`, `ResponsesClient.Failure`, `CoachInferenceInput.imageMIME(_:)`.
- Produces:

```swift
enum MessagesWire {
    static func body(model: String, input: [CoachInferenceInput], toolNamespace: Data?) throws -> Data
    static func result(_ reply: Data) throws -> CoachInferenceResult
}
enum ChatCompletionsWire {
    static func body(model: String, input: [CoachInferenceInput], toolNamespace: Data?) throws -> Data
    static func result(_ reply: Data) throws -> CoachInferenceResult
}
```

Translation rules, both formats:

- `toolNamespace` is the Responses `{"type":"namespace","tools":[…]}` object from `CoachTools`. Send its functions as a flat list and drop `strict`.
- Returned calls are `CoachToolCall(id: <service id>, callID: <service id>, name:, namespace: CoachTools.namespace, arguments: <JSON string>)`.
- `outputItems` is exactly one item: the assistant turn kept verbatim so the next request can send it back unchanged. Claude: `{"type":"message","role":"assistant","claude":<content array>}`. Chat: `{"type":"message","role":"assistant","chat":<message object>}`. A `.priorOutput` without that key throws `.invalidInput`.
- `input.count <= 128` and a body of at most 8,388,608 bytes, else `.invalidInput`.

Claude specifics: every `.developer` message becomes a text block in top-level `system`, in order. A user message is its `image` blocks (`source.type` `base64`) followed by its text block. Consecutive `.functionOutput` items become **one** user message of `tool_result` blocks. Tools are `{name, description, input_schema}`. `max_tokens` is `16000`. Add top-level `"cache_control": {"type": "ephemeral"}`. `result`: `stop_reason` `refusal` returns the text `I can't help with that one.` with no calls; `max_tokens` throws `.incompleteResponse`; no text and no `tool_use` throws `.malformedResponse`. `model` comes from the reply.

Chat specifics: `.developer` becomes role `system`. A user message is content parts `text` and `image_url` with a `data:` URL. `.functionOutput` becomes `{"role":"tool","tool_call_id":…,"content":…}`. Tools are `{"type":"function","function":{name, description, parameters}}`. `result`: reads `choices[0].message`; `finish_reason` `length` throws `.incompleteResponse`; `content_filter` returns the same refusal text; no content and no `tool_calls` throws `.malformedResponse`.

- [ ] **Step 1: Write the failing tests**

Fixtures: `let png = Data([137, 80, 78, 71, 13, 10, 26, 10])` and a namespace built with `JSONSerialization` holding one function `log_meal` with `"strict": true` and parameters `{"type":"object","properties":{"kcal":{"type":["number","null"]}}}`.

```swift
@Suite struct KeyServiceWireTests {
    @Test func claudeRequestCarriesSystemImageToolsAndGroupedResults() throws {
        let first = try MessagesWire.result(claudeReply(content: [
            ["type": "thinking", "thinking": "", "signature": "sig"],
            ["type": "tool_use", "id": "toolu_1", "name": "log_meal", "input": ["kcal": 420]],
            ["type": "tool_use", "id": "toolu_2", "name": "log_meal", "input": ["kcal": 90]]], stop: "tool_use"))
        #expect(first.calls.map(\.callID) == ["toolu_1", "toolu_2"])
        #expect(first.calls[0].namespace == "mivu")
        #expect(try JSONSerialization.jsonObject(with: Data(first.calls[0].arguments.utf8)) as? [String: Int] == ["kcal": 420])
        let body = try object(MessagesWire.body(model: "claude-haiku-5-5", input: [
            .message(role: .developer, text: "rules"), .message(role: .user, text: "lunch", images: [png]),
            .priorOutput(first.outputItems[0]),
            .functionOutput(callID: "toolu_1", output: "{\"saved\":true}"),
            .functionOutput(callID: "toolu_2", output: "{\"saved\":true}")], toolNamespace: namespace))
        #expect((body["system"] as? [[String: String]])?.map { $0["text"] } == ["rules"])
        let messages = try #require(body["messages"] as? [[String: Any]])
        #expect(messages.map { $0["role"] as? String } == ["user", "assistant", "user"])
        #expect((messages[0]["content"] as? [[String: Any]])?.map { $0["type"] as? String } == ["image", "text"])
        #expect((messages[1]["content"] as? [[String: Any]])?.first?["signature"] as? String == "sig")   // verbatim, thinking kept
        #expect((messages[2]["content"] as? [[String: Any]])?.map { $0["tool_use_id"] as? String } == ["toolu_1", "toolu_2"])
        let tool = try #require((body["tools"] as? [[String: Any]])?.first)
        #expect(tool["name"] as? String == "log_meal" && tool["input_schema"] != nil && tool["strict"] == nil)
        #expect(body["max_tokens"] as? Int == 16000)
        #expect(["temperature", "top_p", "top_k", "thinking", "stream"].allSatisfy { body[$0] == nil })
    }

    @Test func claudeRefusalLengthAndEmptyReplies() throws {
        let refusal = try MessagesWire.result(claudeReply(content: [], stop: "refusal"))
        #expect(refusal.text == "I can't help with that one." && refusal.calls.isEmpty)
        #expect(throws: ResponsesClient.Failure.incompleteResponse) {
            try MessagesWire.result(claudeReply(content: [["type": "text", "text": "cut"]], stop: "max_tokens")) }
        #expect(throws: ResponsesClient.Failure.malformedResponse) {
            try MessagesWire.result(claudeReply(content: [["type": "thinking", "thinking": "", "signature": "s"]], stop: "end_turn")) }
        #expect(throws: ResponsesClient.Failure.malformedResponse) { try MessagesWire.result(Data("not json".utf8)) }
    }

    @Test func chatRequestAndReplyRoundTrip() throws {
        let first = try ChatCompletionsWire.result(chatReply(message: ["role": "assistant", "content": NSNull(),
            "tool_calls": [["id": "call_1", "type": "function", "extra_content": ["google": ["thought_signature": "ts"]],
                            "function": ["name": "log_meal", "arguments": "{\"kcal\":420}"]]]], finish: "tool_calls"))
        #expect(first.calls == [CoachToolCall(id: "call_1", callID: "call_1", name: "log_meal", namespace: "mivu", arguments: "{\"kcal\":420}")])
        let body = try object(ChatCompletionsWire.body(model: "m", input: [
            .message(role: .developer, text: "rules"), .message(role: .user, text: "lunch", images: [png]),
            .priorOutput(first.outputItems[0]), .functionOutput(callID: "call_1", output: "{}")], toolNamespace: namespace))
        let messages = try #require(body["messages"] as? [[String: Any]])
        #expect(messages.map { $0["role"] as? String } == ["system", "user", "assistant", "tool"])
        #expect((messages[1]["content"] as? [[String: Any]])?.map { $0["type"] as? String } == ["text", "image_url"])
        #expect(String(describing: messages[2]).contains("thought_signature"))   // verbatim
        #expect(messages[3]["tool_call_id"] as? String == "call_1")
        let function = try #require(((body["tools"] as? [[String: Any]])?.first?["function"]) as? [String: Any])
        #expect(function["name"] as? String == "log_meal" && function["strict"] == nil)
    }

    @Test func chatLengthFilterAndEmptyReplies() throws {
        #expect(throws: ResponsesClient.Failure.incompleteResponse) {
            try ChatCompletionsWire.result(chatReply(message: ["role": "assistant", "content": "cut"], finish: "length")) }
        #expect(try ChatCompletionsWire.result(chatReply(message: ["role": "assistant", "content": NSNull()], finish: "content_filter")).text == "I can't help with that one.")
        #expect(throws: ResponsesClient.Failure.malformedResponse) {
            try ChatCompletionsWire.result(chatReply(message: ["role": "assistant", "content": ""], finish: "stop")) }
    }

    @Test func foreignPriorOutputIsRejected() {
        let responsesItem = try! JSONSerialization.data(withJSONObject: ["type": "message", "role": "assistant", "content": []])
        #expect(throws: ResponsesClient.Failure.invalidInput) { try MessagesWire.body(model: "m", input: [.priorOutput(responsesItem)], toolNamespace: nil) }
        #expect(throws: ResponsesClient.Failure.invalidInput) { try ChatCompletionsWire.body(model: "m", input: [.priorOutput(responsesItem)], toolNamespace: nil) }
    }
}
```

File-private helpers in the test file: `object(_ data: Data) throws -> [String: Any]`, `claudeReply(content:stop:)` building `{"model":"claude-haiku-5-5","content":…,"stop_reason":…}`, and `chatReply(message:finish:)` building `{"model":"m","choices":[{"message":…,"finish_reason":…}]}`.

- [ ] **Step 2: Run to verify it fails** — `-only-testing:MivuTests/KeyServiceWireTests`. Expected: build fails, `MessagesWire` not found.
- [ ] **Step 3: Implement both translators** with `JSONSerialization`, as `ResponsesClient` does. Serialise tool `input` to the `arguments` string with `.sortedKeys`.
- [ ] **Step 4: Run to verify it passes.** Expected: 5 tests pass.
- [ ] **Step 5: Commit** — `git commit -m "feat(analysis): translate Coach requests for Claude and Chat Completions"`

---

### Task 3: HTTP client for key services

**Files:**
- Create: `ios/Mivu/Analysis/KeyServiceClient.swift`
- Test: `ios/MivuTests/KeyServiceClientTests.swift`
- Modify: `ios/MivuTests/ResponsesClientTests.swift:506-560` (make `RequestCapture` and `sessionReturning` internal so the new suite reuses them)

**Interfaces:**
- Consumes: Task 1 `KeyService`; Task 2 translators; `ResponsesClient.respond(model:input:toolNamespace:accessToken:)`.
- Produces:

```swift
struct KeyServiceClient: Sendable {
    init(session: URLSession = .shared)
    /// Costs nothing and sends no diary data; a 401 here means the key is wrong.
    func models(_ service: KeyService, key: String) async throws -> [AvailableModel]
    func respond(_ service: KeyService, model: String, input: [CoachInferenceInput],
                 toolNamespace: Data?, key: String) async throws -> CoachInferenceResult
}
```

Endpoints:

| Service | respond | models |
|---|---|---|
| claude | `POST https://api.anthropic.com/v1/messages` | `GET https://api.anthropic.com/v1/models?limit=100`, reads `data[].id` and `display_name` |
| openAI | `ResponsesClient(session:).respond(…, accessToken: key)` | `GET https://api.openai.com/v1/models`, reads `data[].id` |
| gemini | `POST https://generativelanguage.googleapis.com/v1beta/openai/chat/completions` | `GET https://generativelanguage.googleapis.com/v1beta/openai/models`, reads `data[].id` |
| openRouter | `POST https://openrouter.ai/api/v1/chat/completions`, extra header `X-Title: Mivu` | `GET https://openrouter.ai/api/v1/key` to check the key, then returns `service.shortlist` |

Claude sends `x-api-key` and `anthropic-version: 2026-10-21`; the others send `Authorization: Bearer`. `models` keeps only ids where `service.lists(id)` is true, and uses the id as the display name when the service gives none. Timeout 180 s. Use `RejectAuthRedirects()` as `ResponsesClient` does. Status mapping: 200 ok, 401 `.unauthorized`, 403 `.forbidden`, 402 and 429 `.quotaReached`, 529 `.usageUnavailable`, anything else `.http(status:)`. Never read an error body into a thrown error or a log.

- [ ] **Step 1: Write the failing tests**

```swift
@Suite(.serialized) struct KeyServiceClientTests {
    @Test func claudeSendsItsOwnHeadersAndNoBearer() async throws {
        let capture = RequestCapture()
        let reply = Data(#"{"model":"claude-haiku-5-5","stop_reason":"end_turn","content":[{"type":"text","text":"Hi"}]}"#.utf8)
        let result = try await KeyServiceClient(session: sessionReturning(status: 200, body: reply, capture: capture))
            .respond(.claude, model: "claude-haiku-5-5", input: [.message(role: .user, text: "hi")], toolNamespace: nil, key: "fixture-key")
        #expect(result.text == "Hi")
        let request = try #require(capture.request)
        #expect(request.url?.absoluteString == "https://api.anthropic.com/v1/messages")
        #expect(request.value(forHTTPHeaderField: "x-api-key") == "fixture-key")
        #expect(request.value(forHTTPHeaderField: "anthropic-version") == "2026-10-21")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test(arguments: [(KeyService.gemini, "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions"),
                      (KeyService.openRouter, "https://openrouter.ai/api/v1/chat/completions")])
    func chatServicesUseBearerAtTheirOwnAddress(service: KeyService, url: String) async throws {
        let capture = RequestCapture()
        let reply = Data(#"{"model":"m","choices":[{"finish_reason":"stop","message":{"role":"assistant","content":"Hi"}}]}"#.utf8)
        _ = try await KeyServiceClient(session: sessionReturning(status: 200, body: reply, capture: capture))
            .respond(service, model: "m", input: [.message(role: .user, text: "hi")], toolNamespace: nil, key: "fixture-key")
        #expect(capture.request?.url?.absoluteString == url)
        #expect(capture.request?.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-key")
    }

    @Test(arguments: [(401, ResponsesClient.Failure.unauthorized), (402, .quotaReached), (429, .quotaReached),
                      (529, .usageUnavailable), (500, .http(status: 500))])
    func statusesMapToTheFailuresCoachAlreadyHandles(status: Int, failure: ResponsesClient.Failure) async {
        let client = KeyServiceClient(session: sessionReturning(status: status, body: Data("{}".utf8)))
        await #expect(throws: failure) {
            try await client.respond(.claude, model: "m", input: [.message(role: .user, text: "hi")], toolNamespace: nil, key: "fixture-key") }
        if status == 401 { await #expect(throws: failure) { try await client.models(.gemini, key: "fixture-key") } }
    }

    @Test func modelListsAreFilteredToChatModels() async throws {
        let body = Data(#"{"data":[{"id":"gpt-fixture-mini"},{"id":"text-embedding-3-small"},{"id":"gpt-fixture-tts"}]}"#.utf8)
        let models = try await KeyServiceClient(session: sessionReturning(status: 200, body: body)).models(.openAI, key: "fixture-key")
        #expect(models == [AvailableModel(slug: "gpt-fixture-mini", displayName: "gpt-fixture-mini")])
    }

    @Test func openRouterChecksTheKeyAndReturnsItsShortlist() async throws {
        let capture = RequestCapture()
        let models = try await KeyServiceClient(session: sessionReturning(status: 200, body: Data("{}".utf8), capture: capture)).models(.openRouter, key: "fixture-key")
        #expect(capture.request?.url?.absoluteString == "https://openrouter.ai/api/v1/key")
        #expect(models == KeyService.openRouter.shortlist && !models.isEmpty)
    }
}
```

- [ ] **Step 2: Run to verify it fails** — `-only-testing:MivuTests/KeyServiceClientTests`.
- [ ] **Step 3: Implement `KeyServiceClient`.** Non-streamed: `session.data(for:delegate:)`, then the Task 2 `result`.
- [ ] **Step 4: Run to verify it passes**, and rerun `-only-testing:MivuTests/ResponsesClientTests` to confirm the shared helpers still serve it.
- [ ] **Step 5: Commit** — `git commit -m "feat(analysis): call Claude, Gemini and OpenRouter with a person's own key"`

---

### Task 4: The connection chooses and binds a key service

**Files:**
- Modify: `ios/Mivu/Connection/ChatGPTConnection.swift` (`Provider`, `provider`, `available`, `tunesTargets`, `init`, `restore`, `inference`, `ConnectionNotice`)
- Create: `ios/Mivu/Connection/KeyConnection.swift` (the new methods, as an extension)
- Test: `ios/MivuTests/KeyConnectionTests.swift`

**Interfaces:**
- Consumes: Tasks 1 and 3.
- Produces, on `ChatGPTConnection`:

```swift
enum Provider: String, CaseIterable { case apple, chatGPT, claude, openAI, gemini, openRouter
    var keyService: KeyService? { KeyService(rawValue: rawValue) } }
enum KeyConnectionError: Error, Equatable { case consentRequired, invalidKey, rejected, unavailable, storage }

init(…, keyStore: AIKeyStore? = nil, keyClient: KeyServiceClient = KeyServiceClient(), …)   // nil -> AIKeyStore.local
private(set) var connectedServices: Set<KeyService>
private(set) var serviceModels: [KeyService: [AvailableModel]]
private(set) var isCheckingKey: Bool
func selectedModel(for service: KeyService) -> String          // preference "aiModel.<rawValue>"
func selectModel(_ slug: String, for service: KeyService)      // bumps generation
func consented(to service: KeyService) -> Bool
func recordConsent(to service: KeyService)
func saveKey(_ raw: String, for service: KeyService) async throws   // throws KeyConnectionError
func removeKey(for service: KeyService)
var activeName: String        // "ChatGPT", the service name, or "Apple Intelligence"
var activeUsagePage: URL?     // MivuLinks.chatGPTUsage, the service usagePage, or nil
```

Behaviour:

- `saveKey` trims outer whitespace, requires consent, calls `keyClient.models` (401 or 403 becomes `.rejected`, other failures `.unavailable`), and only then saves. It stores the model list, selects `service.defaultModel` if listed else the first model, sets `provider`, adds to `connectedServices`, and bumps `generation`. A key that fails the check is not saved.
- `removeKey` deletes the key, drops the service from `connectedServices` and bumps `generation`. The `provider` getter then falls back exactly as it does today for an unavailable choice.
- `available(_:)` for a key service is `connectedServices.contains(service) && consented(to: service)`.
- `tunesTargets` becomes `provider != .apple && available(provider)`.
- `restore()` fills `connectedServices` from the key store and loads the active key service's models **before** the existing `sharingConsented` guard, which stays as the ChatGPT gate.
- `inference()` for a key service throws `SessionError.noActiveSession` without a key, consent or selected model. Its closure captures `generation`, service, key and model, checks `generation` before and after the request, and throws `SessionError.sessionChanged` on a mismatch. On `.unauthorized` it sets `notice = .keyRejected`; on `.quotaReached`, `notice = .keyQuota`.
- New `ConnectionNotice` cases: `keyRejected = "This key was rejected. Replace it in Settings → Coach AI."` and `keyQuota = "Your AI service is out of credit or over its limit. Check its usage page, then try again."`

- [ ] **Step 1: Write the failing tests**

Build the fixture as `CoachConnectionTests` does at line 279, adding `keyStore: AIKeyStore(service: "Mivu.AIKeysTest." + UUID().uuidString)` and `keyClient: KeyServiceClient(session: session)`, with a session whose reply is switchable per test and which records requests. `modelsReply` is `{"data":[{"id":"claude-haiku-5-5","display_name":"Claude Haiku 5.5"},{"id":"claude-opus-5-5","display_name":"Claude Opus 5.5"}]}`.

```swift
@Suite(.serialized) @MainActor struct KeyConnectionTests {
    @Test func aKeyIsCheckedBeforeItIsSavedAndThenBecomesTheActiveAI() async throws {
        let f = try Fixture(); f.reply(200, modelsReply)
        await #expect(throws: KeyConnectionError.consentRequired) { try await f.connection.saveKey("fixture-key", for: .claude) }
        #expect(f.requests.isEmpty)                                   // nothing sent before consent
        f.connection.recordConsent(to: .claude)
        try await f.connection.saveKey("  fixture-key\n", for: .claude)
        #expect(try f.keyStore.load(.claude) == "fixture-key")
        #expect(f.connection.provider == .claude && f.connection.canInfer && f.connection.tunesTargets)
        #expect(f.connection.selectedModel(for: .claude) == "claude-haiku-5-5")
        #expect(f.connection.activeName == "Claude")
        #expect(!f.preferences.dictionaryRepresentation().values.contains { "\($0)".contains("fixture-key") })
    }

    @Test func aRejectedKeyIsNotSaved() async throws {
        let f = try Fixture(); f.connection.recordConsent(to: .gemini); f.reply(401, "{}")
        await #expect(throws: KeyConnectionError.rejected) { try await f.connection.saveKey("fixture-key", for: .gemini) }
        #expect(try f.keyStore.load(.gemini) == nil)
        #expect(!f.connection.available(.gemini))
        await #expect(throws: KeyConnectionError.invalidKey) { try await f.connection.saveKey("has space", for: .gemini) }
    }

    @Test func consentIsPerService() throws {
        let f = try Fixture(); f.connection.recordConsent(to: .openAI)
        #expect(f.connection.sharingConsented)                        // same preference as ChatGPT
        #expect(!f.connection.consented(to: .claude))
    }

    @Test func replacingOrRemovingTheKeyEndsARequestInFlight() async throws {
        let f = try Fixture.connected(.claude)
        let respond = try f.connection.inference()
        f.connection.removeKey(for: .claude)
        await #expect(throws: SessionError.sessionChanged) { _ = try await respond([.message(role: .user, text: "hi")], nil) }
        #expect(f.requests.count == 1)                                // only the earlier key check
        #expect(throws: SessionError.noActiveSession) { _ = try f.connection.inference() }
    }

    @Test func aVanishedModelFallsBackToTheDefaultThenTheFirstListed() async throws {
        let f = try Fixture.connected(.claude)
        f.connection.selectModel("claude-opus-5-5", for: .claude)
        f.reply(200, #"{"data":[{"id":"claude-sonnet-5-5","display_name":"Claude Sonnet 5.5"}]}"#)
        let restored = f.relaunched(); await restored.restore()
        #expect(restored.selectedModel(for: .claude) == "claude-sonnet-5-5")
    }

    @Test func savedKeysSurviveSwitchingAndRelaunch() async throws {
        let f = try Fixture.connected(.claude)
        f.connection.provider = .chatGPT
        #expect(f.connection.connectedServices == [.claude])
        f.connection.provider = .claude; f.reply(200, modelsReply)
        let restored = f.relaunched(); await restored.restore()
        #expect(restored.provider == .claude && restored.canInfer)
    }

    @Test func noCreditAndABadKeySetTheirOwnNotices() async throws {
        let f = try Fixture.connected(.claude); f.reply(402, "{}")
        await #expect(throws: ResponsesClient.Failure.quotaReached) { _ = try await f.connection.inference()([.message(role: .user, text: "hi")], nil) }
        #expect(f.connection.notice == .keyQuota)
        f.reply(401, "{}")
        await #expect(throws: ResponsesClient.Failure.unauthorized) { _ = try await f.connection.inference()([.message(role: .user, text: "hi")], nil) }
        #expect(f.connection.notice == .keyRejected)
    }
}
```

- [ ] **Step 2: Run to verify it fails** — `-only-testing:MivuTests/KeyConnectionTests`.
- [ ] **Step 3: Implement** as described under Behaviour.
- [ ] **Step 4: Run to verify it passes**, then rerun `-only-testing:MivuTests/CoachConnectionTests` and `-only-testing:MivuTests/ConnectionTests`. Expected: all pass, ChatGPT behaviour unchanged.
- [ ] **Step 5: Commit** — `git commit -m "feat(connection): choose a key service as the Coach AI"`

---

### Task 5: OpenRouter sign-in

**Files:**
- Create: `ios/Mivu/Connection/OpenRouterSignIn.swift`
- Modify: `ios/Mivu/Connection/OAuthAttempt.swift:98` (`randomValue()` from `private` to internal)
- Modify: `ios/Mivu/Connection/KeyConnection.swift`
- Test: `ios/MivuTests/OpenRouterSignInTests.swift`

**Interfaces:**
- Consumes: `LoopbackCallback.start()` and `receive(validating:openBrowser:browserURL:)`, `OAuthAttempt.challenge(for:)`, `OAuthAttempt.randomValue()`, `OAuthError.invalidCallback`, Task 4 `saveKey`.
- Produces:

```swift
struct OpenRouterSignIn {
    let verifier: String, state: String, authorizationURL: URL
    static func make(callbackURL: URL) throws -> OpenRouterSignIn
    func code(from callback: URL) throws -> String      // OAuthError.invalidCallback on a wrong or missing state, or no code
    func exchange(code: String) -> URLRequest            // the POST that trades the code for a key
    static func key(from reply: Data) throws -> String
}
extension ChatGPTConnection {
    func signInOpenRouter() async                                             // front window, like connect()
    func signInOpenRouter(openBrowser: @escaping @MainActor (URL) async throws -> Void) async
}
```

`authorizationURL` is `https://openrouter.ai/auth` with `callback_url`, `code_challenge`, `code_challenge_method=S256` and `state`. The exchange is `POST https://openrouter.ai/api/v1/auth/keys` with JSON `code`, `code_verifier`, `code_challenge_method: "S256"`; the reply's `key` string is the credential. `signInOpenRouter` mirrors `authorize(revision:openBrowser:)`: it requires consent to OpenRouter, sets `isConnecting`, honours `generation` and cancellation, and finishes by calling `saveKey(key, for: .openRouter)`. Failures set `notice` to `.cancelled` or `.unavailable` as today.

- [ ] **Step 1: Write the failing tests**

```swift
@Suite struct OpenRouterSignInTests {
    let callback = URL(string: "http://127.0.0.1:49152/auth/callback")!

    @Test func authorizationURLCarriesCallbackChallengeAndState() throws {
        let attempt = try OpenRouterSignIn.make(callbackURL: callback)
        let items = Dictionary(uniqueKeysWithValues: URLComponents(url: attempt.authorizationURL, resolvingAgainstBaseURL: false)!.queryItems!.map { ($0.name, $0.value ?? "") })
        #expect(attempt.authorizationURL.absoluteString.hasPrefix("https://openrouter.ai/auth?"))
        #expect(items["callback_url"] == callback.absoluteString)
        #expect(items["code_challenge"] == OAuthAttempt.challenge(for: attempt.verifier))
        #expect(items["code_challenge_method"] == "S256" && items["state"] == attempt.state)
    }

    @Test func callbackNeedsTheSameStateAndACode() throws {
        let attempt = try OpenRouterSignIn.make(callbackURL: callback)
        #expect(try attempt.code(from: URL(string: "\(callback)?code=abc&state=\(attempt.state)")!) == "abc")
        #expect(throws: OAuthError.invalidCallback) { try attempt.code(from: URL(string: "\(callback)?code=abc&state=other")!) }
        #expect(throws: OAuthError.invalidCallback) { try attempt.code(from: URL(string: "\(callback)?state=\(attempt.state)")!) }
    }

    @Test func exchangeReplyYieldsTheKey() throws {
        #expect(try OpenRouterSignIn.key(from: Data(#"{"key":"fixture-or-key"}"#.utf8)) == "fixture-or-key")
        #expect(throws: OAuthError.invalidCallback) { try OpenRouterSignIn.key(from: Data("{}".utf8)) }
    }
}
```

- [ ] **Step 2: Run to verify it fails** — `-only-testing:MivuTests/OpenRouterSignInTests`.
- [ ] **Step 3: Implement.** Add `// shortcut: OpenRouter's acceptance of a 127.0.0.1 callback is unverified, fall back to a pasted key if sign-in cannot return` above `signInOpenRouter`.
- [ ] **Step 4: Run to verify it passes**, and rerun `-only-testing:MivuTests/SessionTests`.
- [ ] **Step 5: Commit** — `git commit -m "feat(connection): sign in to OpenRouter without copying a key"`

---

### Task 6: Screens

**Files:**
- Create: `ios/Mivu/Connection/KeyServiceViews.swift`
- Modify: `ios/Mivu/Diary/SettingsView.swift:205-246` (the `.connection` case) and `:55` (summary row)
- Modify: `ios/Mivu/Onboarding/OnboardingView.swift:149-158` (actions under the connect step)
- Test: `ios/MivuUITests/CoachUITests.swift` (next to the existing Coach AI settings test near line 555)

**Interfaces:**
- Consumes: Task 4 and Task 5 members of `ChatGPTConnection`; Task 1 `KeyService`.
- Produces:

```swift
struct UseAnotherAIView: View { init(connection: ChatGPTConnection, onConnected: @escaping () -> Void) }
struct ConnectKeyServiceView: View { init(connection: ChatGPTConnection, service: KeyService, onConnected: @escaping () -> Void) }
extension View { func sharingConsent(for service: KeyService, isPresented: Binding<Bool>, connection: ChatGPTConnection, onAgree: @escaping () -> Void) -> some View }
```

Accessibility identifiers: `onboardingUseAnotherAI`, `keyService.<rawValue>`, `keyField`, `saveKey`, `signInOpenRouter`, `replaceKey`, `removeKey`.

Follow the mockup in the spec. Exact copy:

- **UseAnotherAIView**: title `Use another AI`; lead `Bring a key from a service you already use.`; four rows showing `name` and `caption`; footer `You pay the service directly for what you use. Mivu adds nothing.`
- **Consent alert** (shown when a row is tapped and `consented(to:)` is false, before the connect screen): title `Share with \(company)?`; buttons `Agree and Continue` and `Not Now`; message `To estimate nutrition and answer Coach, Mivu sends \(company), using your own \(name) account, what you record: meals, photos, messages, weights, workouts, goals and profile details. Your diary stays on this iPhone, and you can remove the key any time in Settings.` For `.openAI`, reuse the existing `openAIConsent` flag through `recordConsent(to:)`.
- **ConnectKeyServiceView** (paste services): title `Connect \(name)`; row `Get a key` linking to `keyPage`; `SecureField("Paste your key")` with no autocapitalisation or autocorrection and a `Paste` button; footnotes `Stays in this iPhone's Keychain. Never in backups or exports.` and `You pay \(company) directly for what you use.` with a `Privacy policy` link to `MivuLinks.privacyPolicy`; primary button `Test and save`, showing a `ProgressView` while `isCheckingKey`. Errors, shown under the field with the typed text kept: `.invalidKey` → `Enter the key without spaces.`; `.rejected` → `\(name) rejected this key. Check it and try again.`; `.unavailable` → `Couldn't reach \(name). Check your connection and try again.`; `.storage` → `Could not save this key securely. Your input is still here.`
- **ConnectKeyServiceView** (`.openRouter`): the same title and cost footnote, and one primary button `Sign in to OpenRouter` calling `signInOpenRouter()`, with `Cancel connection` while `isConnecting`.
- **Settings › Coach AI**: replace the two-row `Picker` with one row per `Provider` in the order ChatGPT, Claude, OpenAI, Gemini, OpenRouter, Apple Intelligence. A row is a `Button`: available providers select on tap and show a checkmark when active; an unconnected key service shows trailing `Add key` (or `Sign in`) and opens `ConnectKeyServiceView` in a sheet after consent. Keep the existing ChatGPT and Apple captions and the Apple `selectionDisabled` rule. Footer for a key service: `Uses your \(name) key. Coach messages and photos you send are shared with \(company).` When a key service is active, add a section titled with its name: `Picker("Model", …)` over `serviceModels[service]`, `Link("Manage usage", destination: usagePage)`, `Replace key`, and destructive `Remove \(name) key` behind a confirmation dialog. The existing ChatGPT "Connection" section keeps its current condition.
- **Settings summary row** (`:55`): show `connection.activeName` when `canInfer`, else `Connect ChatGPT`.
- **Setup connect step**: above the Apple link add `Button("Use another AI")` with caption `Claude, OpenAI, Gemini or OpenRouter with your own key.`, presenting `UseAnotherAIView` in a sheet whose `onConnected` dismisses it and calls `go(to: .results)`.

- [ ] **Step 1: Write the failing UI test**

```swift
func testCoachAISettingsOffersKeyServicesAndAsksConsentFirst() {
    let app = launchCoachApp()                       // same launch helper the neighbouring settings test uses
    openCoachAISettings(app)                         // the helper at line ~558
    for name in ["Claude", "OpenAI", "Gemini", "OpenRouter"] {
        XCTAssertTrue(app.buttons["keyService.\(name == "OpenAI" ? "openAI" : name == "OpenRouter" ? "openRouter" : name.lowercased())"].exists, name)
    }
    app.buttons["keyService.claude"].tap()
    XCTAssertTrue(app.alerts["Share with Anthropic?"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.secureTextFields["keyField"].exists)      // no key screen before consent
    app.alerts.buttons["Agree and Continue"].tap()
    XCTAssertTrue(app.secureTextFields["keyField"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["saveKey"].exists)
}
```

Use the real helper names found beside the existing test; do not add new launch arguments.

- [ ] **Step 2: Run to verify it fails** — `-only-testing:MivuUITests/CoachUITests/testCoachAISettingsOffersKeyServicesAndAsksConsentFirst`.
- [ ] **Step 3: Implement the views and the two screen edits.**
- [ ] **Step 4: Run to verify it passes**, then run the existing tests that touch these screens: the Coach AI settings tests in `CoachUITests` (near lines 76 and 555), `DiaryUITests` near line 569, and the onboarding UI tests that reference `onboardingChooseApple`. Fix any that relied on the old `Picker`.
- [ ] **Step 5: Look at it.** Run the app in the reserved simulator, open Settings › Coach AI and the setup connect step, and compare with the mockup in light, dark and the largest Dynamic Type size. Save three screenshots under `docs/verification/bring-your-own-ai/`.
- [ ] **Step 6: Commit** — `git commit -m "feat(settings): add your own AI key from setup and Settings"`

---

### Task 7: Copy that assumed ChatGPT

**Files:**
- Modify: `ios/Mivu/Coach/CoachView.swift:469-480` and `:791`
- Modify: `ios/Mivu/Coach/CoachViewModel.swift:764-767`
- Modify: `ios/Mivu/Diary/TodayView.swift:208` and `:447`
- Modify: `ios/Mivu/Onboarding/OnboardingView.swift:299`, `:316`, `:319`
- Test: `ios/MivuTests/KeyConnectionTests.swift` (one added test)

**Interfaces:**
- Consumes: `connection.activeName`, `connection.activeUsagePage`, `connection.provider.keyService`.
- Produces: `func coachFailureText(_ error: any Error, serviceName: String?) -> String`, extracted from the existing private function in `CoachViewModel`. A `nil` name means ChatGPT. Its other branches stay unchanged.

Changes:

- `CoachView` footer: for a key service show `Using your \(name) key` with a `Manage usage` link to `activeUsagePage`. ChatGPT and Apple lines unchanged.
- `CoachView:791`: `Connect ChatGPT in Settings to continue` becomes `Connect a Coach AI in Settings to continue`.
- `CoachViewModel:764` and `:767`: with a key service active, `\(name) is busy right now. Your message is saved; try again soon.` and `Your \(name) account is out of credit or over its limit. Your message is saved; see Manage usage in Settings.` ChatGPT wording stays as is when ChatGPT is active.
- `TodayView:208`: observe `connection.canInfer` instead of `planAuthorized`, so a saved key resumes pending captures.
- `TodayView:447`: `Analyzes when ChatGPT is connected` becomes `Analyzes when a Coach AI is connected`, and the "Analyzing" branch keys off `canInfer`.
- `OnboardingView`: `ChatGPT couldn't answer just now…`, `ChatGPT is tuning your targets…` and `Tuned by ChatGPT` use `connection.activeName`.

- [ ] **Step 1: Write the failing test**

```swift
@Test func failureCopyNamesTheActiveService() {
    #expect(coachFailureText(ResponsesClient.Failure.quotaReached, serviceName: "Claude")
        == "Your Claude account is out of credit or over its limit. Your message is saved; see Manage usage in Settings.")
    #expect(coachFailureText(ResponsesClient.Failure.quotaReached, serviceName: nil)
        == "You've reached your ChatGPT usage limit. Your message is saved; see Manage usage in Settings.")
}
```

The view model calls it with `connection.provider.keyService?.name`.

- [ ] **Step 2: Run to verify it fails.**
- [ ] **Step 3: Make the edits above.**
- [ ] **Step 4: Run** `-only-testing:MivuTests/KeyConnectionTests`, then the suites whose assertions quote the changed strings: search `ios/MivuTests` and `ios/MivuUITests` for `Connect ChatGPT in Settings`, `Analyzes when ChatGPT` and `Tuned by ChatGPT`, update those expectations, and run the affected suites.
- [ ] **Step 5: Commit** — `git commit -m "fix(coach): name the active AI service in status and failure copy"`

---

### Task 8: Record, review and pull request

**Files:**
- Create: `docs/verification/2026-11-14-bring-your-own-ai.md`
- Modify: `docs/parity.md` (one new row)

- [ ] **Step 1: Run the feature's suites once more on the final commit:** `KeyServiceTests`, `KeyServiceWireTests`, `KeyServiceClientTests`, `KeyConnectionTests`, `OpenRouterSignInTests`, `CoachConnectionTests`, `ConnectionTests`, `ResponsesClientTests`, `SessionTests`, plus the UI tests named in Task 6. Record the result bundle path and counts.
- [ ] **Step 2: Write the verification record** with: the 40-character source SHA, Xcode and simulator versions, each suite's pass/fail counts, the three screenshots, and a table of the four services each marked **built, not verified live**. List the four open items from the spec's "Unverified until live testing". State plainly that no request has reached a real service. Do not run the full UI suite; say so.
- [ ] **Step 3: Add the parity row:** `| byo-ai | Bring your own AI key (Claude, OpenAI, Gemini, OpenRouter) | post-baseline | [spec](superpowers/specs/2026-11-14-bring-your-own-ai-design.md) | partial | pending | iOS: docs/verification/2026-11-14-bring-your-own-ai.md | Built on iOS, not verified against a live service. Android follows from the same spec. |` Run `python3 scripts/ci/parity.py` and the other script checks CI runs.
- [ ] **Step 4: Ponytail Review** of the branch diff, as `AGENTS.md` requires before merge. Fix blocking findings and rerun the affected suites.
- [ ] **Step 5: Commit** the record and parity row — `git commit -m "docs(coach): record bring-your-own-AI verification and parity"`.
- [ ] **Step 6: Rename the branch** to `feat/bring-your-own-ai`, push, and open a **draft** pull request titled `feat(coach): bring your own AI key`. The body states what was built, the test counts and SHA, and in its first paragraph that no service is verified live and that the owner will test with real keys before merge. Link the pull request to the thread.

## Not in this plan

- Android. It gets its own plan from the same spec once iOS is tested live.
- The privacy policy page and App Store answers. They are the owner's, outside this repository.
- Streaming, refusal fallbacks to another model, usage counters, QR key entry, custom server addresses.
