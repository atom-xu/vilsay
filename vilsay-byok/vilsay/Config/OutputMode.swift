//
//  OutputMode.swift
//  vilsay — PM-01 / PM-11：输出模式与 Bundle 解析（UserDefaults 覆盖优先）。
//

import Foundation

/// 输出模式：由目标应用决定。`.general` 即 V3 原有行为。
enum OutputMode: String, Codable, CaseIterable, Identifiable {
    case aiCommand
    case chat
    case email
    case document
    case note
    case general

    var id: String { rawValue }

    /// 设置页展示用
    var title: String {
        switch self {
        case .aiCommand: return "AI 指令"
        case .chat: return "聊天"
        case .email: return "邮件"
        case .document: return "文档"
        case .note: return "笔记"
        case .general: return "通用（V3）"
        }
    }
}

enum OutputModeResolver {
    private static let overrideKeyPrefix = "vilsay.output_mode_override."

    private static let modeMap: [String: OutputMode] = [
        // AI 对话 — 暂不自动激活 aiCommand（用户在 AI 工具前台不一定在下指令，
        // 强行编号输出会破坏正常语句；用户可在设置页手动开启）
        // "com.anthropic.claudefordesktop": .aiCommand,
        // "com.openai.chat": .aiCommand,
        // "com.cursor.ide": .aiCommand,
        // "dev.continue.continue": .aiCommand,
        // 聊天
        "com.tencent.xinWeChat": .chat,
        "com.apple.MobileSMS": .chat,
        "com.tencent.qq": .chat,
        "com.slack.Slack": .chat,
        "com.electron.lark": .chat,
        "com.alibaba.DingTalkMac": .chat,
        "ru.keepcoder.Telegram": .chat,
        // 邮件
        "com.apple.mail": .email,
        "com.tencent.foxmail": .email,
        "com.microsoft.Outlook": .email,
        // 文档
        "com.microsoft.Word": .document,
        "com.apple.Pages": .document,
        "com.notion.id": .document,
        "md.obsidian": .document,
        // 笔记
        "com.apple.Notes": .note,
        "net.shinyfrog.bear": .note,
    ]

    /// 所有可自动识别的 Bundle ID（用于设置页）
    static var knownBundleIDs: [String] {
        Array(modeMap.keys).sorted()
    }

    /// 用户为某 Bundle 设置的覆盖（无则 nil）
    static func userOverride(for bundleID: String) -> OutputMode? {
        guard let raw = UserDefaults.standard.string(forKey: overrideKeyPrefix + bundleID),
              let m = OutputMode(rawValue: raw) else { return nil }
        return m
    }

    static func setUserOverride(bundleID: String, mode: OutputMode?) {
        let key = overrideKeyPrefix + bundleID
        if let mode {
            UserDefaults.standard.set(mode.rawValue, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    static func resolve(bundleID: String?) -> OutputMode {
        guard let id = bundleID, !id.isEmpty else { return .general }
        if let override = userOverride(for: id) {
            return override
        }
        return modeMap[id] ?? .general
    }
}
