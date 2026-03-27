//
//  PipelineStatusWriter.swift
//  vilsay
//
//  `VILSAY_TECH_SPEC_SUPPLEMENT` §1.2：合法转换；非法转换忽略并打日志。

import os.log

@MainActor
enum PipelineStatusWriter {
    private static let log = Logger(subsystem: "com.vilsay.app", category: "PipelineStatus")

    /// 尝试切换主链路状态；非法转换时**不修改** `AppState.status`。
    static func transition(to new: AppStatus, reason: String = "") {
        let old = AppState.shared.status
        guard old != new else { return }
        guard isValidTransition(from: old, to: new) else {
            Self.log.warning("忽略非法状态转换 \(String(describing: old)) → \(String(describing: new)) \(reason)")
            return
        }
        AppState.shared.status = new
        if !reason.isEmpty {
            Self.log.debug("状态 \(String(describing: old)) → \(String(describing: new))：\(reason)")
        }
    }

    private static func isValidTransition(from old: AppStatus, to new: AppStatus) -> Bool {
        switch (old, new) {
        case (.idle, .recording), (.idle, .editMode): return true
        case (.recording, .idle), (.recording, .processing): return true
        case (.editMode, .idle), (.editMode, .processing): return true
        case (.processing, .injecting), (.processing, .idle), (.processing, .error), (.processing, .attention): return true
        case (.injecting, .idle), (.injecting, .error), (.injecting, .attention): return true
        case (_, .error): return true
        case (.error, .idle), (.error, .attention): return true
        case (.attention, .idle), (.attention, .recording), (.attention, .processing), (.attention, .editMode): return true
        case (.idle, .processing): return false
        case (.idle, .injecting): return false
        case (.recording, .injecting): return false
        case (.injecting, .recording): return false
        case (.processing, .recording): return false
        default:
            return false
        }
    }
}
