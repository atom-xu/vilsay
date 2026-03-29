//
//  AppConfig.swift
//  vilsay — FIX-P01 v2：环境变量 > UserDefaults，无调试开关。
//

import Foundation

/// 运行时配置：统一 `envOrDefaults`；Scheme 环境变量可覆盖设置页。
enum AppConfig {
    // MARK: - 热键 / 触发（与 `AppState` 共用 UserDefaults 键）

    private static let triggerModeKey = "vilsay.trigger_mode"

    private static let dashscopeAPIKeyKey = "vilsay.dashscope_api_key"
    private static let dashscopeModelAsrKey = "vilsay.dashscope_model_asr"
    private static let dashscopeModelPolishKey = "vilsay.dashscope_model_polish"
    private static let dashscopeModelAnalyzerKey = "vilsay.dashscope_model_analyzer"
    private static let dashscopeModelReviewKey = "vilsay.dashscope_model_review"
    private static let dashscopeParaformerFileURLKey = "vilsay.dashscope_paraformer_file_url"
    private static let asrProxyTranscribeURLKey = "vilsay.asr_proxy_transcribe_url"

    /// 当前触发方式（Push/Toggle）；与 `AppState.triggerMode` 同步。
    static var triggerMode: TriggerMode {
        guard let raw = UserDefaults.standard.string(forKey: triggerModeKey),
              let mode = TriggerMode(rawValue: raw) else {
            return .toggle
        }
        return mode
    }

    /// 热键：**优先 FN / 🌐**；无内置 Globe 键的机器自动使用右 Option。
    static var hotkeyBindingMode: HotkeyBindingMode {
        GlobeKeyHardwareCapabilities.isGlobeModifierLikelyAvailable ? .fnGlobe : .builtinRightOption
    }

    // MARK: - 统一读取：环境变量 > UserDefaults

    /// 百炼 API Key。
    static var dashscopeAPIKey: String? {
        envOrDefaults("DASHSCOPE_API_KEY", key: dashscopeAPIKeyKey)
    }

    // MARK: - 模型配置
    // 三层模型架构：fast（主链路）/ balanced（Review+AI3）/ ASR
    // 默认值为 DashScope Qwen 系列；用户可通过环境变量或设置页切换为其他供应商模型。
    // 例如 OpenAI：VILSAY_QWEN_MODEL=gpt-4o-mini  VILSAY_REVIEW_MODEL=gpt-4o
    // 例如豆包：VILSAY_QWEN_MODEL=doubao-lite     VILSAY_REVIEW_MODEL=doubao-pro

    // MARK: - 模型配置（从 DashScope API /v1/models 拉取确认）
    //
    // 可用文本模型及价格（元/百万token）：
    //   qwen-flash      输入 0.15  输出 1.5   — 最快最便宜，Qwen3 Flash
    //   qwen-turbo      输入 0.3   输出 0.6   — 轻量快速，Qwen3 Turbo
    //   qwen-plus       输入 0.8   输出 2.0   — 平衡，Qwen3 Plus
    //   qwen-max        输入 2.4   输出 9.6   — 最强，千问2.5 Max
    //   qwen3.5-flash   输入 0.2   输出 2.0   — Qwen3.5 最新 Flash
    //   qwen3.5-plus    输入 0.8   输出 4.8   — Qwen3.5 最新 Plus
    //
    // 用户可通过环境变量或设置页切换模型（包括其他供应商）。

    /// 主链路润色模型（速度优先）。qwen-flash：最快最便宜，适合实时润色。
    static var dashscopePolishModel: String {
        envOrDefaults("VILSAY_QWEN_MODEL", key: dashscopeModelPolishKey) ?? "qwen-flash"
    }

    /// 与 `dashscopePolishModel` 同义（历史命名）。
    static var qwenModel: String { dashscopePolishModel }

    /// 录音文件识别（Paraformer 等）模型 ID。
    static var dashscopeAsrModel: String {
        envOrDefaults("VILSAY_ASR_MODEL", key: dashscopeModelAsrKey) ?? "paraformer-v2"
    }

    /// AI3 分析模型（理解力优先，后台运行）。qwen-plus：更强理解力，分析用户画像和候选词。
    static var dashscopeAnalyzerModel: String {
        envOrDefaults("VILSAY_ANALYZER_MODEL", key: dashscopeModelAnalyzerKey) ?? "qwen-plus"
    }

    /// L3 Review 审校模型（理解力优先，后台运行，用不同模型避免"自己审自己"）。
    static var dashscopeReviewModel: String {
        envOrDefaults("VILSAY_REVIEW_MODEL", key: dashscopeModelReviewKey) ?? "qwen-plus"
    }

    /// DEBUG：原生 `text-generation` 与 OpenAI 兼容 `chat/completions` 切换。
    static var polishUsesOpenAICompatChatCompletions: Bool {
        #if DEBUG
        if let e = ProcessInfo.processInfo.environment["VILSAY_POLISH_USE_COMPAT"]?
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            if e == "1" || e == "true" || e == "yes" { return true }
            if e == "0" || e == "false" || e == "no" { return false }
        }
        return dashscopePolishModel.contains("/")
        #else
        return false
        #endif
    }

    /// 用户自备 DashScope Key 时的直连 URL（原生 text-generation 接口）。
    static let dashscopeDirectURL = URL(string: "https://dashscope.aliyuncs.com/api/v1/services/aigc/text-generation/generation")!

    /// 用户自备 DashScope Key 时的 OpenAI 兼容模式 URL。
    static let dashscopeCompatURL = URL(string: "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions")!

    /// 润色 HTTP 目标：自备 Key 始终直连 DashScope，否则走 Vilsay 代理。
    static var polishHTTPURL: URL {
        // 用户自备 API Key → 永远直连 DashScope，不受构建配置影响
        if hasDashScopeAPIKey {
            if polishUsesOpenAICompatChatCompletions {
                return dashscopeCompatURL
            }
            return dashscopeDirectURL
        }
        return qwenPolishEndpoint
    }

    /// 润色 API 代理端点（无自备 Key 时走后端代理）。
    static var qwenPolishEndpoint: URL {
        if let raw = ProcessInfo.processInfo.environment["VILSAY_POLISH_PROXY_URL"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           let u = URL(string: raw), !raw.isEmpty {
            return u
        }
        #if BYOK_ONLY || DEBUG
        return dashscopeDirectURL
        #else
        return URL(string: "https://vilsay-api.vilhil.cn/api/v1/polish")!
        #endif
    }

    static var hasDashScopeAPIKey: Bool {
        dashscopeAPIKey != nil
    }

    /// BYOK 专版：用户自备 API Key，无内购，无后端账号。
    static var byokOnly: Bool {
        #if BYOK_ONLY
        return true
        #else
        return false
        #endif
    }

    /// 当前是否可以执行润色：BYOK 版仅检查 API Key；标准版检查 Key 或 Pro Token。
    static var canRunPolishWithCurrentCredentials: Bool {
        #if BYOK_ONLY
        return hasDashScopeAPIKey
        #else
        if hasDashScopeAPIKey { return true }
        let t = KeychainTokenStore.loadToken()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !t.isEmpty
        #endif
    }

    /// 流式 ASR：有百炼 Key 且网络可用时启用。
    static var streamingASREnabled: Bool {
        hasDashScopeAPIKey && NetworkMonitor.shared.isConnected
    }

    /// L3 Review：润色后二次校验开关。通过设置页或环境变量 VILSAY_POLISH_REVIEW=1 启用。
    static var polishReviewEnabled: Bool {
        if let e = ProcessInfo.processInfo.environment["VILSAY_POLISH_REVIEW"]?
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           e == "1" || e == "true" { return true }
        return UserDefaults.standard.bool(forKey: "vilsay.polish_review_enabled")
    }

    /// WebSocket 实时识别模型（流式反馈用）。
    static var streamingASRModel: String {
        envOrDefaults("VILSAY_STREAMING_ASR_MODEL", key: "vilsay.streaming_asr_model") ?? "paraformer-realtime-v2"
    }

    /// 文件识别模型。qwen-audio-asr：基于 Qwen-Audio 的端到端 LLM ASR，自带上下文纠偏，中英文混合更准。
    static var fileASRModel: String {
        envOrDefaults("VILSAY_FILE_ASR_MODEL", key: "vilsay.file_asr_model") ?? "qwen-audio-asr"
    }

    /// 账号后端基址（vilsay-api.vilhil.cn）。环境变量或 UserDefaults 可覆盖。
    /// 域名规划：vilsay.com = 官网，vilsay-api.vilhil.cn = Vilsay API，api.vilhil.cn 预留给 VilHil。
    static var backendAPIBaseURL: URL? {
        if let raw = envOrDefaults("VILSAY_API_BASE", key: "vilsay.api_base") {
            var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            while s.hasSuffix("/") { s.removeLast() }
            if !s.isEmpty { return URL(string: s) }
        }
        return URL(string: "https://vilsay-api.vilhil.cn/api/v1")
    }

    /// Paraformer 录音文件公网联调 URL（经后端上传 OSS 等）。
    static var dashscopeParaformerFileURL: String? {
        envOrDefaults("DASHSCOPE_PARAFORMER_FILE_URL", key: dashscopeParaformerFileURLKey)
    }

    /// 云端 ASR 代理完整 URL。
    static var asrProxyTranscribeURL: URL? {
        guard let raw = envOrDefaults("VILSAY_ASR_PROXY_URL", key: asrProxyTranscribeURLKey) else { return nil }
        return URL(string: raw)
    }

    /// 与后端 `ASR_INTERNAL_KEY` 一致。
    static var asrInternalKey: String? {
        envOrDefaults("VILSAY_ASR_INTERNAL_KEY", key: "vilsay.asr_internal_key")
    }

    /// Google OAuth Client ID。
    static var googleOAuthClientId: String? {
        envOrDefaults("VILSAY_GOOGLE_CLIENT_ID", key: "vilsay.google_oauth_client_id")
    }

    /// 微信授权页 URL。
    static var weChatOAuthAuthorizeURL: URL? {
        guard let raw = envOrDefaults("VILSAY_WECHAT_OAUTH_URL", key: "vilsay.wechat_oauth_url") else { return nil }
        return URL(string: raw)
    }

    // MARK: - Private

    /// 环境变量优先，UserDefaults 兜底。
    private static func envOrDefaults(_ envKey: String, key defaultsKey: String) -> String? {
        if let env = ProcessInfo.processInfo.environment[envKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines), !env.isEmpty {
            return env
        }
        if let val = UserDefaults.standard.string(forKey: defaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !val.isEmpty {
            return val
        }
        return nil
    }
}

