//
//  UserProfile.swift
//

import Foundation

// MARK: - §1 结构化画像（由 `ProfileService` 从 SQLite 组装）

struct HabitualWord: Equatable, Sendable {
    var word: String
    var action: String
    var confidence: Double
}

struct ThinkingStyle: Equatable, Sendable {
    var expand: String
    var topicSwitchSignals: [String]
    var closeSignals: [String]
    var confidence: Double
}

struct ToneProfile: Equatable, Sendable {
    var overall: String
    var sentenceLength: String
    var mixedLang: String
    var confidence: Double
}

struct DictionaryItem: Equatable, Sendable {
    /// 展示用：`用语` / `专有` 等
    var type: String
    var word: String
    /// V14：无声调拼音，§1.P 同音纠偏用。
    var pinyin: String?
}

/// 用户画像（§1.1～§1.4）；**不要**直接拼进 `Prompts.swift`，须经 `PromptComposer`。
struct UserProfile: Equatable, Sendable {
    var habitualWords: [HabitualWord] = []
    var thinkingStyle: ThinkingStyle?
    var tone: ToneProfile?
    var dictionaryItems: [DictionaryItem] = []

    var isEmpty: Bool {
        habitualWords.isEmpty && thinkingStyle == nil && tone == nil && dictionaryItems.isEmpty
    }
}
