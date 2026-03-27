# Phase 2: WeTextProcessing ITN 集成方案

## 目标

在 ASR → LLM 之间加一层**规则 ITN（Inverse Text Normalization）**，把确定性的文本标准化从 LLM 的职责中剥离出来。

## 为什么

| 问题 | 当前做法 | ITN 后 |
|---|---|---|
| `三千两百万` → `3200万` | LLM 猜，长上下文时可能不转 | 规则保证 100% |
| `百分之十二点五` → `12.5%` | LLM 猜 | 规则保证 |
| `一三八零六七五` → `13806754321` | LLM 猜，效果好 | 规则保证，LLM 不需要处理 |
| `二零二六年三月` → `2026年3月` | LLM 可能不转 | 规则保证 |
| 音译还原（微一→V1） | LLM 猜，短上下文不敢改 | ITN 不处理，留给 LLM |

**核心思想**：确定性的交给规则，不确定的交给 LLM。LLM 收到的文本已经过数字标准化，可以专注在语义纠偏和格式化上。

## 技术选型

### WeTextProcessing
- **仓库**: https://github.com/wenet-e2e/WeTextProcessing
- **Star**: 737 | **License**: Apache-2.0
- **安装**: `pip install WeTextProcessing`
- **用法**:
```python
from itn.chinese.inverse_normalizer import InverseNormalizer
itn = InverseNormalizer()
itn.normalize("三千两百万")  # → "3200万"
itn.normalize("百分之十二点五")  # → "12.5%"
itn.normalize("二零二六年三月二十七号")  # → "2026年3月27号"
```

### 备选: wetext（轻量版，无 Pynini 依赖）
- **仓库**: https://github.com/pengzhendong/wetext
- **更轻量**，打包更容易，但功能覆盖可能不如 WeTextProcessing 全

## 集成架构

### 方案 A：Python 微服务（推荐）

```
┌─────────────┐     ┌──────────────┐     ┌─────────────┐
│  ASR 输出    │ ──→ │ ITN 微服务    │ ──→ │ LLM 润色     │
│ (原始文本)   │     │ (Python/Flask)│     │ (千问 API)   │
└─────────────┘     └──────────────┘     └─────────────┘
                    localhost:5001
                    POST /itn
                    {"text": "...", "lang": "zh"}
```

**优点**: 独立进程，不影响 Swift 主 App，可独立更新规则
**缺点**: 需要额外启动一个 Python 进程

### 方案 B：Swift 调 Python 脚本

```swift
// Pipeline.swift 中在调 PolishService 之前
let itnText = try ITNService.normalize(asrText)
let polished = try await polishService.polishStreaming(system: prompt, user: itnText)
```

```swift
// ITNService.swift
enum ITNService {
    static func normalize(_ text: String) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/local/bin/python3")
        process.arguments = ["-c", """
            from itn.chinese.inverse_normalizer import InverseNormalizer
            itn = InverseNormalizer()
            import sys
            print(itn.normalize(sys.argv[1]))
        """, text]
        // ... capture stdout
    }
}
```

**优点**: 不需要跑服务
**缺点**: 每次调用启动 Python 进程，冷启动 ~500ms（ITN 模型加载）

### 方案 C：内嵌规则（纯 Swift，无依赖）

不用 WeTextProcessing，自己写核心 ITN 规则：

```swift
enum ChineseITN {
    /// 中文数字 → 阿拉伯数字
    static func normalize(_ text: String) -> String {
        var result = text
        result = normalizePercent(result)    // 百分之十二 → 12%
        result = normalizeInteger(result)    // 三千两百 → 3200
        result = normalizeDecimal(result)    // 十二点五 → 12.5
        result = normalizePhone(result)      // 一三八零六 → 13806
        result = normalizeDate(result)       // 二零二六年 → 2026年
        return result
    }
}
```

**优点**: 零依赖，零延迟，打包简单
**缺点**: 需要自己实现和维护规则，边界 case 多

### 推荐：方案 A（短期）→ 方案 C（长期）

1. **短期**用 Python 微服务验证效果，确认 ITN 对整体质量的提升
2. **长期**把验证过的规则用 Swift 重写，内嵌到 App，去掉 Python 依赖

## 集成点

### 当前数据流
```
AudioCapture → ASR(text, confidence) → VADBuffer → PromptComposer → PolishService
```

### ITN 后数据流
```
AudioCapture → ASR(text, confidence) → ITNService.normalize(text) → VADBuffer → PromptComposer → PolishService
```

### 关键代码位置

| 文件 | 行 | 改什么 |
|---|---|---|
| `Pipeline.swift` | `deliverASRThroughVADToPolish()` | 在传给 VADBuffer 之前调 ITN |
| 新建 `ITNService.swift` | - | ITN 调用封装 |
| `Prompts.swift` `section2` P5 | - | 去掉数字标准化指令（已由 ITN 处理） |

## 验证计划

1. 用现有 mix_04/mix_l04（数字密集场景）做 A/B 对比
2. ITN 前 vs ITN 后喂给 LLM 的文本差异
3. 确认 ITN 不会误伤（如"第一"不应转为"第1"）

## 不处理的（留给 LLM）

- 音译还原（微一→V1）— 非确定性，需上下文
- 同音字纠偏 — 非确定性
- 格式化/分段 — LLM 核心职责
- 英文缩写识别 — 非确定性

## 时间估算

| 步骤 | 耗时 |
|---|---|
| Python 微服务搭建 + 测试 | 0.5 天 |
| Pipeline 集成 + 端到端验证 | 0.5 天 |
| 调优测试 A/B 对比 | 0.5 天 |
| Swift 纯规则版本（可选） | 1-2 天 |
