//
//  DependenciesSmoke.swift
//  vilsay
//
//  Week 1：验证 SPM 依赖可解析并参与编译。
//  以下依赖均来自 docs/spec 与任务书，非随意引入：
//  - WhisperKit：W3 本地 ASR 降级
//  - GRDB：W5 SQLite
//  - 热键：嵌入式 XPC `HotkeyMonitor` + 分布式通知（`Entry/HotkeyManager`），无 KeyboardShortcuts
//  - LaunchAtLogin：W2-06 / 设置页「开机启动」
//  Week 3：WhisperKit（ASR 降级）、Pipeline 全链路
//

import Foundation
import GRDB
import LaunchAtLogin
import WhisperKit

enum DependenciesSmoke {
    static func noop() {
        // 仅用于链接各模块；后续 Week 会替换为真实调用。
    }
}
