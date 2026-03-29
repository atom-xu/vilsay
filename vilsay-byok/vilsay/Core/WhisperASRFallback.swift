//
//  WhisperASRFallback.swift
//

import Foundation
import os.log
import WhisperKit

/// W3-04：本地 WhisperKit。
///
/// 预加载时机：不在应用启动时触发，而在 **首次（及后续）录音结束、`audio.stop()` 释放 HAL 之后** 由 `Pipeline` 调用 `preloadIfNeeded()`，
/// 避免与麦克风/HAL 同时完成时和 AppState 更新抢 MainActor。
///
/// 加载完成/失败时对 AppState 的更新用 `Task { @MainActor in }` 投递。
actor WhisperASRFallback {
    static let shared = WhisperASRFallback()

    private var kit: WhisperKit?
    private(set) var isModelReady = false
    private var loadError: Error?
    private var loadingTask: Task<Void, Never>?

    /// 在录音已释放 HAL 之后调用；已就绪或已失败则直接返回，不重复下载。
    func preloadIfNeeded() async {
        if DiagnosticsExclusion.excludeWhisperLocal {
            return
        }
        if isModelReady { return }
        if loadError != nil { return }

        Task { @MainActor in
            AppState.shared.localWhisperLoading = true
            AppState.shared.localWhisperStatusHint = "正在加载本地语音模型..."
        }
        await ensureLoaded()
    }

    func transcribe(fileURL: URL) async throws -> String {
        try await transcribeWithMetrics(fileURL: fileURL).text
    }

    /// V14：返回文本与各段平均 `avgLogprob`（用于 Prompt §C / raw_log）。
    func transcribeWithMetrics(fileURL: URL) async throws -> (text: String, avgLogprob: Float?) {
        let log = Logger(subsystem: "com.vilsay.app", category: "Whisper")
        if DiagnosticsExclusion.excludeWhisperLocal {
            log.warning("🧪 VILSAY_EXCLUDE_WHISPER=1：跳过本地 Whisper 转写，返回空")
            return ("", nil)
        }
        log.info("⏳ 等待 Whisper 模型就绪（首次无包内模型时下载可能需数分钟，控制台会持续无新日志属正常现象）…")
        await ensureLoaded()

        if let loadError {
            throw loadError
        }

        guard let kit else {
            throw WhisperFallbackError.kitUnavailable
        }

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw WhisperFallbackError.audioFileNotFound
        }

        let byteSize = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? NSNumber)?.int64Value ?? -1
        let t0 = CFAbsoluteTimeGetCurrent()
        log.info("🎙️ 开始 Whisper transcribe: \(fileURL.lastPathComponent)（约 \(byteSize) 字节）")
        let lang = ASRSpokenLanguage.currentFromDefaults().whisperLanguageCode
        let decodingOptions = DecodingOptions(language: lang)
        let results = try await kit.transcribe(audioPath: fileURL.path, decodeOptions: decodingOptions)
        let transcribeMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000

        let text = results.map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines)
        let segments = results.flatMap { $0.segments }
        let avgLogprob: Float? = segments.isEmpty
            ? nil
            : segments.map(\.avgLogprob).reduce(0, +) / Float(segments.count)

        if text.isEmpty {
            log.warning("Whisper 识别结果为空（耗时 \(Int(transcribeMs))ms）")
        } else {
            log.info("✅ Whisper 转写完成：\(text.count) 字，耗时 \(Int(transcribeMs))ms")
        }

        return (text, avgLogprob)
    }

    private func ensureLoaded() async {
        if isModelReady { return }
        if loadError != nil { return }
        if let loadingTask {
            await loadingTask.value
            return
        }
        let task = Task { await self.performLoad() }
        loadingTask = task
        await task.value
        loadingTask = nil
    }

    private func performLoad() async {
        guard !isModelReady, loadError == nil else { return }

        let logger = Logger(subsystem: "com.vilsay.app", category: "Whisper")
        let modelName = Constants.asrFallbackModel
        logger.info("开始加载 WhisperKit 模型: \(modelName)")

        do {
            let k: WhisperKit
            if let bundled = WhisperModelLocator.bundledModelFolderPath() {
                logger.info("使用包内模型路径: \(bundled)")
                let t0 = CFAbsoluteTimeGetCurrent()
                k = try await WhisperKit(
                    model: modelName,
                    modelFolder: bundled,
                    verbose: false,
                    logLevel: .error,
                    load: true,
                    download: false
                )
                logger.info("包内模型初始化完成，耗时 \(Int((CFAbsoluteTimeGetCurrent() - t0) * 1000))ms")
            } else {
                logger.warning("包内未找到 WhisperModels/\(modelName)，将从网络下载（首次常需数分钟；请保持网络，勿退出）")
                Task { @MainActor in
                    AppState.shared.localWhisperStatusHint = "正在下载语音模型（首次可能数分钟）…"
                }
                let t0 = CFAbsoluteTimeGetCurrent()
                k = try await WhisperKit(
                    model: modelName,
                    verbose: false,
                    logLevel: .error,
                    load: true,
                    download: true
                )
                let dlSec = CFAbsoluteTimeGetCurrent() - t0
                logger.info("✅ 网络下载并加载 Whisper 完成，耗时 \(String(format: "%.1f", dlSec)) 秒")
            }
            kit = k
            isModelReady = true

            logger.info("✅ WhisperKit 模型可开始转写")

            // 异步投递 UI 更新，避免与主线程上其它 HAL / 音频路径抢同一轮 MainActor 执行。
            Task { @MainActor in
                AppState.shared.localWhisperLoading = false
                AppState.shared.localWhisperReady = true
                AppState.shared.localWhisperStatusHint = nil
            }
        } catch {
            loadError = error
            let hint = WhisperLoadErrorPresentation.userMessage(for: error)
            logger.error("❌ WhisperKit 加载失败: \(hint)")

            Task { @MainActor in
                AppState.shared.localWhisperLoading = false
                AppState.shared.localWhisperReady = false
                AppState.shared.localWhisperStatusHint = hint
            }
        }
    }

    enum WhisperFallbackError: Error {
        case kitUnavailable
        case audioFileNotFound
    }
}
