//
//  HotkeyHealthChecker.swift
//

import Foundation
import os.log

/// 启动时自检 + 持续健康监控（参考 VoiceInk 的自动重启机制）。
@MainActor
final class HotkeyHealthChecker {
    static let shared = HotkeyHealthChecker()
    
    private static let log = Logger(subsystem: "com.vilsay.app", category: "HotkeyHealth")

    enum HealthStatus: Equatable {
        case healthy
        case degraded
        case unavailable
    }

    struct HealthReport: Equatable {
        let status: HealthStatus
        let canUseEventTap: Bool
        let canUseFnKey: Bool
        let canUseRightOption: Bool
        let issues: [String]
        let suggestions: [String]
    }
    
    // VoiceInk 风格的持续监控
    private var monitoringTask: Task<Void, Never>?
    private let checkInterval: TimeInterval = 10.0  // 每 10 秒检查一次

    private init() {}
    
    // MARK: - 启动检查

    func performStartupCheck() -> HealthReport {
        let canUseEventTap = HotkeyManager.isEventTapInstalled
        let canUseFnKey = true  // ✅ Fn 键所有 Mac 都有，不需要检测硬件
        let canUseRightOption = true

        var issues: [String] = []
        var suggestions: [String] = []

        if !canUseEventTap {
            issues.append("热键监听未安装")
            suggestions.append("请重启应用或检查权限")
        }

        // ✅ 移除硬件检测的警告，因为所有 Mac 都有 Fn 键
        let status: HealthStatus = canUseEventTap ? .healthy : .unavailable
        
        return HealthReport(
            status: status,
            canUseEventTap: canUseEventTap,
            canUseFnKey: canUseFnKey,
            canUseRightOption: canUseRightOption,
            issues: issues,
            suggestions: suggestions
        )
    }

    private func determineStatus(canUseEventTap: Bool, canUseFnKey: Bool) -> HealthStatus {
        if !canUseEventTap { return .unavailable }
        return .healthy  // ✅ Fn 键不影响状态
    }
    
    // MARK: - VoiceInk 风格的持续监控
    
    /// 启动持续健康监控（类似 VoiceInk 的进程监听）
    func startContinuousMonitoring() {
        stopContinuousMonitoring()

        if DiagnosticsExclusion.excludeHotkeyHealthMonitor {
            Self.log.warning("🧪 VILSAY_EXCLUDE_HOTKEY_HEALTH=1：不启动定时健康监控")
            return
        }

        Self.log.info("🔍 启动热键健康监控")
        
        monitoringTask = Task { @MainActor in
            while !Task.isCancelled {
                // 每隔一段时间检查 EventTap 状态
                try? await Task.sleep(for: .seconds(checkInterval))
                
                guard !Task.isCancelled else { break }
                
                // 执行健康检查
                HotkeyManager.checkHealth()
            }
        }
    }
    
    func stopContinuousMonitoring() {
        monitoringTask?.cancel()
        monitoringTask = nil
        Self.log.info("🛑 停止热键健康监控")
    }
}
