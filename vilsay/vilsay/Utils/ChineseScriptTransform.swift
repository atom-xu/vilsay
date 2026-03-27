//
//  ChineseScriptTransform.swift
//  ICU transliteration：繁体 ↔ 简体（ASR 输出字形归一）。
//

import CoreFoundation
import Foundation

enum ChineseScriptTransform {
    /// 繁体、异体等 → 大陆规范简体字形。
    static func toSimplified(_ s: String) -> String {
        let m = NSMutableString(string: s)
        CFStringTransform(m, nil, "Traditional-Simplified" as CFString, false)
        return m as String
    }

    /// 简体 → 繁體（台湾/香港常用字形，依系统 ICU 规则）。
    static func toTraditional(_ s: String) -> String {
        let m = NSMutableString(string: s)
        CFStringTransform(m, nil, "Simplified-Traditional" as CFString, false)
        return m as String
    }
}
