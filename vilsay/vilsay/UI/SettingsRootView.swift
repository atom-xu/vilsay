//
//  SettingsRootView.swift
//  vilsay
//

import AppKit
import GRDB
import LaunchAtLogin
import StoreKit
import SwiftUI

/// W2-06：设置页主内容（⌘, 打开的窗口内「设置」Tab）。
struct SettingsRootView: View {
    @ObservedObject private var state = AppState.shared
    @ObservedObject private var auth = AuthService.shared
    @ObservedObject private var subscription = SubscriptionManager.shared
    @StateObject private var micTestController = MicTestController()
    @State private var permissionRefreshTick = 0

    @AppStorage("vilsay.api_base") private var apiBaseStored = ""
    @AppStorage("vilsay.dashscope_api_key") private var dashscopeKeyStored = ""
    @AppStorage("vilsay.dashscope_model_asr") private var modelAsr = "paraformer-v2"
    @AppStorage("vilsay.dashscope_model_polish") private var modelPolish = "qwen-turbo"
    @AppStorage("vilsay.dashscope_model_analyzer") private var modelAnalyzer = "qwen-turbo"
    @AppStorage("vilsay.asr_proxy_transcribe_url") private var asrProxyURLStored = ""
    @AppStorage("vilsay.asr_internal_key") private var asrInternalKeyStored = ""
    @AppStorage("vilsay.dashscope_paraformer_file_url") private var paraformerFileURLStored = ""

    @State private var asrModelOptions: [String] = DashScopeModelCatalog.defaultAsrModels
    @State private var textModelOptions: [String] = DashScopeModelCatalog.defaultTextModels
    @State private var modelFetchBusy = false
    @State private var modelFetchHint: String?
    @State private var showClearAILearningConfirm = false
    @State private var showPrivacyPolicy = false
    @State private var apiTestBusy = false
    @State private var apiTestResult: String?
    @State private var apiTestSuccess = false
    @State private var rawLogCount = 0
    @State private var analyzerStateLastRun: String?
    @State private var analyzerRunning = false
    @State private var outputModeSectionExpanded = false

    private var triggerModeFootnote: String {
        switch state.triggerMode {
        case .push:
            return "主热键与悬浮球一致：只识别长按——按住约 0.25s 后开始录音，松手结束；短按不触发。"
        case .toggle:
            return "主热键与悬浮球一致：只识别短按单击——一下开始录音、再一下结束；长按不产生录音。"
        }
    }

    private var hotkeyTriggerDescription: String {
        let current = state.globeModifierLikelyAvailable ? "FN / Globe" : "右 Option (⌥)"
        return "规则：能用 FN / Globe 就用 FN / Globe，不能用就用右 Option。本机当前：\(current)。"
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VSpacing.cardGap) {
                inputSection
                accountSection
                recognitionSection
                permissionsSection
                hotkeyHealthSection
                aiLearningSection
                dataSection
                upcomingSection
                aboutSection
                outputModeOverridesSection
                diagnosticsSection
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(VSpacing.pageInset)
        }
        .background(VSettingsBackground())
        .groupBoxStyle(VCardStyle())
        .environmentObject(micTestController)
        .sheet(isPresented: $state.showLoginSheet) {
            LoginView()
        }
        .sheet(isPresented: $showPrivacyPolicy) {
            PrivacyPolicyView()
        }
        .onAppear {
            refreshAI3State()
            guard state.hotkeyHealthReport == nil else { return }
            Task { @MainActor in
                if AppState.shared.hotkeyHealthReport == nil {
                    AppState.shared.hotkeyHealthReport = HotkeyHealthChecker.shared.performStartupCheck()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permissionRefreshTick += 1
        }
    }

    // MARK: - 常规（触发方式 + 提示音 + 开机启动）

    private var inputSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: VSpacing.md) {
                HStack {
                    Text("触发方式")
                    Spacer()
                    Picker("", selection: $state.triggerMode) {
                        Text(TriggerMode.push.title).tag(TriggerMode.push)
                        Text(TriggerMode.toggle.title).tag(TriggerMode.toggle)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 220)
                }
                Text(triggerModeFootnote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(hotkeyTriggerDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("需「辅助功能」权限；录音中可按 ESC 取消。")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)

                Divider()

                Toggle("提示音", isOn: $state.soundFeedbackEnabled)
                    .toggleStyle(.switch)
                LaunchAtLogin.Toggle("开机自动启动")
            }
        } label: {
            Label("常规", systemImage: "dial.low")
        }
    }

    // MARK: - 账号

    private var accountSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: VSpacing.md) {
                if !auth.hasBackendConfigured {
                    Label("未配置后端 API 地址。", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(VColor.warn)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if auth.isAuthenticated {
                    HStack {
                        Label(auth.userEmail ?? "已登录", systemImage: "person.circle.fill")
                            .foregroundStyle(.primary)
                        Spacer()
                        Button("退出登录") { auth.logout() }
                            .foregroundStyle(VColor.fail)
                    }
                    HStack {
                        Text("本月用量")
                        Spacer()
                        Text("\(auth.usageUsed) / \(auth.usageQuota) 次")
                            .foregroundStyle(.secondary)
                        Button("刷新") {
                            Task { await auth.refreshUsage() }
                        }
                        .controlSize(.small)
                    }
                } else {
                    HStack {
                        Label("未登录", systemImage: "person.circle")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("登录 / 注册…") { state.showLoginSheet = true }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                    }
                    HStack {
                        Text("本月用量")
                        Spacer()
                        Text("登录后同步")
                            .foregroundStyle(.tertiary)
                    }
                }

                #if !BYOK_ONLY
                HStack {
                    Text("套餐")
                    Spacer()
                    if auth.isPro || subscription.isProEntitled {
                        Text("Pro")
                            .fontWeight(.medium)
                            .foregroundStyle(VColor.accent)
                    } else {
                        Text("免费版")
                        Button {
                            Task { await subscription.purchase() }
                        } label: {
                            if subscription.isPurchasing {
                                ProgressView().controlSize(.small)
                            } else if let product = subscription.proProduct {
                                Text("升级 Pro — \(product.displayPrice)/月")
                            } else {
                                Text("升级 Pro")
                            }
                        }
                        .disabled(subscription.isPurchasing || subscription.proProduct == nil)
                        .help("升级后由 Vilsay 提供云端服务，无需自备 API Key")
                    }
                }
                #endif

                if let err = auth.lastAuthError, !err.isEmpty {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(VColor.warn)
                        .fixedSize(horizontal: false, vertical: true)
                }

                #if !BYOK_ONLY
                if let err = subscription.lastError {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(VColor.warn)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !auth.isPro && !subscription.isProEntitled {
                    Button("恢复购买") {
                        Task { await subscription.restore() }
                    }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundStyle(VColor.accent)
                }
                #endif
            }
        } label: {
            Label("账号", systemImage: "person.circle.fill")
        }
    }

    // MARK: - 语音识别 & 云端服务

    private var recognitionSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: VSpacing.md) {
                Picker("识别模式", selection: $state.recognitionMode) {
                    ForEach(RecognitionMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)

                Picker("识别语言", selection: $state.asrSpokenLanguage) {
                    ForEach(ASRSpokenLanguage.allCases) { lang in
                        Text(lang.title).tag(lang)
                    }
                }
                .pickerStyle(.radioGroup)
                .help("云端与本地 Whisper 的语种提示；中文简繁还会在识别后按选项统一字形。")

                Divider()

                if auth.isPro || subscription.isProEntitled {
                    // Pro 会员：由 Vilsay 提供云端服务，不需要自备 Key
                    VStack(alignment: .leading, spacing: VSpacing.xs) {
                        HStack {
                            Label("Pro 会员", systemImage: "checkmark.seal.fill")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(VColor.accent)
                            Spacer()
                        }
                        Text("云端语音识别与润色服务由 Vilsay 提供，无需配置 API Key。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    // Free 用户：需要自备 DashScope API Key
                    VStack(alignment: .leading, spacing: VSpacing.xs) {
                        HStack {
                            Text("DashScope API Key")
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            apiKeyStatusBadge
                        }
                        HStack(spacing: VSpacing.sm) {
                            SecureField("sk-…", text: $dashscopeKeyStored)
                                .textFieldStyle(.roundedBorder)
                            Button("验证连接") {
                                Task { await testAPIConnection() }
                            }
                            .controlSize(.small)
                            .disabled(
                                dashscopeKeyStored.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || apiTestBusy
                            )
                            if apiTestBusy {
                                ProgressView().controlSize(.small)
                            }
                        }
                        if let result = apiTestResult {
                            Text(result)
                                .font(.caption)
                                .foregroundStyle(apiTestSuccess ? VColor.ok : VColor.warn)
                        }
                        Text("免费版需自备 API Key。从 dashscope.console.aliyun.com 获取，或升级 Pro 由 Vilsay 提供服务。")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .onChange(of: dashscopeKeyStored) { _, _ in
                        apiTestSuccess = false
                        apiTestResult = nil
                    }
                }

                Divider()

                HStack(spacing: VSpacing.sm) {
                    Button("拉取可用模型") {
                        Task { await refreshDashScopeModels() }
                    }
                    .controlSize(.small)
                    .disabled(
                        modelFetchBusy
                            || dashscopeKeyStored.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                    if modelFetchBusy { ProgressView().controlSize(.small) }
                    if let hint = modelFetchHint, !hint.isEmpty {
                        Text(hint)
                            .font(.caption2)
                            .foregroundStyle(hint.contains("失败") ? VColor.warn : .secondary)
                    }
                }

                modelPicker(title: "ASR 模型", options: asrModelOptions, selection: $modelAsr)
                modelPicker(title: "润色模型", options: textModelOptions, selection: $modelPolish)
                modelPicker(title: "洞察引擎", options: textModelOptions, selection: $modelAnalyzer)

                Divider()

                DisclosureGroup("高级配置") {
                    VStack(alignment: .leading, spacing: VSpacing.sm) {
                        Text("后端 API 基址（账号服务，可留空）")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        TextField("例：http://127.0.0.1:8000", text: $apiBaseStored)
                            .textFieldStyle(.roundedBorder)

                        Text("ASR 代理 URL（可留空，自建 Paraformer 代理）")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        TextField("可选", text: $asrProxyURLStored)
                            .textFieldStyle(.roundedBorder)

                        Text("ASR 内部密钥（可留空）")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        TextField("可选", text: $asrInternalKeyStored)
                            .textFieldStyle(.roundedBorder)

                        Text("Paraformer 公网联调 URL（可留空）")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        TextField("可选", text: $paraformerFileURLStored)
                            .textFieldStyle(.roundedBorder)
                    }
                    .padding(.top, VSpacing.xs)
                }

                if state.recognitionMode == .cloud {
                    Text("云端：优先代理上传录音；否则固定 URL 联调；再否则 Whisper。")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .onAppear { ensureModelPickersIncludeSelections() }
        } label: {
            Label("语音识别 & 云端服务", systemImage: "waveform")
        }
    }

    @ViewBuilder
    private var apiKeyStatusBadge: some View {
        let key = dashscopeKeyStored.trimmingCharacters(in: .whitespacesAndNewlines)
        if key.isEmpty {
            Label("未配置", systemImage: "exclamationmark.circle")
                .font(.caption)
                .foregroundStyle(VColor.warn)
        } else if apiTestSuccess {
            Label("已连接", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(VColor.ok)
        } else {
            Label("已填写", systemImage: "circle.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @MainActor
    private func testAPIConnection() async {
        apiTestBusy = true
        apiTestResult = nil
        defer { apiTestBusy = false }

        let key = dashscopeKeyStored.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            apiTestResult = "请先填写 API Key"
            apiTestSuccess = false
            return
        }

        let model = modelPolish.trimmingCharacters(in: .whitespacesAndNewlines)

        let url = AppConfig.polishHTTPURL
        let httpBody: Data?
        #if DEBUG
        if AppConfig.polishUsesOpenAICompatChatCompletions {
            let body: [String: Any] = [
                "model": model,
                "messages": [["role": "user", "content": "hi"]],
            ]
            httpBody = try? JSONSerialization.data(withJSONObject: body)
        } else {
            let body: [String: Any] = [
                "model": model,
                "input": [
                    "messages": [
                        ["role": "user", "content": "你好"],
                    ],
                ],
                "parameters": ["result_format": "message"],
            ]
            httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        #else
        let body: [String: Any] = [
            "model": model,
            "input": [
                "messages": [
                    ["role": "user", "content": "你好"],
                ],
            ],
            "parameters": ["result_format": "message"],
        ]
        httpBody = try? JSONSerialization.data(withJSONObject: body)
        #endif

        guard let payloadData = httpBody else {
            apiTestResult = "请求构造失败"
            apiTestSuccess = false
            return
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = payloadData
        req.timeoutInterval = 12

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 12
        let session = URLSession(configuration: config)

        do {
            let (_, response) = try await session.data(for: req)
            if let http = response as? HTTPURLResponse {
                if (200 ... 299).contains(http.statusCode) {
                    apiTestResult = "✓ 连接成功（HTTP \(http.statusCode)）"
                    apiTestSuccess = true
                } else if http.statusCode == 401 {
                    apiTestResult = "✗ Key 无效（HTTP 401）"
                    apiTestSuccess = false
                } else if http.statusCode == 429 {
                    apiTestResult = "✓ Key 有效，当前限流（HTTP 429）"
                    apiTestSuccess = true
                } else {
                    apiTestResult = "✗ 异常（HTTP \(http.statusCode)）"
                    apiTestSuccess = false
                }
            }
        } catch {
            apiTestResult = "✗ 网络错误：\(error.localizedDescription)"
            apiTestSuccess = false
        }
    }

    private func modelPicker(title: String, options: [String], selection: Binding<String>) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .frame(width: 100, alignment: .leading)
            Picker("", selection: selection) {
                ForEach(options, id: \.self) { id in
                    Text(id).tag(id)
                }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func ensureModelPickersIncludeSelections() {
        if !asrModelOptions.contains(modelAsr) { asrModelOptions = [modelAsr] + asrModelOptions }
        if !textModelOptions.contains(modelPolish) { textModelOptions = [modelPolish] + textModelOptions }
        if !textModelOptions.contains(modelAnalyzer) { textModelOptions = [modelAnalyzer] + textModelOptions }
    }

    @MainActor
    private func refreshDashScopeModels() async {
        modelFetchHint = nil
        guard !dashscopeKeyStored.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            modelFetchHint = "请先填写百炼 API Key。"
            return
        }
        modelFetchBusy = true
        defer { modelFetchBusy = false }
        let key = dashscopeKeyStored.trimmingCharacters(in: .whitespacesAndNewlines)
        let all = await DashScopeModelCatalog.fetchModelIds(apiKey: key)
        let split = DashScopeModelCatalog.splitAsrAndText(from: all ?? [])
        asrModelOptions = split.asr
        textModelOptions = split.text
        ensureModelPickersIncludeSelections()
        modelFetchHint = all != nil
            ? "已更新 \(all!.count) 个模型 ID"
            : "已加载内置模型列表（云端接口暂不可用）"
    }

    // MARK: - 权限

    private var permissionsSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: VSpacing.md) {
                let _ = permissionRefreshTick

                permissionRow(
                    label: "麦克风",
                    icon: microphonePermissionIcon,
                    color: microphonePermissionColor,
                    status: microphonePermissionStatus,
                    onOpenSettings: { PermissionManager.shared.openMicrophonePrivacySettings() },
                    showRequestButton: PermissionManager.shared.checkMicrophonePermission() != .authorized,
                    onRequest: { PermissionManager.shared.showMicrophonePermissionAlert() }
                )

                permissionRow(
                    label: "辅助功能",
                    icon: accessibilityPermissionIcon,
                    color: accessibilityPermissionColor,
                    status: accessibilityPermissionStatus,
                    onOpenSettings: { PermissionManager.shared.openAccessibilityPrivacySettings() },
                    showRequestButton: !PermissionManager.shared.checkAccessibilityPermission(),
                    onRequest: { PermissionManager.shared.showAccessibilityPermissionAlert() }
                )

                if state.hotkeyAccessibilityRequired {
                    Text("需要辅助功能权限才能使用全局热键。")
                        .font(.caption)
                        .foregroundStyle(VColor.warn)
                }

                Button("重新检测") { permissionRefreshTick += 1 }
                    .controlSize(.small)
            }
        } label: {
            Label("权限", systemImage: "lock.shield.fill")
        }
    }

    private func permissionRow(
        label: String,
        icon: String,
        color: Color,
        status: String,
        onOpenSettings: @escaping () -> Void,
        showRequestButton: Bool,
        onRequest: @escaping () -> Void
    ) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 18)
            Text(label)
            Spacer()
            Text(status)
                .foregroundStyle(.secondary)
                .font(.callout)
            Button("系统设置") { onOpenSettings() }
                .controlSize(.small)
            if showRequestButton {
                Button("授权…") { onRequest() }
                    .controlSize(.small)
            }
        }
    }

    private var microphonePermissionStatus: String {
        switch PermissionManager.shared.checkMicrophonePermission() {
        case .authorized: return "已授权"
        case .denied: return "已拒绝"
        case .notDetermined: return "未询问"
        }
    }

    private var microphonePermissionIcon: String {
        switch PermissionManager.shared.checkMicrophonePermission() {
        case .authorized: return "checkmark.circle.fill"
        case .denied: return "xmark.circle.fill"
        case .notDetermined: return "questionmark.circle.fill"
        }
    }

    private var microphonePermissionColor: Color {
        switch PermissionManager.shared.checkMicrophonePermission() {
        case .authorized: return VColor.ok
        case .denied: return VColor.fail
        case .notDetermined: return VColor.warn
        }
    }

    private var accessibilityPermissionStatus: String {
        PermissionManager.shared.checkAccessibilityPermission() ? "已授权" : "未授权"
    }

    private var accessibilityPermissionIcon: String {
        PermissionManager.shared.checkAccessibilityPermission() ? "checkmark.circle.fill" : "xmark.circle.fill"
    }

    private var accessibilityPermissionColor: Color {
        PermissionManager.shared.checkAccessibilityPermission() ? VColor.ok : VColor.warn
    }

    // MARK: - 热键系统

    private var hotkeyHealthSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: VSpacing.md) {
                HStack {
                    Image(systemName: hotkeyHealthIconName)
                        .foregroundStyle(hotkeyHealthIconColor)
                    Text("系统状态")
                    Spacer()
                    Text(hotkeyHealthStatusText)
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }

                if let report = state.hotkeyHealthReport {
                    HStack {
                        Text("EventTap")
                        Spacer()
                        Text(report.canUseEventTap ? "可用" : "不可用")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                    HStack {
                        Text("FN / Globe")
                        Spacer()
                        Text(report.canUseFnKey ? "可能可用" : "不可用（已用右 ⌥）")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                }

                if let issues = state.hotkeyHealthReport?.issues, !issues.isEmpty {
                    VStack(alignment: .leading, spacing: VSpacing.xxs) {
                        Text("检测到的问题：")
                            .font(.caption)
                            .foregroundStyle(VColor.warn)
                        ForEach(issues, id: \.self) { issue in
                            Text("• \(issue)").font(.caption)
                        }
                    }
                }

                if let suggestions = state.hotkeyHealthReport?.suggestions, !suggestions.isEmpty {
                    VStack(alignment: .leading, spacing: VSpacing.xxs) {
                        Text("建议：")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(suggestions, id: \.self) { line in
                            Text("• \(line)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                Button("重新检测") {
                    state.hotkeyHealthReport = HotkeyHealthChecker.shared.performStartupCheck()
                }
                .controlSize(.small)
            }
        } label: {
            Label("热键系统", systemImage: "keyboard")
        }
    }

    private var hotkeyHealthIconName: String {
        switch state.hotkeyHealthReport?.status {
        case .some(.healthy): return "checkmark.circle.fill"
        case .some(.degraded): return "exclamationmark.triangle.fill"
        case .some(.unavailable): return "xmark.circle.fill"
        case .none: return "questionmark.circle"
        }
    }

    private var hotkeyHealthIconColor: Color {
        switch state.hotkeyHealthReport?.status {
        case .some(.healthy): return VColor.ok
        case .some(.degraded): return VColor.warn
        case .some(.unavailable): return VColor.fail
        case .none: return .secondary
        }
    }

    private var hotkeyHealthStatusText: String {
        switch state.hotkeyHealthReport?.status {
        case .some(.healthy): return "正常"
        case .some(.degraded): return "部分可用"
        case .some(.unavailable): return "不可用"
        case .none: return "未检测"
        }
    }

    // MARK: - AI 个性化学习

    private var aiLearningSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: VSpacing.sm) {
                HStack {
                    Text("已记录会话")
                    Spacer()
                    Text("\(rawLogCount) 条")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("触发阈值（自动分析）")
                    Spacer()
                    Text("\(Constants.analyzerTriggerThreshold) 条/次")
                        .foregroundStyle(.secondary)
                }
                HStack(alignment: .firstTextBaseline) {
                    Text("学习状态")
                    Spacer()
                    if analyzerRunning {
                        ProgressView()
                            .controlSize(.small)
                        Text("分析中…")
                            .foregroundStyle(.secondary)
                    } else if let summary = state.ai3LastAnalysisResult, let d = state.ai3LastAnalysisDate {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(d.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    } else if let run = analyzerStateLastRun, !run.isEmpty {
                        Text("上次分析: \(run)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("尚未运行")
                            .foregroundStyle(.tertiary)
                    }
                }

                HStack {
                    Button("立即分析") {
                        guard !analyzerRunning else { return }
                        analyzerRunning = true
                        Task {
                            await AI3Analyzer.shared.analyze()
                            await MainActor.run {
                                analyzerRunning = false
                                refreshAI3State()
                            }
                        }
                    }
                    .disabled(analyzerRunning || rawLogCount == 0 || !AppConfig.hasDashScopeAPIKey)

                    if rawLogCount == 0 {
                        Text("完成至少 1 次录音后可用")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    } else if !AppConfig.hasDashScopeAPIKey {
                        Text("需要配置 DashScope API Key 才能运行分析")
                            .font(.caption)
                            .foregroundStyle(VColor.warn)
                    }
                }

                if state.candidatesCount > 0 {
                    HStack {
                        Text("待审核推荐词")
                        Spacer()
                        Text("\(state.candidatesCount) 个")
                            .foregroundStyle(VColor.accent)
                    }
                    Button {
                        state.selectedNavItem = .dictionary
                        bringMainWindowToFront()
                    } label: {
                        Text("去词典查看")
                    }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundStyle(VColor.accent)
                }
            }
        } label: {
            Label("AI 个性化学习", systemImage: "brain")
        }
        .onAppear { refreshAI3State() }
    }

    private func bringMainWindowToFront() {
        for window in NSApp.windows {
            if window.identifier?.rawValue == "main" || window.title == "Vilsay" {
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                return
            }
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    private func refreshAI3State() {
        Task {
            guard let pool = try? AppDatabase.shared.dbPool else { return }
            let count = (try? await pool.read { db in try RawLogRecord.fetchCount(db) }) ?? 0
            let lastRun: String? = try? await pool.read { db in
                try AnalyzerStateRecord.fetchOne(db, key: 1)?.lastRunAt
            }
            await MainActor.run {
                rawLogCount = count
                analyzerStateLastRun = lastRun
            }
        }
    }

    // MARK: - 数据

    private var dataSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: VSpacing.sm) {
                HStack {
                    Text("清除 AI 学习数据")
                    Spacer()
                    Button("清除…") { showClearAILearningConfirm = true }
                        .foregroundStyle(VColor.fail)
                }
                Text("将清除所有语音记录、AI 画像和推荐词，手动词典不受影响。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } label: {
            Label("数据", systemImage: "externaldrive.fill")
        }
        .alert("清除 AI 学习数据？", isPresented: $showClearAILearningConfirm) {
            Button("取消", role: .cancel) {}
            Button("清除", role: .destructive) {
                do {
                    try AppDatabase.shared.clearAIData()
                    AppState.shared.candidatesCount = 0
                    AppState.shared.dictionaryBadgeCount = 0
                    AppState.shared.ai3LastAnalysisResult = nil
                    AppState.shared.ai3LastAnalysisDate = nil
                    refreshAI3State()
                } catch {
                    state.lastPipelineError = "清除数据失败：\(error.localizedDescription)"
                }
            }
        } message: {
            Text("将清除 raw_log、用户画像与候选推荐；手动词典保留。")
        }
    }

    // MARK: - 即将推出

    private var upcomingSection: some View {
        GroupBox {
            PlaceholderToggle(label: "翻译模式")
        } label: {
            Label("即将推出", systemImage: "sparkles")
        }
    }

    // MARK: - 关于

    private var aboutSection: some View {
        GroupBox {
            HStack(spacing: VSpacing.md) {
                Text("版本")
                Text(appVersion)
                    .foregroundStyle(.secondary)
                Text("·").foregroundStyle(.tertiary)
                Button("隐私政策") { showPrivacyPolicy = true }
                    .buttonStyle(.plain)
                    .foregroundStyle(VColor.accent)
                Text("·").foregroundStyle(.tertiary)
                Button("条款") { NSWorkspace.shared.open(WebsiteURL.terms) }
                    .buttonStyle(.plain)
                    .foregroundStyle(VColor.accent)
            }
            .font(.subheadline)
        } label: {
            Label("关于", systemImage: "info.circle.fill")
        }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

    // openPlaceholder removed — links now use WebsiteURL constants

    // MARK: - 应用输出模式（V4，UserDefaults 覆盖）

    private var outputModeOverridesSection: some View {
        GroupBox {
            DisclosureGroup(isExpanded: $outputModeSectionExpanded) {
                VStack(alignment: .leading, spacing: VSpacing.sm) {
                    Text("按 Bundle ID 覆盖自动识别；选「自动」则恢复映射表规则。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    ForEach(OutputModeResolver.knownBundleIDs, id: \.self) { bid in
                        HStack(alignment: .firstTextBaseline) {
                            Text(bid)
                                .font(.caption2)
                                .lineLimit(2)
                                .frame(maxWidth: 260, alignment: .leading)
                            Spacer(minLength: 8)
                            let resolved = OutputModeResolver.resolve(bundleID: bid)
                            Text("自动→\(resolved.title)")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            Picker("", selection: Binding(
                                get: {
                                    OutputModeResolver.userOverride(for: bid)?.rawValue ?? "__auto__"
                                },
                                set: { new in
                                    if new == "__auto__" {
                                        OutputModeResolver.setUserOverride(bundleID: bid, mode: nil)
                                    } else if let m = OutputMode(rawValue: new) {
                                        OutputModeResolver.setUserOverride(bundleID: bid, mode: m)
                                    }
                                }
                            )) {
                                Text("自动").tag("__auto__")
                                ForEach(OutputMode.allCases) { m in
                                    Text(m.title).tag(m.rawValue)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 120)
                        }
                    }
                }
                .padding(.top, VSpacing.xs)
            } label: {
                Text("已识别 \(OutputModeResolver.knownBundleIDs.count) 个应用；展开后为各 Bundle 设置覆盖模式。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } label: {
            Label("应用输出模式", systemImage: "app.badge.checkmark")
        }
    }

    // MARK: - 页脚：官网与反馈

    private var settingsFooterLinks: some View {
        HStack(spacing: VSpacing.lg) {
            Spacer(minLength: 0)
            Button {
                if let url = URL(string: "mailto:support@vilsay.com?subject=Vilsay%20%E5%8F%8D%E9%A6%88") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Label("联系我们", systemImage: "envelope")
            }
            .buttonStyle(.plain)
            .foregroundStyle(VColor.accent)
            .help("反馈意见：发送邮件至 shay1230xh@163.com")

            Text("·")
                .foregroundStyle(.tertiary)

            Button {
                NSWorkspace.shared.open(WebsiteURL.home)
            } label: {
                Label("进入官网", systemImage: "safari")
            }
            .buttonStyle(.plain)
            .foregroundStyle(VColor.accent)
            .help("在浏览器中打开 vilsay.com")
            Spacer(minLength: 0)
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity)
        .padding(.top, VSpacing.lg)
    }

    // MARK: - 开发者诊断（折叠，普通用户不感知）

    private var diagnosticsSection: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: VSpacing.xl) {
                RecentIssuesSection()
                MicTestSection()
                Week3PipelineTraceSection()
                HotkeySelfTestSection()
                AIDiagnosticsSection()
            }
            .padding(.top, VSpacing.md)
        } label: {
            Label("开发者诊断", systemImage: "wrench.and.screwdriver")
                .font(.system(size: 13, weight: .semibold))
        }
        .padding(20)
        .background(.thickMaterial,
                    in: RoundedRectangle(cornerRadius: VRadius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: VRadius.xl, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.05), radius: 1, x: 0, y: 1)
        .shadow(color: .black.opacity(0.08), radius: 16, x: 0, y: 6)
    }
}
