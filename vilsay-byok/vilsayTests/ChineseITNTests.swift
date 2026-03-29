//
//  ChineseITNTests.swift
//  vilsay — ChineseITN 单元测试
//

import Foundation
import Testing
@testable import vilsay

@Suite("ChineseITN 单元测试")
struct ChineseITNTests {

    // MARK: - 百分比

    @Test("百分比转换")
    func percent() {
        #expect(ChineseITN.normalize("增长了百分之十二") == "增长了12%")
        #expect(ChineseITN.normalize("百分之十二点五") == "12.5%")
        #expect(ChineseITN.normalize("百分之四十三") == "43%")
        #expect(ChineseITN.normalize("百分之一百") == "100%")
    }

    // MARK: - 小数

    @Test("小数转换")
    func decimal() {
        #expect(ChineseITN.normalize("比值是三点二") == "比值是3.2")
        #expect(ChineseITN.normalize("降到二点七") == "降到2.7")
    }

    // MARK: - 整数（带量词）

    @Test("整数 + 量词")
    func integerWithUnit() {
        #expect(ChineseITN.normalize("三千两百万") == "3200万")
        #expect(ChineseITN.normalize("两百八十五块") == "285块")
        #expect(ChineseITN.normalize("一百二十天") == "120天")
        #expect(ChineseITN.normalize("五百毫秒") == "500毫秒")
        #expect(ChineseITN.normalize("十五年") == "15年")
    }

    @Test("不应转换的数字")
    func preservedNumbers() {
        // "第一"不转
        #expect(ChineseITN.normalize("第一个") == "第一个")
        // 单字数字+量词不转（太口语化）
        #expect(ChineseITN.normalize("一个") == "一个")
        #expect(ChineseITN.normalize("两天") == "两天")
        // "一下" 不是数字
        #expect(ChineseITN.normalize("看一下") == "看一下")
    }

    // MARK: - 电话号码 / 连续数字串

    @Test("电话号码（连续单数字）")
    func phoneNumber() {
        #expect(ChineseITN.normalize("电话一三八零六七五四三二一") == "电话13806754321")
    }

    @Test("门牌号（连续单数字）")
    func address() {
        // "八十九" 有十，是正常数字不是序列；"五零二" 是序列
        #expect(ChineseITN.normalize("五零二室") == "502室")
    }

    // MARK: - 日期

    @Test("日期转换")
    func date() {
        #expect(ChineseITN.normalize("二零二六年三月二十七号") == "2026年3月27号")
        #expect(ChineseITN.normalize("二零二六年") == "2026年")
        #expect(ChineseITN.normalize("三月") == "3月")
    }

    // MARK: - 时间

    @Test("时间转换")
    func time() {
        #expect(ChineseITN.normalize("下午三点") == "下午3点")
        #expect(ChineseITN.normalize("十点三十分") == "10点30分")
    }

    // MARK: - 综合场景

    @Test("综合：数据汇报")
    func mixedReport() {
        let input = "上个月的GMV是三千两百万环比增长了百分之十二点五客单价从两百三涨到两百八十五块"
        let output = ChineseITN.normalize(input)
        #expect(output.contains("3200万"))
        #expect(output.contains("12.5%"))
        #expect(output.contains("285"))
    }

    @Test("综合：电话+地址")
    func phoneAndAddress() {
        let input = "电话一三八零六七五四三二一地址是建国路八十九号院三号楼五零二"
        let output = ChineseITN.normalize(input)
        #expect(output.contains("13806754321"))
        #expect(output.contains("502"))
    }

    @Test("不影响非数字文本")
    func passthrough() {
        let input = "把这个bug fix一下然后提PR"
        #expect(ChineseITN.normalize(input) == input)
    }
}
