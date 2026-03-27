# API Key 配置指南

## 已配置的 Key

```
DASHSCOPE_API_KEY=sk-82036f7482f543cabf81a9e7fd9c6ab3
```

## Xcode 环境变量配置步骤

### 方法一：通过 Xcode Scheme 配置（推荐）

1. 打开 `vilsay/vilsay.xcodeproj`
2. 点击工具栏的 Scheme（显示 vilsay）
3. 选择 **Edit Scheme...**
4. 左侧选择 **Run**
5. 右侧选择 **Arguments** 标签
6. 在 **Environment Variables** 区域点击 **+**
7. 添加：
   - Name: `DASHSCOPE_API_KEY`
   - Value: `sk-82036f7482f543cabf81a9e7fd9c6ab3`
8. 点击 **Close**
9. 按 Cmd+R 运行

### 方法二：通过终端运行

```bash
cd /Users/atom/Desktop/Vilsay/vilsay
export DASHSCOPE_API_KEY=sk-82036f7482f543cabf81a9e7fd9c6ab3
xcodebuild build -scheme vilsay -destination 'platform=macOS'
```

### 方法三：通过 UserDefaults（开发调试用）

在 App 内设置页添加临时输入框，或使用命令行：

```bash
defaults write com.vilsay.app vilsay.dashscope_api_key "sk-82036f7482f543cabf81a9e7fd9c6ab3"
```

## 验证配置

配置完成后，运行 App，测试以下功能：

1. 按住悬浮按钮说话
2. 松开按钮后，文字应被润色后注入
3. 查看控制台日志，确认没有 "无 API Key" 的降级提示

## 故障排查

### 问题：润色功能仍返回原文

**检查：**
1. Xcode Console 中搜索 "dashscopeAPIKey"，确认 Key 已加载
2. 检查 Key 是否包含多余空格（已在代码中做 trimming 处理）
3. 使用 `docs/DASHSCOPE_SMOKE_TEST.md` 中的 curl 命令测试 Key 是否有效

### 问题：API 返回 401/403

**可能原因：**
- Key 已过期
- Key 地域不匹配（国内/国际站）
- Key 未开通 Qwen 服务

**解决：**
1. 登录 https://dashscope.aliyun.com/ 检查 Key 状态
2. 确认已开通「通义千问」服务
3. 重新生成 Key

---

**配置完成后，记得测试延迟！**
