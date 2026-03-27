//
//  DiagnosticsExclusion.swift
//
//  通过 Scheme / 启动参数设置环境变量，逐项关闭子系统，用排除法定位崩溃或卡死。
//  仅用于开发诊断，勿在正式发行包中长期开启。
//

import Foundation
import os.log

enum DiagnosticsExclusion {
    private static let log = Logger(subsystem: "com.vilsay.app", category: "Diagnostics")

    /// 接受 `1`、`true`、`yes`、`on`（忽略大小写与首尾空格）；避免 Scheme 里填错导致「没反应」。
    nonisolated private static func env(_ name: String) -> Bool {
        guard let raw = ProcessInfo.processInfo.environment[name] else { return false }
        let v = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return v == "1" || v == "true" || v == "yes" || v == "on"
    }

    /// `VILSAY_EXCLUDE_SOUND=1` — 不调用 `AudioServicesPlaySystemSound`（排除 AudioToolbox 与 HAL 同机竞争）
    nonisolated static var excludeSystemSound: Bool { env("VILSAY_EXCLUDE_SOUND") }

    /// `VILSAY_EXCLUDE_HOTKEY_XPC=1` — 不启动 `HotkeyManager` / 不连接 HotkeyMonitor XPC（排除热键子进程与 XPC）
    nonisolated static var excludeHotkeyXPC: Bool { env("VILSAY_EXCLUDE_HOTKEY_XPC") }

    /// `VILSAY_EXCLUDE_HOTKEY_HEALTH=1` — 不启动热键定时 `checkHealth`（排除周期性 XPC ping）
    nonisolated static var excludeHotkeyHealthMonitor: Bool { env("VILSAY_EXCLUDE_HOTKEY_HEALTH") }

    /// `VILSAY_EXCLUDE_WHISPER=1` — 不预加载 WhisperKit，转写直接返回空串（排除本地模型与 CoreML/下载）
    nonisolated static var excludeWhisperLocal: Bool { env("VILSAY_EXCLUDE_WHISPER") }

    /// `VILSAY_EXCLUDE_MIC_HAL=1`（或短名 `VILSAY_NO_MIC=1`）— 不调用 `AVAudioRecorder` / HAL
    nonisolated static var excludeMicrophoneHAL: Bool {
        env("VILSAY_EXCLUDE_MIC_HAL") || env("VILSAY_NO_MIC")
    }

    /// `VILSAY_EXCLUDE_FLOATING_BUTTON=1` — 不调用 `FloatingButtonController.showIfNeeded()`（排除悬浮窗创建）
    nonisolated static var excludeFloatingButton: Bool { env("VILSAY_EXCLUDE_FLOATING_BUTTON") }

    static func logActiveExclusionsAtLaunch() {
        let pairs: [(String, Bool)] = [
            ("VILSAY_EXCLUDE_SOUND", excludeSystemSound),
            ("VILSAY_EXCLUDE_HOTKEY_XPC", excludeHotkeyXPC),
            ("VILSAY_EXCLUDE_HOTKEY_HEALTH", excludeHotkeyHealthMonitor),
            ("VILSAY_EXCLUDE_WHISPER", excludeWhisperLocal),
            ("VILSAY_EXCLUDE_MIC_HAL|VILSAY_NO_MIC", excludeMicrophoneHAL),
            ("VILSAY_EXCLUDE_FLOATING_BUTTON", excludeFloatingButton),
        ]
        let on = pairs.filter { $0.1 }.map(\.0)
        if on.isEmpty {
            log.info("🧪 诊断排除：未设置任何 VILSAY_EXCLUDE_*。若已在 Scheme 里添加却仍见此行：请用 Xcode ⌘R 运行（从访达双击 .app 不会带入环境变量）；并确认变量左侧已勾选。")
        } else {
            log.warning("🧪 诊断排除已启用：\(on.joined(separator: ", ")) — 仅用于定位问题")
        }
        if let raw = ProcessInfo.processInfo.environment["VILSAY_EXCLUDE_MIC_HAL"] {
            log.info("🧪 VILSAY_EXCLUDE_MIC_HAL 原始值=\"\(raw)\" → 生效=\(excludeMicrophoneHAL)")
        }
        if let raw = ProcessInfo.processInfo.environment["VILSAY_NO_MIC"] {
            log.info("🧪 VILSAY_NO_MIC 原始值=\"\(raw)\" → 生效=\(excludeMicrophoneHAL)")
        }
    }
}
