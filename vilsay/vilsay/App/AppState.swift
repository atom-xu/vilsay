//
//  AppState.swift
//  vilsay
//

import Combine
import SwiftUI

/// 全局 UI 状态（菜单栏 / 悬浮钮 / 设置；录音与处理状态由 `Pipeline` 驱动）。
///
/// **不提供** `createMenus()` 等 AppKit 菜单 API：菜单栏由 `vilsayApp` 的 `MenuBarExtra` 与 `UI/MenuBarRootMenu.swift` 负责。
/// 若其他文件调用 `AppState.shared.createMenus()`，说明混入了错误模板代码，应删除该调用及多余 `App.swift`。
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var status: AppStatus = .idle
    @Published var dictionaryBadgeCount: Int = 0
    /// 词典 Tab「智能推荐」待处理候选数（与 `dictionaryBadgeCount` 同步用于角标）。
    @Published var candidatesCount: Int = 0
    /// `triggerMode` 同时约束 **主热键（Fn / 🌐 / 右 Option）** 与 **悬浮钮**：
    /// - **单击**：仅识别短按切换（一下开始 / 再一下结束）；长按不产生录音。
    /// - **长按**：仅识别按住说话（≥ `Constants.fnTapVersusHoldMs` 后 `fnHoldPushDown`，松手结束）；短按不触发。
    @Published var triggerMode: TriggerMode = .push {
        didSet { UserDefaults.standard.set(triggerMode.rawValue, forKey: Keys.triggerMode) }
    }

    @Published var recognitionMode: RecognitionMode = .cloud {
        didSet { UserDefaults.standard.set(recognitionMode.rawValue, forKey: Keys.recognitionMode) }
    }

    /// 语音识别语种与中文简繁偏好（云端 hints + 本地 Whisper + 识别后字形归一）。
    @Published var asrSpokenLanguage: ASRSpokenLanguage = .chineseSimplified {
        didSet { UserDefaults.standard.set(asrSpokenLanguage.rawValue, forKey: UserDefaultsKeys.asrSpokenLanguage) }
    }

    /// 设置窗口内 Tab：设置 / 词典 / 用量（兼容旧引用，Phase 4 清理）
    @Published var settingsMainTab: SettingsMainTab = .settings

    /// 主窗口侧边栏当前选中项
    @Published var selectedNavItem: MainNavItem = .dashboard

    @Published var showLoginSheet: Bool = false

    /// W3-09：取消后短暂显示 ✕
    @Published var showCancelFlash: Bool = false
    /// 短暂错误提示（录音太短、未识别到语音等），浮层显示后自动清除。
    @Published var transientErrorFlash: String?

    /// Push 模式下按住视觉（与 `Pipeline` 录音并行）
    @Published var isPushPressed: Bool = false

    /// 操作提示音（开始/结束录音、注入完成）；默认开启。
    @Published var soundFeedbackEnabled: Bool {
        didSet { UserDefaults.standard.set(soundFeedbackEnabled, forKey: Keys.soundFeedbackEnabled) }
    }

    /// Whisper 模型是否在后台加载中（用于菜单栏提示「本地模式准备中」）。
    @Published var localWhisperLoading = false
    /// 本地 ASR 是否已可用了（预加载完成）。
    @Published var localWhisperReady = false
    /// 菜单栏副文案：本地模型准备中等。
    @Published var localWhisperStatusHint: String?

    /// 润色降级 / API 不可用时的说明；非空时菜单栏用橙色 `attention`，并在菜单里可查看。
    @Published var polishAttentionMessage: String?

    /// 上一次润色是否真正改变输出（相对 ASR 原文）；用于浮层与菜单栏提示。
    @Published var lastPolishDidWork: Bool = true
    /// 润色未生效时的原因（无 Key、API 失败等）。
    @Published var lastPolishFailReason: String?

    /// AI3 最近一次手动/自动分析结果摘要（设置页展示）。
    @Published var ai3LastAnalysisResult: String?
    /// AI3 最近一次分析完成时间。
    @Published var ai3LastAnalysisDate: Date?

    /// 最近一次主链路错误摘要（严重错误时与 `status == .error` 同步）。
    @Published var lastPipelineError: String?

    // MARK: - Week 3 验收（最近一次成功跑通主链路的输入/输出，仅内存，设置页可见）

    /// 最近一次 ASR 原文（Whisper / 云端）。
    @Published var lastPipelineASRText: String = ""
    /// 最近一次润色侧累计输出（与注入内容一致，用于对照「输入→输出」）。
    @Published var lastPipelinePolishedText: String = ""
    @Published var lastPipelineASRDurationMs: Double = 0
    @Published var lastPipelinePolishWallMs: Double = 0
    @Published var lastPipelineInjectMs: Double = 0
    @Published var lastPipelineCompletedAt: Date?

    /// 新一次 `process` 开始时清空，避免与上一轮混淆。
    func resetPipelineTraceForNewRun() {
        lastPipelineASRText = ""
        lastPipelinePolishedText = ""
        lastPipelineASRDurationMs = 0
        lastPipelinePolishWallMs = 0
        lastPipelineInjectMs = 0
        lastPipelineCompletedAt = nil
        lastPolishDidWork = true
        lastPolishFailReason = nil
    }

    /// 开发诊断：环境变量排除项触发时的短提示（如已跳过麦克风），数秒后自动清空。
    @Published var diagnosticsExclusionHint: String?

    /// 嵌入式 `HotkeyMonitor` XPC 内 `CGEventTap` 未就绪（常见原因：未在「辅助功能」中勾选本应用）。为 true 时全局 Fn 与 ESC 可能无效，请用菜单「开始录音」或打开系统设置授权。
    @Published var hotkeyAccessibilityRequired = false

    /// 最近一次热键健康自检结果（启动时与设置页「重新检测」更新）。
    @Published var hotkeyHealthReport: HotkeyHealthChecker.HealthReport?

    /// Week 4-P05：无网络时提示（与 `NetworkMonitor` 同步）。
    @Published var networkOfflineHint: String?

    /// Week 4-P03：热键自测 — 为 true 时下一次合法按下仅记录结果，不启动 Pipeline。
    @Published var hotkeySelfTestAwaiting = false
    /// Week 4-P03：ESC 自测。
    @Published var escSelfTestAwaiting = false
    @Published var hotkeySelfTestMessage: String?

    // MARK: - W7 权限（菜单栏警告 / Onboarding 续传）
    /// 麦克风是否已授权（与 `didBecomeActive` 重检同步）。
    @Published var microphoneGranted: Bool = false
    /// 辅助功能是否已信任（与 `didBecomeActive` 重检同步）。
    @Published var accessibilityGranted: Bool = false

    // MARK: - W6 浮层 pill
    /// 非空且晚于当前时间时显示润色预览 pill；悬停可延长。
    @Published var floatingPreviewDismissAt: Date?
    @Published var floatingAudioLevel: Float = 0
    /// 用户点击「有误」后的短暂 UI 状态。
    @Published var floatingFeedbackRecorded: Bool = false

    func extendFloatingPreviewOnHover() {
        guard let d = floatingPreviewDismissAt else { return }
        floatingPreviewDismissAt = max(d, Date().addingTimeInterval(5))
    }

    /// 是否可能具备 FN/🌐 硬件（非 MacBook 通常为 false，用于设置项禁用）。
    let globeModifierLikelyAvailable = GlobeKeyHardwareCapabilities.isGlobeModifierLikelyAvailable

    private enum Keys {
        static let triggerMode = "vilsay.trigger_mode"
        static let recognitionMode = "vilsay.recognition_mode"
        static let soundFeedbackEnabled = "vilsay.sound_feedback_enabled"
    }

    private init() {
        UserDefaults.standard.register(defaults: [
            Keys.soundFeedbackEnabled: true,
            Keys.triggerMode: TriggerMode.push.rawValue,
            UserDefaultsKeys.asrSpokenLanguage: ASRSpokenLanguage.chineseSimplified.rawValue,
        ])
        self.soundFeedbackEnabled = UserDefaults.standard.bool(forKey: Keys.soundFeedbackEnabled)

        if let raw = UserDefaults.standard.string(forKey: Keys.triggerMode),
           let mode = TriggerMode(rawValue: raw) {
            triggerMode = mode
        }
        if let raw = UserDefaults.standard.string(forKey: Keys.recognitionMode),
           let mode = RecognitionMode(rawValue: raw) {
            recognitionMode = mode
        }
        if let raw = UserDefaults.standard.string(forKey: UserDefaultsKeys.asrSpokenLanguage),
           let lang = ASRSpokenLanguage(rawValue: raw) {
            asrSpokenLanguage = lang
        }
    }

    /// 开发调试用：循环切换状态，便于 Kimi 验收五种样式
    func cycleStatusForDebug() {
        let all = AppStatus.allCases
        if let i = all.firstIndex(of: status), all.indices.contains(i + 1) {
            status = all[i + 1]
        } else {
            status = all.first!
        }
    }
}

enum SettingsMainTab: Int, Hashable {
    case settings = 0
    case dictionary = 1
    case usage = 2
}

/// 由硬件自动决定，用户不可选：`AppConfig.hotkeyBindingMode`。
enum HotkeyBindingMode: String, CaseIterable, Identifiable {
    /// 无内置 🌐 时回退（台式机等）。
    case builtinRightOption
    /// MacBook 内置键盘优先使用。
    case fnGlobe

    var id: String { rawValue }

    var title: String {
        switch self {
        case .builtinRightOption: return "右 Option"
        case .fnGlobe: return "FN / Globe"
        }
    }
}

enum RecognitionMode: String, CaseIterable, Identifiable {
    case cloud
    case local

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cloud: return "云端"
        case .local: return "本地"
        }
    }
}

// MARK: - ASR 语种（百炼 hints / Whisper language / 简繁归一）

enum ASRSpokenLanguage: String, CaseIterable, Identifiable {
    /// 默认：大陆简体输出（识别后做 Traditional-Simplified）。
    case chineseSimplified
    case chineseTraditional
    /// 中文为主，夹杂英文（hints 同 zh；简繁同「简体」）。
    case mixedZhEn
    case english

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chineseSimplified: return "中文（简体）"
        case .chineseTraditional: return "中文（繁體）"
        case .mixedZhEn: return "中英混合"
        case .english: return "English"
        }
    }

    static func currentFromDefaults() -> ASRSpokenLanguage {
        if let raw = UserDefaults.standard.string(forKey: UserDefaultsKeys.asrSpokenLanguage),
           let v = ASRSpokenLanguage(rawValue: raw) {
            return v
        }
        return .chineseSimplified
    }

    /// DashScope 流式：文档称仅首个 hint 生效。
    var dashScopeStreamingHints: [String] {
        switch self {
        case .chineseSimplified, .chineseTraditional, .mixedZhEn: return ["zh"]
        case .english: return ["en"]
        }
    }

    /// DashScope 异步文件识别：可多语言提示。
    var dashScopeBatchHints: [String] {
        switch self {
        case .english: return ["en"]
        case .mixedZhEn: return ["zh", "en"]
        case .chineseSimplified, .chineseTraditional: return ["zh"]
        }
    }

    /// Whisper `DecodingOptions.language`
    var whisperLanguageCode: String? {
        switch self {
        case .english: return "en"
        case .chineseSimplified, .chineseTraditional, .mixedZhEn: return "zh"
        }
    }

    /// 识别完成后按用户偏好做简繁归一（英文模式不改字形）。
    func normalizeScript(_ text: String) -> String {
        switch self {
        case .chineseSimplified, .mixedZhEn:
            return ChineseScriptTransform.toSimplified(text)
        case .chineseTraditional:
            return ChineseScriptTransform.toTraditional(text)
        case .english:
            return text
        }
    }
}
