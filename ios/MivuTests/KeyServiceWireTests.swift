import Foundation
import Testing
@testable import Mivu

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
        let responsesItem = try! JSONSerialization.data(withJSONObject: ["type": "message", "role": "assistant", "content": [Any]()])
        #expect(throws: ResponsesClient.Failure.invalidInput) { try MessagesWire.body(model: "m", input: [.priorOutput(responsesItem)], toolNamespace: nil) }
        #expect(throws: ResponsesClient.Failure.invalidInput) { try ChatCompletionsWire.body(model: "m", input: [.priorOutput(responsesItem)], toolNamespace: nil) }
    }
}

private let png = Data([137, 80, 78, 71, 13, 10, 26, 10])
private let namespace = try! JSONSerialization.data(withJSONObject: [
    "type": "namespace", "name": "mivu", "description": "Synthetic tools",
    "tools": [["type": "function", "name": "log_meal", "description": "Log a meal", "strict": true,
               "parameters": ["type": "object", "properties": ["kcal": ["type": ["number", "null"]]]]]]])

private func object(_ data: Data) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
}
private func claudeReply(content: [[String: Any]], stop: String) -> Data {
    try! JSONSerialization.data(withJSONObject: ["model": "claude-haiku-5-5", "content": content, "stop_reason": stop])
}
private func chatReply(message: [String: Any], finish: String) -> Data {
    try! JSONSerialization.data(withJSONObject: ["model": "m", "choices": [["message": message, "finish_reason": finish]]])
}
