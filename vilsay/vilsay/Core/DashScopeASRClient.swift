//
//  DashScopeASRClient.swift
//  vilsay
//

import Foundation

/// W3-03：阿里云百炼 Paraformer 录音文件识别（REST 异步任务 + 轮询）。
///
/// **限制（官方）**：仅支持公网可访问的 `file_urls`。麦克风文件需经 **`server/` 代理**上传 OSS 再识别（`VILSAY_ASR_PROXY_URL` + `VILSAY_ASR_INTERNAL_KEY`），或仅联调时设 `DASHSCOPE_PARAFORMER_FILE_URL`。
/// **实时 WebSocket 流式 ASR** 见 `DashScopeStreamingASRClient`（`Pipeline` 云端模式 + Key）。
///
/// **联调建议**：返回 `nil` 时优先怀疑 **Bearer Token**（格式、过期、地域 Key）。请先用 `curl`/Postman 单独验证接口与鉴权，不要在 App 内盲调；见仓库 `docs/DASHSCOPE_SMOKE_TEST.md`。
enum DashScopeASRClient {
    private static let submitEndpoint = URL(string: "https://dashscope.aliyuncs.com/api/v1/services/audio/asr/transcription")!

    /// 本地上传 → 自建后端 → OSS → Paraformer。需 `asrProxyTranscribeURL`，以及 **`X-Vilsay-Internal-ASR-Key` 或 `Authorization: Bearer`（与百炼 API Key 一致）**。
    /// - Returns: 成功返回文本；未配置或失败返回 `nil`，由 `Pipeline` 回退其它路径。
    static func transcribeViaProxyIfConfigured(_ localFileURL: URL) async -> String? {
        guard let endpoint = AppConfig.asrProxyTranscribeURL else { return nil }
        let internalKey = AppConfig.asrInternalKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let apiKey = AppConfig.dashscopeAPIKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if internalKey.isEmpty, apiKey.isEmpty { return nil }
        guard FileManager.default.fileExists(atPath: localFileURL.path) else { return nil }

        let boundary = "Boundary-\(UUID().uuidString)"
        let body: Data
        do {
            body = try Self.buildMultipartBody(
                fileURL: localFileURL,
                boundary: boundary,
                asrModel: AppConfig.dashscopeAsrModel
            )
        } catch {
            return nil
        }

        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if !internalKey.isEmpty {
            req.setValue(internalKey, forHTTPHeaderField: "X-Vilsay-Internal-ASR-Key")
        } else {
            req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = body

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
                return nil
            }
            guard
                let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let text = obj["text"] as? String
            else {
                return nil
            }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        } catch {
            return nil
        }
    }

    private static func buildMultipartBody(fileURL: URL, boundary: String, asrModel: String) throws -> Data {
        let fileData = try Data(contentsOf: fileURL)
        let filename = fileURL.lastPathComponent
        var d = Data()
        let crlf = "\r\n"
        d.append("--\(boundary)\(crlf)".data(using: .utf8)!)
        d.append("Content-Disposition: form-data; name=\"model\"\(crlf)\(crlf)".data(using: .utf8)!)
        d.append(Data(asrModel.utf8))
        d.append(crlf.data(using: .utf8)!)
        d.append("--\(boundary)\(crlf)".data(using: .utf8)!)
        d.append(
            "Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\(crlf)".data(using: .utf8)!
        )
        d.append("Content-Type: application/octet-stream\(crlf)\(crlf)".data(using: .utf8)!)
        d.append(fileData)
        d.append("\(crlf)--\(boundary)--\(crlf)".data(using: .utf8)!)
        return d
    }

    /// 使用 `DASHSCOPE_PARAFORMER_FILE_URL` 固定公网 URL 联调（与本次录音文件无关）。
    /// - Returns: 非空则云端 ASR 成功；`nil` 时 `Pipeline` 使用其它路径。
    static func transcribeFileIfAvailable(_ localFileURL: URL) async -> String? {
        _ = localFileURL
        guard let key = AppConfig.dashscopeAPIKey, !key.isEmpty else { return nil }
        guard let remote = AppConfig.dashscopeParaformerFileURL, !remote.isEmpty else { return nil }

        do {
            let taskId = try await submitTask(apiKey: key, fileURLs: [remote])
            let transcriptURL = try await pollForTranscriptionURL(apiKey: key, taskId: taskId)
            return try await downloadTranscriptionText(from: transcriptURL)
        } catch {
            return nil
        }
    }

    private static func submitTask(apiKey: String, fileURLs: [String]) async throws -> String {
        var req = URLRequest(url: submitEndpoint)
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("enable", forHTTPHeaderField: "X-DashScope-Async")
        let body: [String: Any] = [
            "model": AppConfig.dashscopeAsrModel,
            "input": ["file_urls": fileURLs],
            "parameters": ["channel_id": [0], "language_hints": ASRSpokenLanguage.currentFromDefaults().dashScopeBatchHints]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
            throw DashScopeError.badResponse
        }
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let output = json["output"] as? [String: Any],
            let taskId = output["task_id"] as? String
        else {
            throw DashScopeError.parseFailed
        }
        return taskId
    }

    /// 任务查询：先 `POST` 空 body（与官方文档一致）；若无法解析再 `GET`。
    private static func pollForTranscriptionURL(apiKey: String, taskId: String) async throws -> URL {
        guard let taskURL = URL(string: "https://dashscope.aliyuncs.com/api/v1/tasks/\(taskId)") else {
            throw DashScopeError.parseFailed
        }
        for _ in 0 ..< 120 {
            let output = try await queryTaskOutput(apiKey: apiKey, taskURL: taskURL)
            guard let status = output["task_status"] as? String else {
                throw DashScopeError.parseFailed
            }
            switch status {
            case "FAILED":
                throw DashScopeError.taskFailed
            case "SUCCEEDED":
                if let results = output["results"] as? [[String: Any]] {
                    for r in results {
                        if (r["subtask_status"] as? String) == "SUCCEEDED",
                           let urlStr = r["transcription_url"] as? String,
                           let u = URL(string: urlStr) {
                            return u
                        }
                    }
                }
                throw DashScopeError.parseFailed
            default:
                try await Task.sleep(nanoseconds: 500_000_000)
            }
        }
        throw DashScopeError.timeout
    }

    private static func queryTaskOutput(apiKey: String, taskURL: URL) async throws -> [String: Any] {
        var postReq = URLRequest(url: taskURL)
        postReq.httpMethod = "POST"
        postReq.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        postReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        postReq.httpBody = Data()

        let (dataPost, respPost) = try await URLSession.shared.data(for: postReq)
        if let http = respPost as? HTTPURLResponse,
           (200 ... 299).contains(http.statusCode),
           let json = try? JSONSerialization.jsonObject(with: dataPost) as? [String: Any],
           let output = json["output"] as? [String: Any] {
            return output
        }

        var getReq = URLRequest(url: taskURL)
        getReq.httpMethod = "GET"
        getReq.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let (dataGet, respGet) = try await URLSession.shared.data(for: getReq)
        guard let http = respGet as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
            throw DashScopeError.badResponse
        }
        guard let json = try JSONSerialization.jsonObject(with: dataGet) as? [String: Any],
              let output = json["output"] as? [String: Any] else {
            throw DashScopeError.parseFailed
        }
        return output
    }

    private static func downloadTranscriptionText(from url: URL) async throws -> String {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
            throw DashScopeError.badResponse
        }
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let transcripts = json["transcripts"] as? [[String: Any]],
            let first = transcripts.first,
            let text = first["text"] as? String
        else {
            throw DashScopeError.parseFailed
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private enum DashScopeError: Error {
        case badResponse
        case parseFailed
        case taskFailed
        case timeout
    }
}
