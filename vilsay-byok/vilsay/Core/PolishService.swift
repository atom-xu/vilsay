//
//  PolishService.swift
//

import Foundation
import os.log

/// W3-07：阿里云 Qwen 润色。无 Key 时原样返回；DEBUG 直连时原生走 `text-generation` SSE，OpenAI 兼容模型走 `compatible-mode/v1/chat/completions` 流式。
enum PolishService {
    private static let log = Logger(subsystem: "com.vilsay.app", category: "PolishService")
    /// 流式：SSE 增量解析；**任意情况**若未产出有效片段则降级 `polishPlain`，保证有文字输出。
    /// `onFirstToken`：首个来自网络的有效片段时调用（用量计数，§3.1）。
    static func polishStreaming(
        system: String,
        user: String,
        onFirstToken: (@Sendable () -> Void)? = nil
    ) -> AsyncStream<String> {
        AsyncStream { continuation in
            Task {
                defer { continuation.finish() }

                var yieldedAny = false

                // 凭证优先级：用户自备 DashScope Key → Vilsay 账号 Token（Pro 走代理）
                let ownKey = AppConfig.dashscopeAPIKey
                let vilsayToken = KeychainTokenStore.loadToken()
                let hasOwnKey = ownKey != nil && !ownKey!.isEmpty
                let hasToken = vilsayToken != nil && !vilsayToken!.isEmpty

                guard hasOwnKey || hasToken else {
                    Self.log.warning("⚠️ 无 API Key 且无账号 Token，跳过润色，返回原文")
                    let text = extractPlainText(from: user)
                    continuation.yield(text)
                    return
                }

                // 用自备 Key 时可走 compat 模式；走代理时用原生模式
                let useCompat: Bool = {
                    guard hasOwnKey else { return false }
                    return AppConfig.polishUsesOpenAICompatChatCompletions
                }()

                let body: [String: Any] = {
                    if useCompat {
                        return [
                            "model": AppConfig.dashscopePolishModel,
                            "messages": [
                                ["role": "system", "content": system],
                                ["role": "user", "content": user]
                            ],
                            "stream": true
                        ]
                    }
                    return [
                        "model": AppConfig.dashscopePolishModel,
                        "input": [
                            "messages": [
                                ["role": "system", "content": system],
                                ["role": "user", "content": user]
                            ]
                        ],
                        "parameters": [
                            "result_format": "message",
                            "incremental_output": true
                        ]
                    ]
                }()

                guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else {
                    Self.log.error("❌ 润色请求 JSON 序列化失败，降级 polishPlain")
                    let text = await polishPlain(system: system, user: user)
                    continuation.yield(text)
                    return
                }

                // 自备 Key → 直连 DashScope；否则走 Vilsay 代理
                let targetURL: URL = hasOwnKey ? AppConfig.polishHTTPURL : AppConfig.qwenPolishEndpoint
                let bearerToken = hasOwnKey ? ownKey! : vilsayToken!
                var req = URLRequest(url: targetURL)
                req.httpMethod = "POST"
                req.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                if !useCompat {
                    req.setValue("enable", forHTTPHeaderField: "X-DashScope-SSE")
                }
                req.httpBody = httpBody
                req.timeoutInterval = Double(Constants.polishTimeoutMs) / 1000.0

                let config = URLSessionConfiguration.ephemeral
                config.timeoutIntervalForRequest = Double(Constants.polishTimeoutMs) / 1000.0
                // timeoutIntervalForResource 限制 SSE 总时长，防止服务端 keep-alive 行无限重置 per-chunk 计时
                config.timeoutIntervalForResource = Double(Constants.polishTimeoutMs) / 1000.0 * 6 // 30s
                let session = URLSession(configuration: config)

                do {
                    let (bytes, response) = try await session.bytes(for: req)
                    guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
                        let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                        Self.log.error("❌ 润色流式 API HTTP \(code)，降级 polishPlain")
                        let text = await polishPlain(system: system, user: user)
                        continuation.yield(text)
                        return
                    }
                    _ = http
                    for try await line in bytes.lines {
                        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard trimmed.hasPrefix("data:") else { continue }
                        let payload = String(trimmed.dropFirst("data:".count)).trimmingCharacters(in: .whitespaces)
                        if payload.isEmpty || payload == "[DONE]" { continue }
                        guard let data = payload.data(using: .utf8),
                              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                        else { continue }
                        if !useCompat, obj["code"] != nil, obj["message"] != nil {
                            break
                        }
                        let piece: String? = useCompat
                            ? PolishStreamParsing.openAICompatSSEDelta(from: obj)
                            : PolishStreamParsing.nativeSSEDelta(from: obj)
                        if let piece, !piece.isEmpty {
                            if !yieldedAny {
                                yieldedAny = true
                                onFirstToken?()
                            }
                            continuation.yield(piece)
                        }
                    }
                } catch {
                    Self.log.error("❌ 润色流式请求失败：\(error.localizedDescription)")
                    let text = await polishPlain(system: system, user: user)
                    continuation.yield(text)
                    return
                }

                if !yieldedAny {
                    Self.log.warning("⚠️ 流式润色无有效输出，降级 polishPlain")
                    let text = await polishPlain(system: system, user: user)
                    continuation.yield(text)
                }
            }
        }
    }

    static func polishPlain(system: String, user: String) async -> String {
        // 凭证优先级：用户自备 DashScope Key → Vilsay 账号 Token（Pro 走代理）
        let ownKey = AppConfig.dashscopeAPIKey
        let vilsayToken = KeychainTokenStore.loadToken()
        let hasOwnKey = ownKey != nil && !ownKey!.isEmpty
        let hasToken = vilsayToken != nil && !vilsayToken!.isEmpty

        guard hasOwnKey || hasToken else {
            Self.log.warning("⚠️ polishPlain：无 API Key 且无账号 Token，返回原文")
            return extractPlainText(from: user)
        }

        // 用自备 Key 时可走 compat 模式；走代理时用原生模式
        let useCompat: Bool = {
            guard hasOwnKey else { return false }
            return AppConfig.polishUsesOpenAICompatChatCompletions
        }()

        let body: [String: Any] = {
            if useCompat {
                return [
                    "model": AppConfig.dashscopePolishModel,
                    "messages": [
                        ["role": "system", "content": system],
                        ["role": "user", "content": user]
                    ]
                ]
            }
            var b: [String: Any] = [
                "model": AppConfig.dashscopePolishModel,
                "input": [
                    "messages": [
                        ["role": "system", "content": system],
                        ["role": "user", "content": user]
                    ]
                ]
            ]
            b["parameters"] = ["result_format": "message"]
            return b
        }()

        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else {
            Self.log.error("❌ polishPlain JSON 序列化失败")
            return extractPlainText(from: user)
        }

        // 自备 Key → 直连 DashScope；否则走 Vilsay 代理
        let targetURL: URL = hasOwnKey ? AppConfig.polishHTTPURL : AppConfig.qwenPolishEndpoint
        let bearerToken = hasOwnKey ? ownKey! : vilsayToken!
        var req = URLRequest(url: targetURL)
        req.httpMethod = "POST"
        req.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = httpBody
        req.timeoutInterval = Double(Constants.polishTimeoutMs) / 1000.0

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = Double(Constants.polishTimeoutMs) / 1000.0
        let session = URLSession(configuration: config)

        do {
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                Self.log.error("❌ polishPlain API HTTP \(code)")
                return extractPlainText(from: user)
            }
            _ = http
            let content = useCompat
                ? PolishStreamParsing.openAICompatNonStreamContent(from: data)
                : PolishStreamParsing.nativeNonStreamQwenContent(from: data)
            return content ?? extractPlainText(from: user)
        } catch {
            Self.log.error("❌ polishPlain 网络错误：\(error.localizedDescription)")
            return extractPlainText(from: user)
        }
    }

    private static func extractPlainText(from userMessage: String) -> String {
        if userMessage.contains("请整理以下语音转写文字") {
            let parts = userMessage.components(separatedBy: "\n")
            return parts.last?.trimmingCharacters(in: .whitespacesAndNewlines) ?? userMessage
        }
        if userMessage.contains("原文："), userMessage.contains("用户指令：") {
            if let range = userMessage.range(of: "用户指令：") {
                return String(userMessage[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        if userMessage.contains("原文：") {
            let lines = userMessage.split(separator: "\n", omittingEmptySubsequences: false)
            if let first = lines.first(where: { $0.hasPrefix("原文：") }) {
                return String(first.dropFirst("原文：".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return userMessage
    }

}
