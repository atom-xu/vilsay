//
//  Constants.swift
//  vilsay
//

import Foundation

enum Constants {
    /// AI3 自动分析：DEBUG 降低阈值便于联调；Release 保持 20。
    #if DEBUG
    static let analyzerTriggerThreshold = 5
    #else
    static let analyzerTriggerThreshold = 20
    #endif
    static let analyzerRecentSessions = 50
    static let vadPauseMs: UInt64 = 800
    /// 最短有效语音（秒），低于此视为空音频兜底，不进入 ASR（`VILSAY_TECH_SPEC_SUPPLEMENT` §1.4）。
    static let vadMinSpeechSeconds: TimeInterval = 0.3
    static let maxTotalLatencyMs: UInt64 = 1500
    static let polishTimeoutMs: UInt64 = 5000

    // MARK: - 热键 / 录音保护（对齐 VoiceInk：防误触、连击、竞态、超长录音、空音频卡死）
    /// 按住至少该时长才真正开始录音，避免极短点击产生空文件。
    static let minHoldDurationSeconds: TimeInterval = 0.15
    /// 一次结束后的冷却，忽略新触发，防连击。
    static let postStopCooldownSeconds: TimeInterval = 0.3
    /// Push 按住最长时长，超时强制结束，防泄露与挂死。
    static let maxPushRecordingSeconds: TimeInterval = 300
    /// 全局 **Fn** 键：按下时长 **低于** 此值后松开 → **单击**（Toggle）；**达到** 此值仍按住 → **长按**（Push 按住说话）。与 `minHoldDurationSeconds` 独立。
    static let fnTapVersusHoldMs: UInt64 = 250
    /// 低于此时长视为无效音频，不进入 ASR（与 `vadMinSpeechSeconds` 对齐为 300ms）。
    static let minAudioDurationForASRSeconds: TimeInterval = vadMinSpeechSeconds
    /// 润色 SSE 注入：攒够约 3～5 个字符再 `pasteChunk`，减轻逐 token 粘贴导致的光标跳动。
    static let polishStreamingPasteMinBatchCharacters = 4
    static let profileMinConfidence: Double = 0.3
    static let profileMaxDictItems = 200
    /// V14：低于此 ASR 置信度时在 Prompt 注入 §C「识别质量」提示。
    static let asrLowConfidenceThreshold: Double = 0.4
    /// 主链路绝对超时（与 Pipeline `withTaskGroup` 对齐）。
    static let pipelineAbsoluteDeadlineMs: UInt64 = 35_000
    static let polishResourceTimeoutMs: UInt64 = 30_000
    /// W6：浮层完成态预览默认停留（毫秒）。
    static let floatingPillPreviewDurationMs: UInt64 = 2_000
    static let floatingPillPreviewMaxChars = 20
    /// 与 WhisperKit Hub / 包内文件夹名一致；包内路径见 `WhisperModels/<name>`。
    nonisolated static let asrFallbackModel = "openai_whisper-base"

    /// 通过 AX 读其它应用选区时的上限；部分应用/焦点树异常时 `AXUIElementCopyAttributeValue` 会长时间阻塞，必须在主链路外带超时。
    static let axSelectedTextFetchTimeoutNanoseconds: UInt64 = 400_000_000

    // MARK: - 主链路超时兜底（FIX-04～06）
    /// ASR（Whisper/云端）转写竞速上限。
    static let asrTranscribeTimeoutNanoseconds: UInt64 = 60_000_000_000
    /// `deliverASRThroughVADToPolish` 整段外层上限（与内层 35s 润色竞速独立）。
    static let vadDeliverOuterTimeoutNanoseconds: UInt64 = 40_000_000_000
    /// `AudioCapture.start()` 等待 HAL 就绪上限。
    static let audioStartTimeoutNanoseconds: UInt64 = 5_000_000_000
}

/// 产品官网深链（与 `website/` 部署域名一致；内购未接时仍可从浏览器了解套餐）。
enum WebsiteURL {
    static let home = URL(string: "https://vilsay.com")!
    static let pricing = URL(string: "https://vilsay.com/pricing")!
    static let privacy = URL(string: "https://vilsay.com/privacy")!
    static let terms = URL(string: "https://vilsay.com/terms")!
}

/// Whisper 从 Hugging Face 拉取失败时，将 NSURLError -1009 等转为可操作的中文说明（避免仅显示英文 “Model not found”）。
enum WhisperLoadErrorPresentation {
    nonisolated static func isLikelyOfflineNetworkFailure(_ error: Error) -> Bool {
        var cur: NSError? = error as NSError
        while let c = cur {
            if c.domain == NSURLErrorDomain, c.code == NSURLErrorNotConnectedToInternet {
                return true
            }
            cur = c.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return false
    }

    nonisolated static func userMessage(for error: Error) -> String {
        if isLikelyOfflineNetworkFailure(error) {
            return "无法下载 Whisper 模型（网络离线或无法访问 Hugging Face）。请将 \(Constants.asrFallbackModel) 放入 Xcode 资源 WhisperModels/ 后重新编译，或检查网络与代理。"
        }
        return (error as NSError).localizedDescription
    }
}
