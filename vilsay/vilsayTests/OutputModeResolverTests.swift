//
//  OutputModeResolverTests.swift
//  PM-01：与 Config/OutputMode.swift 中 modeMap 一致；覆盖 UserDefaults 优先。
//

import Foundation
import Testing
@testable import vilsay

struct OutputModeResolverTests {

    /// 须与 `OutputModeResolver` 内 `modeMap` 逐项一致（任务书 PM-01 验收）。
    private static let expectedMap: [String: OutputMode] = [
        // AI 对话暂不自动激活（已注释）
        "com.tencent.xinWeChat": .chat,
        "com.apple.MobileSMS": .chat,
        "com.tencent.qq": .chat,
        "com.slack.Slack": .chat,
        "com.electron.lark": .chat,
        "com.alibaba.DingTalkMac": .chat,
        "ru.keepcoder.Telegram": .chat,
        "com.apple.mail": .email,
        "com.tencent.foxmail": .email,
        "com.microsoft.Outlook": .email,
        "com.microsoft.Word": .document,
        "com.apple.Pages": .document,
        "com.notion.id": .document,
        "md.obsidian": .document,
        "com.apple.Notes": .note,
        "net.shinyfrog.bear": .note,
    ]

    @Test func knownBundleIDs_matchesExpectedMapCount() {
        let sortedKeys = OutputModeResolver.knownBundleIDs
        #expect(sortedKeys.count == Self.expectedMap.count)
        #expect(Set(sortedKeys) == Set(Self.expectedMap.keys))
    }

    @Test func resolve_eachKnownBundle_returnsMappedMode() {
        // 清除所有可能残留的 UserDefaults override（并行测试隔离）
        for bid in Self.expectedMap.keys {
            OutputModeResolver.setUserOverride(bundleID: bid, mode: nil)
        }
        for (bid, mode) in Self.expectedMap {
            #expect(OutputModeResolver.resolve(bundleID: bid) == mode)
        }
    }

    @Test func resolve_nilOrEmpty_returnsGeneral() {
        #expect(OutputModeResolver.resolve(bundleID: nil) == .general)
        #expect(OutputModeResolver.resolve(bundleID: "") == .general)
    }

    @Test func resolve_unknown_returnsGeneral() {
        #expect(OutputModeResolver.resolve(bundleID: "com.example.not.in.map") == .general)
    }

    @Test func userOverride_takesPrecedence() {
        // 使用测试专用 bundleID，避免并行测试中污染 modeMap 中的真实 bundleID
        let bid = "com.vilsay.unit.test.override.precedence"
        let key = "vilsay.output_mode_override." + bid
        let previous = UserDefaults.standard.object(forKey: key)
        defer {
            if let previous {
                UserDefaults.standard.set(previous, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }

        UserDefaults.standard.removeObject(forKey: key)
        #expect(OutputModeResolver.resolve(bundleID: bid) == .general)

        OutputModeResolver.setUserOverride(bundleID: bid, mode: .document)
        #expect(OutputModeResolver.resolve(bundleID: bid) == .document)
        #expect(OutputModeResolver.userOverride(for: bid) == .document)

        OutputModeResolver.setUserOverride(bundleID: bid, mode: nil)
        #expect(OutputModeResolver.userOverride(for: bid) == nil)
        #expect(OutputModeResolver.resolve(bundleID: bid) == .general)
    }

    @Test func userOverride_unknownBundle_stillApplies() {
        let bid = "com.vilsay.unit.test.unknown"
        let key = "vilsay.output_mode_override." + bid
        let previous = UserDefaults.standard.object(forKey: key)
        defer {
            if let previous {
                UserDefaults.standard.set(previous, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }

        UserDefaults.standard.removeObject(forKey: key)
        #expect(OutputModeResolver.resolve(bundleID: bid) == .general)

        OutputModeResolver.setUserOverride(bundleID: bid, mode: .email)
        #expect(OutputModeResolver.resolve(bundleID: bid) == .email)

        OutputModeResolver.setUserOverride(bundleID: bid, mode: nil)
        #expect(OutputModeResolver.resolve(bundleID: bid) == .general)
    }
}
