import Foundation
import JOSESwift
import Security
import Testing
@testable import Mivu

struct SyntheticIdentityToken {
    let key: SecKey
    let jwks: Data
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let clientID = "oaiapp_synthetic"
    let nonce = "synthetic-nonce"

    init(kid: String = "synthetic-key") throws {
        let attributes: [String: Any] = [kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
                                       kSecAttrKeySizeInBits as String: 2048]
        var error: Unmanaged<CFError>?
        key = try #require(SecKeyCreateRandomKey(attributes as CFDictionary, &error))
        let publicKey = try #require(SecKeyCopyPublicKey(key))
        let jwk = try RSAPublicKey(publicKey: publicKey)
        let data = try #require(jwk.jsonString()?.data(using: .utf8))
        var fields = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        fields["kid"] = kid
        fields["use"] = "sig"
        fields["alg"] = "RS256"
        jwks = try JSONSerialization.data(withJSONObject: ["keys": [fields]])
    }

    func token(changes: [String: Any] = [:], header changesToHeader: [String: Any] = [:]) throws -> String {
        var claims: [String: Any] = ["iss": "https://auth.openai.com", "sub": "synthetic-account",
            "aud": clientID, "iat": Int(now.timeIntervalSince1970) - 10,
            "exp": Int(now.timeIntervalSince1970) + 300, "nonce": nonce]
        claims.merge(changes) { _, new in new }
        var fields: [String: Any] = ["alg": "RS256", "kid": "synthetic-key"]
        fields.merge(changesToHeader) { _, new in new }
        return try JWS(header: JWSHeader(parameters: fields),
            payload: Payload(JSONSerialization.data(withJSONObject: claims)),
            signer: #require(Signer(signatureAlgorithm: .RS256, key: key))).compactSerializedString
    }
}

struct IDTokenValidatorTests {
    @Test func validatesSignedIdentity() throws {
        let fixture = try SyntheticIdentityToken()
        let identity = try IDTokenValidator().validate(fixture.token(), jwks: fixture.jwks,
            clientID: fixture.clientID, nonce: fixture.nonce, now: fixture.now)
        #expect(identity == VerifiedIdentity(issuer: "https://auth.openai.com", subject: "synthetic-account"))
    }
}

extension IDTokenValidatorTests {
    @Test func rejectsMalformedToken() {
        #expect(throws: IDTokenError.invalidToken) {
            try IDTokenValidator().validate("invalid", jwks: Data("{}".utf8), clientID: "oaiapp_synthetic",
                                             nonce: "synthetic-nonce", now: .now)
        }
    }

    @Test(arguments: ["iss", "sub", "aud", "nonce", "expired", "future", "missingIat", "fractionalIat", "nbf", "multiAudience"])
    func rejectsInvalidClaims(_ change: String) throws {
        let fixture = try SyntheticIdentityToken()
        let seconds = Int(fixture.now.timeIntervalSince1970)
        let mutations: [String: [String: Any]] = [
            "iss": ["iss": "https://untrusted.example"], "sub": ["sub": "  "],
            "aud": ["aud": "oaiapp_other"], "nonce": ["nonce": "another-nonce"],
            "expired": ["exp": seconds - 6, "iat": seconds - 60],
            "future": ["iat": seconds + 6], "missingIat": ["iat": NSNull()],
            "fractionalIat": ["iat": Double(seconds) - 0.5], "nbf": ["nbf": seconds + 6],
            "multiAudience": ["aud": [fixture.clientID, "oaiapp_other"]]]
        let token = try fixture.token(changes: #require(mutations[change]))
        #expect(throws: IDTokenError.invalidClaims) {
            try IDTokenValidator().validate(token, jwks: fixture.jwks, clientID: fixture.clientID,
                                             nonce: fixture.nonce, now: fixture.now)
        }
    }

    @Test func acceptsFiveSecondClockSkewAndArrayAudience() throws {
        let fixture = try SyntheticIdentityToken()
        let seconds = Int(fixture.now.timeIntervalSince1970)
        let token = try fixture.token(changes: ["iat": seconds + 5, "aud": [fixture.clientID, "oaiapp_other"], "azp": fixture.clientID])
        _ = try IDTokenValidator().validate(token, jwks: fixture.jwks, clientID: fixture.clientID,
                                            nonce: fixture.nonce, now: fixture.now)
    }

    @Test(arguments: ["none", "HS256", "RS512"])
    func rejectsUnexpectedAlgorithm(_ algorithm: String) throws {
        let fixture = try SyntheticIdentityToken()
        var components = try fixture.token().split(separator: ".").map(String.init)
        let header = try JSONSerialization.data(withJSONObject: ["alg": algorithm, "kid": "synthetic-key"])
        components[0] = header.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        #expect(throws: IDTokenError.unsupportedAlgorithm) {
            try IDTokenValidator().validate(components.joined(separator: "."), jwks: fixture.jwks,
                clientID: fixture.clientID, nonce: fixture.nonce, now: fixture.now)
        }
    }

    @Test func rejectsMissingAndUnknownKey() throws {
        let fixture = try SyntheticIdentityToken()
        for (header, expected) in [(NSNull() as Any, IDTokenError.missingKey), ("unpublished-key" as Any, .unknownKey)] {
            let token = try fixture.token(header: ["kid": header])
            #expect(throws: expected) {
                try IDTokenValidator().validate(token, jwks: fixture.jwks, clientID: fixture.clientID,
                                                nonce: fixture.nonce, now: fixture.now)
            }
        }
    }

    @Test(arguments: ["type", "algorithm", "use", "operations", "duplicate"])
    func rejectsInvalidKeyMetadata(_ change: String) throws {
        let fixture = try SyntheticIdentityToken()
        var object = try #require(JSONSerialization.jsonObject(with: fixture.jwks) as? [String: Any])
        var keys = try #require(object["keys"] as? [[String: Any]])
        switch change {
        case "type": keys[0]["kty"] = "EC"
        case "algorithm": keys[0]["alg"] = "RS512"
        case "use": keys[0]["use"] = "enc"
        case "operations": keys[0]["key_ops"] = ["sign"]
        default: keys.append(keys[0])
        }
        object["keys"] = keys
        let jwks = try JSONSerialization.data(withJSONObject: object)
        let token = try fixture.token()
        #expect(throws: IDTokenError.invalidKey) {
            try IDTokenValidator().validate(token, jwks: jwks, clientID: fixture.clientID,
                                             nonce: fixture.nonce, now: fixture.now)
        }
    }

    @Test func rejectsTamperingAndWrongSigningKey() throws {
        let fixture = try SyntheticIdentityToken()
        let other = try SyntheticIdentityToken()
        var parts = try fixture.token().split(separator: ".").map(String.init)
        let changedPayload = try fixture.token(changes: ["sub": "different-synthetic-account"]).split(separator: ".")[1]
        parts[1] = String(changedPayload)
        let tampered = parts.joined(separator: ".")
        let valid = try fixture.token()
        for (token, keys) in [(tampered, fixture.jwks), (valid, other.jwks)] {
            #expect(throws: IDTokenError.invalidSignature) {
                try IDTokenValidator().validate(token, jwks: keys, clientID: fixture.clientID,
                                                nonce: fixture.nonce, now: fixture.now)
            }
        }
    }

    @Test func ignoresTokenSuppliedKeyURLs() throws {
        let fixture = try SyntheticIdentityToken()
        let token = try fixture.token(header: ["jku": "https://untrusted.example/keys", "x5u": "https://untrusted.example/cert"])
        _ = try IDTokenValidator().validate(token, jwks: fixture.jwks, clientID: fixture.clientID,
                                            nonce: fixture.nonce, now: fixture.now)
    }
}

extension IDTokenValidatorTests {
    @Test(arguments: ["crit", "b64"])
    func rejectsUnsupportedCriticalHeaderSemantics(_ parameter: String) throws {
        let fixture = try SyntheticIdentityToken()
        let token = try fixture.token(header: [parameter: parameter == "crit" ? ["unsupported"] : false])
        #expect(throws: IDTokenError.unsupportedAlgorithm) {
            try IDTokenValidator().validate(token, jwks: fixture.jwks, clientID: fixture.clientID,
                                             nonce: fixture.nonce, now: fixture.now)
        }
    }
}
