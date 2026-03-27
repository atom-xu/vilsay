//
//  Pipeline.swift
//

import AppKit
import AVFoundation
import Foundation
import os.log

/// W3-11：主链路编排（热键 / 悬浮钮 / 菜单栏共用）。
///
/// MainActor 竞态：Step 1 — `beginRecordingSession()` 为 `async` + `await audio.start()` + `isStartingRecording`；
/// Step 2 — `SoundFeedback.recordingStart/End/injectionDone` 均包在 `Task { @MainActor in }`，不与 HAL 同帧。
@MainActor
final class Pipeline {
    static let shared = Pipeline()

    private static let log = Logger(subsystem: "com.vilsay.app", category: "Pipeline")

    private struct ASRTranscribeTimeoutError: Error {}
    private struct VADDeliverOuterTimeoutError: Error {}

    private var audio = AudioCapture()
    private var sessionActive = false
    /// 防止并发 `Task` 在 `await audio.start()` 前同时通过 `guard !sessionActive`。
    private var isStartingRecording = false
    private var cancelled = false
    private var capturedSelection: String?

    /// Push：未到最短按住时间时的延迟启动任务；`sessionId` 与 `pendingPushSessionId` 比对防竞态。
    private var pendingPushSessionId: UUID?
    private var pendingPushStartTask: Task<Void, Never>?

    /// 供热键 Fn 组合键等判断：是否在正式录音中，或 Push 模式最短按住等待中（与 `cancel()` 可生效范围一致）。
    var isRecordingSessionActive: Bool {
        sessionActive || pendingPushStartTask != nil
    }

    /// 一次结束后的时间戳，用于 `postStopCooldown`。
    private var lastRecordingBoundaryAt: Date?
    /// 最长录音强制结束任务。
    private var maxRecordingDurationTask: Task<Void, Never>?
    /// ESC 键取消录音的本地事件监听。
    private var escKeyMonitor: Any?

    private init() {}

    // MARK: - 入口

    /// Toggle / 菜单栏「开始录音」：受冷却约束。
    func startRecording() {
        guard !sessionActive else { return }
        guard AppState.shared.status != .processing else { return }
        if isPostStopCooldownActive() { return }
        Task { await beginRecordingSession() }
    }

    /// Push 按住经过 `minHoldDuration` 后由内部调用，**不**再检查冷却（已在按下时检查过）。
    private func beginRecordingSessionAfterMinHold() async {
        guard !sessionActive else { return }
        guard AppState.shared.status != .processing else { return }
        await beginRecordingSession()
    }

    private func beginRecordingSession() async {
        guard !sessionActive else { return }
        guard !isStartingRecording else { return }
        guard AppState.shared.status != .processing else { return }

        if AuthService.shared.isAuthenticated && AuthService.shared.isQuotaExceeded {
            AppState.shared.lastPipelineError = "本月免费次数已用完，请升级继续使用。"
            AppState.shared.status = .attention
            return
        }

        if DiagnosticsExclusion.excludeMicrophoneHAL {
            Self.log.warning("🧪 VILSAY_EXCLUDE_MIC_HAL：跳过录音会话，不调用 AVAudioRecorder / HAL（若仍崩溃，问题不在麦克风/HAL 路径）")
            AppState.shared.diagnosticsExclusionHint = "诊断：已跳过麦克风/HAL（悬停菜单栏图标可看）"
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
                if AppState.shared.diagnosticsExclusionHint?.contains("已跳过麦克风") == true {
                    AppState.shared.diagnosticsExclusionHint = nil
                }
            }
            return
        }

        isStartingRecording = true
        defer { isStartingRecording = false }

        if AppState.shared.status == .attention {
            AppState.shared.polishAttentionMessage = nil
        }
        cancelled = false
        AppState.shared.floatingPreviewDismissAt = nil
        AppState.shared.floatingFeedbackRecorded = false

        TargetAppMonitor.shared.captureTargetApp()
        capturedSelection = await TargetAppMonitor.shared.getSelectedTextAsync(
            timeoutNanoseconds: Constants.axSelectedTextFetchTimeoutNanoseconds
        )
        if !DiagnosticsExclusion.excludeFloatingButton {
            FloatingButtonController.shared.showIfNeeded()
        }
        if capturedSelection != nil {
            AppState.shared.status = .editMode
        } else {
            AppState.shared.status = .recording
        }

        do {
            try await audio.start()
            sessionActive = true
            startESCKeyMonitor()
            Self.log.info("✅ 录音会话已启动")
            audio.onAudioLevelUpdate = { level in
                Task { @MainActor in
                    AppState.shared.floatingAudioLevel = level
                }
            }

            let streamSid = UUID()
            if AppConfig.streamingASREnabled, AppState.shared.recognitionMode == .cloud, let key = AppConfig.dashscopeAPIKey {
                audio.onPCMChunk = { data in
                    Task { @MainActor in
                        DashScopeStreamingASRClient.shared.send(pcmChunk: data)
                    }
                }
                let model = AppConfig.streamingASRModel
                // 不 await：WebSocket 握手与 task-started 在后台完成，避免拖慢音效与 maxDuration；未就绪前 send 丢弃 PCM。
                Task.detached {
                    await DashScopeStreamingASRClient.shared.startSession(
                        taskId: streamSid,
                        apiKey: key,
                        model: model
                    )
                }
            }

            scheduleMaxRecordingDurationIfNeeded()
            // 勿与 HAL 刚就绪的同帧立刻播系统音，易与 CoreAudio 互锁。
            Task { @MainActor in
                SoundFeedback.recordingStart()
            }
        } catch let error as AudioCapture.AudioCaptureError {
            if case .excludedForDiagnostics = error {
                Self.log.warning("🧪 录音被诊断项跳过（AudioCapture 兜底）")
                AppState.shared.status = .idle
                return
            }
            Self.log.error("录音启动失败: \(error.localizedDescription)")
            AppState.shared.lastPipelineError = error.localizedDescription
            AppState.shared.status = .error
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                if AppState.shared.status == .error {
                    AppState.shared.status = .idle
                    AppState.shared.lastPipelineError = nil
                }
            }
        } catch {
            Self.log.error("录音启动失败: \(error.localizedDescription)")
            AppState.shared.lastPipelineError = error.localizedDescription
            AppState.shared.status = .error
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                if AppState.shared.status == .error {
                    AppState.shared.status = .idle
                    AppState.shared.lastPipelineError = nil
                }
            }
        }
    }

    private func scheduleMaxRecordingDurationIfNeeded() {
        maxRecordingDurationTask?.cancel()
        maxRecordingDurationTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(Constants.maxPushRecordingSeconds))
            } catch {
                return
            }
            guard let self else { return }
            guard self.sessionActive else { return }
            Self.log.warning("⏰ 达到最大录音时长，强制停止")
            await self.stopRecording()
        }
    }

    func stopRecording() async {
        Self.log.info("🔹 stopRecording 被调用")
        Self.log.info("   sessionActive = \(self.sessionActive)")
        
        guard sessionActive else {
            Self.log.warning("   ❌ sessionActive = false，提前返回")
            return
        }
        
        defer { markRecordingBoundaryForCooldown() }
        
        Self.log.info("   → 停止录音")
        sessionActive = false
        stopESCKeyMonitor()
        maxRecordingDurationTask?.cancel()
        maxRecordingDurationTask = nil
        resetFloatingAudioMeter()
        audio.stop()
        scheduleWhisperPreloadAfterRecordingReleased()
        let url = audio.fileURL
        
        if cancelled {
            Self.log.info("   → 录音已取消，清理文件")
            audio.discardFile()
            AppState.shared.status = .idle
            capturedSelection = nil
            return
        }
        
        guard let url else {
            Self.log.warning("   ❌ 没有录音文件")
            AppState.shared.status = .idle
            capturedSelection = nil
            return
        }
        
        Self.log.info("   → 播放结束音效，切换到 processing 状态")
        Task { @MainActor in
            SoundFeedback.recordingEnd()
        }
        AppState.shared.status = .processing

        let useStreaming = AppConfig.streamingASREnabled && AppState.shared.recognitionMode == .cloud
        if useStreaming {
            Self.log.info("⏳ 等待流式 ASR finishTask…")
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await DashScopeStreamingASRClient.shared.finishTask() }
                group.addTask { try? await Task.sleep(nanoseconds: 5_000_000_000) } // 5s 绝对上限
                _ = await group.next()
                group.cancelAll()
            }
            Self.log.info("✅ finishTask 完成，流式结果: \(DashScopeStreamingASRClient.shared.snapshotFinalText() ?? "<nil>")")
        }

        if let dur = audioDurationSeconds(fileURL: url), dur < Constants.minAudioDurationForASRSeconds {
            Self.log.warning("录音过短（<\(Constants.minAudioDurationForASRSeconds)s），跳过 ASR")
            AppState.shared.localWhisperStatusHint = nil
            AppState.shared.lastPipelineError = "录音太短，未进入识别。"
            showTransientError("录音太短")
            DashScopeStreamingASRClient.shared.clearFinalText()
            audio.discardFile()
            capturedSelection = nil
            return
        }

        if useStreaming,
           let trimmed = DashScopeStreamingASRClient.shared.snapshotFinalText()?.trimmingCharacters(in: .whitespacesAndNewlines),
           !trimmed.isEmpty {
            DashScopeStreamingASRClient.shared.clearFinalText()
            let asrMs = (audioDurationSeconds(fileURL: url) ?? 0) * 1000
            Self.log.info("✅ 流式 ASR 结果非空，跳过文件 ASR，走 paraformer-streaming")
            AppState.shared.resetPipelineTraceForNewRun()
            let normalized = ASRSpokenLanguage.currentFromDefaults().normalizeScript(trimmed)
            let itnText = ChineseITN.normalize(normalized)
            AppState.shared.lastPipelineASRText = itnText
            AppState.shared.lastPipelineASRDurationMs = asrMs
            await deliverASRThroughVADToPolish(
                asrText: itnText,
                asrMs: asrMs,
                usageAsrProvider: "paraformer-streaming",
                asrConfidence: nil,
                logAsrProvider: "dashScope"
            )
            audio.discardFile()
            capturedSelection = nil
            return
        }

        DashScopeStreamingASRClient.shared.clearFinalText()
        Self.log.info("   → 开始处理音频文件（Whisper / 文件 ASR 兜底）")
        await process(fileURL: url)
        audio.discardFile()
        capturedSelection = nil
    }

    func toggleRecording() async {
        guard AppState.shared.status != .processing else { return }
        if sessionActive {
            await stopRecording()
        } else {
            startRecording()
        }
    }

    func onHotkeyToggle() async {
        await toggleRecording()
    }

    /// 悬浮钮 / 菜单栏等与 `triggerMode == .push` 对齐的 Push 按下。
    func onHotkeyPushDown() {
        Self.log.info("🔹 onHotkeyPushDown 被调用")
        Self.log.info("   AppState.triggerMode = \(AppState.shared.triggerMode.rawValue)")
        Self.log.info("   AppState.status = \(AppState.shared.status)")

        guard AppState.shared.triggerMode == .push else {
            Self.log.warning("   ❌ triggerMode 不是 push，提前返回")
            return
        }
        pushHoldDownCore(sourceLabel: "onHotkeyPushDown")
    }

    /// 悬浮钮 / 菜单栏等与 `triggerMode == .push` 对齐的 Push 松开。
    func onHotkeyPushUp() async {
        Self.log.info("🔹 onHotkeyPushUp 被调用")
        Self.log.info("   AppState.triggerMode = \(AppState.shared.triggerMode.rawValue)")
        Self.log.info("   sessionActive = \(self.sessionActive)")
        Self.log.info("   pendingPushStartTask = \(self.pendingPushStartTask != nil ? "存在" : "nil")")

        guard AppState.shared.triggerMode == .push else {
            Self.log.warning("   ❌ triggerMode 不是 push，提前返回")
            return
        }
        pushHoldUpCore(sourceLabel: "onHotkeyPushUp")
    }

    /// 全局 Fn 在 **长按模式** 下经 `Constants.fnTapVersusHoldMs` 判定后调用；`HotkeyManager` 仅在 `triggerMode == .push` 时走此路径。
    /// 已在 `HotkeyManager` 侧按住 ≥ 分界时间，视为满足最短按住，直接开始录音。
    func fnHoldPushDown() {
        Self.log.info("🔹 fnHoldPushDown（全局 Fn · 长按模式）")
        pushHoldDownImmediateAfterFnLongPress()
    }

    /// 全局 Fn 在 **长按模式** 下、对应 `fnHoldPushDown` 后松开。
    func fnHoldPushUp() async {
        Self.log.info("🔹 fnHoldPushUp（全局 Fn · 长按模式松开）")
        pushHoldUpCore(sourceLabel: "fnHoldPushUp")
    }

    // MARK: - Push 核心（热键路径共享）

    private func pushHoldDownCore(sourceLabel: String) {
        Self.log.info("   [\(sourceLabel)] pushHoldDownCore")

        guard AppState.shared.status != .processing else {
            Self.log.warning("   ❌ 正在处理中，提前返回")
            return
        }

        if isPostStopCooldownActive() {
            Self.log.warning("   ❌ 冷却期内，提前返回")
            return
        }

        if sessionActive || pendingPushStartTask != nil {
            Self.log.warning("   ❌ 已有活动会话或待定任务，提前返回")
            return
        }

        Self.log.info("   → 设置 isPushPressed = true")
        AppState.shared.isPushPressed = true

        cancelPendingPushArmOnly()
        let sessionId = UUID()
        pendingPushSessionId = sessionId

        Self.log.info("   → 启动延迟任务（\(Constants.minHoldDurationSeconds)秒后开始录音）")
        pendingPushStartTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(Constants.minHoldDurationSeconds))
            } catch {
                return
            }
            guard let self else { return }
            guard self.pendingPushSessionId == sessionId else { return }
            self.pendingPushSessionId = nil
            self.pendingPushStartTask = nil
            Self.log.info("   → 延迟结束，调用 beginRecordingSessionAfterMinHold()")
            await self.beginRecordingSessionAfterMinHold()
        }
    }

    /// 全局 Fn 长按：已越过 `fnTapVersusHoldMs`，不再叠加 `minHoldDurationSeconds` 防误触延迟。
    private func pushHoldDownImmediateAfterFnLongPress() {
        guard AppState.shared.status != .processing else {
            Self.log.warning("   ❌ 正在处理中，提前返回")
            return
        }
        if isPostStopCooldownActive() {
            Self.log.warning("   ❌ 冷却期内，提前返回")
            return
        }
        if sessionActive || pendingPushStartTask != nil {
            Self.log.warning("   ❌ 已有活动会话或待定任务，提前返回")
            return
        }

        cancelPendingPushArmOnly()
        AppState.shared.isPushPressed = true
        Self.log.info("   → Fn 长按：直接 beginRecordingSessionAfterMinHold()")
        Task { await self.beginRecordingSessionAfterMinHold() }
    }

    /// 🔧 修复：简化 Push 松开处理，确保一定能停止录音
    private func pushHoldUpCore(sourceLabel: String) {
        Self.log.info("   [\(sourceLabel)] pushHoldUpCore")
        AppState.shared.isPushPressed = false

        if pendingPushStartTask != nil {
            Self.log.info("   → 取消待定的启动任务")
            cancelPendingPushArmOnly()
            markRecordingBoundaryForCooldown()
            return
        }

        // 🔧 关键修复：只要正在录音，就停止
        guard sessionActive else {
            Self.log.info("   → 无活动会话，不停止")
            return
        }
        
        Self.log.info("   → 调用 stopRecording()")
        // 使用 Task 包装 async 调用，避免调用方需要 await
        Task {
            await stopRecording()
        }
    }

    func cancel() async {
        if pendingPushStartTask != nil {
            cancelPendingPushArmOnly()
            markRecordingBoundaryForCooldown()
        }
        guard sessionActive || AppState.shared.status == .recording || AppState.shared.status == .editMode else {
            return
        }
        cancelled = true
        stopESCKeyMonitor()
        AppState.shared.isPushPressed = false
        AppState.shared.floatingPreviewDismissAt = nil
        if sessionActive {
            sessionActive = false
            maxRecordingDurationTask?.cancel()
            maxRecordingDurationTask = nil
            resetFloatingAudioMeter()
            audio.stop()
            DashScopeStreamingASRClient.shared.cancel()
            scheduleWhisperPreloadAfterRecordingReleased()
            audio.discardFile()
            markRecordingBoundaryForCooldown()
        }
        capturedSelection = nil
        TargetAppMonitor.shared.clear()
        AppState.shared.status = .idle
        AppState.shared.showCancelFlash = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            AppState.shared.showCancelFlash = false
        }
    }

    private func cancelPendingPushArmOnly() {
        pendingPushStartTask?.cancel()
        pendingPushStartTask = nil
        pendingPushSessionId = nil
    }

    private func isPostStopCooldownActive() -> Bool {
        guard let t = lastRecordingBoundaryAt else { return false }
        return Date().timeIntervalSince(t) < Constants.postStopCooldownSeconds
    }

    private func markRecordingBoundaryForCooldown() {
        lastRecordingBoundaryAt = Date()
    }

    private func resetFloatingAudioMeter() {
        audio.onAudioLevelUpdate = nil
        AppState.shared.floatingAudioLevel = 0
    }

    // MARK: - ESC 键取消

    private func startESCKeyMonitor() {
        guard escKeyMonitor == nil else { return }
        escKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // ESC
                Task { @MainActor in
                    await self?.cancel()
                }
                return nil // consume the event
            }
            return event
        }
        // Global monitor for when app is not focused (during recording the target app is focused)
        let globalMon = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                Task { @MainActor in
                    await self?.cancel()
                }
            }
        }
        // Store both monitors: use a wrapper
        if let globalMon {
            escGlobalMonitor = globalMon
        }
        Self.log.debug("ESC 键监听已启动")
    }

    private var escGlobalMonitor: Any?

    private func stopESCKeyMonitor() {
        if let m = escKeyMonitor {
            NSEvent.removeMonitor(m)
            escKeyMonitor = nil
        }
        if let m = escGlobalMonitor {
            NSEvent.removeMonitor(m)
            escGlobalMonitor = nil
        }
    }

    // MARK: - 短暂错误提示（浮层显示）

    private func showTransientError(_ message: String) {
        AppState.shared.transientErrorFlash = message
        AppState.shared.status = .idle
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if AppState.shared.transientErrorFlash == message {
                AppState.shared.transientErrorFlash = nil
            }
        }
    }

    /// Whisper `avgLogprob` → [0,1]，供 §C 与 raw_log。
    private static func normalizeWhisperConfidence(_ avgLogprob: Float) -> Double {
        Double(1.0 / (1.0 + exp(-2.0 * (Double(avgLogprob) + 1.0))))
    }

    /// WhisperKit 在后台预加载，与 HAL 录音错开；须在 `audio.stop()` 之后调用。
    private func scheduleWhisperPreloadAfterRecordingReleased() {
        guard !DiagnosticsExclusion.excludeWhisperLocal else { return }
        Task.detached(priority: .background) {
            await WhisperASRFallback.shared.preloadIfNeeded()
        }
    }

    // MARK: - 延迟测试统计
    #if DEBUG
    private static var latencyMetrics: [(date: Date, latencyMs: Double)] = []
    private static var testCount = 0

    static func exportLatencyReport() -> String {
        latencyMetrics.map { "\($0.date): \($0.latencyMs)ms" }.joined(separator: "\n")
    }

    static var averageLatency: Double {
        guard !latencyMetrics.isEmpty else { return 0 }
        return latencyMetrics.map(\.latencyMs).reduce(0, +) / Double(latencyMetrics.count)
    }
    #endif

    // MARK: - 处理链

    private func audioDurationSeconds(fileURL: URL) -> TimeInterval? {
        guard let file = try? AVAudioFile(forReading: fileURL) else { return nil }
        let rate = file.fileFormat.sampleRate
        guard rate > 0 else { return nil }
        return Double(file.length) / rate
    }

    /// ASR 转写（无外层超时；超时由 `process` 内 TaskGroup 包裹）。
    private func performASRTranscription(fileURL: URL) async throws -> (String, Float?, String) {
        var whisperAvgLogprob: Float?
        var logAsrProvider = "whisperKit"
        let raw: String
        if AppState.shared.recognitionMode == .cloud,
           NetworkMonitor.shared.isConnected {
            if let viaProxy = await DashScopeASRClient.transcribeViaProxyIfConfigured(fileURL),
               !viaProxy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                raw = viaProxy
                logAsrProvider = "dashScope"
            } else if let cloud = await DashScopeASRClient.transcribeFileIfAvailable(fileURL),
                      !cloud.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                raw = cloud
                logAsrProvider = "dashScope"
            } else {
                let m = try await WhisperASRFallback.shared.transcribeWithMetrics(fileURL: fileURL)
                raw = m.text
                whisperAvgLogprob = m.avgLogprob
                logAsrProvider = "whisperKit"
            }
        } else {
            let m = try await WhisperASRFallback.shared.transcribeWithMetrics(fileURL: fileURL)
            raw = m.text
            whisperAvgLogprob = m.avgLogprob
            logAsrProvider = "whisperKit"
        }
        return (raw, whisperAvgLogprob, logAsrProvider)
    }

    private func process(fileURL: URL) async {
        #if DEBUG
        let startTime = CFAbsoluteTimeGetCurrent()
        Self.testCount += 1
        let currentTest = Self.testCount
        #endif

        AppState.shared.resetPipelineTraceForNewRun()

        defer {
            if AppState.shared.status == .processing {
                AppState.shared.status = .idle
            }
        }

        if let dur = audioDurationSeconds(fileURL: fileURL) {
            let bytes = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? NSNumber)?.int64Value ?? -1
            Self.log.info("📁 待处理录音：时长 \(String(format: "%.2f", dur))s，文件约 \(bytes) 字节")
            if dur < Constants.minAudioDurationForASRSeconds {
                Self.log.warning("录音过短（<\(Constants.minAudioDurationForASRSeconds)s），跳过 ASR")
                AppState.shared.localWhisperStatusHint = nil
                AppState.shared.lastPipelineError = "录音太短，未进入识别。"
                return
            }
        } else {
            Self.log.error("无法读取录音文件时长")
            AppState.shared.localWhisperStatusHint = nil
            AppState.shared.lastPipelineError = "无法读取录音文件。"
            return
        }

        do {
            if AppState.shared.recognitionMode == .local,
               AppState.shared.localWhisperLoading,
               !AppState.shared.localWhisperReady {
                AppState.shared.localWhisperStatusHint = "本地语音识别准备中…"
            }

            let asrStart = CFAbsoluteTimeGetCurrent()
            let (raw, whisperAvgLogprob, logAsrProvider) = try await withThrowingTaskGroup(of: (String, Float?, String).self) { group in
                group.addTask {
                    try await self.performASRTranscription(fileURL: fileURL)
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: Constants.asrTranscribeTimeoutNanoseconds)
                    throw ASRTranscribeTimeoutError()
                }
                let first = try await group.next()!
                group.cancelAll()
                return first
            }
            let asrMs = (CFAbsoluteTimeGetCurrent() - asrStart) * 1000
            let asrConfidence: Double? = whisperAvgLogprob.map { Self.normalizeWhisperConfidence($0) }

            AppState.shared.localWhisperStatusHint = nil

            guard !cancelled else {
                return
            }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                Self.log.warning("ASR 返回空文本：请检查麦克风音量、环境噪音，或确认 Whisper 已加载成功。")
                AppState.shared.lastPipelineError = "语音识别结果为空。"
                showTransientError("未识别到语音")
                return
            }

            let normalized = ASRSpokenLanguage.currentFromDefaults().normalizeScript(trimmed)
            let itnText = ChineseITN.normalize(normalized)
            AppState.shared.lastPipelineASRText = itnText
            AppState.shared.lastPipelineASRDurationMs = asrMs

            await deliverASRThroughVADToPolish(
                asrText: itnText,
                asrMs: asrMs,
                usageAsrProvider: nil,
                asrConfidence: asrConfidence,
                logAsrProvider: logAsrProvider
            )

            #if DEBUG
            let endTime = CFAbsoluteTimeGetCurrent()
            let latencyMs = (endTime - startTime) * 1000
            Self.latencyMetrics.append((Date(), latencyMs))
            Self.log.debug("[Pipeline] #\(currentTest) latency \(Int(latencyMs))ms")
            #endif
        } catch is ASRTranscribeTimeoutError {
            Self.log.error("ASR 转写超时（\(Constants.asrTranscribeTimeoutNanoseconds / 1_000_000_000)s）")
            AppState.shared.lastPipelineError = "语音识别超时，请重试。"
            AppState.shared.status = .error
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                if AppState.shared.status == .error {
                    AppState.shared.status = .idle
                    AppState.shared.lastPipelineError = nil
                }
            }
        } catch {
            let userMsg = WhisperLoadErrorPresentation.userMessage(for: error)
            Self.log.error("主链路失败: \(userMsg)")
            AppState.shared.lastPipelineError = userMsg
            AppState.shared.status = .error
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                if AppState.shared.status == .error {
                    AppState.shared.status = .idle
                    AppState.shared.lastPipelineError = nil
                }
            }
        }
    }

    // MARK: - VAD → 润色 / 注入

    /// ASR 文本经 `VADBuffer` 统一出口后再进入润色；整段文件 ASR 使用 `acceptFinalTranscript`。流式 ASR 接入后可改为多次 `feed` + `flush`。
    private func deliverASRThroughVADToPolish(
        asrText: String,
        asrMs: Double,
        usageAsrProvider: String? = nil,
        asrConfidence: Double? = nil,
        logAsrProvider: String? = nil
    ) async {
        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    await self.deliverASRThroughVADToPolishUnbounded(
                        asrText: asrText,
                        asrMs: asrMs,
                        usageAsrProvider: usageAsrProvider,
                        asrConfidence: asrConfidence,
                        logAsrProvider: logAsrProvider
                    )
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: Constants.vadDeliverOuterTimeoutNanoseconds)
                    throw VADDeliverOuterTimeoutError()
                }
                try await group.next()!
                group.cancelAll()
            }
        } catch is VADDeliverOuterTimeoutError {
            Self.log.error("VAD→润色 外层超时（\(Constants.vadDeliverOuterTimeoutNanoseconds / 1_000_000_000)s）")
            if AppState.shared.status == .processing || AppState.shared.status == .injecting {
                AppState.shared.status = .idle
            }
        } catch {
            Self.log.error("deliverASRThroughVADToPolish: \(error.localizedDescription)")
        }
    }

    private func deliverASRThroughVADToPolishUnbounded(
        asrText: String,
        asrMs: Double,
        usageAsrProvider: String? = nil,
        asrConfidence: Double? = nil,
        logAsrProvider: String? = nil
    ) async {
        defer {
            if AppState.shared.status == .processing {
                AppState.shared.status = .idle
            }
        }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            let vad = VADBuffer()
            var resumed = false
            func finish() {
                if !resumed {
                    resumed = true
                    cont.resume()
                }
            }
            vad.onSentenceComplete = { [weak self] segment in
                guard let self else {
                    finish()
                    return
                }
                Task { @MainActor in
                    // 35s 绝对上限：防止 polish/inject 路径挂死导致 continuation 永久泄漏
                    await withTaskGroup(of: Void.self) { group in
                        group.addTask {
                            await self.runPolishInjectAfterVAD(
                                asrText: segment,
                                asrMs: asrMs,
                                usageAsrProvider: usageAsrProvider,
                                asrConfidence: asrConfidence,
                                logAsrProvider: logAsrProvider
                            )
                        }
                        group.addTask {
                            try? await Task.sleep(nanoseconds: UInt64(Constants.pipelineAbsoluteDeadlineMs) * 1_000_000)
                        }
                        _ = await group.next()
                        group.cancelAll()
                    }
                    finish()
                }
            }
            vad.acceptFinalTranscript(asrText)
        }
    }

    private func runPolishInjectAfterVAD(
        asrText: String,
        asrMs: Double,
        usageAsrProvider: String? = nil,
        asrConfidence: Double? = nil,
        logAsrProvider: String? = nil
    ) async {
        let outputMode = OutputModeResolver.resolve(
            bundleID: TargetAppMonitor.shared.capturedBundleIdentifier
        )
        let profile = ProfileService.getProfile(for: outputMode)
        let system = PromptComposer.systemPrompt(
            for: profile,
            targetAppBundleID: TargetAppMonitor.shared.capturedBundleIdentifier,
            asrConfidence: asrConfidence
        )
        let user: String
        if let original = capturedSelection {
            user = Prompts.buildEditPrompt(original: original, instruction: asrText)
        } else {
            user = Prompts.polishUserMessage(asrText: asrText)
        }
        guard !cancelled else {
            return
        }

        guard TargetAppMonitor.shared.activateTargetApp() else {
            Self.log.error("目标应用激活失败，跳过注入")
            AppState.shared.lastPipelineError = "无法激活目标应用，请手动切回原文窗口。"
            return
        }
        try? await Task.sleep(for: .milliseconds(50))

        AppState.shared.status = .injecting
        defer {
            if AppState.shared.status == .injecting {
                AppState.shared.status = .idle
            }
        }

        TextInjector.beginProtectedPasteSession()
        defer { TextInjector.endProtectedPasteSession() }

        let polishPhaseStart = CFAbsoluteTimeGetCurrent()
        var injectAccumSec: CFAbsoluteTime = 0
        func pasteTimed(_ text: String) {
            let p = CFAbsoluteTimeGetCurrent()
            TextInjector.pasteChunk(text)
            injectAccumSec += CFAbsoluteTimeGetCurrent() - p
        }

        var receivedPolish = false
        var polishPending = ""
        var fullPolishForTrace = ""

        let polishUsageGate = PolishUsageOnceGate()
        func recordPolishUsageFromGateIfFirst() {
            guard polishUsageGate.tryConsume() else { return }
            let asrMsInt = max(0, Int(min(asrMs, Double(Int.max))))
            let provider = usageAsrProvider
                ?? (AppState.shared.recognitionMode == .cloud ? "dashscope_cloud" : "whisper_local")
            Self.log.info("Pipeline 用量上报 ASR 来源: \(provider)")
            Task { @MainActor in
                await AuthService.shared.recordUsageAfterFirstPolishToken(
                    durationMs: asrMsInt,
                    asrProvider: provider
                )
            }
        }

        if !AppConfig.canRunPolishWithCurrentCredentials {
            Self.log.warning("⚠️ 润色凭证不可用，输出将等同 ASR 原文")
        }

        for await chunk in PolishService.polishStreaming(
            system: system,
            user: user,
            onFirstToken: {
                Task { @MainActor in
                    recordPolishUsageFromGateIfFirst()
                }
            }
        ) {
            guard !cancelled else { break }
            if chunk.isEmpty { continue }
            receivedPolish = true
            fullPolishForTrace.append(contentsOf: chunk)
            polishPending.append(contentsOf: chunk)
        }
        // 流式接收完成后一次性注入，避免多次 CGEvent.post 异步竞争导致粘贴错误内容
        if !polishPending.isEmpty {
            pasteTimed(polishPending)
        }
        if !receivedPolish, !cancelled {
            let fallback = await PolishService.polishPlain(system: system, user: user)
            if !fallback.isEmpty {
                recordPolishUsageFromGateIfFirst()
                pasteTimed(fallback)
                fullPolishForTrace = fallback
            }
        }

        guard !cancelled else {
            return
        }

        let polishWallMs = (CFAbsoluteTimeGetCurrent() - polishPhaseStart) * 1000
        let injectMs = injectAccumSec * 1000
        let polishMs = max(0, polishWallMs - injectMs)
        PerformanceTracker.logPipeline(asrMs: asrMs, polishMs: polishMs, injectMs: injectMs)

        if !fullPolishForTrace.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            RawLogger.logAsync(
                asr: asrText,
                polished: fullPolishForTrace,
                durationMs: Int(asrMs),
                sessionId: UUID().uuidString,
                asrProvider: logAsrProvider ?? usageAsrProvider,
                asrConfidence: asrConfidence,
                targetAppBundleID: TargetAppMonitor.shared.capturedBundleIdentifier,
                outputMode: outputMode.rawValue
            )
        }

        AppState.shared.lastPipelinePolishedText = fullPolishForTrace
        AppState.shared.floatingFeedbackRecorded = false
        AppState.shared.floatingPreviewDismissAt = Date().addingTimeInterval(
            Double(Constants.floatingPillPreviewDurationMs) / 1000.0
        )
        AppState.shared.lastPipelinePolishWallMs = polishMs
        AppState.shared.lastPipelineInjectMs = injectMs
        AppState.shared.lastPipelineCompletedAt = Date()
        Self.log.info("📋 Week3 主链路输出已更新：设置 → 可查看「ASR 原文 / 润色输出」与耗时。")

        Task { @MainActor in
            SoundFeedback.injectionDone()
        }

        let trimmedPolish = fullPolishForTrace.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAsr = asrText.trimmingCharacters(in: .whitespacesAndNewlines)
        let canPolish = AppConfig.canRunPolishWithCurrentCredentials
        let polishActuallyWorked = canPolish && !trimmedPolish.isEmpty && trimmedPolish != trimmedAsr

        AppState.shared.lastPolishDidWork = polishActuallyWorked
        if !polishActuallyWorked {
            if !canPolish {
                #if DEBUG
                AppState.shared.lastPolishFailReason = "未配置 API Key，请在设置中填写"
                #else
                AppState.shared.lastPolishFailReason = "未登录，无法使用云端润色"
                #endif
            } else {
                AppState.shared.lastPolishFailReason = "润色 API 返回异常"
            }
        } else {
            AppState.shared.lastPolishFailReason = nil
        }

        if !canPolish {
            #if DEBUG
            AppState.shared.polishAttentionMessage = "润色不可用：请配置 DASHSCOPE_API_KEY 或在设置中填写 DashScope API Key。"
            #else
            AppState.shared.polishAttentionMessage = "润色不可用：请先登录账号。"
            #endif
            AppState.shared.status = .attention
        } else {
            AppState.shared.polishAttentionMessage = nil
            AppState.shared.status = .idle
        }
    }
}

/// 润色用量（登录用户）仅上报一次：SSE 首 token 与 `polishPlain` 降级互斥。
private final class PolishUsageOnceGate: @unchecked Sendable {
    private let lock = NSLock()
    private var consumed = false

    func tryConsume() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !consumed else { return false }
        consumed = true
        return true
    }
}
