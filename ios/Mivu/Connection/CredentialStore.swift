import Foundation
import Security

protocol CredentialStoring: Sendable {
    func hostID() throws -> String
    func registrations() throws -> [AccountRegistration]
    func load(registrationID: String) throws -> Credentials?
    func replace(_ credentials: Credentials) throws
    func delete(registrationID: String) throws
}

enum CredentialStoreError: Error, Equatable {
    case keychain(OSStatus), invalidRecord
}

struct CredentialStore: CredentialStoring {
    private let service: String

    init(service: String = "com.yakov103.mivu.account-sessions") { self.service = service }

    func hostID() throws -> String {
        if let data = try read(account: "host") {
            guard let value = String(data: data, encoding: .utf8), value.hasPrefix("urn:uuid:"), UUID(uuidString: String(value.dropFirst(9))) != nil else {
                throw CredentialStoreError.invalidRecord
            }
            return value
        }
        let value = "urn:uuid:\(UUID().uuidString.lowercased())"
        var query = baseQuery(account: "host")
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        query[kSecValueData as String] = Data(value.utf8)
        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem { return try hostID() }
        guard status == errSecSuccess else { throw CredentialStoreError.keychain(status) }
        return value
    }

    func registrations() throws -> [AccountRegistration] {
        var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                  kSecAttrService as String: service,
                                  kSecReturnAttributes as String: true,
                                  kSecReturnData as String: true,
                                  kSecMatchLimit as String: kSecMatchLimitAll]
        query[kSecAttrSynchronizable as String] = false
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess, let items = result as? [[String: Any]] else {
            throw CredentialStoreError.keychain(status)
        }
        return try items.compactMap { item in
            guard let account = item[kSecAttrAccount as String] as? String,
                  account.hasPrefix("registration:"), let data = item[kSecValueData as String] as? Data else { return nil }
            let registration = try JSONDecoder().decode(AccountRegistration.self, from: data)
            guard account == "registration:\(registration.id)" else { throw CredentialStoreError.invalidRecord }
            return registration
        }.sorted { $0.id < $1.id }
    }

    func load(registrationID: String) throws -> Credentials? {
        guard let data = try read(account: "credentials:\(registrationID)") else { return nil }
        let credentials = try JSONDecoder().decode(Credentials.self, from: data)
        guard credentials.registrationID == registrationID,
              credentials.registration.identity.issuer == "https://auth.openai.com",
              !credentials.registration.identity.subject.isEmpty,
              !credentials.registration.issuedClientID.isEmpty,
              credentials.registration.issuedClientID != "dynamic_agent_client",
              !credentials.accessToken.isEmpty, !credentials.idToken.isEmpty else {
            throw CredentialStoreError.invalidRecord
        }
        return credentials
    }

    func replace(_ credentials: Credentials) throws {
        let data = try JSONEncoder().encode(credentials)
        try write(JSONEncoder().encode(credentials.registration), account: "registration:\(credentials.registrationID)")
        // All rotating tokens and expiry replace one Keychain value atomically.
        try write(data, account: "credentials:\(credentials.registrationID)")
    }

    func delete(registrationID: String) throws {
        let status = SecItemDelete(baseQuery(account: "credentials:\(registrationID)") as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CredentialStoreError.keychain(status)
        }
    }

    private func baseQuery(account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: account, kSecAttrSynchronizable as String: false]
    }

    private func read(account: String) throws -> Data? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw CredentialStoreError.keychain(status) }
        return data
    }

    private func write(_ data: Data, account: String) throws {
        let attributes: [String: Any] = [kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let query = baseQuery(account: account)
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            let added = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
            guard added == errSecSuccess else { throw CredentialStoreError.keychain(added) }
        } else if status != errSecSuccess { throw CredentialStoreError.keychain(status) }
    }
}
