import Foundation
import CryptoKit

extension CoachWrite {
    func commandFingerprint() throws -> String {
        func nullable<T>(_ value: T?) -> Any { value.map { $0 as Any } ?? NSNull() }
        func object<Value: Encodable>(_ value: Value) throws -> [String: Any] {
            guard let result = try JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any] else { throw DiaryError.invalidData }; return result
        }
        func foods(_ items: [FoodItem]) throws -> [[String: Any]] {
            try items.map { item in var result = try object(item); result.removeValue(forKey: "id"); return result }
        }
        func workout(_ draft: WorkoutDraft) throws -> [String: Any] {
            ["kind": draft.kind.rawValue, "duration": draft.durationMinutes, "exercises": try draft.exercises.map(object), "burn": nullable(draft.estimatedBurnKcal), "source": nullable(draft.burnSource?.rawValue)]
        }
        var payload: [String: Any] = ["domain": "mivu.coach.command.v1", "target": target]
        switch self {
        case .food(let date, let items, let time, let review): payload["arguments"] = ["date": date, "items": try foods(items), "time": nullable(time?.timeIntervalSinceReferenceDate), "review": review]
        case .correction(_, let item, let revision):
            // correct_item supplies quantity only; copied live nutrition is grounding, not new intent.
            payload["arguments"] = ["quantity": item.quantity, "revision": revision]
        case .close(_, let completeness): payload["arguments"] = completeness.rawValue
        case .weight(_, let value, let unit, let revision): payload["arguments"] = ["value": value, "unit": unit, "revision": nullable(revision)]
        case .correctWeight(_, let value, let unit, let revision): payload["arguments"] = ["value": value, "unit": unit, "revision": revision]
        case .workout(_, let draft): payload["arguments"] = try workout(draft)
        case .editWorkout(_, let draft, let revision): payload["arguments"] = ["workout": try workout(draft), "revision": revision]
        case .deleteWeight(_, let revision), .deleteWorkout(_, let revision): payload["arguments"] = revision
        case .manual(let edit, let patchKey):
            var arguments: [String: Any] = [:]
            switch edit {
            case .item(_, let item, let revision, let submission, let explicitNutrients, let original):
                arguments = ["revision": revision, "submission": nullable(submission?.uuidString)]
                if item.name != original.name { arguments["name"] = item.name }
                if item.unit != original.unit { arguments["unit"] = item.unit }
                if item.quantity != original.quantity { arguments["quantity"] = item.quantity }
                for (key, field) in [("kcal", \NutritionValues.kcal), ("carbs", \NutritionValues.carbs), ("protein", \NutritionValues.protein), ("fat", \NutritionValues.fat)] where explicitNutrients.contains(key) { arguments[key] = nullable(item.nutrition[keyPath: field]) }
            case .append(_, let items, let revision): arguments = ["items": try foods(items), "revision": revision]
            case .accept(_, _, let revision), .deleteMeal(_, let revision), .deletePhoto(_, _, let revision), .retry(_, let revision), .startDay(let revision): arguments = ["revision": revision]
            case .move(_, let date, let revision, _): arguments = ["date": date, "revision": revision]
            case .attach(_, let ids, let role, let revision): arguments = ["photos": ids.map(\.uuidString).sorted(), "role": role.rawValue, "revision": revision]
            case .goals(_, let targets, let weight, let clear, let credit, let revision):
                arguments = ["targets": targets.sorted { $0.nutrient < $1.nutrient }.map { ["nutrient": $0.nutrient, "value": nullable($0.value)] }, "weight": nullable(weight), "clear": clear, "credit": nullable(credit), "revision": nullable(revision)]
            case .preferences(let timezone, let text, let revision): arguments = ["timezone": nullable(timezone), "text": nullable(text), "revision": revision]
            case .coverage(_, let completeness): arguments = ["coverage": completeness.rawValue]
            case .open: break
            }
            // Parser patch keys preserve explicit supplied fields even when current values later match.
            if let patchKey {
                let guards = arguments.filter { ["revision", "submission"].contains($0.key) }
                arguments = guards; arguments["patch"] = patchKey
            }
            payload["arguments"] = arguments
        }
        let bytes = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }
}
