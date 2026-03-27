//
//  PolishStreamParsing.swift
//  润色流式 SSE 与 JSON 解析（供 `PolishService` 与单元测试共用）。
//

import Foundation

enum PolishStreamParsing {
    /// 百炼原生 `text-generation` 流式增量。
    static func nativeSSEDelta(from obj: [String: Any]) -> String? {
        guard let output = obj["output"] as? [String: Any] else { return nil }
        if let choices = output["choices"] as? [[String: Any]],
           let first = choices.first,
           let msg = first["message"] as? [String: Any],
           let content = msg["content"] as? String {
            return content
        }
        if let text = output["text"] as? String {
            return text
        }
        return nil
    }

    /// OpenAI 兼容流式：`choices[0].delta.content`。
    static func openAICompatSSEDelta(from obj: [String: Any]) -> String? {
        if obj["error"] != nil { return nil }
        guard let choices = obj["choices"] as? [[String: Any]],
              let first = choices.first,
              let delta = first["delta"] as? [String: Any],
              let content = delta["content"] as? String,
              !content.isEmpty else { return nil }
        return content
    }

    static func openAICompatNonStreamContent(from data: Data) -> String? {
        guard
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = obj["choices"] as? [[String: Any]],
            let msg = choices.first?["message"] as? [String: Any],
            let content = msg["content"] as? String
        else { return nil }
        return content
    }

    static func nativeNonStreamQwenContent(from data: Data) -> String? {
        guard
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let output = obj["output"] as? [String: Any]
        else { return nil }

        if let choices = output["choices"] as? [[String: Any]],
           let msg = choices.first?["message"] as? [String: Any],
           let content = msg["content"] as? String {
            return content
        }
        if let text = output["text"] as? String {
            return text
        }
        return nil
    }
}
