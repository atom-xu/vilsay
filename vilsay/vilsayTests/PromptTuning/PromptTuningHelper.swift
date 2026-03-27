import Foundation
@testable import vilsay

/// Prompt 调优测试公共辅助
enum PromptTuningHelper {

    /// 环境变量 `DASHSCOPE_API_KEY` > `AppConfig.dashscopeAPIKey`（UserDefaults 兜底）；都无则 nil → 调用方 `guard` 跳过。
    static var apiKey: String? {
        let k = ProcessInfo.processInfo.environment["DASHSCOPE_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !k.isEmpty { return k }
        return AppConfig.dashscopeAPIKey
    }

    /// 构造 system prompt 并调用 polishPlain，返回润色结果
    static func polish(
        asrText: String,
        profile: UserProfile? = nil,
        appBundleID: String? = nil,
        asrConfidence: Double? = nil
    ) async -> String {
        let system = PromptComposer.systemPrompt(
            for: profile,
            targetAppBundleID: appBundleID,
            asrConfidence: asrConfidence
        )
        let user = Prompts.polishUserMessage(asrText: asrText)
        return await PolishService.polishPlain(system: system, user: user)
    }

    /// 标准日志输出
    static func log(_ id: String, input: String, output: String) {
        print("[\(id)] input=\"\(input)\" → output=\"\(output)\"")
    }

    // MARK: - 常用 Profile 工厂

    /// 空画像
    static let emptyProfile = UserProfile()

    /// 程序员画像（技术术语多）
    static let devProfile = UserProfile(
        habitualWords: [
            HabitualWord(word: "其实", action: "保留", confidence: 0.8),
            HabitualWord(word: "我觉得", action: "保留", confidence: 0.7),
        ],
        thinkingStyle: ThinkingStyle(
            expand: "逻辑递进型，先说结论再展开",
            topicSwitchSignals: ["然后", "另外"],
            closeSignals: ["就这样"],
            confidence: 0.8
        ),
        tone: ToneProfile(
            overall: "偏技术风格，简洁直接",
            sentenceLength: "中等偏短",
            mixedLang: "中英混用频繁",
            confidence: 0.7
        ),
        dictionaryItems: [
            DictionaryItem(type: "专有", word: "Kubernetes", pinyin: "ku bo nei ti si"),
            DictionaryItem(type: "专有", word: "Docker", pinyin: "duo ke"),
            DictionaryItem(type: "专有", word: "CI/CD", pinyin: "si ai si di"),
            DictionaryItem(type: "用语", word: "部署"),
            DictionaryItem(type: "用语", word: "回滚"),
        ]
    )

    /// 商务人士画像
    static let bizProfile = UserProfile(
        habitualWords: [
            HabitualWord(word: "赋能", action: "保留", confidence: 0.9),
            HabitualWord(word: "抓手", action: "保留", confidence: 0.8),
            HabitualWord(word: "对齐", action: "保留", confidence: 0.85),
        ],
        thinkingStyle: ThinkingStyle(
            expand: "总分总结构，先说目标再列行动项",
            topicSwitchSignals: ["第二个", "接下来"],
            closeSignals: ["以上"],
            confidence: 0.8
        ),
        tone: ToneProfile(
            overall: "正式商务风格",
            sentenceLength: "中等偏长",
            mixedLang: "少量英文缩写",
            confidence: 0.85
        ),
        dictionaryItems: [
            DictionaryItem(type: "专有", word: "OKR", pinyin: "ou kei a"),
            DictionaryItem(type: "专有", word: "ROI", pinyin: "a ou ai"),
            DictionaryItem(type: "用语", word: "闭环"),
            DictionaryItem(type: "用语", word: "颗粒度"),
        ]
    )

    /// 学生画像（口语化）
    static let studentProfile = UserProfile(
        habitualWords: [
            HabitualWord(word: "然后", action: "保留", confidence: 0.6),
            HabitualWord(word: "就是说", action: "保留", confidence: 0.5),
        ],
        tone: ToneProfile(
            overall: "随意口语化",
            sentenceLength: "偏短",
            mixedLang: "偶尔英文单词",
            confidence: 0.6
        ),
        dictionaryItems: []
    )

    /// 医学专业画像
    static let medProfile = UserProfile(
        habitualWords: [],
        thinkingStyle: nil,
        tone: ToneProfile(
            overall: "严谨专业",
            sentenceLength: "中等",
            mixedLang: "医学术语中英混用",
            confidence: 0.8
        ),
        dictionaryItems: [
            DictionaryItem(type: "专有", word: "阿莫西林", pinyin: "a mo xi lin"),
            DictionaryItem(type: "专有", word: "布洛芬", pinyin: "bu luo fen"),
            DictionaryItem(type: "专有", word: "CT", pinyin: "xi ti"),
            DictionaryItem(type: "专有", word: "核磁共振", pinyin: "he ci gong zhen"),
            DictionaryItem(type: "用语", word: "主诉"),
            DictionaryItem(type: "用语", word: "既往史"),
        ]
    )

    /// 纯拼音纠偏画像（大量同音易错词）
    static let pinyinHeavyProfile = UserProfile(
        dictionaryItems: [
            DictionaryItem(type: "专有", word: "Vilsay", pinyin: "wei er sei"),
            DictionaryItem(type: "专有", word: "百炼", pinyin: "bai lian"),
            DictionaryItem(type: "专有", word: "通义千问", pinyin: "tong yi qian wen"),
            DictionaryItem(type: "专有", word: "魏则西", pinyin: "wei ze xi"),
            DictionaryItem(type: "用语", word: "权益", pinyin: "quan yi"),
            DictionaryItem(type: "用语", word: "全域", pinyin: "quan yu"),
        ]
    )
}
