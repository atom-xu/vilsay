//
//  SettingsDiagnosticsSection.swift
//  vilsay
//

import AppKit
import AVFoundation
import Combine
import SwiftUI

// MARK: - 麦克风试录（W4-P02）

@MainActor
final class MicTestController: ObservableObject {
    @Published var isRecording = false
    @Published var lastURL: URL?
    @Published var durationSeconds: Double?
    @Published var errorMessage: String?
    @Published var playbackPlaying = false

    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?

    func start() {
        errorMessage = nil
        durationSeconds = nil
        lastURL = nil
        let status = PermissionManager.shared.checkMicrophonePermission()
        if status == .denied {
            errorMessage = "麦克风权限被拒绝。请在系统设置中允许 Vilsay 访问麦克风。"
            return
        }
        if status == .notDetermined {
            errorMessage = "请先授予麦克风权限（可在上方权限区请求）。"
            return
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("vilsay-mictest-\(UUID().uuidString).wav")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16_000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
        ]
        do {
            let r = try AVAudioRecorder(url: url, settings: settings)
            r.prepareToRecord()
            guard r.record() else {
                errorMessage = "无法启动录音引擎。"
                return
            }
            recorder = r
            lastURL = url
            isRecording = true
        } catch {
            errorMessage = "录音启动失败：\(error.localizedDescription)"
        }
    }

    func stop() {
        recorder?.stop()
        recorder = nil
        isRecording = false
        guard let url = lastURL else { return }
        if let file = try? AVAudioFile(forReading: url) {
            let rate = file.fileFormat.sampleRate
            if rate > 0 {
                durationSeconds = Double(file.length) / rate
            }
        }
        if let d = durationSeconds, d < Constants.minAudioDurationForASRSeconds {
            errorMessage = "录音时长低于 \(String(format: "%.2f", Constants.minAudioDurationForASRSeconds)) 秒，主链路会忽略此类片段。"
        }
    }

    func playLast() {
        guard let url = lastURL, FileManager.default.fileExists(atPath: url.path) else {
            errorMessage = "没有可播放的试录文件。"
            return
        }
        do {
            player = try AVAudioPlayer(contentsOf: url)
            player?.play()
            playbackPlaying = true
            DispatchQueue.main.asyncAfter(deadline: .now() + (player?.duration ?? 0)) { [weak self] in
                self?.playbackPlaying = false
            }
        } catch {
            errorMessage = "无法播放：\(error.localizedDescription)"
        }
    }

    func discard() {
        player?.stop()
        if let url = lastURL {
            try? FileManager.default.removeItem(at: url)
        }
        lastURL = nil
        durationSeconds = nil
        errorMessage = nil
    }
}

struct MicTestSection: View {
    @EnvironmentObject private var mic: MicTestController

    var body: some View {
        GroupBox("麦克风试录") {
            VStack(alignment: .leading, spacing: 10) {
                Text("短时试录，不经过润色主链路，用于确认设备与权限。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    if mic.isRecording {
                        Button("停止") { mic.stop() }
                            .keyboardShortcut(.defaultAction)
                    } else {
                        Button("开始试录") { mic.start() }
                    }
                    if mic.lastURL != nil, !mic.isRecording {
                        Button("播放") { mic.playLast() }
                            .disabled(mic.playbackPlaying)
                        Button("删除临时文件") { mic.discard() }
                    }
                }
                if let d = mic.durationSeconds {
                    Text(String(format: "时长：%.2f 秒", d))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let err = mic.errorMessage, !err.isEmpty {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("打开麦克风隐私设置") {
                        PermissionManager.shared.openMicrophonePrivacySettings()
                    }
                }
            }
            .padding(8)
        }
    }
}

// MARK: - Week 3 主链路输入/输出（验收）

struct Week3PipelineTraceSection: View {
    @ObservedObject private var state = AppState.shared

    var body: some View {
        GroupBox("主链路（Week 3 · 输入/输出）") {
            VStack(alignment: .leading, spacing: 10) {
                Text("最近一次录音结束 → ASR → 润色 → 注入的结果（仅保存在内存，不写磁盘）。配置 DASHSCOPE_API_KEY 后便于对照延迟与文本。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let at = state.lastPipelineCompletedAt {
                    Text("完成时间：\(at.formatted(date: .abbreviated, time: .standard))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                HStack(spacing: 12) {
                    Text("ASR \(Int(state.lastPipelineASRDurationMs)) ms")
                    Text("润色 \(Int(state.lastPipelinePolishWallMs)) ms")
                    Text("注入 \(Int(state.lastPipelineInjectMs)) ms")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if !state.lastPipelineASRText.isEmpty {
                    Text("ASR 原文")
                        .font(.caption.weight(.semibold))
                    Text(state.lastPipelineASRText)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if !state.lastPipelinePolishedText.isEmpty {
                    Text("润色输出（已注入）")
                        .font(.caption.weight(.semibold))
                    Text(state.lastPipelinePolishedText)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if state.lastPipelineASRText.isEmpty, state.lastPipelinePolishedText.isEmpty {
                    Text("尚无记录：请用 Fn 长按或菜单「开始录音」完成一轮。")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Button("清除本页展示") {
                    state.resetPipelineTraceForNewRun()
                }
                .font(.caption)
                .disabled(state.lastPipelineASRText.isEmpty && state.lastPipelinePolishedText.isEmpty)
            }
            .padding(8)
        }
    }
}

// MARK: - 热键自测（W4-P03）

struct HotkeySelfTestSection: View {
    @ObservedObject private var state = AppState.shared

    var body: some View {
        GroupBox("热键自测") {
            VStack(alignment: .leading, spacing: 10) {
                Text("按下「开始监听」后，请按当前绑定热键（\(bindingHint)）。与 Push/Toggle 无关。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button(state.hotkeySelfTestAwaiting ? "监听中…" : "开始监听热键") {
                        state.hotkeySelfTestMessage = nil
                        state.hotkeySelfTestAwaiting = true
                    }
                    .disabled(state.hotkeySelfTestAwaiting)
                    Button("测试 ESC") {
                        state.hotkeySelfTestMessage = nil
                        state.escSelfTestAwaiting = true
                    }
                    .disabled(state.escSelfTestAwaiting)
                }
                if !HotkeyManager.isEventTapInstalled {
                    Text("热键监听未就绪（嵌入式 XPC HotkeyMonitor）：请授予辅助功能权限后重启应用。")
                        .font(.caption)
                        .foregroundStyle(.red)
                    Button("打开辅助功能隐私设置") {
                        PermissionManager.shared.openAccessibilityPrivacySettings()
                    }
                }
                if let msg = state.hotkeySelfTestMessage {
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
            .padding(8)
        }
    }

    private var bindingHint: String {
        AppConfig.hotkeyBindingMode == .fnGlobe ? "FN / Globe" : "右 Option"
    }
}

// MARK: - AI 分段诊断（W4-P04）

@MainActor
final class AIDiagnosticsController: ObservableObject {
    @Published var localText = ""
    @Published var localDetail = ""
    @Published var cloudText = ""
    @Published var cloudDetail = ""
    @Published var polishText = ""
    @Published var polishDetail = ""
    @Published var busyLocal = false
    @Published var busyCloud = false
    @Published var busyPolish = false

    func runLocalWhisper(fileURL: URL?) async {
        localDetail = ""
        localText = ""
        busyLocal = true
        defer { busyLocal = false }
        guard let url = fileURL, FileManager.default.fileExists(atPath: url.path) else {
            localDetail = "请先完成麦克风试录，或提供有效音频文件。"
            return
        }
        if !AppState.shared.localWhisperReady, AppState.shared.localWhisperLoading {
            localDetail = "本地模型仍在加载，请稍后重试。"
            return
        }
        let start = CFAbsoluteTimeGetCurrent()
        do {
            let t = try await WhisperASRFallback.shared.transcribe(fileURL: url)
            let ms = (CFAbsoluteTimeGetCurrent() - start) * 1000
            localText = t
            localDetail = String(format: "耗时 %.0f ms；若为空可能无有效语音。", ms)
            if t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                localDetail += " 结果为空。"
            }
        } catch {
            localDetail = error.localizedDescription
        }
    }

    func runCloudASR(fileURL: URL?) async {
        cloudText = ""
        cloudDetail = ""
        busyCloud = true
        defer { busyCloud = false }
        if !NetworkMonitor.shared.isConnected {
            cloudDetail = "当前无网络，无法请求云端 ASR。"
            return
        }
        // 优先：自建代理上传真实试录文件（与主链路一致；Bearer 或内部密钥）
        let canUseProxy = AppConfig.asrProxyTranscribeURL != nil
            && (!(AppConfig.asrInternalKey ?? "").isEmpty || AppConfig.hasDashScopeAPIKey)
        if canUseProxy {
            guard let url = fileURL, FileManager.default.fileExists(atPath: url.path) else {
                cloudDetail = "已配置代理，请先完成上方麦克风试录再测云端。"
                return
            }
            let start = CFAbsoluteTimeGetCurrent()
            if let result = await DashScopeASRClient.transcribeViaProxyIfConfigured(url) {
                let ms = (CFAbsoluteTimeGetCurrent() - start) * 1000
                cloudText = result
                cloudDetail = String(format: "代理 Paraformer 成功，耗时约 %.0f ms。", ms)
                return
            }
            cloudDetail = "已配置代理但识别失败。请检查后端（OSS、百炼 Key 与后端一致）或高级里的代理 URL / 内部密钥。"
            return
        }
        if !AppConfig.hasDashScopeAPIKey {
            cloudDetail = "未配置百炼 API Key；或未配置服务基址/代理并完成试录。"
            return
        }
        // W4-01 后云端 ASR 走 WebSocket 流式，无法在诊断面板独立触发（需真实录音）
        cloudDetail = "已配置百炼 API Key，云端 ASR 走 WebSocket 流式（W4-01）。请用热键录音验证完整链路。"
    }

    func runPolish() async {
        polishText = ""
        polishDetail = ""
        busyPolish = true
        defer { busyPolish = false }
        if !NetworkMonitor.shared.isConnected {
            polishDetail = "当前无网络；无 Key 时润色会降级为原文。"
        }
        let system = PromptComposer.systemPrompt(for: nil)
        let user = Prompts.polishUserMessage(asrText: "这是一个用于诊断的固定测试句子。")
        let start = CFAbsoluteTimeGetCurrent()
        let out = await PolishService.polishPlain(system: system, user: user)
        let ms = (CFAbsoluteTimeGetCurrent() - start) * 1000
        polishText = out
        if !AppConfig.hasDashScopeAPIKey {
            polishDetail = String(format: "耗时 %.0f ms；未配置 API Key，输出为降级原文。", ms)
        } else {
            polishDetail = String(format: "耗时 %.0f ms。", ms)
        }
    }
}

struct AIDiagnosticsSection: View {
    @EnvironmentObject private var mic: MicTestController
    @StateObject private var ai = AIDiagnosticsController()

    var body: some View {
        GroupBox("AI 诊断（分段）") {
            VStack(alignment: .leading, spacing: 14) {
                Text("各段独立测试；与主链路差异见文案。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Group {
                    Text("AI1 · 本地 Whisper").font(.subheadline.weight(.medium))
                    HStack {
                        Button("运行本地转写") {
                            Task { await ai.runLocalWhisper(fileURL: mic.lastURL) }
                        }
                        .disabled(ai.busyLocal)
                        if ai.busyLocal { ProgressView().controlSize(.small) }
                    }
                    if !ai.localDetail.isEmpty {
                        Text(ai.localDetail).font(.caption).foregroundStyle(.secondary)
                    }
                    if !ai.localText.isEmpty {
                        Text(ai.localText).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                    }
                }

                Divider()

                Group {
                    Text("AI1 · 云端 Paraformer").font(.subheadline.weight(.medium))
                    HStack {
                        Button("请求云端（样例 URL）") {
                            Task { await ai.runCloudASR(fileURL: mic.lastURL) }
                        }
                        .disabled(ai.busyCloud)
                        if ai.busyCloud { ProgressView().controlSize(.small) }
                    }
                    if !ai.cloudDetail.isEmpty {
                        Text(ai.cloudDetail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    if !ai.cloudText.isEmpty {
                        Text(ai.cloudText).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                    }
                }

                Divider()

                Group {
                    Text("AI2 · 润色").font(.subheadline.weight(.medium))
                    HStack {
                        Button("运行润色诊断") {
                            Task { await ai.runPolish() }
                        }
                        .disabled(ai.busyPolish)
                        if ai.busyPolish { ProgressView().controlSize(.small) }
                    }
                    if !ai.polishDetail.isEmpty {
                        Text(ai.polishDetail).font(.caption).foregroundStyle(.secondary)
                    }
                    if !ai.polishText.isEmpty {
                        Text(ai.polishText).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                    }
                }
            }
            .padding(8)
        }
    }
}

// MARK: - 最近问题（W4-P05）

struct RecentIssuesSection: View {
    @ObservedObject private var state = AppState.shared

    var body: some View {
        GroupBox("最近问题") {
            VStack(alignment: .leading, spacing: 8) {
                if let n = state.networkOfflineHint {
                    HStack(alignment: .top) {
                        Image(systemName: "wifi.slash")
                            .foregroundStyle(.orange)
                        Text(n)
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if let e = state.lastPipelineError {
                    HStack(alignment: .top) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(e)
                            .font(.caption)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if let a = state.polishAttentionMessage {
                    HStack(alignment: .top) {
                        Image(systemName: "info.circle.fill")
                            .foregroundStyle(.orange)
                        Text(a)
                            .font(.caption)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if state.networkOfflineHint == nil, state.lastPipelineError == nil, state.polishAttentionMessage == nil {
                    Text("暂无最近问题。")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                HStack {
                    Button("复制全部摘要") {
                        let parts = [state.networkOfflineHint, state.lastPipelineError, state.polishAttentionMessage].compactMap { $0 }
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(parts.joined(separator: "\n"), forType: .string)
                    }
                    .disabled(state.networkOfflineHint == nil && state.lastPipelineError == nil && state.polishAttentionMessage == nil)
                    Button("清除摘要显示") {
                        state.lastPipelineError = nil
                        state.polishAttentionMessage = nil
                    }
                    .disabled(state.lastPipelineError == nil && state.polishAttentionMessage == nil)
                }
                .font(.caption)
            }
            .padding(8)
        }
    }
}
