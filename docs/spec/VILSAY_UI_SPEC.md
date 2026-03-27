# Vilsay UI 规范 · 实现对齐文档

> **版本**：v1.1 · 2026-03-27（含全文件审计结论）
> **源文件**：`vilsay/vilsay/UI/DesignTokens.swift`、`VilsayMark.swift`
> **原则**：所有 UI 组件必须引用本文档 Token，禁止在业务文件中硬编码颜色/间距/字号。

---

## 一、品牌色彩系统

### 1.1 品牌渐变（橙→粉→紫）

| Token | Hex | 用途 |
|-------|-----|------|
| `VColor.brandOrange` | `#fb923c` | 波形第1条、录音状态、强调 |
| `VColor.brandPink`   | `#f472b6` | 波形第2条、渐变中段 |
| `VColor.brandPurple` | `#c084fc` | 波形第3条、处理状态 |
| `VColor.brandIndigo` | `#818cf8` | 波形第4条、辅助渐变 |

**渐变方向**：水平（leading→trailing）为主，竖向仅用于特殊插图。

```swift
// 使用示例
LinearGradient(
    colors: [VColor.brandOrange, VColor.brandPink, VColor.brandPurple],
    startPoint: .leading, endPoint: .trailing
)
// 或直接用 Token：VColor.brandGradient
```

### 1.2 功能色

| Token | 系统色 | 用途 |
|-------|--------|------|
| `VColor.accent`        | `Color.accentColor` | 主强调色（按钮、选中态）|
| `VColor.ok`            | `Color.green`       | 成功状态 |
| `VColor.warn`          | `Color.orange`      | 警告、标记有误 |
| `VColor.fail`          | `Color.red`         | 错误、徽章 |

### 1.3 背景层级

| Token | 值 | 说明 |
|-------|----|------|
| `VColor.bgBase`  | `NSColor.windowBackgroundColor` | 窗口底色，跟随系统 |
| `VColor.bgCard`  | `NSColor.controlBackgroundColor` | 卡片底色 |
| `VColor.bgInput` | `NSColor.textBackgroundColor` | 输入框底色 |

**浮层专用**（悬浮 Bar，不跟随系统亮/暗）：

| Token | Hex | 说明 |
|-------|-----|------|
| `VColor.floatBgDeep` | `#100904` | 最深背景层 |
| `VColor.floatBgCard` | `#1e1510` | 内容卡片层 |

### 1.4 文字色

全部使用系统 `NSColor` 自适应色，**不允许**写死 `Color.black` / `Color.white`：

| Token | 对应系统色 |
|-------|-----------|
| `VColor.textPrimary`   | `NSColor.labelColor` |
| `VColor.textSecondary` | `NSColor.secondaryLabelColor` |
| `VColor.textTertiary`  | `NSColor.tertiaryLabelColor` |

---

## 二、间距系统（8pt 基准网格）

| Token | 值 | 典型用途 |
|-------|----|---------|
| `VSpacing.xxs` | 2pt  | 图标与文字的最小间距 |
| `VSpacing.xs`  | 4pt  | 紧凑元素内间距 |
| `VSpacing.sm`  | 8pt  | 相关元素间距（HStack spacing）|
| `VSpacing.md`  | 16pt | 标准段落间距、按钮内 padding |
| `VSpacing.lg`  | 24pt | 区块间距 |
| `VSpacing.xl`  | 32pt | 大区块、section 间距 |
| `VSpacing.xxl` | 48pt | 页面级留白 |
| `VSpacing.cardGap`   | 20pt | 卡片之间 |
| `VSpacing.pageInset` | 28pt | 页面左右内边距 |

**禁止**使用 `padding(10)` / `padding(15)` 等非网格值，应对齐到最近的 Token。

---

## 三、圆角系统

| Token | 值 | 用途 |
|-------|----|------|
| `VRadius.sm`   | 8pt  | 输入框、搜索框、小卡片 |
| `VRadius.md`   | 12pt | 标准卡片、弹出层 |
| `VRadius.lg`   | 18pt | 大卡片 |
| `VRadius.xl`   | 24pt | 主卡片（`VCardStyle`）|
| `VRadius.pill` | 999pt | 胶囊按钮、标签 chip |

---

## 四、字体规范

Vilsay 全程使用 **系统字体**（San Francisco），不引入第三方字体。

| 层级 | SwiftUI | 尺寸参考 | 用途 |
|------|---------|---------|------|
| 大标题  | `.largeTitle.weight(.bold)` | ~34pt | 向导欢迎页主标题 |
| 页面标题 | `.title2.weight(.bold)` | ~22pt | 首页 hero 问候语 |
| 小标题  | `.title3.weight(.semibold)` | ~20pt | 弹窗标题 |
| 节标题  | `.headline` | ~17pt | 卡片标题 |
| 正文    | `.body` | ~17pt | 主内容文本 |
| 次级    | `.subheadline` | ~15pt | Tab 按钮、标签 |
| 说明    | `.footnote` | ~13pt | 辅助说明 |
| 小字    | `.caption` | ~12pt | 时间戳、元数据 |

**等宽字体**仅用于录音状态标识（`VILSAY` 品牌标签）：
```swift
.font(.system(size: 9, weight: .semibold, design: .monospaced))
```

---

## 五、核心组件规范

### 5.1 品牌 Logo（VilsayMark）

| 组件 | 尺寸 | 参数 | 用途 |
|------|------|------|------|
| `VilsayMarkSidebar` | 22×22pt | barWidth=3, spacing=3, heights=[8,14,10,5] | 侧边栏标题旁 |
| `VilsayMarkCard`    | 34×34pt | barWidth=5.5, spacing=5, heights=[12,20,16,12] | 首页 hero 卡片 |
| `WaveformBars`（向导页）| 72×56pt | barWidth=8, spacing=7, heights=[28,48,36,22] | 向导欢迎页 |

`showCursor: false` —— **所有静态场景**均关闭光标动画，避免出现第5根条。
`showCursor: true` —— 仅保留给将来的"正在输入"动效场景。

### 5.2 卡片（VCardStyle）

```swift
GroupBox("标题") { content }
    .groupBoxStyle(VCardStyle())
```

- 深色：`Color(white: 0.16).opacity(0.92)` 固定灰，不用 material
- 浅色：`.thickMaterial` + `Color.white.opacity(0.55)` 叠加
- 边框：`Color.primary.opacity(0.06~0.10)`，线宽 1pt
- 阴影：近距 radius=1 + 远距 radius=16（双层）

### 5.3 主按钮（VPrimaryButtonStyle）

- 浅色模式：黑色胶囊 + 白色文字
- 深色模式：白色胶囊 + 黑色文字
- 尺寸：垂直 padding 14pt，字号 15pt semibold
- 动效：按下 scale 0.98，duration 0.15s

### 5.4 次级按钮（VSecondaryButtonStyle）

- 透明背景 + `Color.primary.opacity(0.18)` 描边
- 尺寸：垂直 padding 12pt，字号 14pt medium

### 5.5 Tab 切换器（胶囊 Capsule 样式）

用于词典页等非系统 SegmentedControl 场景：

```swift
Button(title) { selectedTab = tag }
    .font(.subheadline.weight(selected ? .semibold : .regular))
    .foregroundStyle(selected ? .white : .secondary)
    .padding(.horizontal, VSpacing.md).padding(.vertical, 6)
    .background(Capsule().fill(selected ? VColor.accent : Color.primary.opacity(0.06)))
    .buttonStyle(.plain)
    .animation(.easeInOut(duration: 0.15), value: selectedTab)
```

### 5.6 词条 Chip

```swift
HStack { /* 图标 + 文字 + 删除 */ }
    .padding(.horizontal, 10).padding(.vertical, 6)
    .background(
        RoundedRectangle(cornerRadius: VRadius.sm)
            .fill(Color.primary.opacity(0.07))
            .overlay(stroke 0.5pt, Color.primary.opacity(0.10))
    )
```

---

## 六、页面布局规范

### 6.1 主窗口

- 最小尺寸：760×540pt
- 结构：`NavigationSplitView`（侧边栏 180~280pt + detail 自适应）
- Toolbar 样式：`.unified(showsTitle: true)`

### 6.2 侧边栏

- Logo 区：`VilsayMarkSidebar` + "Vilsay" 18pt bold，padding top=20, bottom=10
- 导航项：自定义 `Label` 行，选中高亮背景 `VColor.accent.opacity(0.12)`，圆角 8pt
- 底部：用户头像 + 登录/设置入口

### 6.3 搜索栏原则

- **系统风格搜索**：统一使用 `.searchable(placement: .toolbar)`，呈现 macOS 原生搜索交互
- **禁止**在内容区手写 `TextField` 搜索框（视觉不统一、触发 toolbar 横线问题）
- 历史记录、词典页均已迁移至 `.searchable(placement: .toolbar)`

### 6.4 Toolbar 控件尺寸

- Toolbar 内所有控件统一使用 `.controlSize(.small)`
- 这保持与 macOS 系统 app toolbar 控件视觉一致（Finder、Mail 等）

### 6.5 悬浮 Bar（FloatingButtonView）

| 状态 | 描述 | 背景边框色 |
|------|------|-----------|
| 录音中 | `[● VILSAY] [8根波形] [✕]` | `brandOrange.opacity(0.25)` |
| 完成   | `[✓] [润色预览文字]` | green.opacity(0.22) |
| 空闲   | 隐藏 | — |

- 面板尺寸：260×72pt，`hasShadow = false`
- 阴影：SwiftUI `.shadow()` 在 `.clipShape(Capsule())` 之后追加，确保形状阴影
- 背景：`.ultraThinMaterial` + 深色叠加层 + 1pt 胶囊描边

---

## 七、菜单栏图标规范

- **形态**：4 根竖条（宽 3pt，高 [8,14,11,6]，圆角 1.5pt，间距 3pt）
- **idle**：`Color(nsColor: .labelColor)` 自适应系统亮/暗
- **录音**：4 根各自对应 brandOrange / brandPink / brandPurple / brandIndigo
- **处理中**：`brandPurple.opacity(0.55)`
- **错误/权限警告**：`VColor.warn`
- **禁止**使用 `GeometryReader`（在 MenuBarExtra 中返回 size=0）

---

## 八、已知限制与合理性说明

| 问题 | 当前状态 | 合理性 |
|------|---------|--------|
| 词典/历史页 toolbar 横线 | ⚠️ 仍存在 | macOS 14 SwiftUI 会在每次 re-render 后重置 `titlebarSeparatorStyle`，目前无可靠的纯 SwiftUI 方案；Apple Developer Forums 已确认这是平台限制（thread#762130）。现有 `TitlebarSeparatorRemover` 会在每次 layout pass 后尝试清除，实际可见性取决于系统版本。 |
| 菜单栏图标透明度 | ✅ 已修复 | 升至 0.82（暗色）/ 0.78（亮色）|
| 向导页 logo | ✅ 已替换 | 使用 `WaveformBars` 品牌波形 |
| AppIcon | ✅ 已更新 | 11 个尺寸全部导入 |

---

## 九、全文件审计结论（2026-03-27）

对 `SidebarView`、`DashboardView`、`HistoryView`、`DictionaryView`、`OnboardingView`、`FloatingButtonView`、`LoginView`、`SettingsRootView` 做了全面 Token 合规审计，问题按三级分类：

### P0 · 已修复（本次修复）

| 文件 | 问题 | 修复 |
|------|------|------|
| `FloatingButtonView` | bar 背景渐变硬编码 `Color(red:28,19,14)` | → `VColor.floatBarStart/End` |
| `FloatingButtonView` | 思考中文字颜色 `Color(red:200,185,170)` | → `VColor.floatText` |
| `FloatingButtonView` | 完成 toast 绿色 `Color(red:74,222,128)` | → `VColor.okVivid` |
| `FloatingButtonView` | 有误按钮黄色 `Color(red:251,191,36)` | → `VColor.warn` |
| `FloatingButtonView` | editMode 蓝色 `Color(red:59,130,246)` | → `VColor.brandIndigo` |
| `FloatingButtonView` | editMode 波形 blue/cyan 硬编码 | → `VColor.brandIndigo/brandPurple` |
| `DesignTokens` | 缺失 `floatText`、`floatBarStart/End`、`okVivid`、`socialWechat` | → 已补充 |
| `DesignTokens` | 缺失描边宽度 Token | → 新增 `VBorder.hairline/regular` |
| `DesignTokens` | 缺失图标尺寸 Token | → 新增 `VIconSize.xs/sm/md/lg/xl/hero` |

### P1 · 计划修复（下一轮 UI 整理时处理）

| 类型 | 数量 | 典型例子 | 建议 |
|------|------|---------|------|
| 硬编码间距 | ~40 处 | `spacing: 6`、`.padding(10)` | 替换为 `VSpacing.*` |
| 硬编码字号 | ~20 处 | `.font(.system(size: 14))` | 替换为系统语义字体 `.subheadline` 等 |
| 硬编码圆角 | ~5 处 | `cornerRadius: 6` | → `VRadius.sm` |
| 描边宽度 | ~8 处 | `lineWidth: 1` | → `VBorder.regular` |
| 图标尺寸 | ~6 处 | `.font(.system(size: 11))` | → `VIconSize.sm` |

### P2 · 合理保留（不需要修）

| 情况 | 理由 |
|------|------|
| `FloatingButtonView` 波形条尺寸（width:3, height:22） | 像素级浮层组件，Token 化反而降低可读性 |
| `OnboardingView` 分割线高度（height:1） | 语义已明确，无需 Token |
| `OnboardingView` 向导侧栏宽度（width:260） | 布局专有尺寸，Token 化意义不大 |
| `DashboardView` 累计数据字号（size:26, design:.rounded） | 展示型数字，刻意区分于正文 |
| `LoginView` 微信绿 `socialWechat` | 已归入 `VColor.socialWechat`，使用方保持该值 |
| `VilsayMark` 内部尺寸 | 组件内部，有自己的参数体系 |

---

## 十、开发检查清单

新增页面或组件时，对照以下清单：

- [ ] 颜色全部使用 `VColor.*` Token，无硬编码 hex
- [ ] 间距全部使用 `VSpacing.*`，对齐 8pt 网格
- [ ] 圆角全部使用 `VRadius.*`
- [ ] 搜索框使用 `.searchable(placement: .toolbar)`，不手写 TextField
- [ ] Toolbar 控件添加 `.controlSize(.small)`
- [ ] Logo 使用 `VilsayMarkSidebar` / `VilsayMarkCard` / `WaveformBars`，不使用 AppIcon Image
- [ ] 卡片使用 `VCardStyle` GroupBox
- [ ] 按钮使用 `VPrimaryButtonStyle` / `VSecondaryButtonStyle` / 自定义胶囊（Tab切换）
- [ ] 深/浅模式均经过目测验证
