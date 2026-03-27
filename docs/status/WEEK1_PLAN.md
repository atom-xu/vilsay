# Week 1 · 详细执行计划

**目标：** 完成 `VILSAY_DEV_TASKS.md` 中 WEEK 1 四项，使工程可编译、依赖就绪、目录与权限声明符合规约。

| 步骤 | Task | 动作 | 验收 |
|------|------|------|------|
| 1 | W1-01 | 创建 macOS App（SwiftUI），最低部署 macOS 14 | `xcodebuild` 编译成功，能启动窗口 |
| 2 | W1-02 | 通过 SPM 引入 WhisperKit、GRDB、KeyboardShortcuts、LaunchAtLogin | 解析成功，`import` 无报错 |
| 3 | W1-03 | 建立 `App/ Entry/ Core/ AI3/ Auth/ DB/ UI/ Config/ Utils/` 及占位 Swift | 目录存在且目标参与编译 |
| 4 | W1-04 | `Info.plist` 麦克风说明；`Entitlements` 含 `audio-input`（沙盒麦克风） | 构建通过；文案为中文自定义 |

**依赖仓库（与任务书一致）：**

- `https://github.com/argmaxinc/WhisperKit`
- `https://github.com/groue/GRDB.swift`
- `https://github.com/sindresorhus/KeyboardShortcuts`（任务书写 nicklockwood，以可解析、MIT 的常用库为准；若需更换为指定 fork 可再改 URL）
- `https://github.com/sindresorhus/LaunchAtLogin-modern`

**不纳入 Week 1：** 菜单栏 UI、录音、网络（Week 2+）。

---

## 实施顺序（已完成）

1. 使用你提供的模板工程，工程位于仓库 **`vilsay/vilsay.xcodeproj`**（target / scheme 名：`vilsay`）。  
2. 已在工程中加入 SPM：`WhisperKit`、`GRDB`、`KeyboardShortcuts`、`LaunchAtLogin`（URL 见 `project.pbxproj`）。  
3. 已建立 `App/`、`Entry/`、`Core/`、`AI3/`、`Auth/`、`DB/`、`UI/`、`Config/`、`Utils/` 及占位模块；`Config/DependenciesSmoke.swift` 统一 `import` 四依赖。  
4. 已设置 **最低 macOS 14.0**、`INFOPLIST_KEY_NSMicrophoneUsageDescription`、沙盒 + `com.apple.security.device.audio-input`（`vilsay/vilsay.entitlements`）。  
5. 任务书 W1-01～W1-04 已标 ✅ **2026-03-22**；**Kimi** 请在本地 Xcode 中 **Resolve Packages** 后编译运行验收。

---

## Week 2 进展（2026-03-22）

- **W2-01**：`LSUIElement` 无 Dock；`MenuBarExtra` + 规约菜单；`Settings`（⌘,）打开占位设置页。  
- **W2-02**：`FloatingButtonController`（NSPanel）+ `FloatingButtonView`；右下角可拖动；右键切换 Push/Toggle（视觉模拟录音→处理）。  
- **W2-03**：`AppStatus` + `AppState`；菜单栏图标与悬浮按钮同步；词典角标占位；调试菜单可切换状态。  
- **W2-04～W2-08**：未做，下一批迭代。

---

## 验收提醒（Kimi）

- 若 SPM 首次拉取失败，检查网络与 GitHub 访问后重试 **Resolve Package Versions**。  
- 编译通过后运行：应 **无 Dock 图标**，**菜单栏麦克风**，**右下角悬浮按钮**；**⌘,** 打开设置占位窗。  
- WhisperKit 首次解析耗时长属正常，见根目录 `CLAUDE.md`「Xcode 长时间转圈」说明。
