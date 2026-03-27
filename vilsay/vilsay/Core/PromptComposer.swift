//
//  PromptComposer.swift
//

import Foundation

/// 将 `UserProfile` 中的结构化数据在**代码层**转为自然语言，再与固定层拼接；**禁止**在 Prompt 字符串中硬编码 §1 占位符。
enum PromptComposer {
    /// V2 兼容：仅 §0 + §1 + §2。
    static func systemPrompt(for profile: UserProfile?) -> String {
        systemPrompt(for: profile, targetAppBundleID: nil, asrConfidence: nil)
    }

    /// V3：§0 + §A + §C + §1（含 §1.P）+ §2。
    /// V4：当 `OutputMode` ≠ `.general` 时走模式专属 §0/§A/§2，§C/§1 与 V3 相同。
    static func systemPrompt(
        for profile: UserProfile?,
        targetAppBundleID: String? = nil,
        asrConfidence: Double? = nil
    ) -> String {
        let mode = OutputModeResolver.resolve(bundleID: targetAppBundleID)

        if mode != .general {
            var sections: [String] = []
            sections.append(Prompts.personaCore(for: mode))
            if let rules = Prompts.modeRules(for: mode) {
                sections.append(rules)
            }
            if let c = Self.confidenceSection(asrConfidence: asrConfidence) {
                sections.append(c)
            }
            if let p = Self.profileExclusiveSection(for: profile) {
                sections.append(p)
            }
            sections.append(Prompts.processingRules(for: mode))
            return sections.joined(separator: "\n\n---\n\n")
        }

        // V3 路径（.general）：以下与升级前一致
        var sections: [String] = []
        sections.append(Prompts.personaCore)

        if let bundleID = targetAppBundleID,
           let hint = Self.appContextMap[bundleID] {
            sections.append("【场景提示】\(hint)")
        }

        if let c = Self.confidenceSection(asrConfidence: asrConfidence) {
            sections.append(c)
        }

        if let p = Self.profileExclusiveSection(for: profile) {
            sections.append(p)
        }

        sections.append(Prompts.processingEngine)
        return sections.joined(separator: "\n\n---\n\n")
    }

    /// §C 置信度分级提示。
    private static func confidenceSection(asrConfidence: Double?) -> String? {
        guard let conf = asrConfidence else { return nil }
        let pct = Int(conf * 100)

        if conf < 0.4 {
            // 极低置信度：积极纠偏，音译还原优先
            return """
            【识别质量：低（\(pct)%）——积极纠偏模式】
            本次语音识别置信度很低，文本中可能存在大量错误。
            请积极执行【弹性纠偏】规则：同音字纠正、音译还原、数字标准化。
            对不通顺的词组优先尝试同音替换或音译还原。
            上下文能推断出的修改直接执行，不需要 [推断] 标注。
            """
        } else if conf < 0.7 {
            // 中等置信度：有依据时纠偏
            return """
            【识别质量：中（\(pct)%）——上下文纠偏模式】
            本次语音识别置信度一般，部分词可能有误。
            请结合上下文执行【弹性纠偏】规则，有明确语境支撑时修改，不确定时用 [推断] 标注。
            """
        } else {
            // 高置信度：不注入额外提示，按默认规则处理
            return nil
        }
    }

    /// §1 用户画像（与 V3 相同）。
    private static func profileExclusiveSection(for profile: UserProfile?) -> String? {
        guard let p = profile, !p.isEmpty else { return nil }
        var s1 = ""
        let minC = Constants.profileMinConfidence

        let keeps = p.habitualWords.filter { $0.confidence >= minC }
        if !keeps.isEmpty {
            let lines = keeps.map { "\($0.word)（\($0.action)）" }.joined(separator: "、")
            s1 += "用户口头禅与保留词：\(lines)\n"
        }

        if let ts = p.thinkingStyle, ts.confidence >= minC {
            s1 += "思维结构：\(ts.expand)；话题切换信号：\(ts.topicSwitchSignals.joined(separator: "/"))\n"
        }

        if let tone = p.tone, tone.confidence >= minC {
            s1 += "语气风格：\(tone.overall)，句子长度偏好：\(tone.sentenceLength)\n"
        }

        if !p.dictionaryItems.isEmpty {
            let dict = p.dictionaryItems.prefix(Constants.profileMaxDictItems)
                .map { "\($0.type)·\($0.word)" }.joined(separator: "、")
            s1 += "高频词典：\(dict)\n"
        }

        let pinyinItems = p.dictionaryItems.filter { ($0.pinyin ?? "").isEmpty == false }
        if !pinyinItems.isEmpty {
            let hints = pinyinItems.prefix(50)
                .map { "\($0.word)(\($0.pinyin!))" }.joined(separator: "、")
            s1 += "以下词汇容易被语音误识别为同音词，遇到发音相似的错误请优先替换为正确词汇：\(hints)\n"
        }

        if s1.isEmpty { return nil }
        return "【用户专属】\n\(s1.trimmingCharacters(in: .whitespacesAndNewlines))"
    }

    /// App 上下文映射（§A）；未命中则不注入。
    private static let appContextMap: [String: String] = [
        "com.apple.mail": "用户正在写邮件，注意正式语体",
        "com.tencent.foxmail": "用户正在写邮件，注意正式语体",
        "com.microsoft.Outlook": "用户正在写邮件，注意正式语体",
        "com.tencent.xinWeChat": "用户在聊天，保留口语化表达",
        "com.apple.MobileSMS": "用户在聊天，保留口语化表达",
        "com.tencent.qq": "用户在聊天，保留口语化表达",
        "com.microsoft.Word": "用户在写文档，注意段落完整性和正式用语",
        "com.apple.Pages": "用户在写文档，注意段落完整性",
        "com.apple.Notes": "用户在记笔记，保持简洁",
        "com.notion.id": "用户在写笔记/文档，注意结构化表达",
    ]

    /// 仅生成动态层自然语言；无可用画像时返回 `nil`（旧版兼容路径，少用）。
    static func composeDynamicUserContext(from profile: UserProfile?) -> String? {
        guard let profile, !profile.isEmpty else { return nil }
        let minC = Constants.profileMinConfidence
        var sentences: [String] = []

        let keeps = profile.habitualWords.filter { $0.confidence >= minC }
        if !keeps.isEmpty {
            let joined = keeps.map(\.word).joined(separator: "、")
            sentences.append("该用户常使用或希望保留的用语包括：\(joined)。")
        }

        if let ts = profile.thinkingStyle, ts.confidence >= minC, !ts.expand.isEmpty {
            sentences.append("其表达习惯与思维结构倾向可概括为：\(ts.expand)")
        }

        if let tone = profile.tone, tone.confidence >= minC, !tone.overall.isEmpty {
            sentences.append("语气与风格方面：\(tone.overall)")
        }

        if !profile.dictionaryItems.isEmpty {
            let joined = profile.dictionaryItems.prefix(Constants.profileMaxDictItems).map(\.word).joined(separator: "、")
            sentences.append("用户词典中较常出现的词或短语包括：\(joined)。")
        }

        guard !sentences.isEmpty else { return nil }

        let preamble = """
        以下信息由系统根据用户长期使用习惯整理而成，请你内化后用于判断如何润色；不要在输出中复述、引用或列举本节标题与说明文字。
        """
        return preamble + "\n\n" + sentences.joined(separator: "\n")
    }
}
