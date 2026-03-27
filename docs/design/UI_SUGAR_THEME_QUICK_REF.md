# Sugar Theme 快速参考卡片

> **用途：** 供开发人员快速查阅 Sugar Theme 关键设计 Token  
> **来源：** Vilsay-PromptLab 项目

---

## 🎨 颜色变量

| Token | 值 | 用途 |
|-------|-----|------|
| `--color-primary` | `#8b5cf6` | 主色紫 |
| `--color-primary-light` | `#a78bfa` | 浅紫 |
| `--color-primary-dark` | `#7c3aed` | 深紫 |
| `--color-secondary` | `#06b6d4` | 青色 |
| `--color-background` | `#0f0f1a` | 背景深紫 |
| `--color-background-secondary` | `#1a1a2e` | 次背景 |
| `--color-surface-1` | `rgba(255,255,255,0.05)` | 玻璃态表面 |
| `--color-surface-2` | `rgba(255,255,255,0.08)` |  elevated 表面 |
| `--color-accent` | `#f472b6` | 强调粉 |
| `--color-success` | `#10b981` | 成功绿 |
| `--color-warning` | `#f59e0b` | 警告橙 |
| `--color-destructive` | `#ef4444` | 错误红 |

---

## ✨ 渐变定义

```css
/* 主渐变：紫到粉 */
--gradient-primary: linear-gradient(135deg, #8b5cf6 0%, #ec4899 100%);

/* 次渐变：青到蓝 */
--gradient-secondary: linear-gradient(135deg, #06b6d4 0%, #3b82f6 100%);

/* 背景渐变 */
--gradient-background: linear-gradient(180deg, #0f0f1a 0%, #1a1a2e 50%, #0f0f1a 100%);

/* 表面渐变 */
--gradient-surface: linear-gradient(180deg, rgba(139,92,246,0.1) 0%, rgba(236,72,153,0.05) 100%);
```

---

## 💡 发光效果

```css
/* 主色发光 */
--glow-primary: 0 0 20px rgba(139, 92, 246, 0.5), 0 0 40px rgba(139, 92, 246, 0.3);

/* 次色发光 */
--glow-secondary: 0 0 20px rgba(6, 182, 212, 0.5), 0 0 40px rgba(6, 182, 212, 0.3);

/* 成功发光 */
--glow-success: 0 0 20px rgba(16, 185, 129, 0.5);

/* 录音发光 */
--glow-recording: 0 0 30px rgba(239, 68, 68, 0.6);
```

---

## 🔮 毛玻璃效果

```css
/* 标准玻璃 */
--glass-background: rgba(255, 255, 255, 0.05);
--glass-border: rgba(255, 255, 255, 0.1);
--glass-backdrop: blur(20px) saturate(180%);

/* 强玻璃 */
.sugar-glass-strong {
  background: rgba(26, 26, 46, 0.8);
  backdrop-filter: blur(30px) saturate(200%);
  border: 1px solid rgba(255, 255, 255, 0.15);
}
```

---

## 📐 圆角规范

| Token | 值 | 用途 |
|-------|-----|------|
| `--radius-sm` | `0.5rem` (8px) | 小按钮 |
| `--radius-md` | `0.75rem` (12px) | 输入框 |
| `--radius-lg` | `1rem` (16px) | 卡片 |
| `--radius-xl` | `1.5rem` (24px) | 弹窗 |
| `--radius-2xl` | `2rem` (32px) | 大卡片 |
| `--radius-full` | `9999px` | 圆形/胶囊 |

---

## 🎬 动画时间

| 动画 | 时长 | 缓动函数 |
|------|------|----------|
| 按钮过渡 | `0.2s` / `0.3s` | `ease` / `ease-out` |
| 脉冲动画 | `2s` | `ease-in-out infinite` |
| 渐变流动 | `8s` | `ease infinite` |
| 浮动动画 | `3s` | `ease-in-out infinite` |
| 水波纹 | `2s` | `ease-out infinite` |

---

## 🎯 阴影层级

```css
--shadow-sm: 0 1px 2px rgba(0, 0, 0, 0.3);
--shadow-md: 0 4px 6px -1px rgba(0, 0, 0, 0.4), 0 2px 4px -1px rgba(0, 0, 0, 0.2);
--shadow-lg: 0 10px 15px -3px rgba(0, 0, 0, 0.5), 0 4px 6px -2px rgba(0, 0, 0, 0.3);
--shadow-xl: 0 20px 25px -5px rgba(0, 0, 0, 0.6), 0 10px 10px -5px rgba(0, 0, 0, 0.4);
--shadow-glow: 0 0 20px rgba(139, 92, 246, 0.3);
```

---

## 🧩 关键组件类名

```css
/* 网格背景 */
.sugar-grid-bg
.sugar-grid-bg-dense
.sugar-dot-bg

/* 渐变背景 */
.sugar-gradient-bg
.sugar-gradient-radial

/* 玻璃态 */
.sugar-glass
.sugar-glass-strong
.sugar-glass-subtle

/* 渐变边框 */
.sugar-gradient-border

/* 按钮 */
.sugar-btn-primary
.sugar-btn-glow
.sugar-btn-secondary
.sugar-record-btn

/* 侧边栏 */
.sugar-sidebar
.sugar-sidebar-item

/* 文字 */
.sugar-text-gradient
.sugar-text-glow

/* 状态 */
.sugar-status-dot

/* 输入框 */
.sugar-input

/* 滚动条 */
.sugar-scrollbar

/* 弹窗 */
.sugar-modal-overlay
.sugar-modal-content

/* 分隔线 */
.sugar-divider

/* 徽章 */
.sugar-badge
.sugar-badge-success
.sugar-badge-warning
```

---

## 📱 响应式断点

| 断点 | 尺寸 | 用途 |
|------|------|------|
| 悬浮窗 | 96×96 px | 最小悬浮按钮 |
| 弹窗 | 425px | 确认对话框 |
| 侧边栏 | 280px | 导航宽度 |
| 卡片 | max-w-lg (512px) | 内容卡片 |

---

## 🔗 参考文件路径

```
Vilsay-PromptLab/
├── src/styles/sugar-theme/
│   ├── variables.css      # 所有 Token 定义
│   └── global.css         # 组件类名
├── src/components/ui/
│   ├── button.tsx         # 按钮组件
│   ├── dialog.tsx         # 弹窗组件
│   └── card.tsx           # 卡片组件
└── src/index.css          # 全局样式入口
```

---

*快速参考卡片 - 2026-03-22*
