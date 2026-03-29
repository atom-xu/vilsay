//
//  DashScopeModelCatalogTests.swift
//

import Foundation
import Testing
@testable import vilsay

struct DashScopeModelCatalogTests {

    @Test func parseModelListJSON_nativeOutputModels() throws {
        let json = """
        {"success":true,"output":{"total":2,"page_no":1,"page_size":20,"models":[
            {"model":"paraformer-v2","name":"P"},
            {"model":"qwen-turbo","name":"Q"}
        ]}}
        """
        let data = try #require(json.data(using: .utf8))
        let ids = try #require(DashScopeModelCatalog.parseModelListJSON(data))
        #expect(ids.contains("paraformer-v2"))
        #expect(ids.contains("qwen-turbo"))
    }

    @Test func parseModelListJSON_openAICompatDataArray() throws {
        let json = """
        {"object":"list","data":[
            {"id":"qwen-turbo","object":"model"},
            {"id":"MiniMax/x","object":"model"}
        ]}
        """
        let data = try #require(json.data(using: .utf8))
        let ids = try #require(DashScopeModelCatalog.parseModelListJSON(data))
        #expect(ids.contains("qwen-turbo"))
        #expect(ids.contains("MiniMax/x"))
    }

    @Test func splitAsrAndText_excludesSlashFromTextGroup() {
        let all = ["qwen-turbo", "MiniMax/foo", "paraformer-v2", "deepseek-v3"]
        let split = DashScopeModelCatalog.splitAsrAndText(from: all)
        #expect(split.asr.contains("paraformer-v2"))
        #expect(split.text.contains("qwen-turbo"))
        #expect(split.text.contains("deepseek-v3"))
        #expect(!split.text.contains("MiniMax/foo"))
    }
}
