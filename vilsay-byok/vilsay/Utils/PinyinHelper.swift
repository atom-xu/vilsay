//
//  PinyinHelper.swift
//  V14-03：无声调拼音，词典同音纠偏用。
//

import CoreFoundation
import Foundation

enum PinyinHelper {
    /// 将中文转为无声调拼音，空格分隔。非中文字符保留原文。
    /// 示例："事业" → "shi ye"，"API接口" → "API jie kou"
    static func toPinyin(_ text: String) -> String {
        let mutable = NSMutableString(string: text) as CFMutableString
        CFStringTransform(mutable, nil, kCFStringTransformMandarinLatin, false)
        CFStringTransform(mutable, nil, kCFStringTransformStripDiacritics, false)
        return (mutable as String)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
