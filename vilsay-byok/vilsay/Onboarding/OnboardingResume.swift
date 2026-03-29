//
//  OnboardingResume.swift
//  W7-A01：断点续传步骤解析（权限以运行时为准）
//

import ApplicationServices
import AVFoundation
import Foundation

/// 根据持久化的 `onboarding_step` 与当前系统权限，计算应展示的步骤索引。
/// 步骤：0 欢迎 → 1 麦克风 → 2 辅助功能 → 3 登录 → 4 完成
enum OnboardingResume {
    /// 使用当前进程的麦克风 / 辅助功能状态。
    static func resolveStartStep(fromSaved saved: Int) -> Int {
        let micGranted = AVAudioApplication.shared.recordPermission == .granted
        let axTrusted = AXIsProcessTrusted()
        return resolveStartStep(fromSaved: saved, micGranted: micGranted, axTrusted: axTrusted)
    }

    /// 可单测注入的纯逻辑。
    static func resolveStartStep(fromSaved saved: Int, micGranted: Bool, axTrusted: Bool) -> Int {
        if saved <= 0 { return 0 }
        if !micGranted { return 1 }
        if !axTrusted { return 2 }
        if saved >= 4 { return 4 }
        if saved >= 3 { return 3 }
        return 3
    }
}
