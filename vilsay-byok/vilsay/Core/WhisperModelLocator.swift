//
//  WhisperModelLocator.swift
//

import Foundation

/// 解析 App 包内已嵌入的 Whisper CoreML 目录（免首次联网下载）。
/// 将 Hugging Face `argmaxinc/whisperkit-coreml` 中对应变体文件夹拖入 Xcode → **Copy Bundle Resources**，路径：`WhisperModels/openai_whisper-base/`。
enum WhisperModelLocator {
    nonisolated static func bundledModelFolderPath() -> String? {
        guard let url = Bundle.main.url(forResource: Constants.asrFallbackModel, withExtension: nil, subdirectory: "WhisperModels") else {
            return nil
        }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            return nil
        }
        return url.path
    }
}
