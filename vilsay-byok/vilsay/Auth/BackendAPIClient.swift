//
//  BackendAPIClient.swift
//  vilsay
//

import Foundation

enum BackendAPIError: Error, LocalizedError {
    case missingBaseURL
    case invalidResponse
    case httpStatus(Int, String?)
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .missingBaseURL:
            return "未配置后端地址。请设置环境变量 VILSAY_API_BASE 或在调试 UserDefaults 中写入 vilsay.api_base。"
        case .invalidResponse:
            return "服务器响应无效。"
        case let .httpStatus(code, detail):
            if code == 404 {
                let hint = "接口不存在（404）。请确认 VILSAY_API_BASE / 设置里的「服务基址」指向 **FastAPI 根地址**（例如 http://127.0.0.1:8000），不要填官网首页域名；路径由客户端自动加 /api/v1。"
                if let detail, !detail.isEmpty { return "\(hint)\n\(detail)" }
                return hint
            }
            if let detail, !detail.isEmpty { return "请求失败（\(code)）：\(detail)" }
            return "请求失败（\(code)）。"
        case .decodingFailed:
            return "无法解析服务器数据。"
        }
    }
}

/// 与 `server/` FastAPI 通信；路径统一加 `VILSAY_TECH_SPEC_SUPPLEMENT` §5.1 `/api/v1`。
enum BackendAPIClient {
    private static let apiPrefix = "/api/v1"

    private static let jsonEncoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        return e
    }()

    private static let jsonDecoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    private static func apiURL(path: String) -> URL? {
        guard let base = AppConfig.backendAPIBaseURL else { return nil }
        let p = path.hasPrefix("/") ? path : "/" + path
        let full = Self.apiPrefix + p
        return URL(string: full, relativeTo: base)
    }

    static func postJSON<Body: Encodable, T: Decodable>(
        path: String,
        body: Body,
        token: String?
    ) async throws -> T {
        guard let url = apiURL(path: path) else {
            throw BackendAPIError.missingBaseURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = try jsonEncoder.encode(body)
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw BackendAPIError.invalidResponse
        }
        guard (200 ... 299).contains(http.statusCode) else {
            let msg = Self.parseErrorDetail(data: data)
            throw BackendAPIError.httpStatus(http.statusCode, msg)
        }
        do {
            return try jsonDecoder.decode(T.self, from: data)
        } catch {
            throw BackendAPIError.decodingFailed
        }
    }

    static func getJSON<T: Decodable>(path: String, token: String? = nil) async throws -> T {
        guard let url = apiURL(path: path) else {
            throw BackendAPIError.missingBaseURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        if let token {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw BackendAPIError.invalidResponse
        }
        guard (200 ... 299).contains(http.statusCode) else {
            let msg = Self.parseErrorDetail(data: data)
            throw BackendAPIError.httpStatus(http.statusCode, msg)
        }
        do {
            return try jsonDecoder.decode(T.self, from: data)
        } catch {
            throw BackendAPIError.decodingFailed
        }
    }

    /// §5.2：优先 `message`，其次 `detail`（含 FastAPI 嵌套 `detail` 对象）。
    private static func parseErrorDetail(data: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let m = obj["message"] as? String, !m.isEmpty { return m }
        if let d = obj["detail"] as? String { return d }
        if let nested = obj["detail"] as? [String: Any], let m = nested["message"] as? String, !m.isEmpty {
            return m
        }
        if let arr = obj["detail"] as? [[String: Any]], let first = arr.first, let msg = first["msg"] as? String {
            return msg
        }
        return nil
    }
}
