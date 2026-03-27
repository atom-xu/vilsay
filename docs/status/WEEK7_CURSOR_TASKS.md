# Week 7 · Cursor 任务书

> 版本：1.0 | 2026-03-25
> 前置条件：Week 5+6 开发完成 + 自动化测试通过 + FIX-01~08 修复完成
> 两大块：**W7-A（Onboarding 完整实现，10 任务）** + **W7-B（产品官网，8 任务）**

---

## W7-A · Onboarding 完整实现

> 参考文档：`docs/log/VILSAY_ONBOARDING.md`（状态机完整定义）
> 现状：`UI/OnboardingView.swift` 为 W2-04 占位版，缺少轮询、断点续传、真实 Auth 对接、WhisperKit 触发
> Auth 系统已在 W4 完整实现（`AuthService`、`OAuthSignInCoordinator`、`KeychainTokenStore`），本周只需**对接**

---

### W7-A01 · 断点续传：OnboardingStep 持久化

**目标**：App 中途关闭后重启，从上次未完成的步骤继续，而非回到 Step 0

**文件**：`Config/UserDefaultsKeys.swift`、`UI/OnboardingView.swift`

```swift
// 1. UserDefaultsKeys 新增
static let onboardingStep = "vilsay.onboarding_step"

// 2. OnboardingView 改造
// 2a. 启动时读取已完成步骤，定位到下一步
init(onFinished: @escaping () -> Void) {
    self.onFinished = onFinished
    let saved = UserDefaults.standard.integer(forKey: UserDefaultsKeys.onboardingStep)
    // 权限状态可能变化，不信任保存值，重新检测
    _step = State(initialValue: Self.resolveStartStep(fromSaved: saved))
}

// 2b. resolveStartStep 逻辑
private static func resolveStartStep(fromSaved saved: Int) -> Int {
    // saved=0 → welcome
    // saved>=1 → 检查麦克风是否已授权，已授权跳到 max(saved, 2)
    // saved>=2 → 检查 Accessibility，已授权跳到 max(saved, 3)
    // saved>=3 → 直接到 login
    // saved>=4 → 完成页
    // 关键：权限状态以运行时检测为准，不信任 saved 值
}

// 2c. 每步完成后存储
private func advanceTo(_ next: Int) {
    UserDefaults.standard.set(next, forKey: UserDefaultsKeys.onboardingStep)
    step = next
}
```

**验收**：
- [ ] 在 Step 2 强制退出 App，重启后直接从 Step 2 开始（不回 Step 0）
- [ ] 如果 Step 2 的麦克风已在系统设置授权，重启后跳到 Step 3
- [ ] `onboarding_step` 和 `onboarding_done` 分开存储，互不干扰

---

### W7-A02 · Step 2 麦克风权限：3 态 UI + 轮询

**目标**：替换当前的单次请求 + alert 方案，实现状态 A/B/C 三态流转 + 2 秒轮询

**文件**：`UI/OnboardingView.swift`

```
状态 A（请求中）：
  - 麦克风图标 + 脉冲动画
  - 文字："正在请求麦克风权限..."
  - 无按钮（等待系统弹窗结果）

状态 B（已拒绝）：
  - 麦克风图标红色
  - 文字："麦克风权限被拒绝"
  - 说明："请前往「系统设置 → 隐私与安全性 → 麦克风」中允许 Vilsay"
  - 按钮："打开系统设置"（调用 openMicrophonePrivacy()）

状态 C（等待用户去设置开启）：
  - 麦克风图标 + 脉冲等待动画
  - 文字："请在系统设置中开启麦克风权限"
  - 说明："开启后此页面将自动继续"
  - 按钮："我已开启"（主动检测一次）
  - 30 秒无响应后显示："可以稍后在设置中完成" 跳过按钮
```

**实现要点**：

```swift
// 状态枚举
@State private var micState: MicPermState = .initial
enum MicPermState { case initial, requesting, denied, waitingSettings }

// 轮询 Timer
@State private var micPollTimer: Timer?
@State private var micPollElapsed: Int = 0

private func startMicPolling() {
    micState = .waitingSettings
    micPollElapsed = 0
    micPollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
        Task { @MainActor in
            micPollElapsed += 2
            let status = AVAudioApplication.shared.recordPermission
            if status == .granted {
                micPollTimer?.invalidate()
                micPollTimer = nil
                advanceTo(2)
            }
        }
    }
}

// 进入此步骤时的分支
private func enterMicStep() {
    let status = AVAudioApplication.shared.recordPermission
    switch status {
    case .granted: advanceTo(2)  // 已有权限，直接跳过
    case .undetermined:
        micState = .requesting
        AVAudioApplication.requestRecordPermission { granted in
            DispatchQueue.main.async {
                if granted { advanceTo(2) }
                else { micState = .denied }
            }
        }
    case .denied: micState = .denied
    @unknown default: micState = .denied
    }
}
```

**验收**：
- [ ] 首次进入：系统弹窗 → 允许 → 自动进 Step 3
- [ ] 首次进入：系统弹窗 → 拒绝 → 显示状态 B
- [ ] 状态 B 点击"打开系统设置" → 跳转 → 显示状态 C → 在设置中开启 → 页面自动进 Step 3
- [ ] 状态 C 超 30 秒 → 出现跳过按钮
- [ ] 离开页面时 Timer 被 invalidate（onDisappear）

---

### W7-A03 · Step 3 辅助功能权限：4 态 UI + 1 秒轮询

**目标**：替换当前的"打开系统设置 + 手动点继续"方案，实现 4 态 + 自动检测

**文件**：`UI/OnboardingView.swift`

```
状态 A（未授权 - 初始）：
  - 键盘图标
  - 文字："需要辅助功能权限"
  - 说明："Vilsay 需要此权限将文字输入到任意应用程序"
  - 按钮："打开系统设置"

状态 B（等待用户操作）：
  - 键盘图标 + 脉冲动画
  - 文字："请在系统设置中开启 Vilsay 的辅助功能权限"
  - 分步说明：
    1. 在已打开的系统设置中找到 Vilsay
    2. 将开关打开
    3. 此页面将自动继续
  - 按钮："我已完成"（主动检测一次）
  - 小字："开启后页面自动跳转，无需手动操作"

状态 C（超时 30 秒）：
  - 在状态 B 基础上新增按钮："稍后完成"
  - 提示文字："跳过后将无法自动输入文字到其他应用，但仍可复制润色结果"

状态 D（已授权）：
  - 绿色对勾图标
  - 文字："辅助功能权限已开启"
  - 0.5 秒后自动进下一步
```

**实现要点**：

```swift
@State private var axState: AXPermState = .initial
enum AXPermState { case initial, notAuthorized, waitingSettings, timedOut, authorized }

@State private var axPollTimer: Timer?
@State private var axPollElapsed: Int = 0

private func enterAccessibilityStep() {
    if AXIsProcessTrusted() {
        axState = .authorized
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { advanceTo(3) }
    } else {
        axState = .notAuthorized
    }
}

private func openSettingsAndPoll() {
    openAccessibilityPrivacy()
    axState = .waitingSettings
    axPollElapsed = 0
    axPollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
        Task { @MainActor in
            axPollElapsed += 1
            if AXIsProcessTrusted() {
                axPollTimer?.invalidate()
                axPollTimer = nil
                axState = .authorized
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { advanceTo(3) }
            } else if axPollElapsed >= 30 {
                axState = .timedOut
                // Timer 继续跑，用户可能后来开启
            }
        }
    }
}
```

**验收**：
- [ ] 已有权限 → 绿色对勾 → 0.5 秒后自动下一步
- [ ] 无权限 → 点"打开系统设置" → 状态 B → 在设置中开启 → 自动检测到 → 下一步
- [ ] 30 秒未操作 → 显示"稍后完成"按钮 → 点击可跳过
- [ ] 跳过后 Step 4 和完成页正常流转
- [ ] Timer 在 onDisappear 和授权成功时都被 invalidate

---

### W7-A04 · Step 4 登录：对接真实 AuthService + OAuthSignInCoordinator

**目标**：将占位 OAuth 按钮接入已实现的 Auth 系统，登录成功后自动进完成页

**文件**：`UI/OnboardingView.swift`

**当前问题**：
- Apple/微信/Google 按钮的 action 为空 `{ // Week 4 OAuth }`
- 邮箱表单只有一个 TextField，无密码、无注册/登录切换
- "继续"按钮直接跳到 step 4，不检查登录状态

**改造方案**：

```swift
// 1. 复用 OAuthSignInCoordinator 和 AuthService
@StateObject private var auth = AuthService.shared

// 2. Apple 按钮
socialButton(title: "Apple", ...) {
    Task {
        await OAuthSignInCoordinator.shared.signInWithApple()
        // AuthService 会自动更新 isAuthenticated
        if auth.isAuthenticated { advanceTo(4) }
    }
}

// 3. Google 按钮
socialButton(title: "Google", ...) {
    OAuthSignInCoordinator.shared.signInWithGoogle()
    // 回调走 Deep Link → AuthService.handleDeepLink → isAuthenticated
}

// 4. 微信按钮
socialButton(title: "微信", ...) {
    OAuthSignInCoordinator.shared.signInWithWeChat()
}

// 5. 邮箱登录/注册：直接嵌入 LoginView 的核心逻辑
//    或改为 sheet { LoginView() }，登录成功后自动 dismiss + advanceTo(4)
//    推荐方案：按钮打开 LoginView sheet，避免 Onboarding 内代码膨胀
@State private var showLoginSheet = false

Button("邮箱登录 / 注册") { showLoginSheet = true }
.sheet(isPresented: $showLoginSheet) {
    LoginView()
        .frame(minWidth: 400, minHeight: 560)
}

// 6. 监听登录状态变化
.onChange(of: auth.isAuthenticated) { _, isAuth in
    if isAuth {
        showLoginSheet = false
        advanceTo(4)
    }
}

// 7. "跳过"按钮保留，但提示功能受限
Button("跳过登录") { advanceTo(4) }
    .help("跳过后可使用本地 WhisperKit，云端润色需登录")
```

**验收**：
- [ ] Apple 登录 → 系统弹窗 → 授权 → 自动进完成页
- [ ] Google 登录 → 浏览器 → 回调 → 自动进完成页
- [ ] 邮箱登录 → sheet → 输入 → 成功 → 自动进完成页
- [ ] "跳过登录" → 进完成页，菜单栏显示未登录状态
- [ ] 已登录用户（断点续传场景）进入 Step 4 → 检测到已登录 → 直接跳完成页

---

### W7-A05 · 完成页：WhisperKit 预载 + 使用引导

**目标**：完成页触发 WhisperKit 预载，显示下载进度，引导用户首次使用

**文件**：`UI/OnboardingView.swift`

**改造**：

```swift
private var completion: some View {
    VStack(spacing: VSpacing.lg) {
        Spacer()
        Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 52, weight: .light))
            .foregroundStyle(VColor.ok)

        VStack(spacing: VSpacing.sm) {
            Text("全部就绪")
                .font(.title2.weight(.bold))
            Text("按住悬浮按钮开始说话，松开后文字自动出现在光标位置。")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }

        // WhisperKit 预载状态
        if appState.localWhisperLoading {
            HStack(spacing: VSpacing.sm) {
                ProgressView()
                    .controlSize(.small)
                Text(appState.localWhisperStatusHint ?? "正在加载本地语音模型...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, VSpacing.sm)
        }

        // 快捷键提示
        VStack(alignment: .leading, spacing: VSpacing.xs) {
            Label("长按 Fn 开始录音", systemImage: "command")
            Label("悬浮按钮可拖到任意位置", systemImage: "hand.draw")
            Label("在菜单栏 🎤 中查看更多设置", systemImage: "menubar.rectangle")
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .padding(.vertical, VSpacing.sm)

        Spacer()

        Button("开始使用") {
            UserDefaults.standard.set(true, forKey: UserDefaultsKeys.onboardingDone)
            UserDefaults.standard.set(4, forKey: UserDefaultsKeys.onboardingStep)
            onFinished()
        }
        .buttonStyle(VPrimaryButtonStyle())
        .keyboardShortcut(.defaultAction)
    }
    .onAppear {
        // 触发 WhisperKit 预载
        Task {
            await WhisperASRFallback.shared.preloadIfNeeded()
        }
    }
}
```

**验收**：
- [ ] 进入完成页后 WhisperKit 开始下载/加载（看 AppState.localWhisperLoading）
- [ ] 加载中显示 ProgressView + 提示文字
- [ ] 加载完成后 ProgressView 消失
- [ ] 快捷键提示正确显示
- [ ] 点击"开始使用" → onboardingDone=true + onboardingStep=4 → 关闭窗口

---

### W7-A06 · AppDelegate 集成：Session 恢复 + 权限启动检查

**目标**：修复 AuthService.restoreSession() 未调用的问题；统一启动权限检查

**文件**：`App/AppDelegate.swift`

**现状问题**：
- `AuthService.shared.restoreSession()` 已实现但 **从未被调用**（App 重启后登录态丢失）
- Onboarding 完成后权限被撤销时，PermissionManager 已有检查，但无菜单栏状态联动

**改造**：

```swift
func applicationDidFinishLaunching(_ notification: Notification) {
    // ... 现有代码 ...

    // ⬇️ 新增：恢复登录态（在 DB setup 之后、Onboarding 之前）
    Task {
        await AuthService.shared.restoreSession()
    }

    // ⬇️ 新增：注册 didBecomeActive 权限重检
    NotificationCenter.default.addObserver(
        forName: NSApplication.didBecomeActiveNotification,
        object: nil, queue: .main
    ) { [weak self] _ in
        self?.recheckPermissions()
    }

    // 现有 Onboarding 代码
    let ob = OnboardingWindowController()
    ob.showIfNeeded()
    onboarding = ob
}

/// 从系统设置回来后重新检测权限
private func recheckPermissions() {
    let micGranted = AVAudioApplication.shared.recordPermission == .granted
    let axGranted = AXIsProcessTrusted()

    // 更新 AppState 以驱动菜单栏图标/警告
    DispatchQueue.main.async {
        AppState.shared.microphoneGranted = micGranted
        AppState.shared.accessibilityGranted = axGranted
        // 如果任一权限被撤销，hotkeyAccessibilityRequired 已由 PermissionManager 处理
    }
}
```

**AppState 新增属性**（如尚未有）：

```swift
@Published var microphoneGranted: Bool = false
@Published var accessibilityGranted: Bool = false
```

**验收**：
- [ ] App 重启后 AuthService.isAuthenticated 正确恢复（不需要重新登录）
- [ ] 权限被撤销后回到 App → AppState 更新 → 菜单栏可感知
- [ ] Onboarding 未完成时显示引导窗口，已完成时不显示

---

### W7-A07 · 权限撤销后的菜单栏警告

**目标**：Onboarding 完成后，用户在系统设置撤销权限 → 菜单栏图标变橙色 + 展开显示修复引导

**文件**：`UI/MenuBarRootMenu.swift`

**实现**：

```swift
// 在菜单最顶部，条件显示权限警告
if !appState.microphoneGranted {
    Section {
        Label("⚠️ 麦克风权限已关闭", systemImage: "mic.slash")
        Button("打开系统设置修复") {
            openMicrophonePrivacy()
        }
        Text("录音功能不可用，请重新授权")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

if !appState.accessibilityGranted {
    Section {
        Label("⚠️ 辅助功能权限已关闭", systemImage: "keyboard.badge.exclamationmark")
        Button("打开系统设置修复") {
            openAccessibilityPrivacy()
        }
        Text("文字注入不可用，润色结果只能复制")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
```

**菜单栏图标状态**（在 vilsayApp.swift 或 MenuBarRootMenu 中）：

```swift
// 菜单栏图标根据权限状态变化
var menuBarIcon: String {
    if !appState.microphoneGranted || !appState.accessibilityGranted {
        return "mic.badge.xmark"  // 橙色/警告态
    }
    return currentRecordingIcon  // 正常状态（idle/recording/processing 等）
}
```

**验收**：
- [ ] 撤销麦克风权限 → 回到 App → 菜单栏出现警告段落
- [ ] 撤销辅助功能权限 → 同上
- [ ] 点击"打开系统设置修复" → 跳转到对应设置页
- [ ] 重新授权后 → 警告消失

---

### W7-A08 · Onboarding UI 动画与过渡

**目标**：步骤切换添加过渡动画，权限等待添加脉冲动画，提升体验

**文件**：`UI/OnboardingView.swift`

```swift
// 1. 步骤切换动画
Group {
    switch step {
    case 0: welcome
    case 1: microphone
    case 2: accessibilityStep
    case 3: loginStep
    default: completion
    }
}
.animation(.easeInOut(duration: 0.3), value: step)
.transition(.asymmetric(
    insertion: .move(edge: .trailing).combined(with: .opacity),
    removal: .move(edge: .leading).combined(with: .opacity)
))

// 2. 等待脉冲动画（共用）
struct PulseIcon: View {
    let systemName: String
    @State private var isPulsing = false

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 52, weight: .light))
            .foregroundStyle(VColor.accent)
            .scaleEffect(isPulsing ? 1.08 : 1.0)
            .opacity(isPulsing ? 0.7 : 1.0)
            .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: isPulsing)
            .onAppear { isPulsing = true }
    }
}

// 3. 进度指示器（底部 4 个圆点）
struct StepIndicator: View {
    let currentStep: Int
    let totalSteps: Int = 4

    var body: some View {
        HStack(spacing: VSpacing.sm) {
            ForEach(0..<totalSteps, id: \.self) { i in
                Circle()
                    .fill(i <= currentStep ? VColor.accent : Color.secondary.opacity(0.3))
                    .frame(width: 8, height: 8)
                    .animation(.easeInOut(duration: 0.2), value: currentStep)
            }
        }
    }
}
```

**验收**：
- [ ] 步骤切换有左右滑动 + 淡入淡出效果
- [ ] 等待权限时图标有脉冲缩放动画
- [ ] 底部 4 点进度指示器跟随步骤高亮
- [ ] 动画流畅无卡顿

---

### W7-A09 · OnboardingView 清理 + Timer 生命周期

**目标**：确保所有 Timer 在视图消失时清理，避免内存泄漏

**文件**：`UI/OnboardingView.swift`

```swift
// 统一清理
.onDisappear {
    micPollTimer?.invalidate()
    micPollTimer = nil
    axPollTimer?.invalidate()
    axPollTimer = nil
}

// 每个步骤离开时也清理对应 Timer
private func advanceTo(_ next: Int) {
    // 清理当前步骤的 Timer
    if step == 1 { micPollTimer?.invalidate(); micPollTimer = nil }
    if step == 2 { axPollTimer?.invalidate(); axPollTimer = nil }

    UserDefaults.standard.set(next, forKey: UserDefaultsKeys.onboardingStep)
    step = next
}
```

**验收**：
- [ ] 在 Step 2 等待中直接关闭窗口 → Timer 被清理（Instruments 无泄漏）
- [ ] 在 Step 3 等待中直接关闭窗口 → 同上
- [ ] 快速连续点"上一步""下一步" → 无崩溃、无多个 Timer 叠加

---

### W7-A10 · Onboarding 自动化测试

**目标**：为 Onboarding 核心逻辑编写 Swift Testing 自动测试

**文件**：`vilsayTests/OnboardingTests.swift`

```swift
import Testing
import Foundation

@Suite("Onboarding 逻辑测试")
struct OnboardingTests {

    @Test("断点续传：resolveStartStep 从 saved=0 开始")
    func resumeFromWelcome() {
        // 测试 resolveStartStep(fromSaved: 0) 返回 0
    }

    @Test("断点续传：saved=2 但麦克风已授权 → 跳到 2")
    func resumeSkipsGrantedMic() {
        // 模拟麦克风已授权场景
    }

    @Test("UserDefaultsKeys 不重复")
    func keysUnique() {
        let keys = [
            UserDefaultsKeys.onboardingDone,
            UserDefaultsKeys.onboardingStep,
        ]
        #expect(Set(keys).count == keys.count)
    }

    @Test("advanceTo 存储 step 值")
    func advanceToSavesStep() {
        // 用独立 UserDefaults suite 测试
        let defaults = UserDefaults(suiteName: "test.onboarding")!
        defaults.set(2, forKey: UserDefaultsKeys.onboardingStep)
        #expect(defaults.integer(forKey: UserDefaultsKeys.onboardingStep) == 2)
        defaults.removePersistentDomain(forName: "test.onboarding")
    }

    @Test("完成后 onboardingDone = true")
    func completionSetsFlag() {
        let defaults = UserDefaults(suiteName: "test.onboarding")!
        defaults.set(true, forKey: UserDefaultsKeys.onboardingDone)
        #expect(defaults.bool(forKey: UserDefaultsKeys.onboardingDone) == true)
        defaults.removePersistentDomain(forName: "test.onboarding")
    }
}
```

> 注意：权限轮询和 OAuth 流程涉及系统 API，无法在 CI 自动测试。
> 本测试仅覆盖纯逻辑部分（状态机、持久化、Key 唯一性）。
> 权限和登录的完整验收依赖手动测试（见 VILSAY_ONBOARDING.md 测试场景清单）。

**验收**：
- [ ] `xcodebuild test -only-testing:vilsayTests/OnboardingTests` 全部通过

---

## W7-B · 产品官网

> 技术栈：Next.js 14 (App Router) + Tailwind CSS + TypeScript
> 部署：Vercel（或自建 Nginx）
> 域名：vilsay.com
> 目录：项目根下新建 `website/`

---

### W7-B01 · Next.js 项目初始化

**目标**：创建 `website/` 目录，初始化 Next.js + Tailwind 项目骨架

```bash
cd /Users/atom/Desktop/Vilsay
npx create-next-app@latest website \
  --typescript --tailwind --eslint --app \
  --src-dir --import-alias "@/*" --no-turbo
```

**文件结构**：

```
website/
├── src/
│   ├── app/
│   │   ├── layout.tsx          # 全局 Layout（导航 + 页脚）
│   │   ├── page.tsx            # 首页 Landing
│   │   ├── docs/
│   │   │   └── page.tsx        # 文档页
│   │   ├── pricing/
│   │   │   └── page.tsx        # 定价页
│   │   ├── dashboard/
│   │   │   └── page.tsx        # 用量面板（需登录）
│   │   ├── privacy/
│   │   │   └── page.tsx        # 隐私政策
│   │   └── terms/
│   │       └── page.tsx        # 服务条款
│   ├── components/
│   │   ├── Navbar.tsx
│   │   ├── Footer.tsx
│   │   ├── Hero.tsx
│   │   ├── FeatureGrid.tsx
│   │   ├── PricingCard.tsx
│   │   └── DownloadButton.tsx
│   └── lib/
│       └── api.ts              # 后端 API 封装
├── public/
│   ├── demo.gif                # 产品演示动图
│   ├── icon.png                # Favicon / Logo
│   └── og-image.png            # Open Graph 社交分享图
├── tailwind.config.ts
├── next.config.ts
└── package.json
```

**Design Tokens（与 App 对齐）**：

```typescript
// tailwind.config.ts 扩展
colors: {
  vilsay: {
    accent: '#007AFF',        // 与 VColor.accent 对齐
    bg: '#FAFAFA',
    card: '#FFFFFF',
    text: { primary: '#1A1A1A', secondary: '#6B7280', tertiary: '#9CA3AF' },
    ok: '#34C759',
    warn: '#FF9500',
    fail: '#FF3B30',
  }
}
```

**验收**：
- [ ] `cd website && npm run dev` 可启动本地开发服务器
- [ ] `npm run build` 无报错
- [ ] Layout 有导航栏 + 页脚
- [ ] 导航栏包含：Logo、文档、定价、下载按钮

---

### W7-B02 · 首页 Hero 区域

**目标**：Landing 首屏 Hero，传达核心价值 + 演示 GIF + 下载按钮

**文件**：`website/src/app/page.tsx`、`website/src/components/Hero.tsx`

```
┌─────────────────────────────────────────────────────────┐
│  导航栏：Logo | 文档 | 定价 | [下载 Vilsay]            │
├─────────────────────────────────────────────────────────┤
│                                                         │
│        说话，比打字更快                                   │
│        而且越用越懂你                                     │
│                                                         │
│  macOS 原生语音润色应用。按住说话，松开即得              │
│  流畅文字——自动纠错、润色、适配你的表达习惯。            │
│                                                         │
│  [下载 for macOS]  [查看文档 →]                         │
│                                                         │
│        ┌──────────────────────────┐                     │
│        │    产品演示 GIF/Video    │                     │
│        │  （录音→润色→输出全程）   │                     │
│        └──────────────────────────┘                     │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

**细节**：
- Hero 标题：`text-5xl font-bold`，副标题 `text-xl text-secondary`
- 下载按钮：链接到 Mac App Store（上架前链接到 GitHub Releases 或占位）
- 演示 GIF：`public/demo.gif`，尺寸 800×500 以内，居中，带圆角阴影
- 响应式：移动端标题 `text-3xl`，GIF 全宽

**验收**：
- [ ] Hero 文案清晰可读
- [ ] 下载按钮可点击（上架前可指向 `#`）
- [ ] 演示 GIF 占位（先用灰色 placeholder，有真实 GIF 后替换）
- [ ] 移动端自适应

---

### W7-B03 · 首页功能亮点 + 工作原理

**目标**：Hero 下方展示 4 个核心功能 + 3 步工作原理

**文件**：`website/src/components/FeatureGrid.tsx`

```
## 功能亮点（4 卡片网格，2×2）

┌──────────────────┐  ┌──────────────────┐
│ 🎤 即时语音录入    │  │ ✨ AI 智能润色     │
│ 按住说话，松手输出  │  │ 纠错、润色、保留    │
│ 延迟 < 1.5 秒     │  │ 你的表达习惯       │
└──────────────────┘  └──────────────────┘
┌──────────────────┐  ┌──────────────────┐
│ 🧠 越用越懂你     │  │ 🔒 隐私优先       │
│ AI 学习你的口头禅  │  │ 音频本地处理       │
│ 专业术语、表达风格  │  │ 不上传录音文件     │
└──────────────────┘  └──────────────────┘

## 工作原理（3 步横向）

  ① 按住说话        → ② AI 润色          → ③ 文字自动出现
  录音在设备上处理     纠错+润色+个性化      插入到光标所在位置
```

**验收**：
- [ ] 4 个功能卡片等宽等高，有图标、标题、描述
- [ ] 3 步工作原理有序号和箭头连接
- [ ] 移动端卡片变为单列

---

### W7-B04 · 定价页

**目标**：展示 Free / Pro 方案对比

**文件**：`website/src/app/pricing/page.tsx`、`website/src/components/PricingCard.tsx`

```
┌─────────────────────┐  ┌─────────────────────┐
│       Free           │  │       Pro            │
│                      │  │                      │
│  ¥0 / 月             │  │  ¥XX / 月            │
│                      │  │                      │
│  ✓ 每日 N 次免费     │  │  ✓ 无限次使用         │
│  ✓ 本地 WhisperKit   │  │  ✓ 云端高速 ASR       │
│  ✓ 基础润色          │  │  ✓ AI3 个性化学习     │
│  ✗ AI3 学习          │  │  ✓ 优先技术支持       │
│  ✗ 自定义词典        │  │  ✓ 自定义词典         │
│                      │  │                      │
│  [开始使用]          │  │  [升级 Pro]           │
└─────────────────────┘  └─────────────────────┘

  支持 BYOK（自带 API Key）模式：
  已有 DashScope Key？可在设置中填入，享受 Pro 功能。
```

> 具体价格和配额数字需产品确认后填入，先用占位符 `¥XX`

**验收**：
- [ ] 两栏对比清晰，Pro 栏视觉突出（推荐标签/边框高亮）
- [ ] BYOK 说明放在对比卡片下方
- [ ] 移动端两栏变单列堆叠

---

### W7-B05 · 文档页：快速开始 + 功能说明 + FAQ

**目标**：用户自助文档，减少支持压力

**文件**：`website/src/app/docs/page.tsx`

```
## 快速开始（3 步）
1. 下载安装 → 打开 Vilsay
2. 完成引导（麦克风 + 辅助功能权限）
3. 按住悬浮按钮说话 → 松开 → 文字自动输入

## 功能说明
### 录音与识别
- 支持 DashScope 云端 ASR（默认）和本地 WhisperKit（断网降级）
- 自动检测语音停顿，智能断句

### AI 润色
- 纠正语音识别错误
- 根据你的习惯润色文字
- 支持邮件、聊天、笔记等不同场景自动切换语气

### 个性化学习（AI3）
- 自动学习你的口头禅和专业术语
- 词典管理：审核推荐词、手动添加
- 越用越准

### 快捷键
- Fn 长按：开始/结束录音
- 悬浮按钮可拖动到屏幕任意位置

## 常见问题 FAQ（Accordion 折叠）
- Q: 录音会上传到服务器吗？  A: 不会，音频仅在本地处理...
- Q: 支持哪些语言？  A: 目前支持中文普通话...
- Q: Pro 和 BYOK 有什么区别？  A: Pro 使用我们的服务器代理...
- Q: 如何重置 AI 学习数据？  A: 设置 → 数据 → 清除 AI 学习数据...
- Q: macOS 版本要求？  A: macOS 14 (Sonoma) 及以上...
- Q: 辅助功能权限是否安全？  A: 仅用于文字输入，不读取屏幕内容...
```

**验收**：
- [ ] 快速开始 3 步清晰易读
- [ ] FAQ 折叠展开正常
- [ ] 页面有左侧目录导航（锚点跳转）

---

### W7-B06 · 用量面板（需登录）

**目标**：登录用户查看使用量、订阅状态、账号管理

**文件**：`website/src/app/dashboard/page.tsx`、`website/src/lib/api.ts`

```
┌─────────────────────────────────────────┐
│  我的账号                    [登出]      │
├─────────────────────────────────────────┤
│                                         │
│  📊 本月使用量                           │
│  ┌──────────────────────────┐           │
│  │  已用 156 / 500 次       │           │
│  │  ████████░░░░░░░░  31%   │           │
│  │  重置日期：2026-04-01     │           │
│  └──────────────────────────┘           │
│                                         │
│  📈 使用趋势（近 30 天折线图）           │
│  ┌──────────────────────────┐           │
│  │ ^                        │           │
│  │ |    *   *               │           │
│  │ |  *   *   *  *          │           │
│  │ └──────────────────> 日期 │           │
│  └──────────────────────────┘           │
│                                         │
│  🔑 订阅方案                             │
│  当前：Free（或 Pro / BYOK）             │
│  [升级到 Pro]                            │
│                                         │
│  ⚙️ 账号设置                             │
│  邮箱：atom@example.com                  │
│  [修改密码]  [删除账号]                   │
│                                         │
└─────────────────────────────────────────┘
```

**API 对接**：

```typescript
// website/src/lib/api.ts
const API_BASE = process.env.NEXT_PUBLIC_API_BASE || 'https://api.vilsay.com/api/v1'

export async function getUsage(token: string) {
  const res = await fetch(`${API_BASE}/usage/stats`, {
    headers: { Authorization: `Bearer ${token}` }
  })
  return res.json()  // { used: number, quota: number, resetDate: string, history: [...] }
}

export async function getProfile(token: string) {
  const res = await fetch(`${API_BASE}/auth/profile`, {
    headers: { Authorization: `Bearer ${token}` }
  })
  return res.json()  // { email: string, plan: string, createdAt: string }
}
```

> 注意：后端 API 可能未完全实现，用量面板可先用 mock 数据开发，后端就绪后对接。
> 登录态管理：网页端需独立 OAuth 流程（与 App 的 Keychain 不共享），可用 cookie-based session 或 JWT localStorage。

**验收**：
- [ ] 未登录时跳转到登录页（或显示登录提示）
- [ ] 登录后显示用量进度条 + 趋势图
- [ ] 折线图至少有占位数据可视化（推荐 recharts 或 Chart.js）
- [ ] "升级到 Pro" 按钮跳转定价页

---

### W7-B07 · 法律页面：隐私政策 + 服务条款

**目标**：App Store 审核必需的隐私政策和服务条款

**文件**：`website/src/app/privacy/page.tsx`、`website/src/app/terms/page.tsx`

**隐私政策核心内容**：

```markdown
# Vilsay 隐私政策
最后更新：2026-03-25

## 我们收集的信息
- 账号信息：邮箱地址（注册时）
- 使用数据：润色次数、使用频率（匿名统计）
- 语音数据：**仅在设备本地处理，从不上传录音文件**

## 我们不收集的信息
- 录音音频文件
- 润色前的原始语音识别文本
- 剪贴板内容

## AI3 个性化数据
- 用户画像数据存储在**设备本地 SQLite 数据库**
- 不同步到云端
- 用户可随时在设置中清除

## 第三方服务
- DashScope（阿里云）：仅传输文字进行润色，不传输音频
- Apple Sign-In / Google OAuth：仅用于身份验证

## 数据删除
- 设置 → 数据 → 清除 AI 学习数据
- 注销账号：发送邮件至 privacy@vilsay.com

## 联系我们
privacy@vilsay.com
```

**服务条款核心内容**：

```markdown
# Vilsay 服务条款
最后更新：2026-03-25

## 服务说明
Vilsay 是 macOS 语音润色工具...

## 使用限制
- 免费版每日使用次数有限
- 禁止滥用 API 接口
- 禁止逆向工程

## 付费服务
- Pro 订阅按月计费
- 可随时取消，当月仍可使用至到期

## 免责声明
- AI 润色结果仅供参考
- 不保证 100% 准确

## 变更通知
- 条款变更将通过应用内通知和邮件告知
```

> 正式法律文本需法务审核，此版本为开发占位。URL 必须在上架前生效：
> - `https://vilsay.com/privacy` — App Store 审核要求
> - `https://vilsay.com/terms`

**验收**：
- [ ] `/privacy` 和 `/terms` 页面正常渲染
- [ ] 内容结构清晰，有目录锚点
- [ ] 移动端可读
- [ ] App 内"隐私政策"链接指向此页面（替换 `example.com` 占位）

---

### W7-B08 · SEO + Open Graph + 部署

**目标**：搜索引擎优化 + 社交分享预览 + 部署上线

**文件**：`website/src/app/layout.tsx`、`website/next.config.ts`

```typescript
// layout.tsx metadata
export const metadata: Metadata = {
  title: 'Vilsay - macOS 语音润色应用',
  description: '按住说话，松开即得流畅文字。AI 自动纠错润色，越用越懂你。',
  openGraph: {
    title: 'Vilsay - 说话比打字更快',
    description: 'macOS 原生语音润色应用，AI 纠错 + 个性化学习',
    images: ['/og-image.png'],
    url: 'https://vilsay.com',
    siteName: 'Vilsay',
    locale: 'zh_CN',
    type: 'website',
  },
  twitter: {
    card: 'summary_large_image',
    title: 'Vilsay - macOS 语音润色应用',
    description: '按住说话，松开即得流畅文字',
    images: ['/og-image.png'],
  },
  robots: { index: true, follow: true },
}
```

**部署（Vercel 推荐）**：

```bash
# 1. 在 Vercel 创建项目，关联 Git 仓库
# 2. Root Directory 设为 website
# 3. Build Command: npm run build
# 4. 绑定域名 vilsay.com
# 5. 环境变量：NEXT_PUBLIC_API_BASE=https://api.vilsay.com/api/v1
```

**验收**：
- [ ] `npm run build` 无报错
- [ ] 所有页面 Lighthouse Performance ≥ 90
- [ ] 社交分享（微信/Twitter）显示 OG 图片和描述
- [ ] 部署到 Vercel 后所有页面可访问
- [ ] 域名 HTTPS 正常

---

## 任务总览

| 编号 | 任务 | 优先级 | 依赖 |
|------|------|--------|------|
| W7-A01 | 断点续传 | HIGH | — |
| W7-A02 | 麦克风权限 3 态 | HIGH | A01 |
| W7-A03 | 辅助功能权限 4 态 | HIGH | A01 |
| W7-A04 | 登录对接 AuthService | HIGH | A01 |
| W7-A05 | 完成页 WhisperKit 预载 | MEDIUM | A04 |
| W7-A06 | AppDelegate 集成 | HIGH | A04 |
| W7-A07 | 权限撤销菜单栏警告 | MEDIUM | A06 |
| W7-A08 | 动画与过渡 | LOW | A02, A03 |
| W7-A09 | Timer 清理 | HIGH | A02, A03 |
| W7-A10 | 自动化测试 | MEDIUM | A01~A09 |
| W7-B01 | Next.js 初始化 | HIGH | — |
| W7-B02 | Hero 区域 | HIGH | B01 |
| W7-B03 | 功能亮点 + 工作原理 | MEDIUM | B01 |
| W7-B04 | 定价页 | MEDIUM | B01 |
| W7-B05 | 文档页 | MEDIUM | B01 |
| W7-B06 | 用量面板 | LOW | B01 |
| W7-B07 | 法律页面 | HIGH | B01 |
| W7-B08 | SEO + 部署 | HIGH | B01~B07 |

**建议执行顺序**：
- W7-A 和 W7-B 可**并行**（App 端 vs Web 端互不干扰）
- W7-A 内部：A01 → A02+A03 并行 → A04 → A05+A06 并行 → A07 → A08 → A09 → A10
- W7-B 内部：B01 → B02 → B03+B04+B05 并行 → B06 → B07 → B08

---

## 变更记录

| 版本 | 日期 | 变更 |
|------|------|------|
| 1.0 | 2026-03-25 | 初始版本：W7-A（10 任务）+ W7-B（8 任务） |
