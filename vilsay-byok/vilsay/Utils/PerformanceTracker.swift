//
//  PerformanceTracker.swift
//

import Foundation
import os.log

/// 主链路各阶段耗时（Console / 统一日志格式）。
enum PerformanceTracker {
    private static let log = Logger(subsystem: "com.vilsay.app", category: "Performance")

    static func logPipeline(asrMs: Double, polishMs: Double, injectMs: Double, firstTokenMs: Double? = nil, reviewMs: Double? = nil) {
        let total = asrMs + polishMs + injectMs + (reviewMs ?? 0)
        var msg = "[Performance] ASR: \(Int(asrMs))ms | Polish: \(Int(polishMs))ms"
        if let ft = firstTokenMs {
            msg += " (首字: \(Int(ft))ms)"
        }
        if let rv = reviewMs {
            msg += " | Review: \(Int(rv))ms"
        }
        msg += " | Inject: \(Int(injectMs))ms | Total: \(Int(total))ms"
        log.notice("\(msg)")
        if total > Double(Constants.maxTotalLatencyMs) {
            log.warning("[Performance] 总耗时超过 W6-03 目标 \(Constants.maxTotalLatencyMs)ms：\(Int(total))ms")
        }
    }
}
