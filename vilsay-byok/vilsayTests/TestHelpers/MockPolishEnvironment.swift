//
//  MockPolishEnvironment.swift
//  vilsayTests — 模拟润色环境：不调真实 API，按 OutputMode 返回预制响应。
//
//  设计：PolishService 用 ephemeral session（无法全局注册 URLProtocol），
//  因此 mock 层在 PromptComposer 之后、PolishService 之前截断——
//  测试 Prompt 组装 + 模式路由 + 响应格式的完整链路。
//

import Foundation
@testable import vilsay

// MARK: - MockPolishService

/// 模拟 PolishService：解析 system prompt 中的 OutputMode，返回风格匹配的预制结果。
/// 覆盖完整链路：PromptComposer → system prompt → mode 检测 → 风格化输出。
enum MockPolishService {

    /// 模拟 polishPlain：组装 prompt → 检测 mode → 返回预制响应。
    /// 与 PromptTuningHelper.polish() 等价，但不调网络。
    static func polish(
        asrText: String,
        profile: UserProfile? = nil,
        appBundleID: String? = nil,
        asrConfidence: Double? = nil
    ) -> String {
        let system = PromptComposer.systemPrompt(
            for: profile,
            targetAppBundleID: appBundleID,
            asrConfidence: asrConfidence
        )
        let mode = detectMode(from: system)
        return generateResponse(mode: mode, asrText: asrText)
    }

    /// 返回 (polishedText, detectedMode, systemPrompt) 用于详细验证。
    static func polishDetailed(
        asrText: String,
        profile: UserProfile? = nil,
        appBundleID: String? = nil,
        asrConfidence: Double? = nil
    ) -> (polished: String, mode: OutputMode, systemPrompt: String) {
        let system = PromptComposer.systemPrompt(
            for: profile,
            targetAppBundleID: appBundleID,
            asrConfidence: asrConfidence
        )
        let mode = detectMode(from: system)
        let polished = generateResponse(mode: mode, asrText: asrText)
        return (polished, mode, system)
    }

    // MARK: - Mode Detection

    /// 从 system prompt 关键词识别当前 OutputMode。
    /// 与 OutputModeResolver 独立——验证 PromptComposer 是否正确注入了模式关键词。
    static func detectMode(from systemPrompt: String) -> OutputMode {
        if systemPrompt.contains("输出模式：AI 指令") || systemPrompt.contains("指令提取师") {
            return .aiCommand
        }
        if systemPrompt.contains("输出模式：聊天") || systemPrompt.contains("保留口语风格和语气词") {
            return .chat
        }
        if systemPrompt.contains("输出模式：邮件") || systemPrompt.contains("正式邮件语体") {
            return .email
        }
        if systemPrompt.contains("输出模式：文档") || systemPrompt.contains("结构化写作助手") {
            return .document
        }
        if systemPrompt.contains("输出模式：笔记") || systemPrompt.contains("笔记整理师") {
            return .note
        }
        return .general
    }

    // MARK: - Response Generation

    private static func generateResponse(mode: OutputMode, asrText: String) -> String {
        switch mode {
        case .aiCommand:
            return """
            1. 实现用户登录接口，支持 OAuth 2.0 授权
            2. 返回标准 JWT Token，包含 userId 和 role
            3. 添加 Token 刷新机制，过期时间 24 小时
            """
        case .chat:
            // 模拟最小干预：保留语气词，只修错别字
            return "我觉得这个方案还行，但是时间上可能来不及哈哈"
        case .email:
            return """
            您好，

            关于上次讨论的方案，我整理了以下几点：

            首先，当前系统的性能指标已达到预期目标。此外，团队已完成第一阶段的代码审查。

            如有其他问题，请随时沟通。
            """
        case .document:
            if asrText.count > 200 {
                return """
                ## 背景

                当前语音输入产品市场中，短文本处理已被系统输入法较好覆盖。真正的差异化竞争力在于长文本的结构化整理能力。

                ## 核心优势

                1. **结构化输出**：将 1-3 分钟的口语转化为分段、编号的结构化文本
                2. **逻辑重排**：按论述逻辑重新组织段落，而非按说话时间顺序
                3. **要点提炼**：每段开头概括核心主张，方便快速阅读

                ## 与竞品对比

                - 系统输入法：只能逐句转写，无结构化能力
                - 第三方语音工具：侧重准确率，缺乏文档级整理
                - Vilsay：理解意图后重组为结构化文本
                """
            }
            return """
            ## 方案概述

            本方案提出了一种基于目标应用的自适应输出模式。

            ## 实现要点

            1. 检测前台应用的 Bundle ID
            2. 映射到对应的 OutputMode
            3. 按模式调整 Prompt 和处理规则
            """
        case .note:
            return """
            - 核心竞争力在长文本结构化整理
            - 短文本场景被系统输入法覆盖
            - 需要按目标应用切换输出风格
            - TODO: 补充长文本测试用例
            """
        case .general:
            // V3 行为：轻度纠错，不结构化
            return "我觉得这个方案还行，但是时间上可能来不及。"
        }
    }
}

// MARK: - 模拟 Pipeline 数据流验证

/// 模拟完整 Pipeline 数据流（不依赖真实录音/网络），验证：
/// bundleID → OutputMode → Prompt 组装 → 润色风格 → raw_log 记录
enum MockPipelineSimulator {

    struct SimulationResult {
        let bundleID: String?
        let outputMode: OutputMode
        let systemPrompt: String
        let polishedText: String
        let rawLogRecord: RawLogRecord
    }

    /// 模拟一次完整的录音→润色→记录流程。
    static func simulate(
        asrText: String,
        targetBundleID: String?,
        profile: UserProfile? = nil,
        asrConfidence: Double? = nil
    ) -> SimulationResult {
        // ① OutputMode 解析（= Pipeline 中 OutputModeResolver.resolve）
        let mode = OutputModeResolver.resolve(bundleID: targetBundleID)

        // ② Prompt 组装（= Pipeline 中 PromptComposer.systemPrompt）
        let system = PromptComposer.systemPrompt(
            for: profile,
            targetAppBundleID: targetBundleID,
            asrConfidence: asrConfidence
        )

        // ③ 模拟润色
        let polished = MockPolishService.polish(
            asrText: asrText,
            profile: profile,
            appBundleID: targetBundleID,
            asrConfidence: asrConfidence
        )

        // ④ 构造 raw_log 记录（= Pipeline 中 RawLogger.logAsync）
        let record = RawLogRecord(
            asrText: asrText,
            polishedText: polished,
            durationMs: 1000,
            sessionId: UUID().uuidString,
            asrProvider: "mock",
            asrConfidence: asrConfidence,
            targetAppId: targetBundleID,
            userFlaggedError: false,
            createdAt: ISO8601DateFormatter().string(from: Date()),
            outputMode: mode.rawValue
        )

        return SimulationResult(
            bundleID: targetBundleID,
            outputMode: mode,
            systemPrompt: system,
            polishedText: polished,
            rawLogRecord: record
        )
    }
}
