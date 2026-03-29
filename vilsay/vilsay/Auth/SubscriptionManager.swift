//
//  SubscriptionManager.swift
//  StoreKit 2 自动续期订阅管理：购买、恢复、状态监听。
//

import Combine
import Foundation
import os.log
import StoreKit

@MainActor
final class SubscriptionManager: ObservableObject {
    static let shared = SubscriptionManager()

    private static let log = Logger(subsystem: "com.vilsay.app", category: "Subscription")

    static let proMonthlyID = "vilhil.cn.vilsay.pro.monthly"

    // MARK: - Published State

    /// 当前 Pro 产品（从 App Store 拉取）。
    @Published private(set) var proProduct: Product?
    /// 当前有效订阅（`nil` 表示无有效订阅）。
    @Published private(set) var currentEntitlement: Transaction?
    /// 购买流程进行中。
    @Published private(set) var isPurchasing = false
    /// 上次操作的错误信息。
    @Published var lastError: String?

    /// 是否拥有有效 Pro 订阅（本地 StoreKit 验证）。
    /// BYOK 版始终返回 true（用户自备 Key，功能全开）。
    var isProEntitled: Bool {
        #if BYOK_ONLY
        return true
        #else
        return currentEntitlement != nil
        #endif
    }

    private var transactionListener: Task<Void, Never>?

    // MARK: - Lifecycle

    private init() {}

    /// 应用启动时调用：拉取产品 + 检查现有订阅 + 启动交易监听。
    /// BYOK 版本：跳过所有 StoreKit 调用。
    func start() {
        #if BYOK_ONLY
        return  // BYOK 版无内购，跳过 StoreKit 初始化
        #else
        transactionListener?.cancel()
        transactionListener = listenForTransactions()
        Task {
            await loadProduct()
            await refreshEntitlement()
        }
        #endif
    }

    func stop() {
        transactionListener?.cancel()
        transactionListener = nil
    }

    // MARK: - Product

    private func loadProduct() async {
        do {
            let products = try await Product.products(for: [Self.proMonthlyID])
            proProduct = products.first
            if proProduct == nil {
                Self.log.warning("⚠️ 未找到产品 \(Self.proMonthlyID)，请检查 App Store Connect 配置")
            } else {
                Self.log.info("✅ 已加载产品: \(self.proProduct!.displayName) — \(self.proProduct!.displayPrice)")
            }
        } catch {
            Self.log.error("❌ 加载产品失败: \(error.localizedDescription)")
        }
    }

    // MARK: - Purchase

    func purchase() async {
        guard let product = proProduct else {
            lastError = "产品信息未加载，请稍后再试"
            return
        }
        guard !isPurchasing else { return }

        isPurchasing = true
        lastError = nil
        defer { isPurchasing = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()
                currentEntitlement = transaction
                Self.log.info("✅ 购买成功")
                await syncPlanWithBackend(isPro: true)

            case .userCancelled:
                Self.log.info("ℹ️ 用户取消购买")

            case .pending:
                Self.log.info("ℹ️ 购买待批准（家长控制等）")
                lastError = "购买待审批，请稍后检查"

            @unknown default:
                Self.log.warning("⚠️ 未知购买结果")
            }
        } catch {
            Self.log.error("❌ 购买失败: \(error.localizedDescription)")
            lastError = "购买失败：\(error.localizedDescription)"
        }
    }

    // MARK: - Restore

    func restore() async {
        do {
            try await AppStore.sync()
            await refreshEntitlement()
            Self.log.info("✅ 恢复购买完成")
        } catch {
            Self.log.error("❌ 恢复购买失败: \(error.localizedDescription)")
            lastError = "恢复失败：\(error.localizedDescription)"
        }
    }

    // MARK: - Entitlement

    /// 检查当前是否有有效的 Pro 订阅权益。
    func refreshEntitlement() async {
        var foundActive: Transaction?
        for await result in Transaction.currentEntitlements {
            if let tx = try? checkVerified(result), tx.productID == Self.proMonthlyID {
                foundActive = tx
                break
            }
        }
        let wasEntitled = currentEntitlement != nil
        currentEntitlement = foundActive

        // 同步到 AuthService
        if isProEntitled != wasEntitled {
            await syncPlanWithBackend(isPro: isProEntitled)
        }
    }

    // MARK: - Transaction Listener

    /// 监听来自 App Store 的交易更新（续费、退款、家长审批等）。
    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                if let tx = try? await self.checkVerified(result) {
                    await tx.finish()
                    await self.refreshEntitlement()
                }
            }
        }
    }

    // MARK: - Verification

    private func checkVerified(_ result: VerificationResult<Transaction>) throws -> Transaction {
        switch result {
        case .unverified(_, let error):
            Self.log.error("❌ 交易验证失败: \(error.localizedDescription)")
            throw error
        case .verified(let transaction):
            return transaction
        }
    }

    // MARK: - Backend Sync

    /// 将本地 StoreKit 订阅状态同步到后端（更新 `plan` + 到期时间）。
    private func syncPlanWithBackend(isPro: Bool) async {
        guard let token = KeychainTokenStore.loadToken(), !token.isEmpty else { return }
        guard let baseURL = AppConfig.backendAPIBaseURL else { return }
        guard let url = URL(string: "\(baseURL)/api/v1/subscription/sync") else { return }

        var body: [String: Any] = ["plan": isPro ? "pro" : "free"]

        // 携带 StoreKit transaction 详情
        if isPro, let tx = currentEntitlement {
            body["original_transaction_id"] = String(tx.originalID)
            body["product_id"] = tx.productID
            if let exp = tx.expirationDate {
                body["expires_date_ms"] = Int(exp.timeIntervalSince1970 * 1000)
            }
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 10

        do {
            let (_, response) = try await URLSession.shared.data(for: req)
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            if (200...299).contains(code) {
                Self.log.info("✅ 后端 plan 同步成功: \(isPro ? "pro" : "free")")
                await AuthService.shared.refreshUsage()
            } else {
                Self.log.warning("⚠️ 后端 plan 同步 HTTP \(code)")
            }
        } catch {
            Self.log.warning("⚠️ 后端 plan 同步网络错误: \(error.localizedDescription)")
        }
    }
}
