//
//  HotkeyServiceManager.swift
//  管理独立热键监听进程（参考 VoiceInk globeKeyManager.js）
//

import Foundation
import os.log

/// 🔑 VoiceInk 风格的热键服务管理器
/// 负责启动/重启独立监听进程，处理崩溃恢复
@MainActor
final class HotkeyServiceManager {
    static let shared = HotkeyServiceManager()
    
    private static let svcLog = Logger(subsystem: "com.vilsay.app", category: "HotkeyService")
    
    private var process: Process?
    private var restartCount = 0
    private let maxRestarts = 3  // VoiceInk 同样限制 3 次
    
    /// 服务状态回调
    var onStatusChange: ((ServiceStatus) -> Void)?
    
    enum ServiceStatus {
        case ready
        case error(String)
        case crashed(attempts: Int)
    }
    
    private init() {}
    
    // MARK: - 生命周期
    
    func start() {
        Self.svcLog.info("🚀 启动热键监听服务")
        
        guard let binaryPath = locateListenerBinary() else {
            Self.svcLog.error("❌ 找不到 HotkeyListenerService 二进制文件")
            onStatusChange?(.error("监听服务不可用"))
            return
        }
        
        launchProcess(at: binaryPath)
    }
    
    func stop() {
        Self.svcLog.info("🛑 停止热键监听服务")
        process?.terminate()
        process = nil
        restartCount = 0
    }
    
    // MARK: - 进程管理
    
    private func launchProcess(at path: String) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)
        
        // 捕获 stdout（接收热键事件）
        let pipe = Pipe()
        proc.standardOutput = pipe
        
        // 监听输出
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            guard let self else { return }
            let data = handle.availableData
            guard !data.isEmpty else { return }

            if let line = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                Task { @MainActor [self] in
                    self.handleServiceOutput(line)
                }
            }
        }

        // 监听进程终止（VoiceInk 的自动重启逻辑）
        proc.terminationHandler = { [weak self] proc in
            guard let self else { return }
            let exitCode = proc.terminationStatus
            Task { @MainActor [self] in
                self.handleProcessTermination(exitCode: exitCode)
            }
        }
        
        do {
            try proc.run()
            process = proc
            Self.svcLog.info("✅ 监听进程已启动 - PID: \(proc.processIdentifier)")
        } catch {
            Self.svcLog.error("❌ 进程启动失败: \(error.localizedDescription)")
            onStatusChange?(.error("启动失败"))
        }
    }
    
    private func handleProcessTermination(exitCode: Int32) {
        Self.svcLog.warning("⚠️ 监听进程终止 - exitCode: \(exitCode), restartCount: \(self.restartCount)")
        
        // 检查是否是正常退出
        guard exitCode != 0 else {
            Self.svcLog.info("进程正常退出")
            return
        }
        
        // VoiceInk 风格的重启限制
        guard restartCount < maxRestarts else {
            Self.svcLog.error("❌ 达到最大重启次数 (\(self.maxRestarts))，停止重试")
            onStatusChange?(.error("监听服务崩溃"))
            return
        }
        
        restartCount += 1
        onStatusChange?(.crashed(attempts: restartCount))
        
        Self.svcLog.info("🔄 尝试重启监听服务 (\(self.restartCount)/\(self.maxRestarts))")
        
        // 延迟重启（避免快速循环崩溃）
        Task {
            try? await Task.sleep(for: .seconds(1))
            
            guard let path = locateListenerBinary() else { return }
            launchProcess(at: path)
        }
    }
    
    // MARK: - 事件处理
    
    private func handleServiceOutput(_ line: String) {
        Self.svcLog.debug("📥 收到服务输出: \(line)")
        
        switch line {
        case "READY":
            Self.svcLog.info("✅ 监听服务就绪")
            restartCount = 0  // 成功启动后重置计数
            onStatusChange?(.ready)
            
        case "ERROR:NO_ACCESSIBILITY":
            Self.svcLog.error("❌ 服务报告：无辅助功能权限")
            AppState.shared.hotkeyAccessibilityRequired = true
            
        case "FN_DOWN":
            handleHotkeyEvent(key: .function, pressed: true)
            
        case "FN_UP":
            handleHotkeyEvent(key: .function, pressed: false)
            
        case "RIGHT_OPTION_DOWN":
            handleHotkeyEvent(key: .rightOption, pressed: true)
            
        case "RIGHT_OPTION_UP":
            handleHotkeyEvent(key: .rightOption, pressed: false)
            
        default:
            Self.svcLog.debug("未知输出: \(line)")
        }
    }
    
    private enum HotkeyType {
        case function
        case rightOption
    }
    
    private func handleHotkeyEvent(key: HotkeyType, pressed: Bool) {
        let bindingMode = AppConfig.hotkeyBindingMode
        let triggerMode = AppConfig.triggerMode
        
        // 检查键位是否匹配当前绑定模式
        switch (key, bindingMode) {
        case (.function, .fnGlobe),
             (.rightOption, .builtinRightOption):
            break  // 匹配
        default:
            return  // 不匹配，忽略
        }
        
        Self.svcLog.info("🎹 热键事件: \(String(describing: key)), pressed: \(pressed), mode: \(triggerMode.rawValue)")
        
        // 应用触发模式
        switch triggerMode {
        case .push:
            if pressed {
                Pipeline.shared.onHotkeyPushDown()
            } else {
                Task { await Pipeline.shared.onHotkeyPushUp() }
            }
        case .toggle:
            if pressed {
                Task { await Pipeline.shared.onHotkeyToggle() }
            }
        }
    }
    
    // MARK: - 二进制查找
    
    private func locateListenerBinary() -> String? {
        // 尝试查找二进制文件的可能位置
        let possiblePaths = [
            // 开发环境
            Bundle.main.bundleURL
                .deletingLastPathComponent()
                .appendingPathComponent("HotkeyListenerService")
                .path(percentEncoded: false),
            
            // 生产环境（打包在 App Bundle 中）
            Bundle.main.path(forResource: "HotkeyListenerService", ofType: nil),
            
            // XPC Service
            Bundle.main.bundleURL
                .appendingPathComponent("Contents/XPCServices/HotkeyListenerService.xpc/Contents/MacOS/HotkeyListenerService")
                .path(percentEncoded: false)
        ].compactMap { $0 }
        
        for path in possiblePaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                Self.svcLog.info("✅ 找到监听服务: \(path)")
                return path
            }
        }
        
        Self.svcLog.error("❌ 未找到监听服务二进制文件")
        return nil
    }
}
