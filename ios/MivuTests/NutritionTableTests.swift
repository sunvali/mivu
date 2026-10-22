import Foundation
import Testing
@testable import Mivu

struct NutritionTableTests {
    let table = NutritionTable.bundled

    @Test func searchPutsPlainFoodsBeforeDishesThatMentionThem() throws {
        #expect(try table.search("apple").first?.description == "Apple, raw")
        #expect(try table.search("diet cola").map(\.description).contains("Soft drink, cola, diet"))
        #expect(try table.search("big mac").first?.description == "Big Mac (McDonalds)")
        #expect(try table.search("pepperoni pizza").allSatisfy { $0.description.lowercased().contains("pepperoni") })
        #expect(try table.search("").isEmpty && table.search("\"*)").isEmpty, "Punctuation never reaches the FTS query")
    }

    @Test func portionsResolveUnitsAndSynonymsButNoDefaultServing() throws {
        let apple = try #require(try table.search("apple").first)
        #expect(try table.portionGrams(code: apple.code, unit: "medium") == 200)
        #expect(try table.portionGrams(code: apple.code, unit: "piece") == nil, "No default serving: the caller keeps the model estimate")
        let cola = try #require(try table.search("diet cola").first { $0.description == "Soft drink, cola, diet" })
        #expect(try table.portionGrams(code: cola.code, unit: "can") == 360)
        let pizza = try #require(try table.search("pepperoni pizza", limit: 30).first { $0.description == "Pizza with pepperoni, stuffed crust" })
        #expect(try table.portionGrams(code: pizza.code, unit: "slice") == 164, "A slice resolves to the general 1 piece, NFS portion")
        #expect(apple.per100Grams.kcal == 61)
    }
}
