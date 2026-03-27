//
//  OAuthSignInCoordinator.swift
//  `VILSAY_TECH_SPEC_SUPPLEMENT` §2.1：Apple / Google / 微信
//

import AppKit
import AuthenticationServices
import Foundation

// MARK: - Sign in with Apple

private enum AppleSignInError: LocalizedError {
    case noCredential

    var errorDescription: String? {
        switch self {
        case .noCredential: return "未能获取 Apple identityToken。"
        }
    }
}

private final class AppleSignInDelegate: NSObject, ASAuthorizationControllerDelegate {
    var onComplete: ((Result<(String, String?), Error>) -> Void)?

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let cred = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = cred.identityToken,
              let idToken = String(data: tokenData, encoding: .utf8)
        else {
            onComplete?(.failure(AppleSignInError.noCredential))
            return
        }
        let code: String? = cred.authorizationCode.flatMap { String(data: $0, encoding: .utf8) }
        onComplete?(.success((idToken, code)))
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        onComplete?(.failure(error))
    }
}

private final class AppleSignInPresentationAnchor: NSObject, ASAuthorizationControllerPresentationContextProviding, ASWebAuthenticationPresentationContextProviding {
    static let shared = AppleSignInPresentationAnchor()

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        NSApp.keyWindow ?? NSApp.windows.first { $0.isVisible } ?? NSApp.windows[0]
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApp.keyWindow ?? NSApp.windows.first { $0.isVisible } ?? NSApp.windows[0]
    }
}

/// 协调 Apple / Google / 微信 OAuth 入口（主线程 UI）。
@MainActor
enum OAuthSignInCoordinator {
    private static var appleDelegate: AppleSignInDelegate?

    static func startAppleSignIn() {
        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.requestedScopes = [.fullName, .email]
        let controller = ASAuthorizationController(authorizationRequests: [request])
        let del = AppleSignInDelegate()
        del.onComplete = { result in
            Task { @MainActor in
                defer { appleDelegate = nil }
                switch result {
                case let .success((idToken, code)):
                    await AuthService.shared.signInWithApple(identityToken: idToken, authorizationCode: code)
                case let .failure(err):
                    AuthService.shared.lastAuthError = err.localizedDescription
                }
            }
        }
        appleDelegate = del
        controller.delegate = del
        controller.presentationContextProvider = AppleSignInPresentationAnchor.shared
        // 推迟到下一帧主线程执行，避免与当前 User-interactive 调用栈同步嵌套时，
        // 在 performRequests 内部等待 Default QoS 工作触发的优先级反转（Instruments / Runtime 提示）。
        Task { @MainActor in
            controller.performRequests()
        }
    }

    /// Google OAuth 网页；回调 `vilsay://auth/callback?...&state=google`。
    static func startGoogleOAuth() async {
        guard let clientId = AppConfig.googleOAuthClientId, !clientId.isEmpty else {
            AuthService.shared.lastAuthError = "未配置 VILSAY_GOOGLE_CLIENT_ID（或 UserDefaults vilsay.google_oauth_client_id）。"
            return
        }
        let redirect = "vilsay://auth/callback"
        var comp = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        comp.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirect),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "openid email profile"),
            URLQueryItem(name: "state", value: "google"),
        ]
        guard let url = comp.url else {
            AuthService.shared.lastAuthError = "无法构造 Google 授权 URL。"
            return
        }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            var finished = false
            func finish() {
                if !finished {
                    finished = true
                    cont.resume()
                }
            }
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "vilsay") { callbackURL, error in
                Task { @MainActor in
                    if let callbackURL {
                        AuthService.shared.handleDeepLink(callbackURL)
                    } else if let error {
                        let ns = error as NSError
                        let canceled = ns.domain == "com.apple.AuthenticationServices.WebAuthenticationSession" && ns.code == 1
                        if !canceled {
                            AuthService.shared.lastAuthError = error.localizedDescription
                        }
                    }
                    finish()
                }
            }
            session.presentationContextProvider = AppleSignInPresentationAnchor.shared
            session.prefersEphemeralWebBrowserSession = false
            if !session.start() {
                AuthService.shared.lastAuthError = "无法启动系统浏览器登录。"
                finish()
            }
        }
    }

    /// 在系统浏览器打开微信授权页（需配置 `VILSAY_WECHAT_OAUTH_URL`）。
    static func startWeChatOAuth() {
        guard let url = AppConfig.weChatOAuthAuthorizeURL else {
            AuthService.shared.lastAuthError = "未配置 VILSAY_WECHAT_OAUTH_URL（或 UserDefaults vilsay.wechat_oauth_url）。"
            return
        }
        NSWorkspace.shared.open(url)
    }
}
