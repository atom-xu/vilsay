# Vilsay 架构补齐项清单（Phase 1 待决策）

**文档版本**：v1.0  
**提交日期**：2026-03-23  
**目标受众**：架构师、后端负责人、产品经理  
**当前状态**：客户端核心链路（热键→录音→ASR→润色→注入）已完成，下列项目待架构决策与开发文档化。

---

## 📋 总览：按优先级与依赖关系排列

| 优先级 | 模块 | 关键决策 | 阻塞项 | 预计工作量 |
|-------|------|---------|-------|----------|
| 🔥 P0 | 流式 ASR + VAD | DashScope 实时语音识别接入 | 无 | 2-3 周 |
| 🔥 P0 | 账号体系 | 邮箱验证、密码重置、OAuth | 无 | 3-4 周 |
| 🟡 P1 | 计费与用量 | 套餐限额、超额拦截 | 账号体系 | 2 周 |
| 🟡 P1 | 后端生产化 | PostgreSQL、Redis、安全加固 | 无 | 2 周 |
| 🟢 P2 | 热键子进程 | 独立 Target（可选） | 无 | 1 周 |
| 🟢 P2 | 文档更新 | 架构文档、API 规范 | 所有上述项 | 持续 |

---

## 🔥 P0-1：流式 ASR 与 W4-01（强依赖）

### 背景
当前实现：整段录音 → ASR → VAD 分句 → 润色  
目标实现：实时流式 ASR → 800ms 文本 VAD → 流式润色

### 待决策项

#### 1.1 DashScope 实时语音识别协议

**决策点**：
- [ ] WebSocket 接入方式（wss://端点、鉴权方式）
- [ ] 音频帧格式（采样率、编码格式、帧大小）
- [ ] 断句/结束事件的识别（如何判断用户说完一句话？）
- [ ] 与现有 `Pipeline` / `VADBuffer` 的对接点

**当前代码依赖**：
```swift
// Pipeline.swift - process() 方法
let raw = try await WhisperASRFallback.shared.transcribe(fileURL: fileURL)
// ↑ 需要改为流式接口

// VADBuffer.swift - 当前基于完整文本分句
func acceptFinalTranscript(_ text: String)
// ↑ 需要支持增量文本流
```

**技术方案要求**：
1. WebSocket 连接管理（重连、心跳）
2. 音频流分块发送（实时性 < 500ms）
3. 部分识别结果（partial）vs 最终结果（final）的处理
4. 错误处理与降级（无网时回退本地 Whisper）

**产出文档**：
- `docs/spec/STREAMING_ASR_DESIGN.md`
- API 接入示例代码
- 联调测试方案

---

#### 1.2 800ms 文本 VAD（W4-01）

**决策点**：
- [ ] 仅在「流式 ASR 文本流」上启用（明确与整段 ASR 的边界）
- [ ] 状态机设计（等待首字 → 积累中 → 超时触发 → 润色）
- [ ] 与现有 `VADBuffer` 的关系（扩展 or 新类？）
- [ ] 回退策略（流式失败时如何处理？）

**当前代码**：
```swift
// VADBuffer.swift - 现有实现
class VADBuffer {
    var onSentenceComplete: ((String) -> Void)?
    
    // 当前是基于完整文本的标点符号分句
    func acceptFinalTranscript(_ text: String) {
        // ...
    }
}
```

**技术方案要求**：
1. 增量文本流接口：`func feedPartial(_ text: String)`
2. 800ms 定时器管理（用户停顿 → 触发润色）
3. 取消/中断处理（用户提前按 ESC）
4. 性能指标：延迟 < 1 秒（ASR → 润色开始）

**产出文档**：
- `docs/spec/TEXT_VAD_DESIGN.md`
- 状态机流程图
- 性能测试报告

---

#### 1.3 云端 vs 本地主路径

**决策点**：
- [ ] 无网时的行为（完全回退本地 Whisper？）
- [ ] 弱网时的超时策略（多久放弃云端？）
- [ ] 设置界面「识别模式」的文案一致性
- [ ] 与 `NetworkMonitor` 的联动（网络状态变化时的处理）

**当前代码**：
```swift
// Pipeline.swift - process() 方法
if AppState.shared.recognitionMode == .cloud,
   NetworkMonitor.shared.isConnected,
   let cloud = await DashScopeASRClient.transcribeFileIfAvailable(...) {
    raw = cloud
} else {
    raw = try await WhisperASRFallback.shared.transcribe(fileURL: fileURL)
}
```

**技术方案要求**：
1. 统一策略文档（产品 + 技术共识）
2. 用户设置与实际行为的映射表
3. 降级日志（用户可查看为何使用本地）
4. 性能对比（云端 vs 本地的延迟、准确率）

**产出文档**：
- `docs/spec/ASR_FALLBACK_STRATEGY.md`
- 设置界面文案规范
- 用户帮助文档

---

## 🔥 P0-2：账号体系（W4-03～W4-06）

### 背景
当前后端：`server/` 有基础 SQLite 数据库，但缺少完整的账号功能。

### 待决策项

#### 2.1 邮箱验证与邮件

**决策点**：
- [ ] `POST /auth/register` 后的发信流程（同步 or 异步？）
- [ ] 验证链接格式（如 `https://vilsay.com/verify?token=xxx`）
- [ ] `GET /auth/verify-email` 的契约（幂等性、过期时间）
- [ ] 开发/生产环境的 SMTP 配置与密钥管理

**当前后端代码**：
```python
# server/main.py - 需要扩展
@app.post("/auth/register")
async def register(user: UserCreate):
    # TODO: 发送验证邮件
    pass
```

**技术方案要求**：
1. SMTP 配置（推荐 SendGrid / AWS SES）
2. 邮件模板（HTML + 纯文本版本）
3. Token 生成与验证（JWT or UUID？）
4. 重发逻辑（用户未收到时）
5. 开发环境 Mock（避免真实发信）

**产出文档**：
- `docs/backend/EMAIL_VERIFICATION.md`
- 邮件模板设计稿
- SMTP 配置清单

---

#### 2.2 忘记密码

**决策点**：
- [ ] 重置链接生成规则（临时 Token、单次有效）
- [ ] `POST /auth/reset-password` 与 `POST /auth/confirm-reset` 流程
- [ ] 客户端 `LoginView` 的对接（新增「忘记密码」按钮？）
- [ ] 安全措施（防止暴力重置）

**客户端代码**：
```swift
// 当前 LoginView 缺少「忘记密码」入口
// 需要添加：
Button("忘记密码？") {
    // TODO: 打开重置密码页面
}
```

**技术方案要求**：
1. Token 过期时间（建议 1 小时）
2. 一次性 Token 验证（使用后立即失效）
3. 速率限制（同一邮箱 5 分钟内最多 3 次）
4. 邮件模板（与验证邮件一致的样式）

**产出文档**：
- `docs/backend/PASSWORD_RESET.md`
- 客户端流程图
- 安全策略说明

---

#### 2.3 Sign in with Apple

**决策点**：
- [ ] 客户端 Capability 配置（App ID、Team ID）
- [ ] 服务端 `POST /auth/apple` 验签流程（Apple JWT 验证）
- [ ] 账号绑定规则（同一 Apple ID 多次登录的处理）
- [ ] 账号合并策略（已有邮箱账号 + Apple 登录）

**客户端代码**：
```swift
// 需要添加 Sign in with Apple
import AuthenticationServices

Button(action: {
    // TODO: 调用 ASAuthorizationAppleIDProvider
}) {
    Label("使用 Apple 登录", systemImage: "applelogo")
}
```

**技术方案要求**：
1. Apple Developer 配置（Sign in with Apple Capability）
2. 服务端 JWT 验证（使用 Apple 公钥）
3. 用户唯一标识（`user` identifier）存储
4. 邮箱匹配规则（Apple 可能隐藏真实邮箱）

**产出文档**：
- `docs/backend/APPLE_SIGNIN.md`
- 客户端集成指南
- 账号合并策略

---

#### 2.4 微信登录（可延后）

**决策点**：
- [ ] 开放平台资质申请（企业认证）
- [ ] OAuth 回调域名配置（需备案域名）
- [ ] 服务端 `POST /auth/wechat` 路由设计
- [ ] 审核未通过时的降级策略（任务书允许延后）

**当前状态**：
- ⚠️ 需要企业资质，个人开发者无法接入
- ⚠️ 建议 Phase 2 再考虑

**产出文档**：
- `docs/backend/WECHAT_LOGIN.md`（延后）

---

#### 2.5 Google OAuth

**决策点**：
- [ ] `POST /auth/google` 契约（ID Token 验证）
- [ ] Google Cloud Console 配置（Client ID/Secret）
- [ ] 重定向 URI 规范（开发/生产环境）
- [ ] 账号合并策略（同邮箱）

**技术方案要求**：
1. Google OAuth 2.0 Client 配置
2. ID Token 验证（使用 Google 公钥）
3. 用户信息获取（email、name、picture）
4. 客户端 SDK 集成（`GoogleSignIn`）

**产出文档**：
- `docs/backend/GOOGLE_OAUTH.md`
- 客户端集成指南

---

## 🟡 P1-1：计费与用量（W4-07 / W4-08）

### 背景
当前后端有 `free_monthly_quota` 字段，但缺少完整的计费逻辑。

### 待决策项

#### 3.1 套餐与限额

**决策点**：
- [ ] 免费/Pro 套餐的额度定义（如：免费 100 次/月，Pro 无限）
- [ ] 按月重置规则（UTC 0 点 or 用户注册日？）
- [ ] 与当前 `free_monthly_quota` 的对齐方式
- [ ] 新用户默认套餐

**当前后端代码**：
```python
# server/database.py
class User:
    free_monthly_quota: int = 100  # 默认额度
    used_quota: int = 0
```

**技术方案要求**：
1. 数据库 Schema 更新（`subscription_tier`, `quota_reset_at`）
2. 定时任务（每月重置 `used_quota`）
3. 客户端显示（剩余次数、升级入口）
4. 审计日志（每次使用记录）

**产出文档**：
- `docs/backend/SUBSCRIPTION_TIERS.md`
- 数据库迁移脚本
- 客户端 UI 设计

---

#### 3.2 超额拦截

**决策点**：
- [ ] App 内提示文案（如「本月额度已用完，请升级 Pro」）
- [ ] 是否硬拦润色（拒绝请求 or 降级服务？）
- [ ] 与 HTTP 402 Payment Required 的行为一致性
- [ ] 宽限期策略（超额后是否允许 10 次缓冲？）

**当前代码**：
```swift
// 客户端需要处理 402 响应
if response.statusCode == 402 {
    AppState.shared.showUpgradePrompt = true
}
```

**技术方案要求**：
1. 后端中间件（每次请求检查额度）
2. 客户端统一错误处理
3. 用户友好的提示文案
4. 数据埋点（超额行为分析）

**产出文档**：
- `docs/backend/QUOTA_ENFORCEMENT.md`
- 错误码规范
- 用户提示文案

---

#### 3.3 付费与升级

**决策点**：
- [ ] 官网支付（Stripe / 支付宝）vs App Store IAP
- [ ] 是否仅跳转外链（避免 IAP 30% 抽成）
- [ ] 收据校验与账号绑定（若使用 IAP）
- [ ] 订阅管理（续费、退款、取消）

**技术方案要求**：
1. 支付网关选择（推荐 Stripe for 国际，支付宝 for 国内）
2. Webhook 处理（支付成功 → 升级账号）
3. IAP 收据验证（若选择 App Store）
4. 订阅状态同步（客户端 ↔ 服务端）

**产出文档**：
- `docs/backend/PAYMENT_INTEGRATION.md`
- App Store 审核策略（若使用 IAP）
- 价格策略文档

---

#### 3.4 用量口径

**决策点**：
- [ ] 「一次润色」的计数定义（仅成功注入？含取消？含错误重试？）
- [ ] 审计需求（是否需要详细日志？）
- [ ] 退款时的处理（是否退回额度？）
- [ ] 异常情况（服务端错误不扣额度）

**技术方案要求**：
1. 统一计数逻辑（在 `POST /polish` 成功时计数）
2. 审计表设计（`usage_logs` 表）
3. 客户端上报（成功/失败/取消）
4. 数据分析需求（日活、周活、转化率）

**产出文档**：
- `docs/backend/USAGE_METRICS.md`
- 数据库 Schema
- 数据分析需求文档

---

## 🟡 P1-2：后端生产化

### 背景
当前 `server/` 使用 SQLite，需要升级到生产级别。

### 待决策项

#### 4.1 PostgreSQL 部署

**决策点**：
- [ ] 连接串配置（环境变量 `DATABASE_URL`）
- [ ] 迁移策略（Alembic 等）
- [ ] 与开发 SQLite 的差异说明（SQL 方言）
- [ ] 备份与恢复策略

**技术方案要求**：
1. 数据库服务商选择（AWS RDS / Supabase / 自建）
2. 连接池配置（`asyncpg`）
3. 迁移脚本（`alembic init`, `alembic upgrade head`）
4. 开发/生产环境隔离

**产出文档**：
- `docs/backend/POSTGRESQL_SETUP.md`
- 迁移脚本（`alembic/versions/`）
- 数据库配置清单

---

#### 4.2 Redis

**决策点**：
- [ ] 是否 Phase 1 必上（会话/限流）
- [ ] 键空间设计（如 `user:{id}:session`）
- [ ] 过期策略（会话 7 天，限流 1 分钟）
- [ ] 与现有代码的集成点

**当前代码**：
```python
# 当前使用内存存储，需要改为 Redis
sessions = {}  # 应改为 Redis
```

**技术方案要求**：
1. Redis 服务商选择（AWS ElastiCache / Upstash / 自建）
2. 客户端库（`aioredis`）
3. 键命名规范
4. 持久化策略（RDB or AOF）

**产出文档**：
- `docs/backend/REDIS_DESIGN.md`
- 键空间文档
- 性能测试报告

---

#### 4.3 JWT

**决策点**：
- [ ] 生产环境 `JWT_SECRET` 生成与存储
- [ ] 密钥轮换策略（定期更换？）
- [ ] 短期 Token + Refresh Token 是否要做
- [ ] Token 过期时间（建议 Access Token 1 小时，Refresh Token 7 天）

**当前代码**：
```python
# server/main.py
JWT_SECRET = os.getenv("JWT_SECRET", "dev-secret-key")  # ⚠️ 生产需要真实密钥
```

**技术方案要求**：
1. 密钥管理（AWS Secrets Manager / 环境变量）
2. Refresh Token 机制（避免频繁重新登录）
3. Token 撤销（用户登出时）
4. 过期时间配置

**产出文档**：
- `docs/backend/JWT_DESIGN.md`
- 密钥轮换流程
- 安全最佳实践

---

#### 4.4 安全

**决策点**：
- [ ] HTTPS 配置（SSL 证书、强制跳转）
- [ ] CORS 白名单（允许的客户端域名）
- [ ] 速率限制（API 限流规则）
- [ ] 密码策略（最小长度、bcrypt 轮数）

**技术方案要求**：
1. HTTPS 证书（Let's Encrypt / AWS Certificate Manager）
2. CORS 中间件配置
3. 速率限制（`slowapi` / nginx）
4. 密码强度验证（正则、bcrypt rounds=12）
5. SQL 注入防护（使用 ORM）
6. XSS 防护（输入验证）

**产出文档**：
- `docs/backend/SECURITY_CHECKLIST.md`
- 渗透测试报告（若有）
- 合规性文档（GDPR / CCPA）

---

## 🟢 P2-1：工程与热键子进程（可选）

### 背景
当前 `HotkeyManager.swift` 使用同进程 CGEventTap + NSEvent 备选，已足够稳定。

### 待决策项

#### 5.1 HotkeyListenerService 独立 Target

**决策点**：
- [ ] 是否坚持「独立进程 + stdout」方案（VoiceInk 风格）
- [ ] 单独 Target 配置（Command Line Tool）
- [ ] 打包路径与 `HotkeyServiceManager.locateListenerBinary()` 对齐
- [ ] 崩溃恢复测试（主进程崩溃，热键是否仍可用）

**当前状态**：
- ⚠️ `HotkeyListenerService.swift` 有 `@main`，导致编译错误
- ⚠️ 需要移除或创建独立 Target

**技术方案要求**：
1. Xcode 新建 Command Line Tool Target
2. 将 `HotkeyListenerService.swift` 添加到新 Target
3. 打包脚本（复制到 App Bundle）
4. 进程通信测试（stdout / XPC）

**产出文档**：
- `docs/engineering/HOTKEY_SUBPROCESS.md`
- 构建配置文档
- 性能对比（独立进程 vs 同进程）

**建议**：
- ✅ 当前同进程方案已足够可靠（CGEventTap + NSEvent + 自动重启）
- ⚠️ 独立进程可作为 Phase 2 优化项

---

#### 5.2 多热键 / Backlog

**决策点**：
- [ ] 是否支持多套快捷键（如 Fn + A, Fn + B 不同功能）
- [ ] 任务书已说明为后续评审项
- [ ] 若产品坚持，需单独架构说明

**建议**：
- ⚠️ Phase 1 暂不支持，保持单一热键简洁性

---

## 🟢 P2-2：文档与规约同步

### 待产出文档

#### 6.1 更新架构文档

**文件**：`docs/spec/VILSAY_TECH_ARCH.md`

**需要补充的章节**：
- [ ] 账号后端架构（邮箱验证、OAuth）
- [ ] 用量与计费系统
- [ ] 流式 ASR 设计
- [ ] 安全策略

---

#### 6.2 更新开发任务文档

**文件**：`docs/status/VILSAY_DEV_TASKS.md`

**需要更新**：
- [ ] 上述项对应的状态（TODO / In Progress / Done）
- [ ] 验收标准（Acceptance Criteria）
- [ ] 责任人与截止时间

---

#### 6.3 联调清单

**新建文件**：`docs/operations/INTEGRATION_CHECKLIST.md`

**内容**：
- [ ] `VILSAY_API_BASE` 环境变量配置
- [ ] DashScope API Key 获取与配置
- [ ] Paraformer 公网 URL 测试
- [ ] 流式 ASR 联调步骤
- [ ] 前后端接口契约（OpenAPI / Swagger）

---

## 📊 工作量估算（总计约 10-12 周）

| 模块 | 开发工作量 | 测试工作量 | 文档工作量 | 总计 |
|------|-----------|-----------|-----------|------|
| 流式 ASR + VAD | 2 周 | 1 周 | 0.5 周 | 3.5 周 |
| 账号体系 | 3 周 | 1 周 | 0.5 周 | 4.5 周 |
| 计费与用量 | 1.5 周 | 0.5 周 | 0.3 周 | 2.3 周 |
| 后端生产化 | 1.5 周 | 0.5 周 | 0.2 周 | 2.2 周 |
| 热键子进程（可选） | 0.5 周 | 0.3 周 | 0.2 周 | 1 周 |
| 文档更新 | - | - | 1 周 | 1 周 |
| **总计** | **8.5 周** | **3.3 周** | **2.7 周** | **14.5 周** |

**建议并行开发**：
- 流式 ASR + 账号体系（不同团队）
- 后端生产化可提前准备（数据库迁移）

---

## 🎯 里程碑建议

### Milestone 1（4 周）：账号 + 基础后端
- ✅ 邮箱验证 + 密码重置
- ✅ PostgreSQL + Redis 部署
- ✅ JWT 生产化
- ✅ HTTPS + 安全加固

### Milestone 2（7 周）：流式 ASR + 计费
- ✅ DashScope 流式 ASR 接入
- ✅ 800ms 文本 VAD
- ✅ 套餐限额 + 超额拦截
- ✅ 支付集成（Stripe or IAP）

### Milestone 3（10 周）：OAuth + 优化
- ✅ Sign in with Apple
- ✅ Google OAuth
- ✅ 热键子进程（可选）
- ✅ 完整文档

### Milestone 4（12 周）：测试 + 上线
- ✅ 集成测试
- ✅ 性能测试
- ✅ 安全审计
- ✅ 生产环境部署

---

## 🚀 下一步行动

### 架构师需要产出
1. **流式 ASR 技术方案**（3 天内）
   - DashScope 接入文档
   - VAD 状态机设计
   - 性能目标

2. **账号体系设计文档**（5 天内）
   - 数据库 Schema
   - API 契约（OpenAPI）
   - OAuth 流程图

3. **计费系统设计**（3 天内）
   - 套餐定义
   - 扣费规则
   - 支付集成方案

### 后端团队需要准备
1. PostgreSQL 环境搭建
2. Redis 配置
3. 邮件服务商申请（SendGrid）
4. 支付网关申请（Stripe / 支付宝）

### 客户端团队需要准备
1. OAuth 客户端 SDK 集成
2. 支付界面设计
3. 错误处理完善
4. 流式 ASR UI 适配

---

## 📝 附录：当前代码库状态

### 已完成 ✅
- 核心链路（热键→录音→ASR→润色→注入）
- 本地 Whisper ASR
- VADBuffer 分句
- 热键系统（CGEventTap + NSEvent + 自动重启）
- 基础后端框架（FastAPI + SQLite）

### 进行中 🚧
- 云端 ASR 接入（DashScope 整段识别）
- 网络监控（NetworkMonitor）
- 用户设置界面

### 待启动 ⏸️
- 流式 ASR
- 账号体系
- 计费系统
- 后端生产化

---

## 联系方式

**文档维护人**：客户端开发团队  
**架构师联系**：待指定  
**产品经理**：待指定  

**文档更新日期**：2026-03-23  
**下次评审时间**：待定
