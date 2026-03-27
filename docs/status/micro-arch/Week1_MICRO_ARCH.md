# Week 1 · 微架构说明（追认版）

| 项 | 内容 |
|----|------|
| **状态** | 追认（开发已完成，文档后补） |
| **日期** | 2026-03-22 |
| **对应任务** | W1-01～W1-04 |
| **工程路径** | `vilsay/vilsay.xcodeproj`，源码根目录 `vilsay/vilsay/` |

---

## 1. 范围与模块映射

| 任务 | 落地位置 |
|------|----------|
| W1-01 工程与入口 | `vilsayApp.swift`（唯一 `@main`）、`App/AppDelegate.swift` |
| W1-02 SPM | `vilsay.xcodeproj` 包依赖；`Config/DependenciesSmoke.swift` 编译期引用 WhisperKit / GRDB / LaunchAtLogin 等 |
| W1-03 目录 | `App/`、`Entry/`、`Core/`、`UI/`、`Config/`、`Utils/`、`Auth/`、`DB/`、`AI3/` 等（与 `VILSAY_TECH_ARCH` 第三章对齐，部分为占位模块） |
| W1-04 权限 | `Info.plist` 麦克风用途说明；`vilsay.entitlements`：`app-sandbox`、`device.audio-input`、`network.client` |

**刻意不包含**：业务主链路（Week 3）、账号真实逻辑（Week 4+）。

---

## 2. 对外契约（Week 1 边界）

- **应用形态**：菜单栏应用（`MenuBarExtra`），`Settings` 场景打开 `ContentView`（Week 2 填充）。
- **启动**：`AppDelegate.applicationDidFinishLaunching` 为后续 Week 3 预留（热键、Whisper 预加载等在此演进）。
- **依赖**：以 SPM 解析成功、`DependenciesSmoke.noop()` 可编译为准。

---

## 3. 数据流

- Week 1 无持久化业务数据流；仅确保 App 能启动、沙盒与麦克风声明就绪。

---

## 4. 权限与沙盒

| 能力 | 配置 |
|------|------|
| 沙盒 | `com.apple.security.app-sandbox` = true |
| 麦克风 | `com.apple.security.device.audio-input` + `NSMicrophoneUsageDescription` |
| 出网 | `com.apple.security.network.client`（为后续 Whisper 下载、DashScope 预留） |

**注意**：辅助功能**无** entitlement，由用户在系统设置中授权（Week 3 热键依赖）。

---

## 5. 失败与降级

- SPM 解析失败：开发者环境网络/GitHub 可达性；不在 App 内降级。
- 无麦克风 entitlement：编译/公证阶段即应发现。

---

## 6. 与规约差异

- 任务书 W1-02 曾列 **KeyboardShortcuts**：Phase 1～3 **未**作为主热键方案使用，热键在 Week 3 由 **CGEventTap** 实现（见 `Week3_MICRO_ARCH.md`）。`VILSAY_TECH_ARCH` v1.3 已同步。

---

## 7. 验收步骤（追认用）

1. Xcode 打开 `vilsay.xcodeproj`，**Resolve Package Versions** 成功。
2. **Product → Build** 无错误。
3. 运行：菜单栏出现 Vilsay 图标，可打开设置窗口壳（Week 2+ 内容）。
4. 检查 `vilsay.entitlements` 含上述三项 key。

---

## 8. 确认

- [x] 架构已审阅  
- [x] 开发已确认与实现一致  

**确认人 / 日期：** Kimi / 2026-03-23
