import Foundation
import Testing
@testable import Mivu

@Suite(.serialized)
struct FoodEvidenceTests {
    @Test func missingKeyMakesNoRequest() async throws {
        let (client, capture) = fixture("{}")
        await #expect(throws: FoodEvidenceClient.Failure.notConfigured) { try await client.search(query: "synthetic", apiKey: nil) }
        await #expect(throws: FoodEvidenceClient.Failure.notConfigured) { try await client.fetch(id: 1, apiKey: nil) }
        #expect(capture.request == nil)
    }

    @Test func searchPreservesExactProviderValuesAndEncodesQuery() async throws {
        let (client, capture) = fixture(#"{"foods":[{"fdcId":123,"dataType":"Foundation","description":"Synthetic packaged food","brandOwner":"Fixture brand","foodNutrients":[{"nutrientId":1008,"unitName":"KCAL","value":90},{"nutrientId":1003,"unitName":"G","value":2.5}]}]}"#)
        let results = try await client.search(query: "Fixture brand / restaurant & soup", apiKey: "fixture-key")
        let result = try #require(results.first)
        #expect(results.count == 1 && result.id == 123 && result.brand == "Fixture brand")
        #expect(result.per100Grams == NutritionValues(kcal: 90, protein: 2.5))
        #expect(result.fetchedAt == Date(timeIntervalSince1970: 100))
        #expect(result.reference == "https://fdc.nal.usda.gov/food-details/123/nutrients")
        let request = try #require(capture.request)
        let items = try #require(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(items.first { $0.name == "query" }?.value == "Fixture brand / restaurant & soup")
        #expect(items.first { $0.name == "pageSize" }?.value == "10")
        #expect(request.timeoutInterval == 30)
        #expect(!result.reference.contains("fixture-key"))
    }

    @Test func fullFoodAndGramScalingPreserveSourceAndUnknowns() async throws {
        let (client, _) = fixture(#"{"fdcId":123,"dataType":"Foundation","description":"Synthetic full food","foodNutrients":[{"nutrient":{"id":1005,"unitName":"g"},"amount":12},{"nutrient":{"id":1004,"unitName":"g"},"amount":3}]}"#)
        let record = try await client.fetch(id: 123, apiKey: "fixture-key")
        let item = FoodItem(name: record.name, quantity: 50, unit: "g", nutrition: record.per100Grams.scaled(by: 0.5), provenance: .identifiedSource, reference: record.reference, nutritionBasis: record.per100Grams)
        #expect(item.nutrition == NutritionValues(carbs: 6, fat: 1.5))
        #expect(item.nutritionBasis == record.per100Grams && item.reference == record.reference && item.provenance == .identifiedSource)
    }

    @Test func kilojoulesAndAlternateEnergyDoNotInventCalories() async throws {
        let (client, _) = fixture(#"{"foods":[{"fdcId":123,"dataType":"Foundation","description":"Synthetic energy","foodNutrients":[{"nutrientId":1062,"unitName":"kJ","value":400},{"nutrientId":2047,"unitName":"kcal","value":95}]}]}"#)
        #expect(try await client.search(query: "synthetic", apiKey: "fixture-key").first?.per100Grams.kcal == nil)
    }

    @Test func rejectsInvalidNutrientsAndCounts() async throws {
        let invalid = [
            #"[{"nutrientId":1003,"unitName":"g","value":-1}]"#,
            #"[{"nutrientId":1008,"unitName":"kJ","value":42}]"#,
            #"[{"nutrientId":1003,"unitName":"mg","value":42}]"#,
            #"[{"nutrientId":1003,"unitName":"g","value":2},{"nutrientId":1003,"unitName":"g","value":3}]"#,
            #"[{"nutrientId":1003,"unitName":"g","value":1e999}]"#,
            #"[{"nutrientId":1003,"unitName":"g"}]"#
        ]
        for nutrients in invalid {
            let (client, _) = fixture("{\"foods\":[{\"fdcId\":123,\"dataType\":\"Foundation\",\"description\":\"Synthetic\",\"foodNutrients\":\(nutrients)}]}")
            await #expect(throws: FoodEvidenceClient.Failure.invalidResponse) { try await client.search(query: "synthetic", apiKey: "fixture-key") }
        }
        for body in ["{}", "{\"foods\":[{}]}", "{\"foods\":[" + Array(repeating: "{\"fdcId\":1,\"dataType\":\"Foundation\",\"description\":\"Synthetic\"}", count: 11).joined(separator: ",") + "]}"] {
            let (client, _) = fixture(body)
            await #expect(throws: FoodEvidenceClient.Failure.invalidResponse) { try await client.search(query: "synthetic", apiKey: "fixture-key") }
        }
    }

    @Test func emptyResultsAndFoodWithoutNutrientsRemainRepresentable() async throws {
        let (empty, _) = fixture(#"{"foods":[]}"#)
        #expect(try await empty.search(query: "synthetic", apiKey: "fixture-key").isEmpty)
        let (unknown, _) = fixture(#"{"fdcId":1,"dataType":"Foundation","description":"Synthetic unknown","brandName":"Fixture alternate brand"}"#)
        let food = try await unknown.fetch(id: 1, apiKey: "fixture-key")
        #expect(food.per100Grams == NutritionValues() && food.brand == "Fixture alternate brand")
        #expect(try JSONDecoder().decode(FoodEvidenceRecord.self, from: JSONEncoder().encode(food)) == food)
    }

    @Test func onlyDocumentedGramBasisBecomesPer100Grams() async throws {
        let foods = [
            #"{"fdcId":1,"dataType":"Foundation","description":"Synthetic gram food","foodNutrients":[{"nutrientId":1008,"unitName":"kcal","value":80}]}"#,
            #"{"fdcId":2,"dataType":"SR Legacy","description":"Synthetic legacy food"}"#,
            #"{"fdcId":3,"dataType":"Survey (FNDDS)","description":"Synthetic survey food"}"#,
            #"{"fdcId":4,"dataType":"Branded","description":"Synthetic volume beverage","servingSizeUnit":"ml","foodNutrients":[{"nutrientId":1008,"unitName":"kcal","value":100}]}"#,
            #"{"fdcId":5,"dataType":"Branded","description":"Synthetic unsupported branded solid","servingSizeUnit":"g"}"#,
            #"{"fdcId":6,"dataType":"Future type","description":"Synthetic unknown basis"}"#,
            #"{"fdcId":7,"description":"Synthetic absent basis"}"#
        ]
        let (client, _) = fixture("{\"foods\":[" + foods.joined(separator: ",") + "]}")
        let records = try await client.search(query: "synthetic", apiKey: "fixture-key")
        #expect(records.map(\.id) == [1, 2, 3])
        #expect(records.first?.per100Grams.kcal == 80)
        for (offset, food) in foods.enumerated() where offset >= 3 {
            let (unsupported, _) = fixture(food)
            await #expect(throws: FoodEvidenceClient.Failure.invalidResponse) { try await unsupported.fetch(id: offset + 1, apiKey: "fixture-key") }
        }
    }

    @Test func transportErrorDoesNotExposeSecretURL() async throws {
        let (client, _) = fixture("{}")
        FoodFixtureProtocol.failure = NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut,
                                             userInfo: [NSURLErrorFailingURLErrorKey: URL(string: "https://api.nal.usda.gov/?api_key=fixture-key")!])
        do { _ = try await client.fetch(id: 1, apiKey: "fixture-key"); Issue.record("Expected failure") }
        catch { #expect(error as? FoodEvidenceClient.Failure == .unavailable); #expect(!String(describing: error).contains("fixture-key")) }
    }

    @Test func inputBoundsMakeNoRequest() async throws {
        let (client, capture) = fixture("{}")
        for query in [" ", String(repeating: "x", count: 201), String(repeating: "é", count: 101)] {
            await #expect(throws: FoodEvidenceClient.Failure.invalidInput) { try await client.search(query: query, apiKey: "fixture-key") }
        }
        for key in [" ", "has space", String(repeating: "x", count: 257)] {
            await #expect(throws: FoodEvidenceClient.Failure.invalidInput) { try await client.fetch(id: 1, apiKey: key) }
        }
        await #expect(throws: FoodEvidenceClient.Failure.invalidInput) { try await client.fetch(id: 0, apiKey: "fixture-key") }
        #expect(capture.request == nil)
    }

    @Test func safeProviderFailures() async throws {
        for (status, expected) in [(401, FoodEvidenceClient.Failure.unauthorized), (403, .unauthorized), (429, .rateLimit), (500, .unavailable), (404, .unavailable)] {
            let (client, _) = fixture("fixture-key", status: status)
            do { _ = try await client.fetch(id: 1, apiKey: "fixture-key"); Issue.record("Expected failure") }
            catch { #expect(error as? FoodEvidenceClient.Failure == expected); #expect(!String(describing: error).contains("fixture-key")) }
        }
    }

    @Test func rejectsStreamOverByteLimitAndWrongFetchID() async throws {
        for body in [String(repeating: " ", count: 2_097_153), #"{"fdcId":2,"dataType":"Foundation","description":"Synthetic"}"#] {
            let (client, capture) = fixture(body)
            let oversized = body.utf8.count > 2_097_152
            FoodFixtureProtocol.holdOpen = oversized
            await #expect(throws: FoodEvidenceClient.Failure.invalidResponse) { try await client.fetch(id: 1, apiKey: "fixture-key") }
            if oversized {
                for _ in 0..<100 where !capture.stopped { try await Task.sleep(for: .milliseconds(5)) }
                #expect(capture.stopped)
            }
        }
    }
}

private final class FoodRequestCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: URLRequest?
    private var didStop = false
    var stopped: Bool { lock.withLock { didStop } }
    func stop() { lock.withLock { didStop = true } }
    var request: URLRequest? { lock.withLock { stored } }
    func save(_ request: URLRequest) { lock.withLock { stored = request } }
}

private final class FoodFixtureProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var body = Data()
    nonisolated(unsafe) static var holdOpen = false
    nonisolated(unsafe) static var failure: NSError?
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var capture = FoodRequestCapture()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.capture.save(request)
        if let failure = Self.failure { client?.urlProtocol(self, didFailWithError: failure); return }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        for offset in stride(from: 0, to: Self.body.count, by: 4096) {
            client?.urlProtocol(self, didLoad: Self.body.subdata(in: offset..<min(offset + 4096, Self.body.count)))
        }
        if !Self.holdOpen { client?.urlProtocolDidFinishLoading(self) }
    }
    override func stopLoading() { Self.capture.stop() }
}

private func fixture(_ body: String, status: Int = 200) -> (FoodEvidenceClient, FoodRequestCapture) {
    let capture = FoodRequestCapture()
    FoodFixtureProtocol.holdOpen = false
    FoodFixtureProtocol.failure = nil
    FoodFixtureProtocol.body = Data(body.utf8)
    FoodFixtureProtocol.status = status
    FoodFixtureProtocol.capture = capture
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [FoodFixtureProtocol.self]
    return (FoodEvidenceClient(session: URLSession(configuration: config), clock: { Date(timeIntervalSince1970: 100) }), capture)
}
