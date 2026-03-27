//
//  MenuBarRootMenu.swift
//  vilsay
//

import AppKit
import SwiftUI

/// 菜单栏下拉菜单（后台常驻，快捷控制）。
struct MenuBarRootMenu: View {
    @ObservedObject private var state = AppState.shared

    var body: some View {
        Group {
        if !state.microphoneGranted {
            Section {
                Label("麦克风权限已关闭", systemImage: "mic.slash")
                    .foregroundStyle(VColor.warn)
                Button("打开系统设置修复…") {
                    PermissionManager.shared.openMicrophonePrivacySettings()
                }
                Text("录音功能不可用，请重新授权。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        if !state.accessibilityGranted {
            Section {
                Label("辅助功能权限未开启", systemImage: "keyboard.badge.exclamationmark")
                    .foregroundStyle(VColor.warn)
                Button("打开系统设置修复…") {
                    PermissionManager.shared.openAccessibilityPrivacySettings()
                }
                Text("文字注入不可用，润色结果只能复制。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        if !state.microphoneGranted || !state.accessibilityGranted {
            Divider()
        }

        // 打开主窗口
        Button {
            openMainWindow(nav: .dashboard)
        } label: {
            Label("打开 Vilsay", systemImage: "macwindow")
        }

        Divider()

        // 录音控制
        if state.status == .recording || state.status == .editMode {
            Button {
                Task { @MainActor in await Pipeline.shared.stopRecording() }
            } label: {
                Label("停止录音", systemImage: "stop.fill")
            }
            Button {
                Task { @MainActor in await Pipeline.shared.cancel() }
            } label: {
                Label("取消（不输出）", systemImage: "xmark.circle")
            }
        } else {
            Button {
                Task { @MainActor in await Pipeline.shared.toggleRecording() }
            } label: {
                Label("开始录音", systemImage: "mic.fill")
            }
        }

        if state.hotkeyAccessibilityRequired {
            Text("热键可能未生效：请在「系统设置 → 隐私与安全性 → 辅助功能」中勾选 Vilsay；或始终用上方「开始录音」。")
                .font(.caption)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Label("打开辅助功能设置…", systemImage: "lock.shield")
            }
        }

        if let polishMsg = state.polishAttentionMessage, !polishMsg.isEmpty {
            Button("润色服务不可用…") {
                let alert = NSAlert()
                alert.messageText = "润色服务不可用"
                alert.informativeText = polishMsg
                alert.alertStyle = .informational
                alert.runModal()
            }
        }

        if let reason = state.lastPolishFailReason, !state.lastPolishDidWork {
            Section {
                Label("润色未生效", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(VColor.warn)
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !AppConfig.canRunPolishWithCurrentCredentials {
                    Button("去设置…") {
                        openMainWindow(nav: .settings)
                    }
                }
            }
        }

        if let err = state.lastPipelineError, !err.isEmpty {
            Button("上次错误详情…") {
                let alert = NSAlert()
                alert.messageText = "处理出错"
                alert.informativeText = err
                alert.alertStyle = .warning
                alert.runModal()
            }
        }

        Divider()

        // 快捷导航
        Button {
            openMainWindow(nav: .history)
        } label: {
            Label("历史记录", systemImage: "clock.arrow.circlepath")
        }

        Button {
            openMainWindow(nav: .dictionary)
        } label: {
            HStack {
                Text("词典")
                Spacer()
                if state.dictionaryBadgeCount > 0 {
                    Text("\(state.dictionaryBadgeCount)")
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(VColor.fail.opacity(0.9)))
                        .foregroundStyle(.white)
                        .font(.caption.weight(.semibold))
                }
            }
        }

        Button {
            openMainWindow(nav: .settings)
        } label: {
            Label("设置", systemImage: "gearshape")
        }

        Divider()

        Button {
            NSApplication.shared.terminate(nil)
        } label: {
            Label("退出 Vilsay", systemImage: "power")
        }

        #if DEBUG
        Divider()
        Menu("调试（验收用）") {
            Button("切换状态样式") { state.cycleStatusForDebug() }
            Button("词典角标 +1") { state.dictionaryBadgeCount = min(99, state.dictionaryBadgeCount + 1) }
            Button("词典角标清零") { state.dictionaryBadgeCount = 0 }
            Divider()
            Button("重置向导（重启后生效）") {
                UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.onboardingDone)
                UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.onboardingStep)
            }
        }
        #endif
        }
    }

    // MARK: - 打开主窗口并导航到指定页

    private func openMainWindow(nav: MainNavItem) {
        AppState.shared.selectedNavItem = nav
        for window in NSApp.windows {
            if window.identifier?.rawValue == "main" || window.title == "Vilsay" {
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                return
            }
        }
        NSApp.activate(ignoringOtherApps: true)
    }
}
