//
//  PinyinHelperTests.swift
//  TEST-03
//

import Testing
@testable import vilsay

struct PinyinHelperTests {

    @Test func chinese_basic() {
        let result = PinyinHelper.toPinyin("事业")
        #expect(result.lowercased().contains("shi"))
        #expect(result.lowercased().contains("ye"))
    }

    @Test func chinese_name() {
        let result = PinyinHelper.toPinyin("张思远")
        #expect(result.lowercased().contains("zhang"))
        #expect(result.lowercased().contains("si"))
        #expect(result.lowercased().contains("yuan"))
    }

    @Test func english_passthrough() {
        let result = PinyinHelper.toPinyin("API")
        #expect(result.contains("API") || result.contains("api"))
    }

    @Test func mixed_chinese_english() {
        let result = PinyinHelper.toPinyin("API接口")
        #expect(result.lowercased().contains("jie"))
        #expect(result.lowercased().contains("kou"))
    }

    @Test func empty_string() {
        let result = PinyinHelper.toPinyin("")
        #expect(result.isEmpty)
    }
}
