# Vilsay UI 设计对比分析表

> **文档用途：** 记录当前 Vilsay (SwiftUI) 与 Vilsay-PromptLab (Sugar Theme) 的 UI 设计差异  
> **创建日期：** 2026-03-22  
> **创建人：** Kimi (测试工程师)  
> **状态：** 供参考，后续迭代使用

---

## 一、整体设计哲学对比

| 维度 | Vilsay (当前 SwiftUI) | Vilsay-PromptLab (Sugar Theme) |
|------|----------------------|-------------------------------|
| **设计定位** | 原生 macOS 应用，简约克制 | 科技感/未来感，视觉冲击强 |
| **风格关键词** | 原生、轻量、无打扰 | 玻璃态、发光、渐变、沉浸 |
| **用户感知** | macOS 系统原生应用 | 独立品牌，强视觉识别 |
| **复杂度** | 低，符合 Apple HIG | 高，需要自定义绘制 |

---

## 二、色彩系统对比

### 2.1 主色调

| 元素 | Vilsay (SwiftUI) | Sugar Theme | 差异说明 |
|------|-----------------|-------------|---------|
| **主色** | 系统 `accentColor` (默认蓝) | `#8b5cf6` (紫) → `#ec4899` (粉) 渐变 | Sugar 使用品牌渐变色 |
| **背景色** | `Color(nsColor: .darkGray).opacity(0.88)` | `#0f0f1a` → `#1a1a2e` 渐变 | Sugar 深色更有层次感 |
| **表面色** | 系统 `secondarySystemBackground` | `rgba(255,255,255,0.05)` 毛玻璃 | Sugar 使用玻璃态效果 |
| **文字色** | 系统 `.primary`/`.secondary` | `#f8fafc` / `#94a3b8` | Sugar 明度更高 |

### 2.2 状态色

| 状态 | Vilsay | Sugar Theme |
|------|--------|-------------|
| **待机** | 灰色 `Color.secondary` | 紫粉渐变 + 弱发光 |
| **录音中** | 红色 `.red` | 红色 `#ef4444` + 脉冲发光动画 |
| **处理中** | 黑色/旋转指示器 | 橙色 `#f59e0b` + 流光效果 |
| **成功** | 绿色 `.green` | 绿色 `#10b981` + 发光 |
| **错误** | 橙色 `.orange` | 红色 `#ef4444` + 闪烁 |

### 2.3 颜色变量定义对比

```swift
// Vilsay (当前) - 系统默认
.menuBarColor: Color  // 根据状态返回系统色
.circleFill: Color    // 硬编码状态色

// Sugar Theme - 自定义 Design Token
--color-primary: #8b5cf6
--color-primary-light: #a78bfa
--color-primary-dark: #7c3aed
--color-background: #0f0f1a
--color-background-secondary: #1a1a2e
--color-surface-1: rgba(255,255,255,0.05)
--color-surface-2: rgba(255,255,255,0.08)
--glow-primary: 0 0 20px rgba(139,92,246,0.5)
```

---

## 三、悬浮按钮对比

### 3.1 视觉规格

| 属性 | Vilsay (当前) | Sugar Theme |
|------|--------------|-------------|
| **尺寸** | 60×60 pt | 120×120 px (更大) |
| **形状** | 完整圆形 | 完整圆形 |
| **圆角** | 完全圆角 | 完全圆角 |
| **边框** | 无 | 1px 渐变边框 |
| **阴影** | 系统阴影 `shadow(radius: 6)` | 多层发光阴影 |

### 3.2 样式细节

| 状态 | Vilsay (当前) | Sugar Theme |
|------|--------------|-------------|
| **待机** | 深灰背景 `darkGray.opacity(0.88)` + `mic.fill` | 紫粉渐变背景 + 图标 + 外发光 |
| **录音中** | 红色背景 + 正弦波脉冲环 | 红色渐变 + 脉冲发光动画 + 水波纹 |
| **处理中** | 旋转箭头 `TimelineView` 200度/秒 | 流光效果 + 旋转 |
| **改词模式** | 蓝色背景 `blue` | 青色 `#06b6d4` + 发光 |
| **角标** | 红色圆形数字 | 带发光的小圆点 |

### 3.3 动画对比

| 动画 | Vilsay (当前) | Sugar Theme |
|------|--------------|-------------|
| **脉冲环** | `sin(t * 3.5)` 正弦波，20fps | CSS `sugar-pulse` 2s ease-in-out infinite |
| **旋转** | `rotationEffect` 200度/秒 | CSS rotate + 流光 |
| **hover** | 无特殊效果 | `transform: scale(1.05)` + 阴影增强 |
| **按下** | 无特殊效果 | `transform: scale(0.98)` |

### 3.4 代码实现差异

```swift
// Vilsay (当前实现)
ZStack {
    outerRing  // TimelineView 正弦波
    Circle().fill(circleFill).shadow(...)
    centerIcon
}

// Sugar Theme (目标效果)
// - 渐变背景: LinearGradient(135deg, #8b5cf6, #ec4899)
// - 发光阴影: box-shadow: 0 0 40px rgba(139,92,246,0.5)
// - 水波纹: 伪元素动画
// - 渐变边框: mask + gradient
```

---

## 四、菜单栏图标对比

| 属性 | Vilsay (当前) | Sugar Theme |
|------|--------------|-------------|
| **图标** | SF Symbols `mic`/`mic.fill` | 自定义 SVG 或 Lucide 图标 |
| **颜色** | 系统色 `.secondary`/`.red` | 品牌紫色 `#8b5cf6` |
| **动画** | `TimelineView` 旋转/脉冲 | CSS 动画 |
| **角标** | 红色数字徽章 | 带发光的小红点 |
| **风格** | 原生系统风格 | 品牌定制风格 |

---

## 五、设置页/控制面板对比

### 5.1 布局结构

| 元素 | Vilsay (当前) | Sugar Theme |
|------|--------------|-------------|
| **窗口背景** | 系统默认 | 深色渐变 + 网格背景 |
| **分组方式** | `GroupBox` | 玻璃态卡片 |
| **侧边栏** | TabView (设置/词典/用量) | 玻璃态侧边栏 |
| **间距** | 系统默认 20pt padding | 较大间距，呼吸感强 |

### 5.2 组件样式

| 组件 | Vilsay (当前) | Sugar Theme |
|------|--------------|-------------|
| **按钮** | 系统默认样式 | 渐变背景 + 圆角 1rem + 发光 |
| **输入框** | `textFieldStyle(.roundedBorder)` | 毛玻璃背景 + 细边框 |
| **开关** | `Toggle` 系统样式 | 自定义滑动开关 |
| **选择器** | `Picker` 系统样式 | 自定义分段选择器 |
| **卡片** | `GroupBox` | `sugar-glass` 毛玻璃卡片 |

### 5.3 背景效果

```css
/* Sugar Theme 背景 */
.sugar-grid-bg {
  background-color: #0f0f1a;
  background-image: radial-gradient(circle at 1px 1px, rgba(139,92,246,0.15) 1px, transparent 0);
  background-size: 40px 40px;
}

.sugar-gradient-radial {
  background: 
    radial-gradient(ellipse at top, rgba(139,92,246,0.15) 0%, transparent 50%),
    radial-gradient(ellipse at bottom, rgba(236,72,153,0.1) 0%, transparent 50%),
    #0f0f1a;
}
```

---

## 六、弹窗/对话框对比

### 6.1 确认弹窗

| 属性 | Vilsay (当前) | Sugar Theme |
|------|--------------|-------------|
| **背景** | 系统默认 | `rgba(26,26,46,0.95)` + 毛玻璃 |
| **圆角** | 系统默认 | 1.5rem (24px) |
| **遮罩** | 系统默认 | `rgba(0,0,0,0.7)` + blur |
| **阴影** | 系统默认 | 大尺寸投影 + 内发光 |
| **按钮** | 系统默认 | 渐变背景 |

### 6.2 弹窗结构对比

```swift
// Vilsay (当前) - 系统 Alert
.alert("需要麦克风权限", isPresented: $showAlert) {
    Button("打开系统设置") { }
    Button("好的", role: .cancel) { }
} message: {
    Text("请在系统设置中允许...")
}

// Sugar Theme (目标) - 自定义 Dialog
// - 深色半透明背景
// - 圆角 24px
// - 渐变边框
// - 渐变按钮
// - 发光效果
```

---

## 七、Onboarding 引导页对比

| 页面 | Vilsay (当前) | Sugar Theme |
|------|--------------|-------------|
| **Step 1 欢迎** | 简单图标 + 文字 | 大图/动画 + 品牌色 |
| **Step 2 权限** | SF Symbols 图标 | 自定义插图 |
| **Step 3 登录** | 简洁按钮 | 发光社交登录按钮 |
| **Step 4 完成** | ✅ 图标 | 动画完成效果 |
| **整体风格** | 原生简洁 | 科技/未来感 |

---

## 八、技术实现难度评估

| 效果 | SwiftUI 实现难度 | 备注 |
|------|-----------------|------|
| **渐变背景** | ⭐ 低 | `LinearGradient` 原生支持 |
| **毛玻璃效果** | ⭐ 低 | `.ultraThinMaterial` 或 `VisualEffect` |
| **发光阴影** | ⭐⭐ 中 | 多层 `shadow` 叠加 |
| **渐变边框** | ⭐⭐⭐ 高 | 需要 `overlay` + `mask` 技巧 |
| **网格背景** | ⭐⭐⭐ 高 | 需要 `Canvas` 自定义绘制 |
| **水波纹动画** | ⭐⭐⭐ 高 | 需要自定义 `ViewModifier` |
| **流光效果** | ⭐⭐⭐⭐ 高 | 需要 `TimelineView` + 复杂计算 |
| **脉冲发光** | ⭐⭐ 中 | `TimelineView` + 透明度动画 |

---

## 九、建议与结论

### 9.1 是否采用 Sugar Theme？

| 方案 | 优点 | 缺点 | 建议 |
|------|------|------|------|
| **保持原生 SwiftUI** | 开发快，符合 macOS 习惯 | 视觉普通，品牌感弱 | **MVP 阶段推荐** |
| **采用 Sugar Theme** | 视觉冲击强，品牌识别度高 | 开发成本高，维护复杂 | **品牌成熟后考虑** |
| **混合方案** | 平衡两者 | 需要设计把控 | 参考 Cursor 等工具 |

### 9.2 如采用 Sugar Theme，建议优先级

```
P0 (核心，必须实现):
  - 主色改为品牌紫 (#8b5cf6)
  - 悬浮按钮添加渐变背景
  - 设置页背景加深

P1 (重要，建议实现):
  - 按钮添加发光效果
  - 弹窗改为深色毛玻璃
  - 状态指示器添加脉冲动画

P2 (加分，可延后):
  - 网格背景
  - 流光效果
  - 水波纹动画
```

---

## 十、参考资源

### 10.1 Sugar Theme 源代码位置
- 变量定义：`/Users/atom/Desktop/Vilsay-PromptLab/src/styles/sugar-theme/variables.css`
- 全局样式：`/Users/atom/Desktop/Vilsay-PromptLab/src/styles/sugar-theme/global.css`
- 组件样式：`/Users/atom/Desktop/Vilsay-PromptLab/src/components/ui/*.tsx`

### 10.2 Vilsay 当前实现位置
- 悬浮按钮：`/Users/atom/Desktop/Vilsay/vilsay/vilsay/Entry/FloatingButtonView.swift`
- 菜单栏：`/Users/atom/Desktop/Vilsay/vilsay/vilsay/UI/MenuBarRootMenu.swift`
- 设置页：`/Users/atom/Desktop/Vilsay/vilsay/vilsay/UI/SettingsRootView.swift`
- 状态定义：`/Users/atom/Desktop/Vilsay/vilsay/vilsay/Core/AppStatus.swift`

---

**文档结束**  
**最后更新：** 2026-03-22 by Kimi
