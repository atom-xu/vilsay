//
//  OnboardingView.swift
//  vilsay — W7：首次引导（两栏布局，左侧步骤导航，右侧内容）
//

import AppKit
import ApplicationServices
import AVFoundation
import SwiftUI

struct OnboardingView: View {
    let onFinished: () -> Void

    @ObservedObject private var auth = AuthService.shared
    @ObservedObject private var appState = AppState.shared
    @Environment(\.colorScheme) private var colorScheme

    @State private var step: Int
    @State private var showLoginSheet = false

    // MARK: - Step 1 麦克风
    @State private var micState: MicPermState = .initial
    @State private var micPollTimer: Timer?
    @State private var micPollElapsed: Int = 0
    @State private var micAuthorizationInFlight = false

    // MARK: - Step 2 辅助功能
    @State private var axState: AXPermState = .initial
    @State private var axPollTimer: Timer?
    @State private var axPollElapsed: Int = 0

    init(onFinished: @escaping () -> Void) {
        self.onFinished = onFinished
        let saved = UserDefaults.standard.integer(forKey: UserDefaultsKeys.onboardingStep)
        _step = State(initialValue: OnboardingResume.resolveStartStep(fromSaved: saved))
    }

    // MARK: - Body

    var body: some View {
        HStack(spacing: 0) {
            // 左侧步骤导航
            sidebarPanel
                .frame(width: 260)

            // 分割线（视觉分割，无厚度感）
            Rectangle()
                .fill(Color.primary.opacity(0.07))
                .frame(width: 1)

            // 右侧主内容
            mainContentPanel
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 720, minHeight: 500)
        .background(contentBackground)
        .onAppear { handleStepAppear(step) }
        .onChange(of: step) { _, new in handleStepAppear(new) }
        .onChange(of: auth.isAuthenticated) { _, isAuth in
            guard isAuth, step == 3 else { return }
            Task { @MainActor in
                showLoginSheet = false
                advanceTo(4)
            }
        }
        .onDisappear {
            invalidateMicTimer()
            invalidateAxTimer()
        }
        .sheet(isPresented: $showLoginSheet) {
            LoginView()
                .frame(minWidth: 400, minHeight: 560)
        }
    }

    // MARK: - 背景色

    private var contentBackground: Color {
        colorScheme == .dark
            ? Color(NSColor.windowBackgroundColor)
            : Color.white
    }

    private var sidebarBackground: Color {
        colorScheme == .dark
            ? Color(NSColor.controlBackgroundColor)
            : Color(white: 0.965)
    }

    // MARK: - 左侧导航面板

    private var sidebarPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 品牌区
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    VilsayMarkSidebar()
                    Text("Vilsay")
                        .font(.title2.weight(.bold))
                }
                Text("说话即输入，AI 帮你润色。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 24)
            .padding(.top, 36)
            .padding(.bottom, 32)

            // 步骤列表
            VStack(alignment: .leading, spacing: 0) {
                navStep(
                    number: 1,
                    title: "权限设置",
                    done: step >= 3,
                    subSteps: [
                        ("麦克风", step == 1),
                        ("辅助功能", step == 2)
                    ],
                    showSubs: step < 3
                )
                navStep(
                    number: 2,
                    title: "账号登录",
                    done: step >= 4,
                    subSteps: [],
                    showSubs: false
                )
                navStep(
                    number: 3,
                    title: "体验润色",
                    done: step >= 5,
                    subSteps: [],
                    showSubs: false
                )
                navStep(
                    number: 4,
                    title: "准备就绪",
                    done: step >= 6,
                    subSteps: [],
                    showSubs: false
                )
            }

            Spacer()
        }
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(sidebarBackground)
    }

    // 导航步骤行
    private func navStep(
        number: Int,
        title: String,
        done: Bool,
        subSteps: [(String, Bool)],
        showSubs: Bool
    ) -> some View {
        // 当前大步骤 index：1→权限, 2→权限, 3→登录, 4→完成
        let groupActive: Bool = {
            switch number {
            case 1: return step >= 1 && step < 3
            case 2: return step == 3
            case 3: return step == 4
            case 4: return step >= 5
            default: return false
            }
        }()

        return VStack(alignment: .leading, spacing: 8) {
            // 标题行
            HStack(spacing: 12) {
                stepCircle(number: number, done: done, active: groupActive)
                Text(title)
                    .font(.subheadline.weight(groupActive || done ? .semibold : .regular))
                    .foregroundStyle(groupActive || done ? Color.primary : Color.secondary)
            }

            // 子步骤
            if showSubs && !subSteps.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(subSteps, id: \.0) { name, isActive in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(isActive ? Color.primary : Color.primary.opacity(0.20))
                                .frame(width: 5, height: 5)
                            Text(name)
                                .font(.caption)
                                .foregroundStyle(isActive ? Color.primary : Color.secondary)
                        }
                    }
                }
                .padding(.leading, 36)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }

    private func stepCircle(number: Int, done: Bool, active: Bool) -> some View {
        ZStack {
            Circle()
                .fill(done ? Color.primary : (active ? Color.primary.opacity(0.08) : .clear))
                .overlay(
                    Circle().stroke(
                        Color.primary.opacity(done ? 0 : (active ? 0.25 : 0.18)),
                        lineWidth: 1
                    )
                )
                .frame(width: 26, height: 26)

            if done {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
            } else {
                Text("\(number)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(active ? Color.primary : Color.secondary)
            }
        }
    }

    // MARK: - 右侧主内容面板

    private var mainContentPanel: some View {
        ZStack(alignment: .topTrailing) {
            // 跳过按钮（步骤 1-3 可跳过）
            if step > 0 && step < 5 {
                Button("跳过") { advanceTo(step + 1) }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
                    .padding(.top, 20)
                    .padding(.trailing, 28)
            }

            // 主内容
            VStack {
                Spacer()
                Group {
                    switch step {
                    case 0: welcomeContent
                    case 1: micContent
                    case 2: axContent
                    case 3: loginContent
                    case 4: trialContent
                    default: completionContent
                    }
                }
                .transition(
                    .asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    )
                )
                .animation(.easeInOut(duration: 0.25), value: step)
                Spacer()
            }
            .padding(.horizontal, 56)
            .padding(.vertical, 40)
        }
    }

    // MARK: - 各步骤内容

    // 步骤 0 欢迎
    private var welcomeContent: some View {
        VStack(spacing: 28) {
            WaveformBars(
                barWidth:     8,
                spacing:      7,
                heights:      [28, 48, 36, 22],
                cornerRadius: 4,
                showCursor:   false
            )
            .frame(width: 72, height: 56)

            VStack(spacing: 10) {
                Text("欢迎使用 Vilsay")
                    .font(.largeTitle.weight(.bold))
                Text("说话，比打字更快。而且越用越懂你。")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button("开始设置") { advanceTo(1) }
                .buttonStyle(OnboardingPrimaryButton())
                .keyboardShortcut(.defaultAction)
        }
    }

    // 步骤 1 麦克风
    private var micContent: some View {
        VStack(spacing: 28) {
            micHeaderIcon

            VStack(spacing: 10) {
                Text("需要麦克风权限")
                    .font(.largeTitle.weight(.bold))
                Text(micSubtitle)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
            }

            // 内容区卡片
            RoundedRectangle(cornerRadius: VRadius.lg, style: .continuous)
                .fill(Color.primary.opacity(0.04))
                .overlay(
                    VStack(spacing: 12) {
                        VilsayMarkCard()
                        Text("录音在本设备处理，音频从不上传。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                )
                .frame(height: 110)

            VStack(spacing: 12) {
                micButtons

                HStack {
                    Button("上一步") { advanceTo(0) }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                    Spacer()
                    if micPollElapsed >= 30, micState == .waitingSettings {
                        Button("稍后在设置中完成") { advanceTo(2) }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    }
                }
            }
        }
    }

    // 步骤 2 辅助功能
    private var axContent: some View {
        VStack(spacing: 28) {
            axHeaderIcon

            VStack(spacing: 10) {
                Text(axTitle)
                    .font(.largeTitle.weight(.bold))
                    .multilineTextAlignment(.center)
                Text(axSubtitle)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
            }

            if axState == .waitingSettings || axState == .timedOut {
                RoundedRectangle(cornerRadius: VRadius.lg, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
                    .overlay(
                        VStack(alignment: .leading, spacing: 8) {
                            Label("在系统设置中找到 Vilsay", systemImage: "1.circle.fill")
                            Label("将辅助功能开关打开", systemImage: "2.circle.fill")
                            Label("此页面将自动继续", systemImage: "3.circle.fill")
                        }
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                    )
                    .frame(height: 120)
            } else {
                RoundedRectangle(cornerRadius: VRadius.lg, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
                    .overlay(
                        VStack(spacing: 8) {
                            Image(systemName: "keyboard")
                                .font(.system(size: 28))
                                .foregroundStyle(VColor.accent.opacity(0.7))
                            Text("用于将文字输入到任意应用程序")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    )
                    .frame(height: 110)
            }

            VStack(spacing: 12) {
                axButtons

                HStack {
                    Button("上一步") { advanceTo(1) }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                    Spacer()
                    if axState == .timedOut {
                        Button("稍后完成") { advanceTo(3) }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    }
                }
            }
        }
    }

    // 步骤 3 登录
    private var loginContent: some View {
        VStack(spacing: 28) {
            Image(systemName: "person.crop.circle")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(VColor.accent)

            VStack(spacing: 10) {
                Text("登录以开始使用")
                    .font(.largeTitle.weight(.bold))
                Text("登录后可同步设置、查看用量。升级 Pro 可享受 Vilsay 提供的云端服务。")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            socialButtons

            HStack {
                Rectangle().fill(Color.secondary.opacity(0.15)).frame(height: 1)
                Text("或使用邮箱")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize()
                Rectangle().fill(Color.secondary.opacity(0.15)).frame(height: 1)
            }

            Button {
                showLoginSheet = true
            } label: {
                Label("邮箱登录 / 注册", systemImage: "envelope")
                    .font(.subheadline.weight(.medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(VColor.accent)

            Button("跳过登录") { advanceTo(4) }
                .buttonStyle(.plain)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .help("跳过后需在设置中自行填写 DashScope API Key 以使用云端润色")

            HStack {
                Button("上一步") { advanceTo(2) }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
                Spacer()
                HStack(spacing: VSpacing.sm) {
                    Button("隐私政策") {
                        NSWorkspace.shared.open(WebsiteURL.privacy)
                    }
                    Text("·").foregroundStyle(.tertiary)
                    Button("服务条款") {
                        NSWorkspace.shared.open(WebsiteURL.terms)
                    }
                }
                .font(.caption)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
    }

    // 步骤 4 完成
    private var completionContent: some View {
        VStack(spacing: 28) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(VColor.ok)

            VStack(spacing: 10) {
                Text("全部就绪")
                    .font(.largeTitle.weight(.bold))
                Text("按住快捷键开始说话，Vilsay 帮你润色。")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            RoundedRectangle(cornerRadius: VRadius.lg, style: .continuous)
                .fill(Color.primary.opacity(0.04))
                .overlay(
                    VStack(alignment: .leading, spacing: 12) {
                        Label("按住 Fn 开始录音，松开结束", systemImage: "command")
                        Label("悬浮按钮可拖到任意位置", systemImage: "hand.draw")
                        Label("在菜单栏中查看更多设置", systemImage: "menubar.rectangle")
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                )
                .frame(height: 120)

            // Pro/Free 云端服务说明
            if auth.isAuthenticated && auth.isPro {
                Label("Pro 会员：云端服务已就绪", systemImage: "checkmark.seal.fill")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(VColor.accent)
            } else if !auth.isAuthenticated {
                VStack(spacing: 6) {
                    Label("未登录：云端润色需要 API Key", systemImage: "key")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(VColor.warn)
                    Text("请在「设置 → 语音识别」中填写 DashScope API Key，或登录后升级 Pro 由 Vilsay 提供服务。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            } else if !auth.isPro {
                VStack(spacing: 6) {
                    Label("免费版：云端润色需要 API Key", systemImage: "key")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(VColor.warn)
                    Text("请在「设置 → 语音识别」中填写 DashScope API Key，或升级 Pro 由 Vilsay 提供服务。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }

            if appState.localWhisperLoading {
                HStack(spacing: VSpacing.sm) {
                    ProgressView().controlSize(.small)
                    Text(appState.localWhisperStatusHint ?? "正在加载本地语音模型…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Button("开始使用") {
                UserDefaults.standard.set(true, forKey: UserDefaultsKeys.onboardingDone)
                UserDefaults.standard.set(5, forKey: UserDefaultsKeys.onboardingStep)
                onFinished()
            }
            .buttonStyle(OnboardingPrimaryButton())
            .keyboardShortcut(.defaultAction)
        }
    }

    // 步骤 4 体验润色
    private var trialContent: some View {
        VStack(spacing: 28) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(VColor.accent)

            VStack(spacing: 10) {
                Text("体验 AI 润色")
                    .font(.largeTitle.weight(.bold))
                Text("Vilsay 将口语化的语音转化为精准流畅的文字。")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            // 对比示意卡片
            VStack(spacing: 0) {
                HStack {
                    Label("说出来", systemImage: "mic.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.primary.opacity(0.03))

                Text("\"然后就是那个方案嘛，我觉得可能还不太成熟吧\"")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Divider()

                HStack {
                    Label("润色后", systemImage: "wand.and.stars")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(VColor.accent)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(VColor.accent.opacity(0.05))

                Text("\"这个方案目前还不够成熟，需要进一步完善。\"")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.primary)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .clipShape(RoundedRectangle(cornerRadius: VRadius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: VRadius.lg, style: .continuous)
                    .stroke(Color.primary.opacity(0.07), lineWidth: 1)
            )

            Button("开始使用，自己试试") { advanceTo(5) }
                .buttonStyle(OnboardingPrimaryButton())
                .keyboardShortcut(.defaultAction)

            HStack {
                Button("上一步") { advanceTo(3) }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
                Spacer()
                Button("跳过") { advanceTo(5) }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            }
        }
    }

    // MARK: - 子视图复用

    @ViewBuilder
    private var micHeaderIcon: some View {
        switch micState {
        case .initial, .requesting, .waitingSettings:
            PulseIcon(systemName: "mic.badge.plus", accent: VColor.accent, size: 48)
        case .denied:
            Image(systemName: "mic.slash.fill")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(VColor.fail)
        case .granted:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(VColor.ok)
        }
    }

    private var micSubtitle: String {
        switch micState {
        case .initial: return "Vilsay 需要录音权限才能开始使用。"
        case .requesting: return "正在请求麦克风权限…"
        case .denied: return "请前往「系统设置 → 隐私与安全性 → 麦克风」中允许 Vilsay。"
        case .waitingSettings: return "开启后此页面将自动继续。"
        case .granted: return "麦克风已就绪，即将进入下一步。"
        }
    }

    @ViewBuilder
    private var micButtons: some View {
        switch micState {
        case .initial, .requesting, .granted:
            EmptyView()
        case .denied:
            Button("打开系统设置") {
                openMicrophonePrivacy()
                startMicPolling()
            }
            .buttonStyle(OnboardingPrimaryButton())
        case .waitingSettings:
            Button("我已开启") {
                Task { @MainActor in
                    if await PermissionManager.shared.requestMicrophonePermission() {
                        invalidateMicTimer()
                        advanceTo(2)
                    }
                }
            }
            .buttonStyle(OnboardingPrimaryButton())
        }
    }

    @ViewBuilder
    private var axHeaderIcon: some View {
        switch axState {
        case .authorized:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(VColor.ok)
        case .waitingSettings:
            PulseIcon(systemName: "keyboard", accent: VColor.accent, size: 48)
        default:
            Image(systemName: "keyboard")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(VColor.accent)
        }
    }

    private var axTitle: String {
        switch axState {
        case .initial, .notAuthorized: return "需要辅助功能权限"
        case .waitingSettings: return "请在系统设置中开启"
        case .timedOut: return "尚未检测到授权"
        case .authorized: return "辅助功能已开启"
        }
    }

    private var axSubtitle: String {
        switch axState {
        case .initial, .notAuthorized: return "Vilsay 需要此权限将文字输入到任意应用程序。"
        case .waitingSettings, .timedOut: return "跳过后仍可复制润色结果，但无法自动输入文字。"
        case .authorized: return "即将进入下一步…"
        }
    }

    @ViewBuilder
    private var axButtons: some View {
        switch axState {
        case .initial, .notAuthorized:
            Button("打开系统设置") { openSettingsAndPollAX() }
                .buttonStyle(OnboardingPrimaryButton())
        case .waitingSettings, .timedOut:
            Button("我已完成") {
                if AXIsProcessTrusted() { axToAuthorizedAndAdvance() }
            }
            .buttonStyle(OnboardingPrimaryButton())
        case .authorized:
            EmptyView()
        }
    }

    // MARK: - OAuth 社交登录

    private var socialButtons: some View {
        HStack(spacing: VSpacing.sm) {
            socialButton(title: "Apple", systemImage: "apple.logo", style: .apple)
            socialButton(title: "微信", systemImage: "message.fill", style: .wechat)
            socialButton(title: "Google", systemImage: "g.circle", style: .google)
        }
    }

    private enum SocialKind { case apple, wechat, google }

    private func socialButton(title: String, systemImage: String, style: SocialKind) -> some View {
        Button {
            switch style {
            case .apple:  OAuthSignInCoordinator.startAppleSignIn()
            case .google: Task { await OAuthSignInCoordinator.startGoogleOAuth() }
            case .wechat: OAuthSignInCoordinator.startWeChatOAuth()
            }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .medium))
                Text(title)
                    .font(.caption.weight(.medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(socialBg(style))
            .foregroundStyle(socialFg(style))
            .clipShape(RoundedRectangle(cornerRadius: VRadius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: VRadius.md, style: .continuous)
                    .stroke(Color.primary.opacity(style == .google ? 0.12 : 0), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func socialBg(_ k: SocialKind) -> Color {
        switch k {
        case .apple:  return Color(nsColor: .labelColor).opacity(0.92)
        case .wechat: return Color(red: 0.09, green: 0.73, blue: 0.41)
        case .google: return Color(nsColor: .controlBackgroundColor)
        }
    }
    private func socialFg(_ k: SocialKind) -> Color {
        switch k {
        case .apple:  return Color(nsColor: .textBackgroundColor)
        case .wechat: return .white
        case .google: return Color(nsColor: .labelColor)
        }
    }

    // MARK: - 步骤调度（逻辑不变）

    private func handleStepAppear(_ s: Int) {
        switch s {
        case 1: enterMicStep()
        case 2: enterAccessibilityStep()
        case 3:
            Task { @MainActor in
                await AuthService.shared.restoreSession()
                if AuthService.shared.isAuthenticated { advanceTo(4) }
            }
        case 4: break  // 体验润色步骤，无需预加载
        case 5:
            Task { await WhisperASRFallback.shared.preloadIfNeeded() }
        default: break
        }
    }

    private func enterMicStep() {
        let status = AVAudioApplication.shared.recordPermission
        switch status {
        case .granted:
            micState = .granted
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.advanceTo(2) }
        case .undetermined:
            guard !micAuthorizationInFlight else { return }
            micAuthorizationInFlight = true
            micState = .requesting
            Task {
                let ok = await PermissionManager.shared.requestMicrophonePermission()
                await MainActor.run {
                    micAuthorizationInFlight = false
                    if ok {
                        invalidateMicTimer()
                        micState = .granted
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.advanceTo(2) }
                    }
                    else  { micState = .denied }
                }
            }
        case .denied: micState = .denied
        @unknown default: micState = .denied
        }
    }

    private func startMicPolling() {
        micState = .waitingSettings; micPollElapsed = 0; invalidateMicTimer()
        let t = Timer(timeInterval: 2.0, repeats: true) { _ in
            Task { @MainActor in
                self.micPollElapsed += 2
                if AVAudioApplication.shared.recordPermission == .granted {
                    self.invalidateMicTimer()
                    self.micState = .granted
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.advanceTo(2) }
                }
            }
        }
        RunLoop.main.add(t, forMode: .common)
        micPollTimer = t
    }

    private func invalidateMicTimer() { micPollTimer?.invalidate(); micPollTimer = nil }

    private func enterAccessibilityStep() {
        if AXIsProcessTrusted() {
            axState = .authorized
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { advanceTo(3) }
        } else {
            axState = .notAuthorized
        }
    }

    private func openSettingsAndPollAX() {
        openAccessibilityPrivacy()
        axState = .waitingSettings; axPollElapsed = 0; invalidateAxTimer()
        let t = Timer(timeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in
                self.axPollElapsed += 1
                if AXIsProcessTrusted()          { self.invalidateAxTimer(); self.axToAuthorizedAndAdvance() }
                else if self.axPollElapsed >= 30 { self.axState = .timedOut }
            }
        }
        RunLoop.main.add(t, forMode: .common)
        axPollTimer = t
    }

    private func axToAuthorizedAndAdvance() {
        axState = .authorized
        // UX Fix #2：授权辅助功能后重启 HotkeyManager，使 Fn 热键立即可用，无需手动重启 app
        Task { @MainActor in
            HotkeyManager.shared.stop()
            try? await Task.sleep(for: .milliseconds(300))
            HotkeyManager.shared.start()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { advanceTo(3) }
    }

    private func invalidateAxTimer() { axPollTimer?.invalidate(); axPollTimer = nil }

    private func advanceTo(_ next: Int) {
        if step == 1 { invalidateMicTimer() }
        if step == 2 { invalidateAxTimer() }
        if next == 1 { micAuthorizationInFlight = false; micState = .initial }
        UserDefaults.standard.set(next, forKey: UserDefaultsKeys.onboardingStep)
        step = next
    }

    private func openMicrophonePrivacy() { PermissionManager.shared.openMicrophonePrivacySettings() }
    private func openAccessibilityPrivacy() { PermissionManager.shared.openAccessibilityPrivacySettings() }
}

// MARK: - 枚举（权限状态）

private enum MicPermState {
    case initial, requesting, denied, waitingSettings, granted
}

private enum AXPermState {
    case initial, notAuthorized, waitingSettings, timedOut, authorized
}

// MARK: - 动画脉冲图标

private struct PulseIcon: View {
    let systemName: String
    let accent: Color
    var size: CGFloat = 52
    @State private var isPulsing = false

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size, weight: .light))
            .foregroundStyle(accent)
            .scaleEffect(isPulsing ? 1.06 : 1.0)
            .opacity(isPulsing ? 0.7 : 1.0)
            .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: isPulsing)
            .onAppear { isPulsing = true }
    }
}

// MARK: - Onboarding 专用主按钮样式（深色胶囊，固定宽度）

private struct OnboardingPrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.vertical, 12)
            .padding(.horizontal, 32)
            .background(
                Capsule().fill(Color.primary)
            )
            .opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }
}
