//
//  PermissionManager.swift
//  vilsay
//

import AppKit
import AVFoundation
import os.log

/// 统一的权限检查与管理中心
///
/// 麦克风：与使用 `AVAudioRecorder` / HAL 的路径对齐，**仅**使用 `AVAudioApplication` 查询与请求。
/// 勿与 `AVCaptureDevice.authorizationStatus(for: .audio)` / `requestAccess(for: .audio)` 混用，二者在 macOS 上可能短暂不一致，易误判。
@MainActor
final class PermissionManager {
    static let shared = PermissionManager()
    
    private static let log = Logger(subsystem: "com.vilsay.app", category: "PermissionManager")
    
    private init() {}
    
    // MARK: - 麦克风权限
    
    /// 检查麦克风权限状态（与 `AVAudioApplication.shared.recordPermission` 一致）
    func checkMicrophonePermission() -> PermissionStatus {
        let p = AVAudioApplication.shared.recordPermission
        // 勿用 `String(describing: p)`：在部分系统上会打印成 `rawValue: 1735552628`（FourCC），难读。
        let label: String = {
            switch p {
            case .granted: return "granted"
            case .denied: return "denied"
            case .undetermined: return "undetermined"
            @unknown default: return "unknown"
            }
        }()
        Self.log.info("麦克风权限状态: \(label)")
        
        switch p {
        case .granted:
            return .authorized
        case .denied:
            return .denied
        case .undetermined:
            return .notDetermined
        @unknown default:
            return .denied
        }
    }
    
    /// 请求麦克风权限（异步）；与 `AVAudioApplication.requestRecordPermission` 一致
    func requestMicrophonePermission() async -> Bool {
        let currentStatus = checkMicrophonePermission()
        
        switch currentStatus {
        case .authorized:
            return true
            
        case .notDetermined:
            Self.log.info("请求麦克风权限（AVAudioApplication.requestRecordPermission）...")
            return await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { granted in
                    Task { @MainActor in
                        Self.log.info("麦克风权限请求结果: \(granted)")
                        continuation.resume(returning: granted)
                    }
                }
            }
            
        case .denied:
            return false
        }
    }
    
    /// 显示麦克风权限被拒绝的提示框
    func showMicrophonePermissionAlert() {
        Self.log.warning("显示麦克风权限提示框")
        
        let alert = NSAlert()
        alert.messageText = "需要麦克风权限"
        alert.informativeText = "Vilsay 需要访问麦克风才能进行语音识别。请在系统设置中授予麦克风权限。\n\n录音在本设备处理，音频从不上传。"
        alert.alertStyle = .warning
        alert.icon = NSImage(systemSymbolName: "mic.slash.fill", accessibilityDescription: "麦克风")
        
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "取消")
        
        let response = alert.runModal()
        
        if response == .alertFirstButtonReturn {
            Self.log.info("用户选择打开系统设置")
            openMicrophoneSettings()
        } else {
            Self.log.info("用户取消了权限设置")
        }
    }
    
    /// 打开系统设置的麦克风权限页面（Week 4-P01 设置内深链与 Alert 共用）。
    func openMicrophonePrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }

    private func openMicrophoneSettings() {
        openMicrophonePrivacySettings()
    }
    
    // MARK: - 辅助功能权限
    
    /// 检查辅助功能权限（用于全局热键）
    func checkAccessibilityPermission() -> Bool {
        let trusted = AXIsProcessTrusted()
        Self.log.info("辅助功能权限状态: \(trusted)")
        return trusted
    }
    
    /// 显示辅助功能权限提示框
    func showAccessibilityPermissionAlert() {
        Self.log.warning("显示辅助功能权限提示框")
        
        let alert = NSAlert()
        alert.messageText = "需要辅助功能权限"
        alert.informativeText = "Vilsay 需要辅助功能权限才能使用全局热键。请在系统设置中授予权限。\n\n没有此权限，您仍可以通过菜单栏手动开始录音。"
        alert.alertStyle = .warning
        alert.icon = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "键盘")
        
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "稍后")
        
        let response = alert.runModal()
        
        if response == .alertFirstButtonReturn {
            Self.log.info("用户选择打开辅助功能设置")
            openAccessibilitySettings()
        }
    }
    
    /// 打开系统设置的辅助功能页面（Week 4-P01）。
    func openAccessibilityPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func openAccessibilitySettings() {
        openAccessibilityPrivacySettings()
    }
    
    // MARK: - 综合权限检查
    
    /// 应用启动时检查所有必要权限
    func checkAllPermissionsOnLaunch() {
        Self.log.info("🔍 启动时检查所有权限")
        
        // 检查麦克风权限
        let micStatus = checkMicrophonePermission()
        if micStatus == .denied {
            Self.log.warning("⚠️ 麦克风权限被拒绝")
            // 在主线程延迟显示，避免启动时阻塞
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                self.showMicrophonePermissionAlert()
            }
        } else if micStatus == .notDetermined {
            Self.log.info("ℹ️ 麦克风权限未决定（应该在引导流程中处理）")
        }
        
        // 检查辅助功能权限
        let accessibilityGranted = checkAccessibilityPermission()
        AppState.shared.hotkeyAccessibilityRequired = !accessibilityGranted
        
        if !accessibilityGranted {
            Self.log.warning("⚠️ 辅助功能权限未授予")
        }
    }
    
    /// 在录音前检查麦克风权限（同步检查）
    func ensureMicrophonePermissionForRecording() -> Bool {
        let status = checkMicrophonePermission()
        
        switch status {
        case .authorized:
            return true
            
        case .denied:
            Self.log.error("❌ 录音前检查：麦克风权限被拒绝")
            showMicrophonePermissionAlert()
            return false
            
        case .notDetermined:
            Self.log.warning("⚠️ 录音前检查：麦克风权限未决定")
            // 同步场景下不能异步请求，应该提示用户
            let alert = NSAlert()
            alert.messageText = "需要麦克风权限"
            alert.informativeText = "请先授予 Vilsay 麦克风权限。"
            alert.alertStyle = .informational
            alert.addButton(withTitle: "好的")
            alert.runModal()
            return false
        }
    }
}

// MARK: - 权限状态枚举

enum PermissionStatus {
    case authorized
    case denied
    case notDetermined
}
