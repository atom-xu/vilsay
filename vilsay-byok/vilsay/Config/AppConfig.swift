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

    /// 润色（Qwen）模型 ID。
    static var dashscopePolishModel: String {
        envOrDefaults("VILSAY_QWEN_MODEL", key: dashscopeModelPolishKey) ?? "qwen-turbo"
    }

    /// 与 `dashscopePolishModel` 同义（历史命名）。
    static var qwenModel: String { dashscopePolishModel }

    /// 录音文件识别（Paraformer 等）模型 ID。
    static var dashscopeAsrModel: String {
        envOrDefaults("VILSAY_ASR_MODEL", key: dashscopeModelAsrKey) ?? "paraformer-v2"
    }

    /// AI3 / 分析模型。
    static var dashscopeAnalyzerModel: String {
        envOrDefaults("VILSAY_ANALYZER_MODEL", key: dashscopeModelAnalyzerKey) ?? dashscopePolishModel
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
        return URL(string: "https://api.vilsay.com/api/v1/polish")!
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

    /// WebSocket 实时识别模型。
    static var streamingASRModel: String {
        envOrDefaults("VILSAY_STREAMING_ASR_MODEL", key: "vilsay.streaming_asr_model") ?? "paraformer-realtime-v2"
    }

    /// 账号后端基址。仅填协议 + 主机（+ 端口）。
    static var backendAPIBaseURL: URL? {
        guard let raw = envOrDefaults("VILSAY_API_BASE", key: "vilsay.api_base") else { return nil }
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        guard !s.isEmpty else { return nil }
        return URL(string: s)
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

