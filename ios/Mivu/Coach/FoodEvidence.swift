import Foundation

struct FoodEvidenceRecord: Codable, Equatable, Sendable, Identifiable {
    let id: Int
    let name: String
    let brand: String?
    let per100Grams: NutritionValues
    let reference: String
    let fetchedAt: Date
}

struct FoodEvidenceClient: Sendable {
    enum Failure: Error, Equatable { case notConfigured, unauthorized, rateLimit, unavailable, invalidResponse, invalidInput }
    let session: URLSession
    let clock: @Sendable () -> Date
    init(session: URLSession = URLSession(configuration: .ephemeral), clock: @escaping @Sendable () -> Date = { Date() }) {
        self.session = session
        self.clock = clock
    }
    func search(query: String, apiKey: String?) async throws -> [FoodEvidenceRecord] {
        let key = try validatedKey(apiKey)
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              query.utf8.count <= 200 else { throw Failure.invalidInput }
        let data = try await load(path: "/fdc/v1/foods/search", items: [URLQueryItem(name: "query", value: query), URLQueryItem(name: "pageSize", value: "10")], key: key)
        do {
            let response = try JSONDecoder().decode(SearchResponse.self, from: data)
            guard response.foods.count <= 10, Set(response.foods.map(\.fdcId)).count == response.foods.count else { throw Failure.invalidResponse }
            let fetchedAt = clock()
            return try response.foods.filter(\.hasGramBasis).map { try $0.record(at: fetchedAt) }
        } catch { throw Failure.invalidResponse }
    }

    func fetch(id: Int, apiKey: String?) async throws -> FoodEvidenceRecord {
        let key = try validatedKey(apiKey)
        guard id > 0 else { throw Failure.invalidInput }
        let data = try await load(path: "/fdc/v1/food/\(id)", items: [], key: key)
        do {
            let food = try JSONDecoder().decode(ProviderFood.self, from: data)
            guard food.fdcId == id else { throw Failure.invalidResponse }
            return try food.record(at: clock())
        } catch { throw Failure.invalidResponse }
    }

    private func validatedKey(_ key: String?) throws -> String {
        guard let key else { throw Failure.notConfigured }
        guard !key.isEmpty, key.utf8.count <= 256,
              !key.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.union(.controlCharacters).contains($0) }) else { throw Failure.invalidInput }
        return key
    }

    private func load(path: String, items: [URLQueryItem], key: String) async throws -> Data {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.nal.usda.gov"
        components.path = path
        components.queryItems = items + [URLQueryItem(name: "api_key", value: key)]
        guard let url = components.url else { throw Failure.invalidInput }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (bytes, response) = try await session.bytes(for: request, delegate: FoodEvidenceRedirectPolicy())
            defer { bytes.task.cancel() }
            guard let response = response as? HTTPURLResponse else { throw Failure.invalidResponse }
            switch response.statusCode {
            case 200: break
            case 401, 403: throw Failure.unauthorized
            case 429: throw Failure.rateLimit
            default: throw Failure.unavailable
            }
            let limit = 2_097_152
            guard response.expectedContentLength <= limit else { throw Failure.invalidResponse }
            var data = Data()
            for try await byte in bytes {
                guard data.count < limit else { throw Failure.invalidResponse }
                data.append(byte)
            }
            return data
        } catch let error as Failure { throw error }
        catch {
            if Task.isCancelled { throw CancellationError() }
            // Provider and transport errors can contain the secret-bearing request URL.
            throw Failure.unavailable
        }
    }
}

private struct SearchResponse: Decodable {
    let foods: [ProviderFood]
}

private struct ProviderFood: Decodable {
    let fdcId: Int
    let dataType: String?
    let description: String
    let brandOwner: String?
    let brandName: String?
    let foodNutrients: [ProviderNutrient]?

    // Branded values can be standardized per100ml; serving units do not prove nutrient mass basis.
    var hasGramBasis: Bool {
        guard let dataType else { return false }
        return ["Foundation", "SR Legacy", "Survey (FNDDS)"].contains(dataType)
    }

    func record(at date: Date) throws -> FoodEvidenceRecord {
        guard hasGramBasis, fdcId > 0, !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              description.count <= 500, date.timeIntervalSince1970.isFinite,
              (brandOwner?.count ?? 0) <= 500, (brandName?.count ?? 0) <= 500,
              (foodNutrients?.count ?? 0) <= 1000 else { throw FoodEvidenceClient.Failure.invalidResponse }
        var seen: [Int: NutrientAmount] = [:]
        var values = NutritionValues()
        for nutrient in foodNutrients ?? [] {
            let (id, amount) = try nutrient.validated()
            if let previous = seen[id], previous != amount { throw FoodEvidenceClient.Failure.invalidResponse }
            seen[id] = amount
            switch id {
            case 1008:
                guard amount.unit == "kcal" else { throw FoodEvidenceClient.Failure.invalidResponse }
                values.kcal = amount.value
            case 1003, 1004, 1005:
                guard amount.unit == "g" else { throw FoodEvidenceClient.Failure.invalidResponse }
                if id == 1003 { values.protein = amount.value }
                if id == 1004 { values.fat = amount.value }
                if id == 1005 { values.carbs = amount.value }
            default: break // Distinct energy methods (2047/2048) are not substituted for 1008.
            }
        }
        return FoodEvidenceRecord(id: fdcId, name: description, brand: brandOwner ?? brandName,
                                  per100Grams: values, reference: "https://fdc.nal.usda.gov/food-details/\(fdcId)/nutrients", fetchedAt: date)
    }
}

private struct NutrientAmount: Equatable {
    let value: Double
    let unit: String
}

private struct ProviderNutrient: Decodable {
    struct Detail: Decodable { let id: Int; let unitName: String }
    let nutrientId: Int?
    let unitName: String?
    let value: Double?
    let nutrient: Detail?
    let amount: Double?

    func validated() throws -> (Int, NutrientAmount) {
        guard let id = nutrientId ?? nutrient?.id, id > 0,
              let value = value ?? amount, value.isFinite, value >= 0,
              let unit = unitName ?? nutrient?.unitName,
              ["g", "mg", "µg", "ug", "kcal", "kj", "iu"].contains(unit.lowercased()),
              nutrientId == nil || nutrient == nil || nutrientId == nutrient?.id,
              self.value == nil || amount == nil || self.value == amount,
              unitName == nil || nutrient == nil || unitName?.lowercased() == nutrient?.unitName.lowercased()
        else { throw FoodEvidenceClient.Failure.invalidResponse }
        return (id, NutrientAmount(value: value, unit: unit.lowercased()))
    }
}

private final class FoodEvidenceRedirectPolicy: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        // A redirect must never forward the runtime key to another destination.
        completionHandler(nil)
    }
}
