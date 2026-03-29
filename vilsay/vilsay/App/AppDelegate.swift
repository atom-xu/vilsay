//
//  AppDelegate.swift
//  vilsay
//

import AppKit
import ApplicationServices
import AVFoundation
import os.log
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let log = Logger(subsystem: "com.vilsay.app", category: "AppDelegate")
    private var onboarding: OnboardingWindowController?
    private var appNotificationObservers: [NSObjectProtocol] = []
    private var workspaceNotificationObservers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        DiagnosticsExclusion.logActiveExclusionsAtLaunch()
        DependenciesSmoke.noop()

        // 去掉所有窗口 title bar 下方的分割线（Apple Sonoma 新规范）
        // 用 asyncAfter 确保 SwiftUI 窗口已创建完毕
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            Self.applyTitlebarStyle()
        }
        // 每次窗口成为 key window 时再补一次，确保新窗口也生效
        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { _ in
            Self.applyTitlebarStyle()
        }

        do {
            try AppDatabase.shared.setup()
            let pending = ProfileService.getCandidates().count
            DispatchQueue.main.async {
                AppState.shared.candidatesCount = pending
                AppState.shared.dictionaryBadgeCount = pending
            }
        } catch {
            Self.log.error("SQLite 初始化失败: \(error.localizedDescription)")
        }

        Task {
            await AuthService.shared.restoreSession()
            SubscriptionManager.shared.start()
        }

        // ✅ 应用启动时检查所有权限
        PermissionManager.shared.checkAllPermissionsOnLaunch()
        recheckPermissions()
        
        // WhisperKit 预加载改在首次录音结束、HAL 释放后触发（见 Pipeline），避免与录音同时抢 MainActor。
        AppState.shared.localWhisperLoading = false
        AppState.shared.localWhisperStatusHint = nil
        if !DiagnosticsExclusion.excludeHotkeyXPC {
            HotkeyManager.shared.start()
        } else {
            Self.log.warning("🧪 VILSAY_EXCLUDE_HOTKEY_XPC=1：未启动热键 XPC，请用菜单/悬浮钮测主进程")
        }
        registerHotkeyPriorityObservers()
        _ = FloatingButtonController.shared

        Task { @MainActor in
            let report = HotkeyHealthChecker.shared.performStartupCheck()
            handleHealthReport(report)
            // 推迟写入 @Published，避免与 MenuBarExtra 当前 layout 同帧重入（layoutSubtreeIfNeeded）
            DispatchQueue.main.async {
                AppState.shared.hotkeyHealthReport = report
            }

            if !DiagnosticsExclusion.excludeHotkeyHealthMonitor {
                HotkeyHealthChecker.shared.startContinuousMonitoring()
                Self.log.info("✅ 热键持续监控已启动")
            } else {
                Self.log.warning("🧪 VILSAY_EXCLUDE_HOTKEY_HEALTH=1：已跳过热键定时健康检查")
            }
        }

        let ob = OnboardingWindowController()
        ob.showIfNeeded()
        onboarding = ob

        // UX Fix #1：Onboarding 未完成时隐藏主窗口，避免同时弹出两个窗口
        if !UserDefaults.standard.bool(forKey: UserDefaultsKeys.onboardingDone) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                Self.hideMainWindow()
            }
        }
    }

    /// 隐藏主窗口（Onboarding 期间调用）。
    private static func hideMainWindow() {
        for window in NSApp.windows {
            if (window.identifier?.rawValue == "main" || window.title == "Vilsay"),
               window.title != "欢迎使用 Vilsay" {
                window.orderOut(nil)
            }
        }
    }

    /// 从系统设置返回后同步麦克风 / 辅助功能状态（W7-A06）。
    private func recheckPermissions() {
        let micGranted = AVAudioApplication.shared.recordPermission == .granted
        let axGranted = AXIsProcessTrusted()
        DispatchQueue.main.async {
            AppState.shared.microphoneGranted = micGranted
            AppState.shared.accessibilityGranted = axGranted
        }
    }

    /// `vilsay://auth/callback`、`vilsay://auth/verify`（`VILSAY_TECH_SPEC_SUPPLEMENT` §2.4）
    func applicationWillTerminate(_ notification: Notification) {
        if !DiagnosticsExclusion.excludeHotkeyXPC {
            HotkeyManager.shared.stop()
        }
    }

    /// 点击 Dock 图标时重新打开主窗口。
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            // 查找主窗口并显示
            for window in NSApp.windows {
                if window.identifier?.rawValue == "main" || window.title == "Vilsay" {
                    window.makeKeyAndOrderFront(nil)
                    break
                }
            }
            NSApp.activate(ignoringOtherApps: true)
        }
        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            guard url.scheme == "vilsay" else { continue }
            Task { @MainActor in
                AuthService.shared.handleDeepLink(url)
            }
        }
    }

    private static func applyTitlebarStyle() {
        NSApp.windows.forEach { $0.titlebarSeparatorStyle = .none }
    }

    private func handleHealthReport(_ report: HotkeyHealthChecker.HealthReport) {
        switch report.status {
        case .healthy:
            Self.log.info("✅ 热键系统正常")
        case .degraded:
            Self.log.warning("⚠️ 热键系统部分可用: \(report.issues.joined(separator: "；"))")
        case .unavailable:
            Self.log.error("❌ 热键系统不可用: \(report.issues.joined(separator: "；"))")
        }
    }

    /// 回到前台 / 唤醒：`HotkeyMonitor` XPC 内维护 EventTap；此处保留钩子以备将来扩展。
    private func registerHotkeyPriorityObservers() {
        let q = OperationQueue.main
        appNotificationObservers.append(NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: q) { [weak self] _ in
            HotkeyManager.scheduleReinstallForHeadPriority()
            self?.recheckPermissions()
        })
        workspaceNotificationObservers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: q) { _ in
            HotkeyManager.scheduleReinstallForHeadPriority()
        })
    }

    deinit {
        for o in appNotificationObservers {
            NotificationCenter.default.removeObserver(o)
        }
        for o in workspaceNotificationObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(o)
        }
        appNotificationObservers.removeAll()
        workspaceNotificationObservers.removeAll()
    }
}
