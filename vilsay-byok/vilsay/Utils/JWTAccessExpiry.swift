//
//  JWTAccessExpiry.swift
//

import Foundation

/// 解析 JWT `exp`（access token），用于过期前静默刷新。
enum JWTAccessExpiry {
    static func expirationDate(accessToken: String) -> Date? {
        let parts = accessToken.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var payload = String(parts[1])
        while payload.count % 4 != 0 { payload += "=" }
        payload = payload.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        if let exp = json["exp"] as? TimeInterval {
            return Date(timeIntervalSince1970: exp)
        }
        if let n = json["exp"] as? NSNumber {
            return Date(timeIntervalSince1970: n.doubleValue)
        }
        return nil
    }
}
