//
//  SoundFeedback.swift
//

import AppKit
import AudioToolbox

/// 沙盒下优先 `AudioServicesPlaySystemSound`（系统级，不依赖命名音效资源）。
///
/// MainActor 竞态（Step 2）：调用方须在 `Task { @MainActor in … }` 中调用本类型方法，避免与 HAL 调用栈同帧执行。
@MainActor
enum SoundFeedback {
    /// 录音开始（与历史「Tink」类提示接近的系统声）
    private static let systemSoundRecordingStart: SystemSoundID = 1104
    /// 录音结束
    private static let systemSoundRecordingEnd: SystemSoundID = 1103
    /// 注入完成（短提示）
    private static let systemSoundInjectionDone: SystemSoundID = 1105

    static func recordingStart() {
        guard !DiagnosticsExclusion.excludeSystemSound else { return }
        guard AppState.shared.soundFeedbackEnabled else { return }
        AudioServicesPlaySystemSound(systemSoundRecordingStart)
    }

    static func recordingEnd() {
        guard !DiagnosticsExclusion.excludeSystemSound else { return }
        guard AppState.shared.soundFeedbackEnabled else { return }
        AudioServicesPlaySystemSound(systemSoundRecordingEnd)
    }

    static func injectionDone() {
        guard !DiagnosticsExclusion.excludeSystemSound else { return }
        guard AppState.shared.soundFeedbackEnabled else { return }
        AudioServicesPlaySystemSound(systemSoundInjectionDone)
    }
}
