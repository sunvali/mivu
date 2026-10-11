import Foundation
import JOSESwift
import Security

struct VerifiedIdentity: Codable, Equatable, Sendable {
    let issuer: String
    let subject: String
}

enum IDTokenError: Error, Equatable {
    case invalidToken, unsupportedAlgorithm, missingKey, unknownKey, invalidKey
    case invalidSignature, invalidClaims
}

struct IDTokenValidator: Sendable {
    func validate(_ token: String, jwks: Data, clientID: String, nonce: String, now: Date) throws -> VerifiedIdentity {
        guard !clientID.isEmpty, clientID != "dynamic_agent_client", !nonce.isEmpty else {
            throw IDTokenError.invalidClaims
        }
        let jws: JWS
        do { jws = try JWS(compactSerialization: token) }
        catch { throw IDTokenError.invalidToken }
        var encodedHeader = String(token.split(separator: ".")[0]).replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        encodedHeader += String(repeating: "=", count: (4 - encodedHeader.count % 4) % 4)
        guard let headerData = Data(base64Encoded: encodedHeader),
              let header = try? JSONSerialization.jsonObject(with: headerData) as? [String: Any] else {
            throw IDTokenError.invalidToken
        }
        guard jws.header.algorithm == .RS256, header["crit"] == nil, header["b64"] == nil else {
            throw IDTokenError.unsupportedAlgorithm
        }
        guard let kid = jws.header.kid, !kid.isEmpty else { throw IDTokenError.missingKey }
        let keys: [[String: Any]]
        do {
            guard let object = try JSONSerialization.jsonObject(with: jwks) as? [String: Any],
                  let parsed = object["keys"] as? [[String: Any]] else { throw IDTokenError.invalidKey }
            keys = parsed
        } catch { throw IDTokenError.invalidKey }
        let matching = keys.filter { $0["kid"] as? String == kid }
        guard !matching.isEmpty else { throw IDTokenError.unknownKey }
        guard matching.count == 1, let fields = matching.first,
              fields["kty"] as? String == "RSA",
              fields["alg"] == nil || fields["alg"] as? String == "RS256",
              fields["use"] == nil || fields["use"] as? String == "sig",
              fields["key_ops"] == nil || fields["key_ops"] as? [String] == ["verify"] else {
            throw IDTokenError.invalidKey
        }
        let publicKey: SecKey
        do {
            let key = try RSAPublicKey(data: JSONSerialization.data(withJSONObject: fields))
            publicKey = try key.converted(to: SecKey.self)
        } catch { throw IDTokenError.invalidKey }
        guard let verifier = Verifier(signatureAlgorithm: .RS256, key: publicKey) else {
            throw IDTokenError.invalidKey
        }
        let payload: Data
        do { payload = try jws.validate(using: verifier).payload.data() }
        catch { throw IDTokenError.invalidSignature }
        let claims: Claims
        do { claims = try JSONDecoder().decode(Claims.self, from: payload) }
        catch { throw IDTokenError.invalidClaims }
        let seconds = now.timeIntervalSince1970
        guard claims.iss == "https://auth.openai.com", !claims.sub.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              claims.aud.values.contains(clientID), claims.nonce == nonce,
              claims.aud.values.count <= 1 || claims.azp == clientID,
              claims.azp == nil || claims.azp == clientID,
              Double(claims.exp) > seconds - 5, Double(claims.iat) <= seconds + 5,
              claims.iat > 0, claims.exp > claims.iat,
              claims.nbf == nil || Double(claims.nbf!) <= seconds + 5 else {
            throw IDTokenError.invalidClaims
        }
        return VerifiedIdentity(issuer: claims.iss, subject: claims.sub)
    }

    private struct Claims: Decodable {
        let iss: String
        let sub: String
        let aud: Audience
        let exp: Int
        let iat: Int
        let nonce: String
        let nbf: Int?
        let azp: String?
    }

    private struct Audience: Decodable {
        let values: [String]
        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let value = try? container.decode(String.self) { values = [value] }
            else { values = try container.decode([String].self) }
        }
    }
}
