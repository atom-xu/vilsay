# VILSAY · Onboarding 引导开发文档
# Onboarding Specification
# 版本：1.0 | 日期：2026-03-22
# 开发时机：主系统全部稳定后（Week 6 之后）独立开发
# ⚠️ 此模块涉及多次系统跳转，状态机复杂，不与主系统混合开发

---

## 一、为什么单独开发

```
Onboarding 涉及三次系统级跳转：

跳转1：麦克风权限
  → 系统弹窗（App 失去焦点）
  → 用户选择「允许」或「拒绝」
  → 回到 App（需判断权限结果）

跳转2：Accessibility 权限
  → 跳出到「系统偏好设置 → 隐私与安全性 → 辅助功能」
  → 用户手动开关（App 完全失去焦点）
  → 用户手动回到 App（无系统回调）
  → 需要 App 主动轮询检测权限状态

跳转3：第三方登录
  → 微信/Google：跳出到 Safari 或授权页面
  → Apple：系统弹窗
  → 回调到 App（需处理 URL Scheme）

风险：
  主系统不稳定时，Onboarding 的状态机错误
  会导致用户卡死在引导流程中无法正常使用
  因此必须等主系统验证稳定后再做 Onboarding
```

---

## 二、Onboarding 完整状态机

```
                    ┌─────────────────┐
                    │   App 首次启动   │
                    └────────┬────────┘
                             ↓
                    ┌─────────────────┐
                    │  检查 onboarding │
                    │  _done 标志      │
                    └────────┬────────┘
                    ┌────────┴────────┐
                  true              false
                    ↓                 ↓
              ┌──────────┐    ┌──────────────┐
              │ 主界面   │    │  Step 1 欢迎 │
              └──────────┘    └──────┬───────┘
                                     ↓
                             ┌──────────────────────┐
                             │  Step 2 麦克风权限    │
                             │                      │
                             │  检查当前权限状态：   │
                             │  ① authorized → 跳过 │
                             │  ② notDetermined → 请求│
                             │  ③ denied → 引导设置  │
                             └──────────┬───────────┘
                                        ↓
                          ┌─────────────────────────┐
                          │  等待权限结果             │
                          │  （系统弹窗，App失焦）    │
                          └──────────┬──────────────┘
                          ┌──────────┴──────────┐
                        允许                   拒绝
                          ↓                     ↓
                   ┌──────────┐        ┌────────────────┐
                   │ Step 3   │        │ 显示「权限被拒」│
                   │Accessibility│     │ 提示+重试按钮  │
                   └────┬─────┘        └────────────────┘
                        ↓
              ┌──────────────────────────────────┐
              │  Step 3 Accessibility 权限        │
              │                                  │
              │  检查权限状态：                   │
              │  ① 已授权 → 跳过                 │
              │  ② 未授权：                      │
              │    按钮「打开系统设置」           │
              │    → 跳出到系统偏好设置           │
              │    → App 开始轮询（每1秒检测）    │
              │    → 检测到授权 → 自动进下一步   │
              │    → 用户点「我已完成」→ 再检测  │
              │    → 超时30秒未授权 → 提示可跳过 │
              └──────────────┬───────────────────┘
                             ↓
                    ┌─────────────────┐
                    │  Step 4 登录    │
                    │  （见下方）     │
                    └────────┬────────┘
                             ↓
                    ┌─────────────────┐
                    │ 设置 onboarding │
                    │ _done = true    │
                    └────────┬────────┘
                             ↓
                    ┌─────────────────┐
                    │    主界面       │
                    └─────────────────┘
```

---

## 三、各步骤详细状态处理

### Step 2：麦克风权限

```swift
// 三种权限状态的处理

switch AVCaptureDevice.authorizationStatus(for: .audio) {

case .authorized:
    // 已有权限，直接跳到 Step 3
    proceedToStep3()

case .notDetermined:
    // 首次请求
    AVCaptureDevice.requestAccess(for: .audio) { granted in
        DispatchQueue.main.async {
            if granted {
                self.proceedToStep3()
            } else {
                self.showMicDeniedState()
            }
        }
    }

case .denied, .restricted:
    // 已被拒绝，引导去系统设置
    showMicDeniedState()
    // 显示：「麦克风权限被拒绝」
    // 按钮：「打开系统设置」→ NSWorkspace.open 系统麦克风设置
    // 轮询：每2秒检查一次，授权后自动继续

}
```

**UI 状态（3种）：**
```
状态A：请求中
  图标：🎤 动画
  文字：正在请求麦克风权限...
  无按钮

状态B：已拒绝
  图标：🎤 红色
  文字：麦克风权限被拒绝
  说明：请前往「系统设置 → 隐私与安全性 → 麦克风」开启
  按钮：打开系统设置

状态C：等待用户去设置里开启（从B跳转后）
  图标：🎤 脉冲等待动画
  文字：请在系统设置中开启麦克风权限
  说明：开启后此页面将自动继续
  按钮：我已开启（点击后主动检测一次）
  计时：如果30秒无反应，显示「可以稍后在设置中完成」跳过按钮
```

---

### Step 3：Accessibility 权限

```swift
// Accessibility 权限特殊性：
// 系统不提供授权回调，只能主动检测

func checkAccessibilityPermission() -> Bool {
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
    return AXIsProcessTrustedWithOptions(options as CFDictionary)
}

// 轮询逻辑
var pollingTimer: Timer?

func startPollingAccessibility() {
    pollingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
        if self.checkAccessibilityPermission() {
            self.pollingTimer?.invalidate()
            self.proceedToStep4()
        }
    }
}

// 打开系统设置的准确路径（macOS 13+）
func openAccessibilitySettings() {
    let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
    NSWorkspace.shared.open(url)
    startPollingAccessibility()  // 跳出后开始轮询
}
```

**UI 状态（4种）：**
```
状态A：未授权（初始）
  图标：⌨️
  文字：需要辅助功能权限
  说明：Vilsay 需要此权限将文字输入到任意应用程序
  按钮：打开系统设置

状态B：等待用户操作（跳出后）
  图标：⌨️ 脉冲动画
  文字：请在系统设置中开启 Vilsay 的辅助功能权限
  步骤说明：
    1. 在已打开的系统设置中找到 Vilsay
    2. 将开关打开
    3. 此页面将自动继续
  按钮：我已完成（主动检测一次）
  小字：开启后页面自动跳转，无需手动操作

状态C：超时30秒未完成
  新增按钮：稍后完成（可跳过，但部分功能不可用）
  注意：跳过后主链路无法注入文字，提示用户

状态D：已授权
  图标：✅
  自动进入下一步（0.5秒后）
```

---

### Step 4：登录

```
登录跳转处理：

Apple ID：
  系统弹窗，App 不失焦
  回调：ASAuthorizationControllerDelegate
  成功 → 直接进完成页

微信登录：
  打开微信 App 或浏览器
  App 进入后台
  微信回调 URL Scheme（需配置）
  AppDelegate 处理 openURL
  成功 → 进完成页

Google 登录：
  打开 Safari（ASWebAuthenticationSession）
  App 不完全失焦（Sheet 形式）
  成功回调
  成功 → 进完成页

邮箱注册：
  App 内完成（无跳转）
  发送验证邮件
  显示「请查收验证邮件」等待界面
  用户点验证链接（跳出到浏览器）→ 回来
  需要：验证邮件中的链接能打开 App（Universal Link 或 URL Scheme）
  验证成功 → 进完成页
```

**邮件验证等待界面：**
```
┌─────────────────────────────────┐
│                                 │
│        📧                      │
│                                 │
│   验证邮件已发送                 │
│                                 │
│   请查收 atom@example.com       │
│   的验证邮件，点击邮件中的链接   │
│   完成注册                      │
│                                 │
│   [ 重新发送验证邮件 ]  60s     │
│                                 │
│   没收到？检查垃圾邮件            │
│   或更换邮箱重新注册             │
│                                 │
└─────────────────────────────────┘

轮询：每3秒检查账号是否已验证
验证成功 → 自动进入完成页
```

---

## 四、App 重新启动后的权限检查

```swift
// 每次 App 启动时检查
// 用户可能在 Onboarding 完成后又去系统设置里撤销了权限

struct PermissionChecker {

    func checkOnLaunch() -> PermissionStatus {
        let mic = AVCaptureDevice.authorizationStatus(for: .audio)
        let accessibility = AXIsProcessTrustedWithOptions(nil)
        let isLoggedIn = AuthService.shared.isLoggedIn

        switch (mic, accessibility, isLoggedIn) {
        case (.authorized, true, true):
            return .allGood       // 正常进入主界面

        case (_, _, false):
            return .needsLogin    // 跳到登录页（不走完整 Onboarding）

        case (.denied, _, _):
            return .micDenied     // 菜单栏显示警告，功能受限

        case (_, false, _):
            return .accessibilityDenied  // 菜单栏警告，无法注入文字

        default:
            return .partial
        }
    }
}

// 权限被撤销的处理（非 Onboarding 场景）：
// 不重新走 Onboarding 流程
// 在菜单栏图标上显示橙色警告
// 点击展开说明 + 修复按钮
```

---

## 五、URL Scheme 配置（登录回调）

```
需要在 Info.plist 配置 URL Scheme：
vilsay://auth/callback

用途：
- 微信登录回调
- 邮件验证链接回跳
- Google OAuth 回调

AppDelegate 处理：
func application(_ app: NSApplication,
                 open urls: [URL]) {
    for url in urls {
        if url.scheme == "vilsay" {
            AuthService.shared.handleCallback(url)
        }
    }
}
```

---

## 六、开发任务（独立 Sprint）

**Onboarding 开发前提：**
```
□ 主链路（W3）稳定通过测试
□ 账号登录（W4）后端 API 可用
□ 所有权限功能在主系统中已验证
```

**Onboarding 任务清单：**

| Task | 名称 | 说明 |
|------|------|------|
| OB-01 | 权限状态机 | PermissionChecker，处理所有权限状态 |
| OB-02 | Step2 麦克风 | 3种 UI 状态 + 轮询逻辑 |
| OB-03 | Step3 Accessibility | 4种 UI 状态 + 1秒轮询 + 系统设置跳转 |
| OB-04 | Step4 登录集成 | 4种登录方式跳转处理 |
| OB-05 | 邮件验证等待 | 轮询 + 重发 + 超时处理 |
| OB-06 | URL Scheme 配置 | 登录回调 + 邮件验证回跳 |
| OB-07 | 完成页 | 引导用户第一次使用 |
| OB-08 | 启动权限检查 | 每次启动检查，权限被撤销时菜单栏警告 |
| OB-09 | 跳过机制 | Accessibility 可跳过，但功能受限提示 |
| OB-10 | 完整流程测试 | 所有路径测试，包括权限拒绝和恢复 |

**测试场景清单：**
```
□ 全部权限直接授权（正常路径）
□ 麦克风拒绝后去设置开启
□ Accessibility 30秒内完成
□ Accessibility 超时后跳过
□ Apple ID 登录
□ 微信登录（跳出到微信 App 再回来）
□ Google 登录
□ 邮箱注册 + 验证邮件
□ Onboarding 完成后权限被撤销
□ 完成 Onboarding 后重启 App
□ 中途强制关闭 App 再重启（断点续传）
```

---

## 七、断点续传设计

```swift
// Onboarding 中途关闭 App 怎么处理？

// 每一步完成后记录进度
enum OnboardingStep: Int {
    case welcome = 0
    case microphone = 1
    case accessibility = 2
    case login = 3
    case complete = 4
}

// UserDefaults 存当前步骤
UserDefaults.standard.set(step.rawValue, forKey: "onboarding_step")

// 重启时从上次未完成的步骤继续
// 注意：权限状态需要重新检测，不信任保存的结果
```

---

## 八、变更记录

| 版本 | 日期 | 变更内容 |
|------|------|---------|
| 1.0 | 2026-03-22 | 初始版本，独立拆分 |

---
# 文档结束
# 此文档在 Week 6 主系统稳定后启动开发
# 开发时单独开一个对话，附上此文档 + VILSAY_TECH_ARCH.md
