//
//  AudioCapture.swift
//

import AVFoundation
import Foundation
import os.log

/// W3-02 / W4-01：麦克风录音，16kHz 单声道 PCM；`AVAudioEngine` + tap 同时流式回调与写 `.wav`（Whisper 兜底）。
///
/// MainActor 竞态（Step 1）：HAL 操作在 `com.vilsay.app.audiocapture` 串行队列执行；`start()` 为 `async`。
final class AudioCapture {
    private static let log = Logger(subsystem: "com.vilsay.app", category: "AudioCapture")

    private let queue = DispatchQueue(label: "com.vilsay.app.audiocapture")
    private var engine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var fileURLInternal: URL?
    private var converter: AVAudioConverter?
    private var targetFormat: AVAudioFormat?
    /// 累计 16kHz PCM，按 ~100ms（1600 帧）切块回调。
    private var pcmAccum = Data()
    private let chunkBytes = 1600 * 2 // 16-bit mono

    private let chunkLock = NSLock()
    private var _onPCMChunk: ((Data) -> Void)?
    /// W6：约 50ms 回调一次 RMS（0～1），供浮层波形。
    var onAudioLevelUpdate: ((Float) -> Void)?
    private var lastAudioLevelEmit = CFAbsoluteTimeGetCurrent()
    /// 流式 ASR：tap 线程调用；设置/清除在主线程或其它线程均可。
    var onPCMChunk: ((Data) -> Void)? {
        get {
            chunkLock.lock()
            defer { chunkLock.unlock() }
            return _onPCMChunk
        }
        set {
            chunkLock.lock()
            defer { chunkLock.unlock() }
            _onPCMChunk = newValue
        }
    }

    /// 从任意线程读当前录音文件（与 `queue` 同步）。
    var fileURL: URL? {
        queue.sync { fileURLInternal }
    }

    func start() async throws {
        if DiagnosticsExclusion.excludeMicrophoneHAL {
            Self.log.warning("🧪 AudioCapture：VILSAY_EXCLUDE_MIC_HAL 兜底短路，不创建 AVAudioEngine")
            throw AudioCaptureError.excludedForDiagnostics
        }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("vilsay-\(UUID().uuidString).wav")

        Self.log.info("开始录音准备（AVAudioEngine）… \(url.path)")

        let once = StartContinuationBox()
        let sleepTask = Task {
            try await Task.sleep(nanoseconds: Constants.audioStartTimeoutNanoseconds)
            once.resumeFailure(AudioCaptureError.recordStartTimeout)
        }
        defer { sleepTask.cancel() }

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            once.install(cont)
            queue.async { [weak self] in
                guard let self else {
                    once.resumeFailure(AudioCaptureError.recordStartFailed)
                    return
                }
                do {
                    guard let target = AVAudioFormat(
                        commonFormat: .pcmFormatInt16,
                        sampleRate: 16_000,
                        channels: 1,
                        interleaved: true
                    ) else {
                        throw AudioCaptureError.recordStartFailed
                    }

                    let eng = AVAudioEngine()
                    let input = eng.inputNode
                    let hwFormat = input.outputFormat(forBus: 0)

                    guard let conv = AVAudioConverter(from: hwFormat, to: target) else {
                        throw AudioCaptureError.recordStartFailed
                    }

                    let outSettings = target.settings
                    let audioFile = try AVAudioFile(forWriting: url, settings: outSettings, commonFormat: target.commonFormat, interleaved: target.isInterleaved)

                    let bufferSize = AVAudioFrameCount(max(1024, UInt32(hwFormat.sampleRate * 0.1)))

                    input.installTap(onBus: 0, bufferSize: bufferSize, format: hwFormat) { [weak self] buffer, _ in
                        self?.handleTapBuffer(buffer, converter: conv, target: target, audioFile: audioFile)
                    }

                    eng.prepare()
                    try eng.start()

                    self.engine = eng
                    self.audioFile = audioFile
                    self.converter = conv
                    self.targetFormat = target
                    self.fileURLInternal = url
                    self.pcmAccum = Data()

                    Self.log.info("✅ AVAudioEngine 录音启动成功")
                    once.resumeSuccessOrCleanup(self)
                } catch {
                    self.engine = nil
                    self.audioFile = nil
                    self.converter = nil
                    self.targetFormat = nil
                    self.fileURLInternal = nil
                    self.pcmAccum = Data()
                    self.logFailure(error)
                    once.resumeFailure(error)
                }
            }
        }
    }

    /// FIX-06：`start()` 与 5s 超时竞速，continuation 只 resume 一次。
    private final class StartContinuationBox: @unchecked Sendable {
        private let lock = NSLock()
        private var cont: CheckedContinuation<Void, Error>?

        func install(_ c: CheckedContinuation<Void, Error>) {
            cont = c
        }

        func resumeSuccessOrCleanup(_ capture: AudioCapture) {
            lock.lock()
            defer { lock.unlock() }
            guard let c = cont else {
                capture.queue.async { capture.tearDownEngineForAbortedStart() }
                return
            }
            cont = nil
            c.resume()
        }

        func resumeFailure(_ error: Error) {
            lock.lock()
            defer { lock.unlock() }
            guard let c = cont else { return }
            cont = nil
            c.resume(throwing: error)
        }
    }

    /// 超时已返回后队列线程才完成启动时拆除引擎。
    private func tearDownEngineForAbortedStart() {
        if engine != nil {
            Self.log.warning("录音启动竞态：已超时，拆除半初始化引擎")
        }
        if let eng = engine {
            eng.inputNode.removeTap(onBus: 0)
            eng.stop()
        }
        engine = nil
        audioFile = nil
        converter = nil
        targetFormat = nil
        if let url = fileURLInternal {
            try? FileManager.default.removeItem(at: url)
        }
        fileURLInternal = nil
        pcmAccum = Data()
    }

    private func handleTapBuffer(_ buffer: AVAudioPCMBuffer, converter: AVAudioConverter, target: AVAudioFormat, audioFile: AVAudioFile) {
        let ratio = target.sampleRate / buffer.format.sampleRate
        let outCapacity = AVAudioFrameCount(ceil(Double(buffer.frameLength) * ratio)) + 32
        guard let outBuf = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: outCapacity) else { return }

        var inBuf: AVAudioPCMBuffer? = buffer
        var error: NSError?
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            guard let ib = inBuf else {
                outStatus.pointee = .noDataNow
                return nil
            }
            inBuf = nil
            outStatus.pointee = .haveData
            return ib
        }

        converter.convert(to: outBuf, error: &error, withInputFrom: inputBlock)
        if let error {
            Self.log.error("AVAudioConverter: \(error.localizedDescription)")
            return
        }
        guard outBuf.frameLength > 0 else { return }

        do {
            try audioFile.write(from: outBuf)
        } catch {
            Self.log.error("AVAudioFile 写入失败: \(error.localizedDescription)")
        }

        guard let ch = outBuf.int16ChannelData else { return }
        let n = Int(outBuf.frameLength)
        let byteCount = n * MemoryLayout<Int16>.size
        ch[0].withMemoryRebound(to: UInt8.self, capacity: byteCount) { ptr in
            pcmAccum.append(Data(bytes: ptr, count: byteCount))
        }

        while pcmAccum.count >= chunkBytes {
            let chunk = pcmAccum.prefix(chunkBytes)
            pcmAccum.removeFirst(chunkBytes)
            let data = Data(chunk)
            if let cb = onPCMChunk {
                cb(data)
            }
        }

        var sum: Float = 0
        for i in 0 ..< n {
            let v = Float(ch[0][i]) / 32768.0
            sum += v * v
        }
        let rms = sqrt(sum / Float(n))
        let normalized = min(1, rms * 18)
        let now = CFAbsoluteTimeGetCurrent()
        if now - lastAudioLevelEmit >= 0.05, let cb = onAudioLevelUpdate {
            lastAudioLevelEmit = now
            DispatchQueue.main.async {
                cb(normalized)
            }
        }
    }

    private func logFailure(_ error: Error) {
        if let ne = error as NSError? {
            Self.log.error("录音失败 - domain: \(ne.domain), code: \(ne.code), description: \(ne.localizedDescription)")
            if let underlyingError = ne.userInfo[NSUnderlyingErrorKey] as? NSError {
                Self.log.error("  底层错误 - domain: \(underlyingError.domain), code: \(underlyingError.code)")
            }
        } else {
            Self.log.error("录音失败: \(error.localizedDescription)")
        }
    }

    func stop() {
        queue.sync {
            Self.log.info("停止录音（AVAudioEngine）")
            if let eng = engine {
                eng.inputNode.removeTap(onBus: 0)
                eng.stop()
            }
            engine = nil
            converter = nil
            targetFormat = nil
            audioFile = nil
            onAudioLevelUpdate = nil
            chunkLock.lock()
            let tail = pcmAccum
            let cb = _onPCMChunk
            pcmAccum = Data()
            _onPCMChunk = nil
            chunkLock.unlock()
            if !tail.isEmpty, let cb {
                cb(tail)
            }
        }
    }

    func discardFile() {
        queue.sync {
            if let url = fileURLInternal {
                Self.log.info("删除录音文件: \(url.path)")
                try? FileManager.default.removeItem(at: url)
            }
            fileURLInternal = nil
        }
    }

    enum AudioCaptureError: Error, LocalizedError {
        case recordStartFailed
        case recordStartTimeout
        /// 诊断：`VILSAY_EXCLUDE_MIC_HAL` / `VILSAY_NO_MIC` 开启时故意不碰 HAL。
        case excludedForDiagnostics

        var errorDescription: String? {
            switch self {
            case .recordStartFailed:
                return "无法启动录音。请检查麦克风权限或音频设备是否可用。"
            case .recordStartTimeout:
                return "麦克风启动超时，请检查系统隐私设置或音频设备。"
            case .excludedForDiagnostics:
                return "（诊断）已跳过麦克风/HAL"
            }
        }
    }
}
