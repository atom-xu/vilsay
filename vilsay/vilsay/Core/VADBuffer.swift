//
//  VADBuffer.swift
//  vilsay
//

import Foundation

/// W3-05：基于「文本更新时间」的 800ms 停顿检测；**流式 ASR** 时对 `feed` 的增量做停顿判定，停顿后触发 `onSentenceComplete`。
///
/// - **流式**：反复 `feed(部分文本)`，无新文本超过 `pauseMs` 则视为一句结束；结束时也可 `flush()` 立即送出当前缓冲。
/// - **整段文件 ASR**（当前主路径）：转写完成后调用 **`acceptFinalTranscript`**，取消待定计时并立即触发一次回调（与 Pipeline 统一出口）。
final class VADBuffer {
    var onSentenceComplete: ((String) -> Void)?

    private var buffer = ""
    private var workItem: DispatchWorkItem?
    private let pauseNs: UInt64
    private let queue = DispatchQueue(label: "vilsay.vadbuffer")

    init(pauseMs: UInt64 = Constants.vadPauseMs) {
        self.pauseNs = pauseMs * NSEC_PER_MSEC
    }

    func feed(_ text: String) {
        queue.async { [weak self] in
            guard let self else { return }
            self.buffer = text
            self.workItem?.cancel()
            let captured = text
            let item = DispatchWorkItem { [weak self] in
                self?.emitIfNeeded(captured)
            }
            self.workItem = item
            self.queue.asyncAfter(deadline: .now() + .nanoseconds(Int(self.pauseNs)), execute: item)
        }
    }

    /// 流式结束或需立即提交当前缓冲时调用（取消 800ms 定时器并送出 `buffer`）。
    func flush() {
        queue.async { [weak self] in
            guard let self else { return }
            self.workItem?.cancel()
            let t = self.buffer.trimmingCharacters(in: .whitespacesAndNewlines)
            self.buffer = ""
            if !t.isEmpty {
                DispatchQueue.main.async { [self] in self.onSentenceComplete?(t) }
            }
        }
    }

    /// 文件级 ASR 得到**最终一句**时调用：清空待定计时，在主线程触发一次 `onSentenceComplete`（不经 800ms 等待）。
    func acceptFinalTranscript(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        queue.async { [weak self] in
            self?.workItem?.cancel()
            self?.buffer = ""
        }
        // 强引用：确保 VADBuffer 在主线程回调执行前不被 ARC 释放（[weak self] 会导致 continuation 泄漏）
        DispatchQueue.main.async { [self] in
            self.onSentenceComplete?(t)
        }
    }

    private func emitIfNeeded(_ expected: String) {
        let t = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t == expected.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return }
        buffer = ""
        DispatchQueue.main.async { [weak self] in
            self?.onSentenceComplete?(t)
        }
    }
}
