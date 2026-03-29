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

// MARK: - 语言人格（Social Style Model, Merrill-Reid 1960s）

/// 双轴量化维度，EWMA 累积。
struct StyleDimensions: Equatable, Sendable, Codable {
    /// 表达温度：0 = 理性克制，1 = 感性丰富（Responsiveness 轴）
    var warmth: Double
    /// 沟通节奏：0 = 详尽铺垫，1 = 精炼直接（Assertiveness 轴）
    var directness: Double
    /// EWMA 累积置信度
    var confidence: Double
    /// 累计分析样本数
    var sampleCount: Int

    /// 四象限人格归类。
    var archetype: SpeechArchetype {
        switch (warmth >= 0.5, directness >= 0.5) {
        case (false, true):  return .executor
        case (true,  true):  return .inspirer
        case (false, false): return .analyst
        case (true,  false): return .narrator
        }
    }
}

/// 四象限语言人格（基于 Social Style Model）。
enum SpeechArchetype: String, Codable, Sendable {
    case executor  // 执行者：理性 + 直接
    case inspirer  // 感染者：感性 + 直接
    case analyst   // 分析师：理性 + 详尽
    case narrator  // 讲述者：感性 + 详尽

    var label: String {
        switch self {
        case .executor: return "执行者"
        case .inspirer: return "感染者"
        case .analyst:  return "分析师"
        case .narrator: return "讲述者"
        }
    }

    var englishLabel: String {
        switch self {
        case .executor: return "Executor"
        case .inspirer: return "Inspirer"
        case .analyst:  return "Analyst"
        case .narrator: return "Narrator"
        }
    }

    var tagline: String {
        switch self {
        case .executor: return "精准高效，直击要点。你说话像写代码——零废话。"
        case .inspirer: return "热情有力，感染力强。你的表达自带说服力。"
        case .analyst:  return "严谨周密，逻辑清晰。每句话都有据可依。"
        case .narrator: return "温暖细腻，善于讲述。你用故事传递观点。"
        }
    }

    var icon: String {
        switch self {
        case .executor: return "bolt.fill"
        case .inspirer: return "flame.fill"
        case .analyst:  return "square.grid.3x3.topleft.filled"
        case .narrator: return "book.fill"
        }
    }
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
