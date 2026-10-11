import Testing
@testable import Mivu

@Suite @MainActor
struct ProofStateTests {
    @Test func initialConnectionDoesNotClaimInference() {
        let connection = ChatGPTConnection()
        #expect(connection.state == .disconnected)
        #expect(connection.lastCompletedProbe == nil)
    }
}
