//
//  DashScopeModelCatalog.swift
//

import Foundation

/// 百炼可用模型 ID：优先请求云端列表，失败则用静态兜底。
enum DashScopeModelCatalog {
    static let defaultAsrModels = ["paraformer-v2", "paraformer-v1", "paraformer-realtime-v2"]
    static let defaultTextModels = ["qwen-turbo", "qwen-plus", "qwen-max", "qwen-long", "qwen2.5-72b-instruct"]

    /// `GET /api/v1/models`（分页）；失败时尝试 OpenAI 兼容 `GET …/compatible-mode/v1/models`。
    /// 百炼原生 JSON 为 `output.models[].model`，旧解析只认顶层 `models` / `data`，会导致「拉取失败」。
    static func fetchModelIds(apiKey: String) async -> [String]? {
        let pageSize = 100
        var collected: [String] = []
        var page = 1
        while page <= 20 {
            let qs = "page_size=\(pageSize)&page_no=\(page)"
            guard let url = URL(string: "https://dashscope.aliyuncs.com/api/v1/models?\(qs)") else { break }
            var req = URLRequest(url: url)
            req.httpMethod = "GET"
            req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            req.timeoutInterval = 25
            do {
                let (data, response) = try await URLSession.shared.data(for: req)
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                guard (200 ... 299).contains(statusCode) else {
                    print("[ModelCatalog] HTTP \(statusCode) on page \(page), breaking")
                    break
                }
                guard let batch = parseModelListJSON(data), !batch.isEmpty else {
                    let preview = String(data: data.prefix(200), encoding: .utf8) ?? "<non-utf8>"
                    print("[ModelCatalog] parseModelListJSON returned nil/empty on page \(page): \(preview)")
                    break
                }
                collected.append(contentsOf: batch)
                if batch.count < pageSize { break }
                page += 1
            } catch {
                print("[ModelCatalog] URLSession error on page \(page): \(error)")
                break
            }
        }
        if !collected.isEmpty {
            return Array(Set(collected)).sorted()
        }
        // 兼容模式单列（与设置里「基址」一致；部分账号下原生分页异常时可兜底）
        guard let url = URL(string: "https://dashscope.aliyuncs.com/compatible-mode/v1/models") else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 25
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
                return nil
            }
            return parseModelListJSON(data).map { Array(Set($0)).sorted() }
        } catch {
            return nil
        }
    }

    /// 供单测与 `fetchModelIds` 共用。
    static func parseModelListJSON(_ data: Data) -> [String]? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) else { return nil }
        if let root = obj as? [String: Any] {
            if let arr = root["data"] as? [[String: Any]] {
                let ids = arr.compactMap { $0["id"] as? String ?? $0["name"] as? String }
                if !ids.isEmpty { return ids }
            }
            if let output = root["output"] as? [String: Any],
               let arr = output["models"] as? [[String: Any]] {
                let ids = arr.compactMap { $0["model"] as? String ?? $0["name"] as? String }
                if !ids.isEmpty { return ids }
            }
            if let arr = root["models"] as? [[String: Any]] {
                let ids = arr.compactMap { $0["name"] as? String ?? $0["model_id"] as? String ?? $0["id"] as? String ?? $0["model"] as? String }
                if !ids.isEmpty { return ids }
            }
        }
        if let arr = obj as? [String] { return arr }
        return nil
    }

    /// 从全量列表中拆成「更像 ASR」与「更像文本」两组（启发式）。
    /// 润色走百炼原生 `…/text-generation/generation` 时，**不要**把 OpenAI 兼容列表里的 `厂商/模型` ID 放进「润色」下拉（会 4xx 后静默降级）；兼容 ID 仅适合 `compatible-mode/v1/chat/completions`。
    static func splitAsrAndText(from all: [String]) -> (asr: [String], text: [String]) {
        let asr = all.filter { id in
            let l = id.lowercased()
            return l.contains("paraformer") || l.contains("fun-asr") || l.contains("sensevoice") || l.contains("asr")
        }
        let text = all.filter { id in
            if id.contains("/") { return false }
            let l = id.lowercased()
            return l.contains("qwen") || l.contains("deepseek") || l.contains("llm") || l.contains("turbo") || l.contains("gpt")
        }
        let asrOut = asr.isEmpty ? defaultAsrModels : Array(Set(asr)).sorted()
        let textOut = text.isEmpty ? defaultTextModels : Array(Set(text)).sorted()
        return (asrOut, textOut)
    }
}
