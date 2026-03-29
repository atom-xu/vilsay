//
//  AuthService.swift
//  vilsay
//

import Combine
import Foundation

private enum Keys {
    static let savedEmail = "vilsay.auth.email"
}

struct AuthLoginRequest: Encodable {
    let email: String
    let password: String
}

struct AuthRegisterRequest: Encodable {
    let email: String
    let password: String
}

struct AuthRegisterResponse: Decodable {
    let message: String
    let verificationToken: String?
}

struct AuthUserDTO: Decodable {
    let email: String
}

struct AuthTokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String?
    let tokenType: String?
    let user: AuthUserDTO?
}

struct AuthRefreshRequest: Encodable {
    let refreshToken: String
}

struct AuthUsageCurrent: Decodable {
    let used: Int
    let quota: Int
    let yearMonth: String
    /// 后端返回 "pro" / "free"；字段可选，缺省视为 free。
    let plan: String?
}

struct AuthVerifyStatusResponse: Decodable {
    let verified: Bool
}

/// `POST /usage/record`（`VILSAY_TECH_SPEC_SUPPLEMENT` §3.4）
struct UsageRecordAPIRequest: Encodable {
    let type: String
    let durationMs: Int
    let asrProvider: String
    let clientVersion: String
    let charCount: Int
}

struct UsageRecordAPIResponse: Decodable {
    let remaining: Int
    let total: Int
    let resetAt: String
}

/// Week 4：邮箱账号与用量；OAuth 深链入口。
@MainActor
final class AuthService: ObservableObject {
    static let shared = AuthService()

    @Published private(set) var isAuthenticated = false
    @Published private(set) var userEmail: String?
    @Published private(set) var usageUsed: Int = 0
    @Published private(set) var usageQuota: Int = 500
    /// 用户订阅计划："pro" / "free"。从后端 `/usage/current` 获取。
    @Published private(set) var plan: String = "free"
    @Published var lastAuthError: String?

    /// 是否为 Pro 会员（后端 plan 或本地 StoreKit 订阅任一有效即可）。
    /// BYOK 版始终返回 true（用户自备 Key，功能全开）。
    var isPro: Bool {
        #if BYOK_ONLY
        return true
        #else
        return plan == "pro" || SubscriptionManager.shared.isProEntitled
        #endif
    }

    private init() {}

    var hasBackendConfigured: Bool {
        AppConfig.backendAPIBaseURL != nil
    }

    /// 本地用量已达或超过配额（`TECH_SPEC_SUPPLEMENT` §3.3：客户端先行拦截）。
    /// BYOK 版始终返回 false（用户自备 Key，无配额限制）。
    var isQuotaExceeded: Bool {
        #if BYOK_ONLY
        return false
        #else
        return usageQuota > 0 && usageUsed >= usageQuota
        #endif
    }

    /// 乐观 +1，用于上报前占位；失败时须 `decrementLocalUsage()`。
    func incrementLocalUsage() {
        usageUsed += 1
    }

    func decrementLocalUsage() {
        usageUsed = max(0, usageUsed - 1)
    }

    func restoreSession() async {
        lastAuthError = nil
        guard let token = KeychainTokenStore.loadToken(), !token.isEmpty else {
            isAuthenticated = false
            userEmail = nil
            return
        }
        let email = UserDefaults.standard.string(forKey: Keys.savedEmail) ?? ""
        userEmail = email
        isAuthenticated = true
        await refreshTokensIfNeeded()
        await refreshUsage()
    }

    /// access 过期前 1 天静默刷新（§2.2）。
    func refreshTokensIfNeeded() async {
        guard let access = KeychainTokenStore.loadToken(), !access.isEmpty,
              let refresh = KeychainTokenStore.loadRefreshToken(), !refresh.isEmpty,
              hasBackendConfigured
        else { return }
        guard let exp = JWTAccessExpiry.expirationDate(accessToken: access) else { return }
        let threshold: TimeInterval = 86400
        guard exp.timeIntervalSinceNow < threshold else { return }
        do {
            let body = AuthRefreshRequest(refreshToken: refresh)
            let res: AuthTokenResponse = try await BackendAPIClient.postJSON(path: "/auth/refresh", body: body, token: nil)
            try applyTokens(res, fallbackEmail: userEmail)
            await refreshUsage()
        } catch {
            logout()
            lastAuthError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func login(email: String, password: String) async {
        lastAuthError = nil
        do {
            let body = AuthLoginRequest(email: email.lowercased(), password: password)
            let res: AuthTokenResponse = try await BackendAPIClient.postJSON(path: "/auth/login", body: body, token: nil)
            try applyTokens(res, fallbackEmail: email)
            await refreshUsage()
        } catch {
            lastAuthError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            isAuthenticated = false
        }
    }

    /// 返回 `(成功, 开发环境可选 verificationToken)`。
    func register(email: String, password: String) async -> (Bool, String?) {
        lastAuthError = nil
        do {
            let body = AuthRegisterRequest(email: email.lowercased(), password: password)
            let res: AuthRegisterResponse = try await BackendAPIClient.postJSON(path: "/auth/register", body: body, token: nil)
            return (true, res.verificationToken)
        } catch {
            lastAuthError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return (false, nil)
        }
    }

    /// §2.1：Apple 登录（identityToken + authorizationCode）。
    func signInWithApple(identityToken: String, authorizationCode: String?) async {
        lastAuthError = nil
        guard hasBackendConfigured else {
            lastAuthError = "未配置后端地址。"
            return
        }
        struct Body: Encodable {
            let identityToken: String
            let authorizationCode: String?
        }
        do {
            let body = Body(identityToken: identityToken, authorizationCode: authorizationCode)
            let res: AuthTokenResponse = try await BackendAPIClient.postJSON(path: "/auth/apple", body: body, token: nil)
            try applyTokens(res, fallbackEmail: nil)
            await refreshUsage()
        } catch {
            lastAuthError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func logout() {
        KeychainTokenStore.deleteToken()
        UserDefaults.standard.removeObject(forKey: Keys.savedEmail)
        isAuthenticated = false
        userEmail = nil
        usageUsed = 0
        usageQuota = 500
        plan = "free"
        lastAuthError = nil
    }

    func refreshUsage() async {
        guard let token = KeychainTokenStore.loadToken(), !token.isEmpty else { return }
        do {
            let u: AuthUsageCurrent = try await BackendAPIClient.getJSON(path: "/usage/current", token: token)
            usageUsed = u.used
            usageQuota = u.quota
            plan = u.plan ?? "free"
        } catch {
            if let be = error as? BackendAPIError, case .httpStatus(401, _) = be {
                logout()
            } else {
                lastAuthError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    /// 注册后轮询 `GET /auth/verify-status`（每 3 秒，§2.1）。
    func waitForEmailVerification(email: String, maxAttempts: Int = 100) async -> Bool {
        guard hasBackendConfigured else { return false }
        let normalized = email.lowercased()
        for _ in 0 ..< maxAttempts {
            try? await Task.sleep(for: .seconds(3))
            if await fetchVerifyStatus(email: normalized) {
                return true
            }
        }
        return false
    }

    func fetchVerifyStatus(email: String) async -> Bool {
        guard hasBackendConfigured else { return false }
        var qc = URLComponents()
        qc.queryItems = [URLQueryItem(name: "email", value: email)]
        let q = qc.percentEncodedQuery.map { "?\($0)" } ?? ""
        do {
            let r: AuthVerifyStatusResponse = try await BackendAPIClient.getJSON(path: "/auth/verify-status" + q, token: nil)
            return r.verified
        } catch {
            return false
        }
    }

    /// PolishService 产出第一个有效 token 时调用（§3.1）；失败不阻塞主链路。
    func recordUsageAfterFirstPolishToken(
        type: String = "polish",
        durationMs: Int,
        asrProvider: String,
        charCount: Int = 0
    ) async {
        guard isAuthenticated,
              hasBackendConfigured,
              let token = KeychainTokenStore.loadToken(), !token.isEmpty
        else { return }
        incrementLocalUsage()
        let ver = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let body = UsageRecordAPIRequest(
            type: type,
            durationMs: durationMs,
            asrProvider: asrProvider,
            clientVersion: ver,
            charCount: charCount
        )
        do {
            let res: UsageRecordAPIResponse = try await BackendAPIClient.postJSON(path: "/usage/record", body: body, token: token)
            usageQuota = res.total
            usageUsed = res.total - res.remaining
        } catch {
            if case let BackendAPIError.httpStatus(code, _) = error, code == 402 {
                await refreshUsage()
                await MainActor.run {
                    AppState.shared.lastPipelineError = UserFacingError.quotaExceeded
                    AppState.shared.polishAttentionMessage = UserFacingError.quotaExceeded
                    AppState.shared.status = .attention
                }
            } else {
                decrementLocalUsage()
                await MainActor.run {
                    AppState.shared.lastPipelineError = (error as? LocalizedError)?.errorDescription ?? "用量上报失败。"
                }
            }
        }
    }

    /// `vilsay://auth/callback`、`vilsay://auth/verify`（§2.4）；回调用 `provider` 或 OAuth `state` 区分 Google / 微信。
    func handleDeepLink(_ url: URL) {
        guard url.scheme == "vilsay" else { return }
        let path = url.path.lowercased()
        if path.hasPrefix("/auth/callback") {
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            if let code = items.first(where: { $0.name == "code" })?.value {
                let provider = items.first(where: { $0.name == "provider" })?.value
                    ?? items.first(where: { $0.name == "state" })?.value
                Task { await exchangeOAuthCode(code: code, provider: provider) }
            }
            return
        }
        if path.hasPrefix("/auth/verify") {
            if let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
               let token = items.first(where: { $0.name == "token" })?.value {
                Task { await verifyEmailToken(token: token) }
            }
        }
    }

    private func applyTokens(_ res: AuthTokenResponse, fallbackEmail: String?) throws {
        try KeychainTokenStore.save(res.accessToken)
        if let r = res.refreshToken, !r.isEmpty {
            try KeychainTokenStore.saveRefreshToken(r)
        }
        if let u = res.user {
            let e = u.email.lowercased()
            userEmail = e
            UserDefaults.standard.set(e, forKey: Keys.savedEmail)
        } else if let fb = fallbackEmail {
            let e = fb.lowercased()
            userEmail = e
            UserDefaults.standard.set(e, forKey: Keys.savedEmail)
        }
        isAuthenticated = true
    }

    private func exchangeOAuthCode(code: String, provider: String?) async {
        lastAuthError = nil
        guard hasBackendConfigured else {
            lastAuthError = "未配置后端，无法完成 OAuth。"
            return
        }
        let p = (provider ?? "wechat").lowercased()
        struct CodeBody: Encodable {
            let code: String
        }
        let body = CodeBody(code: code)
        let path: String
        switch p {
        case "google":
            path = "/auth/google"
        default:
            path = "/auth/wechat"
        }
        do {
            let res: AuthTokenResponse = try await BackendAPIClient.postJSON(path: path, body: body, token: nil)
            try applyTokens(res, fallbackEmail: nil)
            await refreshUsage()
        } catch {
            lastAuthError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func verifyEmailToken(token: String) async {
        lastAuthError = nil
        guard hasBackendConfigured else {
            lastAuthError = "未配置后端，无法验证邮箱。"
            return
        }
        do {
            struct Body: Encodable {
                let token: String
            }
            let res: AuthTokenResponse = try await BackendAPIClient.postJSON(path: "/auth/verify-email", body: Body(token: token), token: nil)
            try applyTokens(res, fallbackEmail: nil)
            await refreshUsage()
        } catch {
            lastAuthError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

}
