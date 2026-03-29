# VILSAY · 技术规范补充
# Cursor Technical Spec Supplement
# 版本：1.3 | 日期：2026-03-29
# 与 `docs/spec/VILSAY_TECH_ARCH.md` 配合使用；**若与总架构冲突，以 `VILSAY_TECH_ARCH.md` 为准**。
# **第一～六章**为对开发侧（含 Cursor）此前提出的架构/产品问题的**已定稿答复**；**附录 A** 仅为「当前代码 vs 规约」的迁移对照，**不以附录否定前文**。

---

## 〇、文档角色

| 内容 | 说明 |
|------|------|
| **第一～六章** | **已定稿规约**（流式 ASR/VAD、OAuth、用量计费、密钥阶段、API、错误模型）；开发实现应**以此为准**向代码收敛。 |
| **附录 A** | **实现迁移快照**：列出当时仓库与规约的差异，便于逐项改代码/后端；差异消除后可删减附录行。 |

---

## 一、流式 ASR + VAD + Pipeline 数据流

> **现状**：麦克风 → 整段录音 → **qwen-audio-asr**（主路径，多模态 LLM，API Key 可用时）→ **文本**进入 `VADBuffer.acceptFinalTranscript` → 润色。降级链路：Proxy upload → Paraformer REST async → WhisperKit local。文件 ASR 模型为 qwen-audio-asr（可通过 `VILSAY_FILE_ASR_MODEL` 配置）。**本节下图描述的是目标态：流式音频 + 分段 ASR + 文本/能量 VAD，尚未全量落地。**

### 1.1 整体数据流

```
麦克风音频（连续）
        ↓
AVAudioRecorder 录制 → 音频缓冲区
        ↓ 每 100ms 切一个音频片段
VADBuffer
  ├── 有声音 → 累积到 speechBuffer
  └── 静音 > 800ms → 触发句子完成回调
        ↓ 完整句子音频
ASRService（当前：qwen-audio-asr → Proxy upload → Paraformer REST → WhisperKit）
        ↓ 原始文字
PolishService（Qwen SSE 流式）
        ↓ 逐字符 token
TextInjector（每4字符 pasteChunk 一次）
        ↓
RawLogger（异步写 raw_log，不阻塞）
```

### 1.2 Pipeline 状态机

```
状态枚举：
idle        → 待机，等待热键
recording   → 录音中（热键按住 / Toggle 已开）
processing  → ASR + 润色进行中
injecting   → 文字注入中
error       → 出错，等待用户操作或自动恢复

合法转换：
idle        → recording    （热键按下 ≥ 150ms）
recording   → idle         （ESC 取消）
recording   → processing   （热键松开 / VAD 触发）
processing  → injecting    （ASR + 润色完成）
processing  → idle         （空音频 / 超时 / 降级完成）
injecting   → idle         （注入完成）
任意状态    → error        （不可恢复错误）
error       → idle         （用户点击恢复 / 3秒自动恢复）
```

### 1.3 VAD 接入 Pipeline 的具体实现

```swift
// VAD 触发条件
Constants.vadPauseMs = 800       // 静音超过此值触发
Constants.vadMinSpeechMs = 300   // 最短有效语音（防空触发）

// Pipeline 中的 VAD 回调
vadBuffer.onSentenceComplete = { [weak self] audioChunk in
    guard audioChunk.duration >= Constants.vadMinSpeechMs else {
        // 太短，丢弃，回到 recording 状态
        return
    }
    self?.transitionTo(.processing)
    self?.runASRAndPolish(audioChunk)
}

// 注意：VAD 触发后 Pipeline 仍可继续录音（支持长段分句）
// 状态不从 recording → processing，而是 recording 内部触发处理
// 只有热键松开才真正结束 recording 状态
```

### 1.4 空音频兜底

```swift
// 以下情况视为空音频，直接回到 idle
- 音频时长 < Constants.vadMinSpeechMs（300ms）
- ASR 返回空字符串或纯空白
- ASR 返回 nil

// 兜底时不写 raw_log，不调用 PolishService
// 状态直接 processing → idle，无任何输出
```

---

## 二、账号与 OAuth 端到端流程

### 2.1 四种登录的序列图

**Apple ID：**
```
App → ASAuthorizationAppleIDProvider.request()
    → 系统弹窗（用户授权）
    → 返回 identityToken + authorizationCode
App → POST /auth/apple { identityToken, authorizationCode }
    → 后端验证 Apple 公钥签名
    → 返回 { accessToken, refreshToken, user }
App → 存储 Token，更新登录状态
```

**微信：**
```
App → 打开微信 OAuth URL（Universal Link）
    → 微信 App 授权
    → 回调 vilsay://auth/callback?code=xxx
AppDelegate.openURLs → AuthService.handleCallback(url)
App → POST /auth/wechat { code }
    → 后端换取 access_token + openid
    → 返回 { accessToken, refreshToken, user }
```

**Google：**
```
App → ASWebAuthenticationSession（Google OAuth URL）
    → 用户在 Sheet 内授权
    → 回调 vilsay://auth/callback?code=xxx&provider=google
App → POST /auth/google { code }
    → 后端换取 id_token，验证
    → 返回 { accessToken, refreshToken, user }
```

**邮箱：**
```
注册：
App → POST /auth/register { email, password }
    → 后端发验证邮件（链接含 token）
    → 显示「请查收验证邮件」界面
    → 轮询 GET /auth/verify-status（每3秒）
用户点邮件链接 → 浏览器打开 → 跳转 vilsay://auth/verify?token=xxx
App → POST /auth/verify-email { token }
    → 后端激活账号，返回登录 Token

登录：
App → POST /auth/login { email, password }
    → 返回 { accessToken, refreshToken, user }
```

### 2.2 Token 管理

```
accessToken：有效期 7 天，存 Keychain
refreshToken：有效期 30 天，存 Keychain
自动刷新：accessToken 过期前1天，后台静默刷新
刷新失败：清除 Token，跳转登录页
```

### 2.3 账号合并规则

```
场景：用户先用 Apple 登录，再用绑定同一邮箱的 Google 登录

规则：
- 后端以邮箱为唯一标识
- 同一邮箱的不同 OAuth 提供商视为同一账号
- 自动合并，用户无感知
- 合并后两种方式都可登录

特殊情况：
- 微信账号没有邮箱时，以 openid 为标识，不做合并
- 用户主动在设置页绑定邮箱后可合并
```

### 2.4 URL Scheme 配置

```
Info.plist 中注册：
vilsay://auth/callback    OAuth 回调
vilsay://auth/verify      邮件验证回跳

AppDelegate 处理：
func application(_ app: NSApplication, open urls: [URL]) {
    for url in urls {
        guard url.scheme == "vilsay" else { continue }
        AuthService.shared.handleDeepLink(url)
    }
}
```

---

## 三、用量与计费

### 3.1 计数定义

```
一次计数 = 用户完整触发一次录音并产生润色输出
不计数的情况：
  - 用户 ESC 取消
  - 空音频（无有效语音）
  - ASR 失败回退原文（不经过 PolishService）
  - 改词功能（SelectSpeak）单独计数，与普通输入分开统计

计数时机：
  PolishService 返回第一个有效 token 时计数
  （不在注入完成时计，防止注入失败漏计）

上报时机：
  计数后立即异步 POST /usage/record，不阻塞主链路
  失败时本地缓存，下次 App 启动时重试
```

### 3.2 套餐（待 PRD-SUP-001 确认，当前占位）

```
免费版：
  每月 200 次普通输入 + 50 次改词
  超额后当月不可用，提示升级

Pro 版：
  无限次（合理使用）
  定价见 PRD-SUP-001

套餐重置：每月1日 00:00 UTC+8 重置
```

### 3.3 超额处理

```
本地判断（软限制）：
  App 启动时拉取当月用量
  每次使用后本地 +1
  本地计数 >= 免费额度时，触发前弹出升级提示

服务端判断（硬限制）：
  POST /usage/record 返回 402 时
  后续 POST /polish 返回 402（套餐超限）
  App 收到 402 → 展示升级提示，停止润色

用户体验：
  超额时先完成当前这次，下次触发时提示
  不在用户说话中途打断
```

### 3.4 POST /usage/record 语义

```
Request：
POST /usage/record
Authorization: Bearer <accessToken>
{
  "type": "polish",          // polish | select_speak
  "duration_ms": 3200,       // 录音时长（毫秒）
  "asr_provider": "qwen-audio-asr", // qwen-audio-asr | paraformer | whisper
  "client_version": "1.0.0"
}

Response 200：
{
  "remaining": 167,          // 本月剩余次数
  "total": 200,              // 本月总额度
  "reset_at": "2026-04-01T00:00:00+08:00"
}

Response 402：
{
  "error": "quota_exceeded",
  "message": "本月免费次数已用完",
  "upgrade_url": "https://vilsay.com/pricing"
}
```

---

## 四、客户端密钥与代理

### 4.1 阶段目标

```
当前阶段（开发期）：
  DashScope API Key 写在 AppConfig / 环境变量
  直接从客户端调用 DashScope
  不走自建代理
  风险：Key 泄露，仅限开发测试使用

上线前必须改：
  API Key 移到自建后端服务器
  客户端只持有 Vilsay accessToken
  所有 DashScope 调用走自建代理：
    客户端 → Vilsay 后端 → DashScope
  原因：保护 API Key，控制用量，加计费层
```

### 4.2 代理接口设计

```
客户端请求自建后端（上线后）：

POST /api/v1/polish
Authorization: Bearer <vilsayAccessToken>
{
  "text": "ASR 原始文字",
  "profile": { ... }  // AI3 画像（可选）
}

后端转发 DashScope，返回 SSE 流：
data: {"delta": "润"}
data: {"delta": "色"}
data: [DONE]
```

### 4.3 客户端代码的隔离

```swift
// Config/AppConfig.swift

#if DEBUG
// 开发期：直接配置 Key
static let dashscopeAPIKey = "sk-xxx"
static let polishEndpoint = "https://dashscope.aliyuncs.com/..."
#else
// 生产：走自建代理
static let dashscopeAPIKey = ""  // 不存 Key
static let polishEndpoint = "https://api.vilsay.com/api/v1/polish"
#endif
```

---

## 五、API 规范

### 5.1 版本前缀

```
所有接口统一前缀：/api/v1/
示例：
  /api/v1/auth/login
  /api/v1/usage/record
  /api/v1/polish
  /api/v1/user/profile
```

### 5.2 统一错误体

```json
{
  "error": "error_code",       // 机器可读，snake_case
  "message": "用户可见文字",   // 中文，直接展示给用户
  "detail": "技术细节",        // 可选，仅 DEBUG 模式展示
  "request_id": "uuid"         // 便于排查
}
```

**错误码清单：**

```
认证相关：
  unauthorized          未登录或 Token 失效
  token_expired         Token 已过期，请刷新
  invalid_credentials   邮箱或密码错误
  email_not_verified    邮箱未验证

用量相关：
  quota_exceeded        本月免费次数已用完
  plan_required         需要升级套餐

服务相关：
  asr_failed            语音识别失败
  polish_failed         润色服务暂时不可用
  service_unavailable   服务维护中

通用：
  bad_request           请求参数错误
  not_found             资源不存在
  rate_limited          请求太频繁，请稍后重试
  internal_error        服务器内部错误
```

### 5.3 HTTP 状态码使用规范

```
200  成功
201  创建成功（register）
400  参数错误（bad_request）
401  未认证（unauthorized / token_expired）
402  需要付费（quota_exceeded / plan_required）
404  不存在
422  业务逻辑错误（invalid_credentials / email_not_verified）
429  限流（rate_limited）
500  服务器错误
```

### 5.4 用量明细分页（如需接入）

```
GET /api/v1/usage/history?page=1&per_page=20&month=2026-03

Response：
{
  "data": [
    {
      "id": "uuid",
      "type": "polish",
      "created_at": "2026-03-22T14:32:00+08:00",
      "duration_ms": 3200
    }
  ],
  "pagination": {
    "page": 1,
    "per_page": 20,
    "total": 156,
    "total_pages": 8
  }
}
```

---

## 六、错误与文案（客户端统一模型）

### 6.1 AppState 错误字段映射

```swift
enum AppError {
    // 热键 / 录音
    case micPermissionDenied     // 「需要麦克风权限，请在系统设置中开启」
    case accessibilityDenied     // 「需要辅助功能权限才能输入文字」
    case hotkeyConflict          // 「热键冲突，请在设置中修改」
    case recordingTooShort       // （静默，不提示用户）

    // ASR
    case asrFailed               // 「语音识别失败，已输出原始文字」
    case asrTimeout              // 「识别超时，请重试」

    // 润色
    case polishFailed            // 「润色服务暂时不可用，已输出原始文字」
    case polishHallucination     // （静默降级，输出原文，不提示）
    case apiKeyMissing           // 「服务配置异常，请联系支持」

    // 账号
    case notLoggedIn             // 「请先登录以使用 Vilsay」
    case tokenExpired            // 「登录已过期，请重新登录」
    case quotaExceeded           // 「本月免费次数已用完，升级继续使用」

    // 网络
    case networkUnavailable      // 「网络不可用，已切换本地模式」
    case serverError             // 「服务器异常，请稍后重试」
}
```

### 6.2 错误展示规则

```
展示方式按严重程度分三级：

静默处理（不展示，写日志）：
  recordingTooShort
  polishHallucination（降级输出原文）

菜单栏橙色图标 + 点击查看：
  asrFailed / asrTimeout / polishFailed
  networkUnavailable（同时自动降级本地）
  serverError

弹出提示（需要用户操作）：
  micPermissionDenied → 按钮：打开系统设置
  accessibilityDenied → 按钮：打开系统设置
  notLoggedIn → 按钮：去登录
  tokenExpired → 按钮：重新登录
  quotaExceeded → 按钮：升级 Pro
  hotkeyConflict → 按钮：修改热键
```

### 6.3 自动恢复规则

```
以下错误3秒后自动恢复到 idle，不需要用户操作：
  asrFailed / asrTimeout / polishFailed / serverError

以下错误持续显示，直到用户操作：
  micPermissionDenied / accessibilityDenied
  notLoggedIn / tokenExpired / quotaExceeded
```

---
## 附录 A · 实现迁移对照（刷新：2026-03-29）

**规约来源**：第一～六章。下表描述**当前仓库相对规约**的差异或已收敛项；**产品定义仍以正文 chapters 与 `VILSAY_TECH_ARCH.md` 为准**。

| 主题 | 规约（见上文章节） | 当前实现要点 |
|------|----------------------|--------------|
| ASR Pipeline | 第一章：ASR 优先级与降级 | **已收敛**：主路径 qwen-audio-asr（多模态 LLM，API Key 可用时）→ Proxy upload → Paraformer REST async → WhisperKit local；文件 ASR 模型为 qwen-audio-asr（`VILSAY_FILE_ASR_MODEL` 可配）；**文本 VAD 全量对齐**仍可按任务书 W4-01 继续收紧 |
| `POST /usage/record` | 第三章 JSON body | **已收敛**：客户端 `UsageRecordAPIRequest`；服务端 `UsageRecordBody`（`type`、`duration_ms`、`asr_provider`、`client_version`） |
| API 前缀 `/api/v1/` | 第五章 | **已收敛**：`BackendAPIClient` 统一 `apiPrefix`；FastAPI 路由挂载于 `/api/v1` |
| 免费额度数值 | 第三章 vs 服务端默认 | **产品待定**：`server/app/config.py` 等处默认配额需与 PRD **显式对齐** |
| 计数时机 / 未登录 | 第三章 | **已对齐意向**：`PolishUsageOnceGate` + 润色 **首 token**（或 `polishPlain` 降级）触发；`AuthService.recordUsageAfterFirstPolishToken` **仅在已登录且已配置后端时**上报（否则直接 return） |
| Refresh Token | 第二章 | **已收敛**：`KeychainTokenStore` 存 access + refresh；`AuthService.refreshTokensIfNeeded` |
| 自建润色代理 | 第四章 | **未实现**：润色仍以客户端直连 DashScope（Key/UserDefaults）为主；代理上线后 revisiting |
| 错误体 `error`/`message`/`request_id` | 第五章 | **部分**：`parseErrorDetail` 覆盖 `message`/`detail` 等；**无**客户端统一错误码枚举与规约 JSON 形状一一对应 |
| `AppError` 枚举 | 第六章 | **未收敛**：仍为 `UserFacingError` + `AppState` 多字段，规约第六章枚举为目标态 |
| OAuth / 邮件验证 | 第二章 | **部分收敛**：服务端 `/auth/apple|google|wechat`、客户端 `OAuthSignInCoordinator` + Deep Link；**生产环境** Apple/Google/微信参数、邮件送达与验证 UX 需按上架清单验收 |

**结论**：已将 2026-03 附录中多条「当时落差」更新为当前事实；剩余行随实现继续删减或改为「已收敛」。汇总任务与验收见 **`docs/status/WEEK6_7_IMPLEMENTATION_AND_REMAINING.md`**。

---

# 文档结束
# 与 `docs/spec/VILSAY_TECH_ARCH.md` 配合使用；**冲突时以总架构 `VILSAY_TECH_ARCH.md` 为准**。本文第一～六章为已定稿补充规约；附录 A 为迁移对照，非「未解决问题清单」。
