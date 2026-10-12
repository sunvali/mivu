import Foundation

struct CoachToolCall: Equatable, Sendable {
    let id: String
    let callID: String
    let name: String
    let namespace: String?
    let arguments: String
}

struct CoachInferenceResult: Equatable, Sendable {
    let model: String
    let text: String
    let calls: [CoachToolCall]
    // Preserve reasoning/encrypted content and all other complete items for stateless continuation.
    let outputItems: [Data]
}

enum CoachInferenceInput: Equatable, Sendable {
    enum Role: String, Sendable { case developer, user, assistant }
    case message(role: Role, text: String, images: [Data] = [])
    case priorOutput(Data)
    case functionOutput(callID: String, output: String)

    func object() throws -> [String: Any] {
        switch self {
        case let .message(role, text, images):
            guard text.utf8.count <= 65_536, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !images.isEmpty,
                  images.isEmpty || role == .user, images.count <= 8 else { throw ResponsesClient.Failure.invalidInput }
            var content: [[String: String]] = [["type": role == .assistant ? "output_text" : "input_text", "text": text]]
            for image in images {
                let mime = try Self.imageMIME(image)
                content.append(["type": "input_image", "image_url": "data:\(mime);base64," + image.base64EncodedString()])
            }
            return ["role": role.rawValue, "content": content]
        case let .priorOutput(data):
            guard data.count <= 1_048_576,
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = object["type"] as? String,
                  ["message", "function_call", "reasoning"].contains(type) else { throw ResponsesClient.Failure.invalidInput }
            return object
        case let .functionOutput(callID, output):
            guard !callID.isEmpty, callID.utf8.count <= 256, output.utf8.count <= 65_536 else { throw ResponsesClient.Failure.invalidInput }
            return ["type": "function_call_output", "call_id": callID, "output": output]
        }
    }

    static func imageMIME(_ data: Data) throws -> String {
        guard data.count <= 5_242_880 else { throw ResponsesClient.Failure.invalidInput }
        if data.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]) { return "image/png" }
        if data.starts(with: [255, 216, 255]), data.count >= 4 { return "image/jpeg" }
        throw ResponsesClient.Failure.invalidInput
    }
}
