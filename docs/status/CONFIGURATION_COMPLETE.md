# ✅ API Key 配置完成

## 已完成的配置

### 1. 环境变量（Xcode Scheme）

```
DASHSCOPE_API_KEY=sk-82036f7482f543cabf81a9e7fd9c6ab3
VILSAY_QWEN_MODEL=qwen-turbo
```

配置位置：`vilsay.xcodeproj/xcshareddata/xcschemes/vilsay.xcscheme`

### 2. 延迟测试日志

已在 `Pipeline.swift` 中添加延迟统计代码，运行时会输出：

```
[🎤 测试 #1] 开始录音处理...
[✅ 测试 #1] 完成！本次延迟: 1234ms
[📊 统计] 已完成 1 次测试，平均延迟: 1234ms

[🎤 测试 #2] 开始录音处理...
[✅ 测试 #2] 完成！本次延迟: 1156ms
[📊 统计] 已完成 2 次测试，平均延迟: 1195ms

...

[🎯 里程碑] 10次平均延迟: 1189ms (目标: < 1500ms)
```

---

## 运行步骤

### 方法一：在 Xcode 中运行（推荐）

1. 打开 `vilsay/vilsay.xcodeproj`
2. 等待索引完成
3. 按 **Cmd + R** 运行
4. 查看 Xcode 控制台（Console）输出

### 方法二：命令行运行

```bash
cd /Users/atom/Desktop/Vilsay/vilsay
xcodebuild build -scheme vilsay -destination 'platform=macOS'
```

---

## 测试延迟步骤

### 准备
1. 运行 App（按 Cmd+R）
2. 打开备忘录（或微信输入框）
3. 将光标放在输入框内

### 测试
1. **按住**悬浮按钮（或按 Shift+G）
2. **说一句话**（例如："今天天气很好，适合出去散步"）
3. **松开**按钮
4. 观察 Xcode Console 输出的延迟数据
5. **重复 10 次**

### 查看结果
Xcode Console 会显示：
```
[🎯 里程碑] 10次平均延迟: XXXXms (目标: < 1500ms)
```

---

## 故障排查

### 问题 1：控制台没有延迟日志

**解决**：确保是 **DEBUG 模式**编译（默认就是）

### 问题 2：API Key 未生效

**检查**：Xcode Console 搜索 "dashscopeAPIKey"，看是否加载

如果未加载，手动设置：
1. Xcode → Product → Scheme → Edit Scheme
2. Run → Arguments → Environment Variables
3. 确认有 `DASHSCOPE_API_KEY` 变量

### 问题 3：润色返回原文

**测试 Key 是否有效**：
```bash
curl -sS 'https://dashscope.aliyuncs.com/api/v1/services/aigc/text-generation/generation' \
  -H "Authorization: Bearer sk-82036f7482f543cabf81a9e7fd9c6ab3" \
  -H 'Content-Type: application/json' \
  -d '{"model":"qwen-turbo","input":{"messages":[{"role":"user","content":"hi"}]}}'
```

---

## 配置完成后的功能

| 功能 | 状态 | 说明 |
|------|------|------|
| 录音 | ✅ | 按住悬浮按钮录音 |
| WhisperKit 识别 | ✅ | 本地识别（无需网络）|
| DashScope 识别 | ⏳ | 需要公网音频 URL（当前走 WhisperKit）|
| Qwen 流式润色 | ✅ | 逐字输出 |
| 文字注入 | ✅ | 剪贴板保护方案 |
| 延迟统计 | ✅ | 控制台输出 |

---

## 下一步

1. 运行 App
2. 进行 10 次语音输入测试
3. 记录延迟数据
4. 如果平均延迟 < 1500ms，Week 3 验收通过 ✅

**现在可以运行测试了！**
