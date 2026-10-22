import Foundation
import FoundationModels
import Testing
@testable import Mivu

struct AppleInferenceTests {
    @Test func everyCoachToolBecomesAnAppleToolDefinition() throws {
        guard #available(iOS 27.0, *) else { Issue.record("Apple inference requires iOS 27"); return }
        let namespace = try CoachTools.declarations()
        let tools = try #require((try JSONSerialization.jsonObject(with: namespace) as? [String: Any])?["tools"] as? [[String: Any]])
        let definitions = try AppleInference.toolDefinitions(namespace)
        #expect(definitions.map(\.name) == tools.map { $0["name"] as? String })
        for (definition, tool) in zip(definitions, tools) {
            let source = try #require((tool["parameters"] as? [String: Any])?["properties"] as? [String: Any])
            let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(definition.parameters)) as? [String: Any]
            let properties = try #require(encoded?["properties"] as? [String: Any], "\(definition.name)")
            #expect(Set(properties.keys) == Set(source.keys), "\(definition.name)")
        }
    }
}
