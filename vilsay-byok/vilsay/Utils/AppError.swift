//
//  AppError.swift
//  vilsay
//
//  `VILSAY_TECH_SPEC_SUPPLEMENT` §6.1～6.3

import Foundation

enum AppError: String, CaseIterable, Identifiable {
    case micPermissionDenied
    case accessibilityDenied
    case hotkeyConflict
    case recordingTooShort
    case asrFailed
    case asrTimeout
    case polishFailed
    case polishHallucination
    case apiKeyMissing
    case notLoggedIn
    case tokenExpired
    case quotaExceeded
    case networkUnavailable
    case serverError

    var id: String { rawValue }

    /// 用户可见文案（中文）。
    var userMessage: String {
        switch self {
        case .micPermissionDenied: return "需要麦克风权限，请在系统设置中开启。"
        case .accessibilityDenied: return "需要辅助功能权限才能使用全局热键。"
        case .hotkeyConflict: return "热键冲突，请在设置中修改。"
        case .recordingTooShort: return ""
        case .asrFailed: return "语音识别失败，已输出原始文字。"
        case .asrTimeout: return "识别超时，请重试。"
        case .polishFailed: return "润色服务暂时不可用，已输出原始文字。"
        case .polishHallucination: return ""
        case .apiKeyMissing: return "服务配置异常，请联系支持。"
        case .notLoggedIn: return "请先登录以使用 Vilsay。"
        case .tokenExpired: return "登录已过期，请重新登录。"
        case .quotaExceeded: return "本月免费次数已用完，升级继续使用。"
        case .networkUnavailable: return "网络不可用，已切换本地模式。"
        case .serverError: return "服务器异常，请稍后重试。"
        }
    }

    /// §6.2：静默 / 菜单栏橙色 / 弹窗
    enum Presentation {
        case silent
        case menuBarAttention
        case alert
    }

    var presentation: Presentation {
        switch self {
        case .recordingTooShort, .polishHallucination: return .silent
        case .micPermissionDenied, .accessibilityDenied, .notLoggedIn, .tokenExpired, .quotaExceeded, .hotkeyConflict:
            return .alert
        default:
            return .menuBarAttention
        }
    }

    /// §6.3：是否 3 秒后自动回 idle。
    var autoRecoverToIdleAfterSeconds: TimeInterval? {
        switch self {
        case .asrFailed, .asrTimeout, .polishFailed, .serverError: return 3
        default: return nil
        }
    }
}
