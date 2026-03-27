//
//  UserDefaultsKeys.swift
//  vilsay
//

import Foundation

enum UserDefaultsKeys {
    static let onboardingDone = "vilsay.onboarding_done"
    /// 当前引导步骤索引（0…4）；与 `onboarding_done` 独立存储。
    static let onboardingStep = "vilsay.onboarding_step"
    /// ASR 识别语言（简体 / 繁體 / 中英混合 / English）；与 `AppState.asrSpokenLanguage` 同步。
    static let asrSpokenLanguage = "vilsay.asr_spoken_language"
}
