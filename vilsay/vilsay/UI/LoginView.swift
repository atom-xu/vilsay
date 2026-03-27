//
//  LoginView.swift
//  vilsay
//

import SwiftUI

/// W2-05：登录/注册/忘记密码 UI（逻辑 W4 接入）。
/// 布局：邮箱表单优先，第三方登录作为次选项置于分隔线下方。
struct LoginView: View {
    enum Phase {
        case login
        case register
        case forgotPassword
    }

    @ObservedObject private var auth = AuthService.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var phase: Phase = .login
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var showVerificationHint = false
    @State private var busy = false
    @State private var lastDevVerificationToken: String?
    @State private var verificationPollTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: VSpacing.lg) {
            header

            formFields
            primaryActions

            if !auth.hasBackendConfigured {
                Label("未配置 VILSAY_API_BASE，无法使用邮箱登录。",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(VColor.warn)
            }

            if phase == .login {
                socialDivider
                socialButtons
            }

            Spacer(minLength: 0)
            footerLinks
        }
        .padding(VSpacing.xl)
        .background(VSettingsBackground())
        .frame(minWidth: 400, minHeight: phase == .login ? 560 : 460)
        .alert("请查收验证邮件", isPresented: $showVerificationHint) {
            Button("好的", role: .cancel) {}
        } message: {
            Text(verificationAlertMessage)
        }
        .onChange(of: auth.isAuthenticated) { _, ok in
            guard ok else { return }
            Task { @MainActor in
                dismiss()
            }
        }
        .onDisappear {
            verificationPollTask?.cancel()
            verificationPollTask = nil
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: VSpacing.md) {
            Image(systemName: "mic.fill")
                .font(.title)
                .foregroundStyle(VColor.accent)
            VStack(alignment: .leading, spacing: VSpacing.xxs) {
                Text(titleText)
                    .font(.title2.weight(.semibold))
                Text(subtitleText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var titleText: String {
        switch phase {
        case .login: return "登录 Vilsay"
        case .register: return "注册账号"
        case .forgotPassword: return "重置密码"
        }
    }

    private var subtitleText: String {
        switch phase {
        case .login: return "输入邮箱和密码"
        case .register: return "创建账号后我们会发送验证邮件"
        case .forgotPassword: return "输入邮箱，我们将发送重置链接"
        }
    }

    // MARK: - 表单字段

    @ViewBuilder
    private var formFields: some View {
        switch phase {
        case .login:
            labeledField("邮箱", text: $email)
            labeledSecureField("密码", text: $password)
        case .register:
            labeledField("邮箱", text: $email)
            labeledSecureField("密码", text: $password)
            labeledSecureField("确认密码", text: $confirmPassword)
        case .forgotPassword:
            labeledField("邮箱", text: $email)
        }
    }

    private func labeledField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: VSpacing.xxs) {
            Text(title)
                .font(.subheadline.weight(.medium))
            TextField("", text: text)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func labeledSecureField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: VSpacing.xxs) {
            Text(title)
                .font(.subheadline.weight(.medium))
            SecureField("", text: text)
                .textFieldStyle(.roundedBorder)
        }
    }

    // MARK: - 主操作按钮

    private var primaryActions: some View {
        VStack(spacing: VSpacing.sm) {
            switch phase {
            case .login:
                Button {
                    Task {
                        busy = true
                        await auth.login(email: email, password: password)
                        busy = false
                    }
                } label: {
                    Text(busy ? "登录中…" : "登录")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(busy || email.isEmpty || password.isEmpty || !auth.hasBackendConfigured)

                HStack {
                    Button("没有账号？注册") { phase = .register }
                        .buttonStyle(.plain)
                        .foregroundStyle(VColor.accent)
                    Spacer()
                    Button("忘记密码？") { phase = .forgotPassword }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline)

            case .register:
                Button {
                    Task {
                        busy = true
                        let (ok, devTok) = await auth.register(email: email, password: password)
                        busy = false
                        if ok {
                            lastDevVerificationToken = devTok
                            showVerificationHint = true
                            verificationPollTask?.cancel()
                            verificationPollTask = Task {
                                _ = await auth.waitForEmailVerification(email: email)
                            }
                        }
                    }
                } label: {
                    Text(busy ? "提交中…" : "注册")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(
                    busy || email.isEmpty || password.isEmpty
                    || password != confirmPassword || !auth.hasBackendConfigured
                )

                Button("返回登录") { phase = .login }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)

            case .forgotPassword:
                Button {
                    auth.lastAuthError = "密码重置需邮件服务；请在后端接入 SMTP 后使用。"
                } label: {
                    Text("发送重置邮件")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(email.isEmpty || !auth.hasBackendConfigured)

                Button("返回登录") { phase = .login }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }

            if let err = auth.lastAuthError, !err.isEmpty {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(VColor.warn)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - 第三方登录（次选项）

    private var socialDivider: some View {
        HStack {
            Rectangle().fill(Color.secondary.opacity(0.25)).frame(height: 1)
            Text("或使用第三方登录")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize()
            Rectangle().fill(Color.secondary.opacity(0.25)).frame(height: 1)
        }
    }

    private var socialButtons: some View {
        HStack(spacing: VSpacing.sm) {
            socialButton(title: "Apple", systemImage: "apple.logo", style: .apple) {
                auth.lastAuthError = nil
                OAuthSignInCoordinator.startAppleSignIn()
            }
            socialButton(title: "微信", systemImage: "message.fill", style: .wechat) {
                auth.lastAuthError = nil
                OAuthSignInCoordinator.startWeChatOAuth()
            }
            socialButton(title: "Google", systemImage: "g.circle", style: .google) {
                auth.lastAuthError = nil
                Task { await OAuthSignInCoordinator.startGoogleOAuth() }
            }
        }
    }

    private enum SocialStyle { case apple, wechat, google }

    private func socialButton(
        title: String,
        systemImage: String,
        style: SocialStyle,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: VSpacing.xs) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .medium))
                Text(title)
                    .font(.caption.weight(.medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, VSpacing.sm + 2)
            .background(socialBackground(for: style))
            .foregroundStyle(socialForeground(for: style))
            .clipShape(RoundedRectangle(cornerRadius: VRadius.sm, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: VRadius.sm, style: .continuous)
                    .strokeBorder(socialBorder(for: style), lineWidth: style == .google ? 1 : 0)
            )
        }
        .buttonStyle(.plain)
        .help("需配置后端与 OAuth")
    }

    private func socialBackground(for style: SocialStyle) -> Color {
        switch style {
        case .apple:  return Color(nsColor: .labelColor).opacity(0.92)
        case .wechat: return Color(red: 0.09, green: 0.73, blue: 0.41)
        case .google: return VColor.bgCard
        }
    }

    private func socialForeground(for style: SocialStyle) -> Color {
        switch style {
        case .apple:  return Color(nsColor: .textBackgroundColor)
        case .wechat: return .white
        case .google: return VColor.textPrimary
        }
    }

    private func socialBorder(for style: SocialStyle) -> Color {
        style == .google ? Color.secondary.opacity(0.35) : .clear
    }

    // MARK: - Footer

    private var footerLinks: some View {
        HStack(spacing: VSpacing.sm) {
            linkButton("隐私政策") { openPlaceholderLink() }
            Text("·").foregroundStyle(.tertiary)
            linkButton("服务条款") { openPlaceholderLink() }
        }
        .font(.caption)
        .frame(maxWidth: .infinity)
        .foregroundStyle(.secondary)
    }

    private func linkButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(title) }
            .buttonStyle(.plain)
            .foregroundStyle(VColor.accent)
    }

    private func openPlaceholderLink() {
        if let url = URL(string: "https://example.com") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - 验证邮件提示

    private var verificationAlertMessage: String {
        var parts: [String] = ["验证后即可登录（开发版可能未发信）。"]
        if let t = lastDevVerificationToken, !t.isEmpty {
            parts.append("开发 token：vilsay://auth/verify?token=\(t)")
        }
        return parts.joined(separator: "\n\n")
    }
}

#Preview {
    LoginView()
}
