//
//  ChineseITN.swift
//  vilsay — 中文 Inverse Text Normalization（纯 Swift，零依赖）
//
//  将 ASR 输出中的口语化数字、日期、百分比等转为书面格式。
//  确定性转换不依赖 LLM，规则保证准确。
//

import Foundation

enum ChineseITN {

    // MARK: - Public API

    /// 对 ASR 文本执行 ITN 标准化。
    /// 规则顺序：百分比 → 小数 → 连续数字串（电话/门牌）→ 整数 → 日期/时间
    static func normalize(_ text: String) -> String {
        var s = text
        s = normalizePercent(s)
        s = normalizeDecimal(s)
        s = normalizeDigitSequence(s)
        s = normalizeInteger(s)
        s = normalizeDate(s)
        s = normalizeTime(s)
        return s
    }

    // MARK: - 数字映射

    private static let digitMap: [Character: Int] = [
        "零": 0, "〇": 0, "一": 1, "二": 2, "两": 2, "三": 3,
        "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9,
    ]

    private static let unitMap: [Character: Int] = [
        "十": 10, "百": 100, "千": 1000, "万": 10000, "亿": 100000000,
    ]

    // MARK: - 百分比：百分之X → X%

    private static func normalizePercent(_ text: String) -> String {
        // 匹配"百分之"后跟中文数字（含小数点）
        let pattern = "百分之([零〇一二两三四五六七八九十百千万点\\.]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        var result = text
        let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))
        for match in matches.reversed() {
            guard let numRange = Range(match.range(at: 1), in: result),
                  let fullRange = Range(match.range, in: result) else { continue }
            let numStr = String(result[numRange])
            if let value = parseChineseNumber(numStr) {
                let formatted = formatNumber(value)
                result.replaceSubrange(fullRange, with: "\(formatted)%")
            }
        }
        return result
    }

    // MARK: - 小数：X点Y → X.Y

    private static func normalizeDecimal(_ text: String) -> String {
        // 负向前瞻：小数部分后不能跟十百千万（否则是时间如"十点三十分"）
        let pattern = "([零〇一二两三四五六七八九十百千万]+)点([零〇一二两三四五六七八九]+)(?![十百千万])"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        var result = text
        let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))
        for match in matches.reversed() {
            guard let intRange = Range(match.range(at: 1), in: result),
                  let decRange = Range(match.range(at: 2), in: result),
                  let fullRange = Range(match.range, in: result) else { continue }
            let intPart = String(result[intRange])
            let decPart = String(result[decRange])
            if let intVal = parseChineseNumber(intPart) {
                let decDigits = decPart.compactMap { digitMap[$0] }.map(String.init).joined()
                if !decDigits.isEmpty {
                    let formatted = formatNumber(intVal)
                    result.replaceSubrange(fullRange, with: "\(formatted).\(decDigits)")
                }
            }
        }
        return result
    }

    // MARK: - 连续数字串（电话号码、门牌号）

    /// 检测连续单个中文数字（如「一三八零六七五四三二一」→「13806754321」）
    /// 触发条件：连续 5 个以上单位数字（无十百千万等量词）
    private static func normalizeDigitSequence(_ text: String) -> String {
        let singleDigits: Set<Character> = ["零", "〇", "一", "二", "两", "三", "四", "五", "六", "七", "八", "九"]
        var result = ""
        var buffer: [Character] = []

        func flushBuffer() {
            // 含零/〇的短序列（如"五零二"）是门牌/编号，阈值降为 3
            let hasZero = buffer.contains("零") || buffer.contains("〇")
            let threshold = hasZero ? 3 : 5
            if buffer.count >= threshold {
                let digits = buffer.compactMap { digitMap[$0] }.map(String.init).joined()
                result += digits
            } else {
                result += String(buffer)
            }
            buffer.removeAll()
        }

        for char in text {
            if singleDigits.contains(char) {
                buffer.append(char)
            } else {
                if !buffer.isEmpty {
                    // 遇到量词（十百千万）说明是正常数字，不是序列
                    if unitMap[char] != nil {
                        result += String(buffer)
                        buffer.removeAll()
                        result.append(char)
                    } else {
                        flushBuffer()
                        result.append(char)
                    }
                } else {
                    result.append(char)
                }
            }
        }
        flushBuffer()
        return result
    }

    // MARK: - 整数：中文数字 → 阿拉伯数字

    /// 匹配"中文数字+量词/单位"模式，只转换有明确数量含义的
    private static func normalizeInteger(_ text: String) -> String {
        // 匹配"中文数字词组"后跟量词/单位（万/亿/块/元/个/条/天/月/年/次/人/台/套...）
        // 或者"中文数字词组"前有"第"字不转换
        let numPattern = "[零〇一二两三四五六七八九十百千万亿]+"
        let unitSuffix = "[万亿块元角分个条天月日年次人台套件份期号层楼米公里千米厘米毫秒秒分钟小时]"
        let pattern = "(?<!第)(\(numPattern))(?=\(unitSuffix))"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        var result = text
        let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))
        for match in matches.reversed() {
            guard let range = Range(match.range(at: 1), in: result) else { continue }
            let numStr = String(result[range])
            // 跳过单字（"一个"、"两天"太口语化，不转）
            if numStr.count <= 1 { continue }
            if let value = parseChineseNumber(numStr) {
                let formatted = formatNumber(value)
                result.replaceSubrange(range, with: formatted)
            }
        }
        return result
    }

    // MARK: - 日期：X年X月X号/日

    private static func normalizeDate(_ text: String) -> String {
        // "二零二六年" → "2026年"
        let yearPattern = "([零〇一二三四五六七八九]{4})年"
        if let regex = try? NSRegularExpression(pattern: yearPattern) {
            var result = text
            let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))
            for match in matches.reversed() {
                guard let numRange = Range(match.range(at: 1), in: result),
                      let fullRange = Range(match.range, in: result) else { continue }
                let digits = String(result[numRange]).compactMap { digitMap[$0] }.map(String.init).joined()
                if digits.count == 4 {
                    result.replaceSubrange(fullRange, with: "\(digits)年")
                }
            }
            // "X月" / "X号" / "X日"
            let mdPattern = "([一二三四五六七八九十]+)([月号日])"
            if let mdRegex = try? NSRegularExpression(pattern: mdPattern) {
                let mdMatches = mdRegex.matches(in: result, range: NSRange(result.startIndex..., in: result))
                for match in mdMatches.reversed() {
                    guard let numRange = Range(match.range(at: 1), in: result),
                          let suffixRange = Range(match.range(at: 2), in: result),
                          let fullRange = Range(match.range, in: result) else { continue }
                    let numStr = String(result[numRange])
                    let suffix = String(result[suffixRange])
                    if let value = parseChineseNumber(numStr), value >= 1, value <= 31 {
                        result.replaceSubrange(fullRange, with: "\(Int(value))\(suffix)")
                    }
                }
            }
            return result
        }
        return text
    }

    // MARK: - 时间：X点X分

    private static func normalizeTime(_ text: String) -> String {
        let pattern = "([一二三四五六七八九十两]+)点(?:([一二三四五六七八九十两零〇]+)分?)?"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        var result = text
        let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))
        for match in matches.reversed() {
            guard let hourRange = Range(match.range(at: 1), in: result),
                  let fullRange = Range(match.range, in: result) else { continue }
            let hourStr = String(result[hourRange])
            guard let hour = parseChineseNumber(hourStr), hour >= 1, hour <= 24 else { continue }
            // 检查后面有没有分钟
            if match.numberOfRanges > 2, let minRange = Range(match.range(at: 2), in: result) {
                let minStr = String(result[minRange])
                if let min = parseChineseNumber(minStr) {
                    result.replaceSubrange(fullRange, with: "\(Int(hour))点\(Int(min))分")
                }
            } else {
                result.replaceSubrange(fullRange, with: "\(Int(hour))点")
            }
        }
        return result
    }

    // MARK: - 中文数字解析核心

    /// 解析中文数字为 Double。支持：一百二十三、三千两百万、十二点五。
    static func parseChineseNumber(_ text: String) -> Double? {
        let chars = Array(text)
        if chars.isEmpty { return nil }

        // 如果含"点"，分整数和小数两部分处理
        if let dotIndex = chars.firstIndex(of: "点") {
            let intPart = String(chars[chars.startIndex..<dotIndex])
            let decPart = chars[(chars.index(after: dotIndex))...]
            let intVal = intPart.isEmpty ? 0.0 : (parseChineseNumber(intPart) ?? 0.0)
            let decDigits = decPart.compactMap { digitMap[$0] }
            if decDigits.isEmpty { return intVal > 0 ? intVal : nil }
            var decVal = 0.0
            for (i, d) in decDigits.enumerated() {
                decVal += Double(d) / pow(10.0, Double(i + 1))
            }
            let result = intVal + decVal
            return result > 0 ? result : nil
        }

        var total: Double = 0
        var current: Double = 0
        var yiPart: Double = 0  // 亿以上部分

        for char in chars {
            if let d = digitMap[char] {
                current = Double(d)
            } else if let u = unitMap[char] {
                if u == 100000000 { // 亿
                    if current == 0 && total == 0 { return nil }
                    yiPart = (total + current) * Double(u)
                    total = 0
                    current = 0
                } else if u == 10000 { // 万
                    total = (total + current) * Double(u)
                    current = 0
                } else {
                    if current == 0 && u == 10 {
                        // "十二" = 12（十开头省略一）
                        current = 1
                    }
                    total += current * Double(u)
                    current = 0
                }
            }
        }
        total += current + yiPart

        return total > 0 ? total : nil
    }

    /// 格式化数字：整数不带小数点，小数保留必要精度。
    private static func formatNumber(_ value: Double) -> String {
        if value == value.rounded(.towardZero) && value < 1e15 {
            return String(Int(value))
        } else {
            // 去掉尾部多余的 0
            let s = String(format: "%.10f", value)
            var trimmed = s
            while trimmed.hasSuffix("0") { trimmed.removeLast() }
            if trimmed.hasSuffix(".") { trimmed.removeLast() }
            return trimmed
        }
    }
}
