import Foundation

/// A JWT is three base64url segments; header and payload are JSON. Decoding is local and only
/// happens when the user asks for it.
enum JWTDecoder {
    struct Claim: Identifiable {
        let id = UUID()
        let key: String
        let value: String
        let isTimestamp: Bool
    }

    struct Decoded {
        let header: String
        let payload: String
        let claims: [Claim]
        let expiresAt: Date?
        let issuedAt: Date?

        var isExpired: Bool {
            guard let expiresAt else { return false }
            return expiresAt < Date()
        }

        var expiryLabel: String {
            guard let expiresAt else { return L("無 exp 宣告") }
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy/MM/dd HH:mm"
            return formatter.string(from: expiresAt)
        }
    }

    static func looksLikeJWT(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.split(separator: ".").count == 3 && trimmed.hasPrefix("ey")
    }

    static func decode(_ raw: String) -> Decoded? {
        let parts = raw.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ".")
        guard parts.count == 3,
              let headerData = base64URL(String(parts[0])),
              let payloadData = base64URL(String(parts[1])),
              let header = prettyJSON(headerData),
              let payload = prettyJSON(payloadData) else { return nil }

        var claims: [Claim] = []
        var expiresAt: Date?
        var issuedAt: Date?

        if let object = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any] {
            for key in object.keys.sorted() {
                let value = object[key]
                var rendered: String
                var isTimestamp = false
                if let number = value as? NSNumber, isDateClaim(key) {
                    let date = Date(timeIntervalSince1970: number.doubleValue)
                    let formatter = DateFormatter()
                    formatter.dateFormat = "yyyy/MM/dd HH:mm"
                    rendered = formatter.string(from: date)
                    isTimestamp = true
                    if key == "exp" { expiresAt = date }
                    if key == "iat" || key == "nbf" { issuedAt = date }
                } else if let string = value as? String {
                    rendered = string
                } else if let value {
                    rendered = "\(value)"
                } else {
                    rendered = "null"
                }
                if rendered.count > 120 { rendered = String(rendered.prefix(120)) + "…" }
                claims.append(Claim(key: key, value: rendered, isTimestamp: isTimestamp))
            }
        }

        return Decoded(header: header, payload: payload, claims: claims,
                       expiresAt: expiresAt, issuedAt: issuedAt)
    }

    private static func isDateClaim(_ key: String) -> Bool {
        ["exp", "iat", "nbf", "auth_time", "updated_at"].contains(key)
    }

    private static func base64URL(_ string: String) -> Data? {
        var value = string.replacingOccurrences(of: "-", with: "+")
                        .replacingOccurrences(of: "_", with: "/")
        while value.count % 4 != 0 { value += "=" }
        return Data(base64Encoded: value)
    }

    private static func prettyJSON(_ data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: object,
                                                       options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: pretty, encoding: .utf8) else { return nil }
        return text
    }
}
