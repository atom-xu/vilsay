//
//  PolishStreamParsingTests.swift
//

import Foundation
import Testing
@testable import vilsay

struct PolishStreamParsingTests {

    @Test func nativeSSEDelta_readsMessageContent() {
        let obj: [String: Any] = [
            "output": [
                "choices": [
                    ["message": ["content": "你好"]]
                ]
            ]
        ]
        #expect(PolishStreamParsing.nativeSSEDelta(from: obj) == "你好")
    }

    @Test func nativeSSEDelta_readsOutputText() {
        let obj: [String: Any] = [
            "output": [
                "text": "片段"
            ]
        ]
        #expect(PolishStreamParsing.nativeSSEDelta(from: obj) == "片段")
    }

    @Test func openAICompatSSEDelta_readsDeltaContent() {
        let obj: [String: Any] = [
            "choices": [
                ["delta": ["content": "ab"]]
            ]
        ]
        #expect(PolishStreamParsing.openAICompatSSEDelta(from: obj) == "ab")
    }

    @Test func openAICompatSSEDelta_emptyDeltaReturnsNil() {
        let obj: [String: Any] = [
            "choices": [
                ["delta": ["content": ""]]
            ]
        ]
        #expect(PolishStreamParsing.openAICompatSSEDelta(from: obj) == nil)
    }

    @Test func openAICompatNonStream_parsesMessage() {
        let json = """
        {"choices":[{"message":{"role":"assistant","content":"润色结果"}}]}
        """
        let data = Data(json.utf8)
        #expect(PolishStreamParsing.openAICompatNonStreamContent(from: data) == "润色结果")
    }

    @Test func nativeNonStreamQwen_parsesOutputChoices() {
        let json = """
        {"output":{"choices":[{"message":{"content":"原生"}}]}}
        """
        let data = Data(json.utf8)
        #expect(PolishStreamParsing.nativeNonStreamQwenContent(from: data) == "原生")
    }
}
