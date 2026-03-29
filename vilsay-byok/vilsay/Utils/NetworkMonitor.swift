//
//  NetworkMonitor.swift
//  vilsay
//

import Foundation
import Network

/// 简单在线状态（用于云端 ASR / 润色降级判断与 Week 4 弱网提示）。
final class NetworkMonitor {
    static let shared = NetworkMonitor()

    private(set) var isConnected = true
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "vilsay.network")

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let ok = path.status == .satisfied
            self?.isConnected = ok
            DispatchQueue.main.async {
                AppState.shared.networkOfflineHint = ok ? nil : "当前无网络，云端识别与在线润色不可用。"
            }
        }
        monitor.start(queue: queue)
    }
}
