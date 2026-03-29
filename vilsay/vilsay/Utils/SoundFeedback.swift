//
//  SoundFeedback.swift
//

import AppKit

/// macOS 系统音效反馈。使用 `NSSound` 播放 `/System/Library/Sounds/` 下的音效。
///
/// MainActor 竞态（Step 2）：调用方须在 `Task { @MainActor in … }` 中调用本类型方法，避免与 HAL 调用栈同帧执行。
@MainActor
enum SoundFeedback {
    static func recordingStart() {
        play("Bottle")
    }

    static func recordingEnd() {
        play("Morse")
    }

    static func injectionDone() {
        play("Purr")
    }

    private static func play(_ name: String) {
        guard !DiagnosticsExclusion.excludeSystemSound else { return }
        guard AppState.shared.soundFeedbackEnabled else { return }
        NSSound(named: NSSound.Name(name))?.play()
    }
}
