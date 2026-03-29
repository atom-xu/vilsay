//
//  DashScopeStreamingASRClient.swift
//  W4-01：DashScope Paraformer 实时识别（WebSocket / run-task → 二进制音频 → finish-task）。
//

import Foundation
import os

/// 使用 `OSLog` 而非 `Logger`，避免 Swift 6 下在 `Task.detached` 等非隔离上下文中访问 MainActor 隔离的日志句柄。
private let dashScopeStreamingASRLog = OSLog(subsystem: "com.vilsay.app", category: "DashScopeStreamingASR")

/// DashScope 实时语音识别 WebSocket 客户端（`wss://dashscope.aliyuncs.com/api-ws/v1/inference/`）。
/// 失败静默，由 `Pipeline` 回退 Whisper。
/// 不继承 `NSObject`，避免 Swift 6 下 NSObject 子类与 `Task.detached` 交叉时的 MainActor 隔离推断问题。
final class DashScopeStreamingASRClient: @unchecked Sendable {
    static let shared = DashScopeStreamingASRClient()

    var onPartialText: ((String) -> Void)?
    var onFinalText: ((String) -> Void)?

    private(set) var isConnected = false
    private var finalText: String?

    private var webSocket: URLSessionWebSocketTask?
    private var activeSession: URLSession?   // 持有 per-session URLSession，防 ARC 释放
    private var sessionTaskId: String?
    private var receiveTask: Task<Void, Never>?
    private var taskReady = false
    private var taskFinished = false

    private let stateLock = NSLock()

    private init() {}

    /// 无 API Key 时直接返回；不抛错。
    func startSession(taskId: UUID, apiKey: String, model: String) async {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }

        cancel()

        let tid = taskId.uuidString
        stateLock.withLock {
            sessionTaskId = tid
            finalText = nil
            taskReady = false
            taskFinished = false
        }

        // 用 session 级 httpAdditionalHeaders 传递 Authorization，比 URLRequest 级更可靠
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = ["Authorization": "Bearer \(key)"]
        let session = URLSession(configuration: config, delegate: nil, delegateQueue: nil)

        let wsURL = URL(string: "wss://dashscope.aliyuncs.com/api-ws/v1/inference/")!
        let ws = session.webSocketTask(with: wsURL)
        stateLock.withLock {
            webSocket = ws
            activeSession = session
            isConnected = true
        }

        ws.resume()

        let runPayload: [String: Any] = [
            "header": [
                "action": "run-task",
                "task_id": tid,
                "streaming": "duplex",
            ] as [String: Any],
            "payload": [
                "task_group": "audio",
                "task": "asr",
                "function": "recognition",
                "model": model,
                "parameters": [
                    "format": "pcm",
                    "sample_rate": 16000,
                    "language_hints": ASRSpokenLanguage.currentFromDefaults().dashScopeStreamingHints,
                ] as [String: Any],
                "input": [:] as [String: Any],
            ] as [String: Any],
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: runPayload, options: []),
              let jsonStr = String(data: data, encoding: .utf8) else {
            os_log(.error, log: dashScopeStreamingASRLog, "run-task JSON 构建失败")
            cancel()
            return
        }

        await sendString(ws, text: jsonStr)

        receiveTask = Task.detached { [weak self] in
            await self?.receiveLoopBody(ws: ws)
        }

        // 不在调用方 await 链上阻塞：慢网时握手可在后台完成；send() 在 taskReady 前会丢弃 PCM。
        scheduleTaskStartedTimeout()
    }

    /// 最长等待 task-started，超时则 cancel（仅用于流式兜底失败，不阻塞 `beginRecordingSession`）。
    private func scheduleTaskStartedTimeout() {
        Task.detached { [weak self] in
            guard let self else { return }
            let deadline = Date().addingTimeInterval(8)
            while Date() < deadline {
                let ready = self.stateLock.withLock { self.taskReady }
                if ready { return }
                try? await Task.sleep(nanoseconds: 40_000_000)
            }
            let ok = self.stateLock.withLock { self.taskReady }
            if !ok {
                os_log(.default, log: dashScopeStreamingASRLog, "未收到 task-started，放弃本次流式 ASR")
                await MainActor.run { self.cancel() }
            }
        }
    }

    func send(pcmChunk: Data) {
        let (ready, ws, connected) = stateLock.withLock {
            (taskReady, webSocket, isConnected)
        }
        guard ready, connected, let ws, !pcmChunk.isEmpty else { return }

        ws.send(.data(pcmChunk)) { [weak self] err in
            if let err {
                os_log(.debug, log: dashScopeStreamingASRLog, "WebSocket send PCM 失败: %{public}@", err.localizedDescription)
                guard let self else { return }
                self.stateLock.withLock { self.isConnected = false }
            }
        }
    }

    func finishTask() async {
        let (ws, tid, alreadyDone) = stateLock.withLock {
            (webSocket, sessionTaskId, taskFinished)
        }
        // WebSocket 握手失败时 taskFinished 已为 true；跳过 send 避免 CheckedContinuation 泄漏
        guard let ws, let tid, !alreadyDone else { return }

        let finishPayload: [String: Any] = [
            "header": [
                "action": "finish-task",
                "task_id": tid,
                "streaming": "duplex",
            ] as [String: Any],
            "payload": [
                "input": [:] as [String: Any],
            ],
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: finishPayload, options: []),
              let jsonStr = String(data: data, encoding: .utf8) else {
            return
        }

        await sendString(ws, text: jsonStr)

        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            let done = stateLock.withLock { taskFinished }
            if done { break }
            try? await Task.sleep(nanoseconds: 40_000_000)
        }

        cancelAfterFinish()
    }

    func cancel() {
        receiveTask?.cancel()
        receiveTask = nil
        // 先把 WebSocket 取出再释放锁，避免 cancel(with:) 在锁内阻塞导致其他调用方死锁
        let ws = stateLock.withLock { () -> URLSessionWebSocketTask? in
            let w = webSocket
            webSocket = nil
            activeSession = nil
            isConnected = false
            taskReady = false
            taskFinished = false  // 重置 taskFinished 状态
            sessionTaskId = nil
            return w
        }
        ws?.cancel(with: .goingAway, reason: nil)
    }

    /// 供 `Pipeline` 在消费识别结果后清空。
    func clearFinalText() {
        stateLock.withLock { finalText = nil }
    }

    /// 线程安全读取聚合识别结果（`finishTask` 之后调用）。
    func snapshotFinalText() -> String? {
        stateLock.withLock { finalText }
    }

    private func cancelAfterFinish() {
        receiveTask?.cancel()
        receiveTask = nil
        let ws = stateLock.withLock { () -> URLSessionWebSocketTask? in
            let w = webSocket
            webSocket = nil
            activeSession = nil
            isConnected = false
            taskReady = false
            taskFinished = false  // 重置 taskFinished 状态，为下次会话准备
            sessionTaskId = nil
            return w
        }
        ws?.cancel(with: .normalClosure, reason: nil)
    }

    private func sendString(_ ws: URLSessionWebSocketTask, text: String) async {
        // 使用 withTimeout 模式：使用 TaskGroup 配合 race
        await withTaskGroup(of: Void.self) { group in
            var sendCompleted = false
            let lock = NSLock()
            
            // WebSocket send 任务
            group.addTask {
                await withUnsafeContinuation { (cont: UnsafeContinuation<Void, Never>) in
                    ws.send(.string(text)) { _ in
                        lock.withLock { sendCompleted = true }
                        cont.resume()
                    }
                }
            }
            
            // 超时任务
            group.addTask {
                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2s 超时兜底
            }
            
            // 等待任一任务完成
            _ = await group.next()

            let completed = lock.withLock { sendCompleted }

            if !completed {
                os_log(.debug, log: dashScopeStreamingASRLog, "WebSocket send 超时（2秒）")
            }
            
            // 取消其他任务（超时任务或等待 send 回调）
            group.cancelAll()
        }
    }

    private func receiveLoopBody(ws: URLSessionWebSocketTask) async {
        while !Task.isCancelled {
            do {
                let message = try await ws.receive()
                switch message {
                case .string(let text):
                    parseEventJSON(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        parseEventJSON(text)
                    }
                @unknown default:
                    break
                }
            } catch {
                os_log(.debug, log: dashScopeStreamingASRLog, "WebSocket receive 结束: %{public}@", error.localizedDescription)
                stateLock.withLock {
                    taskFinished = true
                    isConnected = false  // 接收循环结束时标记为未连接
                }
                break
            }
        }
    }

    private func parseEventJSON(_ text: String) {
        guard let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let header = obj["header"] as? [String: Any],
              let event = header["event"] as? String else {
            return
        }

        switch event {
        case "task-started":
            stateLock.withLock { taskReady = true }

        case "result-generated":
            guard let payload = obj["payload"] as? [String: Any],
                  let output = payload["output"] as? [String: Any],
                  let sentence = output["sentence"] as? [String: Any],
                  let t = sentence["text"] as? String else {
                return
            }
            let sentenceEnd = sentence["sentence_end"] as? Bool ?? false
            if sentenceEnd {
                let combined = stateLock.withLock { () -> String? in
                    if let prev = finalText, !prev.isEmpty {
                        finalText = prev + "\n" + t
                    } else {
                        finalText = t
                    }
                    return finalText
                }
                if let combined {
                    onFinalText?(combined)
                }
            } else {
                onPartialText?(t)
            }

        case "task-finished":
            stateLock.withLock { taskFinished = true }

        case "task-failed":
            os_log(.default, log: dashScopeStreamingASRLog, "task-failed: %{public}@", text)
            stateLock.withLock { taskFinished = true }

        default:
            break
        }
    }
}
