# Week 2 · 微架构说明（追认版）

| 项 | 内容 |
|----|------|
| **状态** | 追认 |
| **日期** | 2026-03-22 |
| **对应任务** | W2-01～W2-08 |
| **主战场** | `UI/`、`App/`、`ContentView.swift`、菜单栏与 `Settings` |

---

## 1. 范围与模块映射

| 任务 | 实现要点 | 主要文件 |
|------|----------|----------|
| W2-01 菜单栏 | `MenuBarExtra` + 菜单内容视图 | `vilsayApp.swift`、`UI/MenuBarRootMenu.swift`、`UI/MenuBarStatusLabel.swift` |
| W2-02 悬浮钮 | `NSPanel` + SwiftUI，`showIfNeeded` 延后创建 | `Entry/FloatingButtonController.swift`、`FloatingButtonView.swift`、修饰键 `FloatingTriggerGestureModifier.swift` |
| W2-03 状态 | 全局 `AppStatus` / `AppState` 驱动菜单与悬浮钮 | `Core/AppStatus.swift`、`App/AppState.swift` |
| W2-04 Onboarding | 独立窗口控制器 | `App/OnboardingWindowController.swift`、`UI/OnboardingView.swift` |
| W2-05 登录 | Sheet / 视图占位 | `UI/LoginView.swift`（逻辑 Week 4） |
| W2-06 设置 | Tab、触发方式、识别模式等 | `UI/SettingsRootView.swift`、`Config/AppConfig.swift` |
| W2-07 词典 | 列表与占位数据 | `UI/DictionaryView.swift` |
| W2-08 用量 | 占位图表与文案 | `UI/UsageStatsView.swift` |

**原则**：界面与导航完整，**业务主链路以占位或调试入口为主**，与 `Pipeline` 的深度集成在 Week 3 完成。

---

## 2. 对外契约（UI → 后续 Week）

- **菜单「开始录音」**：Week 3 起绑定 `Pipeline.shared.toggleRecording()` 等（见 `MenuBarRootMenu`）。
- **设置项**：`AppState` / `UserDefaults` 持久化键与 `AppConfig` 读取保持一致，供 `HotkeyManager`、`Pipeline` 使用。
- **悬浮钮**：仅负责展示状态与手势；**不**在 Week 2 承担 ASR/润色逻辑。

---

## 3. 数据流

- 词典 / 用量等以**假数据或占位**为主；持久化接入 Week 5（GRDB）。
- `Onboarding` 完成标志存 `UserDefaults`，控制首次是否展示引导。

---

## 4. 权限与沙盒

- Week 2 主要验证 **UI 可达**；麦克风、辅助功能引导在 Onboarding 文案与步骤中体现，**实际热键权限效果在 Week 3 验收**。

---

## 5. 失败与降级

- 设置页「不可用」项使用 `PlaceholderToggle` 等组件明确禁用，避免用户误以为已接后端。

---

## 6. 与规约差异

- 无结构性冲突；若 UI 文案与 `VILSAY_UI_UX.md` 不一致，以产品后续统一修订为准。

---

## 7. 验收步骤（追认用）

1. 无 Dock 图标，菜单栏图标可点，菜单展开含「开始录音」「设置」「退出」等。
2. **⌘,** 打开设置，`ContentView` 内 Tab（设置 / 词典 / 用量）可切换。
3. 悬浮圆形按钮可出现、可拖动（具体显示策略在 Week 3 与 `FloatingButtonController.showIfNeeded` 收紧）。
4. Onboarding 可走完全部步骤（或跳过逻辑符合 `UserDefaults`）。
5. 登录 / 用量页面可打开，无崩溃。

---

## 8. 确认

- [x] 架构已审阅  
- [x] 开发已确认与实现一致  

**确认人 / 日期：** Kimi / 2026-03-23
