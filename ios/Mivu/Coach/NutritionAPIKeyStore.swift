import Foundation
import Security

struct NutritionAPIKeyStore: Sendable {
    enum Failure: Error, Equatable { case invalidKey, unavailable }
    let service: String
    init(service: String = "Mivu.NutritionLookup") { self.service = service }
    @MainActor static var local: NutritionAPIKeyStore {
        NutritionAPIKeyStore(service: DiaryLaunch.testID.map { "Mivu.NutritionLookupTest." + $0.uuidString } ?? "Mivu.NutritionLookup")
    }
    private var query: [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "USDA"] }
    func load() throws -> String? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data, let key = String(data: data, encoding: .utf8) else { throw Failure.unavailable }
        return key
    }
    func save(_ key: String) throws {
        guard !key.isEmpty, key.utf8.count <= 256,
              !key.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.union(.controlCharacters).contains($0) }) else { throw Failure.invalidKey }
        let data = Data(key.utf8)
        let update = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else { throw Failure.unavailable }
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw Failure.unavailable }
    }
    func remove() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw Failure.unavailable }
    }
}

struct NutritionKeyDraft {
    var text = ""
    var message: String?
    mutating func save(using write: (String) throws -> Void) -> Bool {
        do { try write(text); text = ""; message = "Nutrition lookup key saved securely."; return true }
        catch {
            message = error as? NutritionAPIKeyStore.Failure == .invalidKey
                ? "Enter a key without spaces, up to 256 characters."
                : "Could not save this key securely. Your input is still here."
            return false
        }
    }
}
