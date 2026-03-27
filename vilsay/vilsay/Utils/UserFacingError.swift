//
//  UserFacingError.swift
//  vilsay
//

import Foundation

/// Week 4：主链路与设置诊断的**用户可读**文案（与 `AppState.lastPipelineError` 等配合）。
enum UserFacingError {
    static let audioTooShort = "录音过短，未达到识别所需最小时长，已忽略。"
    static let asrEmpty = "语音识别未返回有效文字，请重试或检查麦克风。"
    static let cloudNeedsNetwork = "当前无网络，云端识别不可用；已尝试使用本地识别。"
    static let quotaExceeded = "本月润色次数已达上限，请稍后再试或升级套餐。"
}
