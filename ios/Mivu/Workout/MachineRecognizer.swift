import Foundation

/// The exercise a gym machine photo most likely shows, and up to four it could be (catalog IDs, best first).
struct MachineGuess: Equatable, Sendable {
    let best: String
    let options: [String]
}

/// Names the exercise in a machine photo with ChatGPT. The photo lives only in this request; nothing is stored.
struct MachineRecognizer: Sendable {
    let infer: @Sendable ([CoachInferenceInput], Data?) async throws -> CoachInferenceResult

    init(infer: @escaping @Sendable ([CoachInferenceInput], Data?) async throws -> CoachInferenceResult) { self.infer = infer }

    /// Only ChatGPT reads photos here; connecting already required the sharing consent.
    static func offered(provider: ChatGPTConnection.Provider, connected: Bool) -> Bool { provider == .chatGPT && connected }

    private static let machines = WorkoutCatalog.exercises.filter(\.machine)

    static let prompt = """
        This photo shows a gym machine. Which of these exercises is it for? Reply with JSON only: \
        {"best": id, "options": [ids]}. List every exercise the machine is commonly used for in options \
        (up to 4, best first); a single-use machine has one. Use only these ids:
        """ + "\n" + machines.map { "\($0.id): \($0.name)" }.joined(separator: "\n")

    func recognize(jpeg: Data) async -> MachineGuess? {
        guard let result = try? await infer([.message(role: .user, text: Self.prompt, images: [jpeg])], nil) else { return nil }
        return Self.guess(from: result.text)
    }

    /// Reads the reply, tolerating a code fence; IDs that are not catalog machines are dropped.
    static func guess(from text: String) -> MachineGuess? {
        guard let open = text.firstIndex(of: "{"), let close = text.lastIndex(of: "}"),
              let object = try? JSONSerialization.jsonObject(with: Data(text[open...close].utf8)) as? [String: Any],
              let best = object["best"] as? String, machines.contains(where: { $0.id == best }) else { return nil }
        let listed = (object["options"] as? [String] ?? []).filter { id in id != best && machines.contains { $0.id == id } }
        var options = [best]
        for id in listed where !options.contains(id) { options.append(id) }
        return MachineGuess(best: best, options: Array(options.prefix(4)))
    }
}
