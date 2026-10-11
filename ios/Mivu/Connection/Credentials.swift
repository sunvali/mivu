import CryptoKit
import Foundation

struct AccountRegistration: Codable, Equatable, Sendable {
    let identity: VerifiedIdentity
    let issuedClientID: String

    var id: String {
        let tuple = try! JSONEncoder().encode([identity.issuer, identity.subject, issuedClientID])
        return SHA256.hash(data: tuple).map { String(format: "%02x", $0) }.joined()
    }
}

struct Credentials: Codable, Equatable, Sendable {
    let registration: AccountRegistration
    let accessToken: String
    let refreshToken: String?
    let idToken: String
    let scopes: Set<String>
    let expiresAt: Date

    var registrationID: String { registration.id }
    var planPermissionGranted: Bool {
        scopes.isSuperset(of: ["resource.invoke", "chatgpt.tokens.use.direct"])
    }
}

struct SessionSnapshot: Equatable, Sendable {
    let registration: AccountRegistration
    let scopes: Set<String>
    let planPermissionGranted: Bool

    var registrationID: String { registration.id }
    var issuedClientID: String { registration.issuedClientID }
    var identity: VerifiedIdentity { registration.identity }

    init(_ credentials: Credentials) {
        registration = credentials.registration
        scopes = credentials.scopes
        planPermissionGranted = credentials.planPermissionGranted
    }
}
