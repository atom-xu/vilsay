# Week 4 · 微架构对齐（正式版）

**版本**: 1.1 | **日期**: 2026-03-25
**范围**: W4-02～W4-08（账号与用量）、W4-P01～P05（诊断与错误显性化）
**参与**: 架构（Claude）+ 开发（Cursor）

> **微架构门禁规则**：本文件通过后，Cursor 可领取下列任务；未完成项不得标为 ✅ 全部完成。

---

## 一、任务与代码映射

| 任务 | 状态 | 主要代码位置 |
|------|------|------------|
| W4-P01 权限中心 | ✅ 已落地 | `Core/PermissionManager.swift`、`UI/SettingsDiagnosticsSection.swift` |
| W4-P02 麦克风试录 | ✅ 已落地 | `SettingsDiagnosticsSection.MicTestSection` / `MicTestController` |
| W4-P03 热键自测 | ✅ 已落地 | `SettingsDiagnosticsSection.HotkeySelfTestSection`、`AppState.hotkeySelfTestAwaiting` |
| W4-P04 AI 分段诊断 | ✅ 已落地 | `SettingsDiagnosticsSection.AIDiagnosticsSection` / `AIDiagnosticsController` |
| W4-P05 最近问题 | ✅ 已落地 | `SettingsDiagnosticsSection.RecentIssuesSection` |
| W4-02 后端 API 框架 | ✅ 已落地 | `server/app/main.py`（FastAPI）、`models.py`、`schemas.py`、`security.py` |
| W4-03 邮箱注册/登录 | ✅ 客户端 + 服务端骨架；⚠️ **SMTP 发信缺失** | `Auth/AuthService.swift`、`UI/LoginView.swift`、`server/app/main.py` |
| W4-04 Apple ID | ✅ 已落地 | `Auth/OAuthSignInCoordinator.startAppleSignIn()`、`server /auth/apple` |
| W4-05 微信 | ⚠️ 客户端有 URL 跳转占位；服务端为 dev 假 email | `OAuthSignInCoordinator.startWeChatOAuth()`、`server /auth/wechat` |
| W4-06 Google | ⚠️ 客户端 `ASWebAuthenticationSession` 完成；服务端为 dev 假 email | `OAuthSignInCoordinator.startGoogleOAuth()`、`server /auth/google` |
| W4-07 用量统计 | ✅ 主体落地；⚠️ 缺 `GET /usage/history` | `AuthService.refreshUsage()`、`UI/UsageStatsView.swift`、`server /usage/current` |
| W4-08 计费/订阅 | 🔲 未实现 | 客户端占位按钮；服务端无 `/billing/` 路由 |
| W4-01 流式 VAD | 🔲 阻塞于 WebSocket ASR，延后 | 见任务书说明 |

---

## 二、对外契约

### 2.1 客户端 → 后端 HTTP 接口（已实现部分）

| 方法 | 路径 | 调用位置 | 备注 |
|------|------|----------|------|
| `POST` | `/api/v1/auth/register` | `AuthService.register()` | 返回 `verificationToken`（开发可选） |
| `POST` | `/api/v1/auth/login` | `AuthService.login()` | 返回 access + refresh JWT |
| `POST` | `/api/v1/auth/refresh` | `AuthService.refreshTokensIfNeeded()` | access 过期前 1 天自动刷新 |
| `GET` | `/api/v1/auth/verify-status?email=` | `AuthService.fetchVerifyStatus()` | 注册后轮询，每 3 秒 |
| `POST` | `/api/v1/auth/verify-email` | Deep link `vilsay://auth/verify?token=` → `AuthService.verifyEmailToken()` | |
| `POST` | `/api/v1/auth/apple` | `AuthService.signInWithApple()` | identityToken + authorizationCode |
| `POST` | `/api/v1/auth/google` | Deep link `vilsay://auth/callback?...&state=google` | 服务端当前 **dev 占位** |
| `POST` | `/api/v1/auth/wechat` | Deep link `vilsay://auth/callback?code=` | 服务端当前 **dev 占位** |
| `GET` | `/api/v1/usage/current` | `AuthService.refreshUsage()` | 已登录时返回本月用量 |
| `POST` | `/api/v1/usage/record` | `AuthService.recordUsageAfterFirstPolishToken()` | 润色首 token 时异步上报 |

### 2.2 Token 存储

- `accessToken`（7 天）→ `KeychainTokenStore.save(_:)` → `kSecAttrAccessibleAfterFirstUnlock`
- `refreshToken`（30 天）→ `KeychainTokenStore.saveRefreshToken(_:)`
- 登出 → `KeychainTokenStore.deleteToken()`（同时清除两 token）
- JWT 过期解析（仅为刷新调度，非鉴权）→ `JWTAccessExpiry.expirationDate(accessToken:)`

### 2.3 URL Scheme

```
vilsay://auth/callback    Google / 微信 OAuth 回调
vilsay://auth/verify      邮件验证回跳（?token=xxx）
```

**Info.plist `CFBundleURLSchemes`** 须注册 `vilsay`；`AppDelegate.application(_:open:)` 调用 `AuthService.shared.handleDeepLink(_:)`。

---

## 三、数据流

```
[LoginView] → AuthService.login() / register() / signInWithApple()
                     ↓
              BackendAPIClient.postJSON()
              base: AppConfig.backendAPIBaseURL
              prefix: /api/v1
                     ↓ JSON snake_case ↔ camelCase (JSONEncoder/Decoder)
              server/app/main.py (FastAPI)
                     ↓
              models.User (SQLAlchemy) → DB (SQLite/PostgreSQL)
                     ↓ 返回 TokenResponse
              KeychainTokenStore.save(accessToken)
              KeychainTokenStore.saveRefreshToken(refreshToken)
              AuthService.isAuthenticated = true

[Pipeline 润色完成第一个 token]
  → AuthService.recordUsageAfterFirstPolishToken()
  → POST /api/v1/usage/record  (异步，不阻塞主链路)
  → 402 → AppState.status = .attention + lastPipelineError = quotaExceeded
```

---

## 四、权限与沙盒

本 Week 无新 entitlement 需求；现有已满足：
- `com.apple.security.network.client`：后端 HTTP 已覆盖
- Keychain：`kSecAttrAccessibleAfterFirstUnlock`，沙盒内合法

`ASWebAuthenticationSession` 和 `ASAuthorizationAppleIDProvider` 无需额外 entitlements。

---

## 五、失败与降级

| 场景 | 用户可见行为 |
|------|------------|
| 未配置后端 URL | LoginView 橙色提示「未配置 VILSAY_API_BASE」；用量显示占位 |
| 注册后未收到验证邮件 | alert 提示「请查收验证邮件」；开发版展示 token 供直接验证 |
| login 返回 401 | `AuthService.lastAuthError` → LoginView 显示错误 |
| 用量上报 402 | `AppState.lastPipelineError = quotaExceeded`；菜单栏橙色图标 |
| Token 过期 refresh 失败 | 清除 Token，退回未登录状态，`lastAuthError` 提示 |
| Google OAuth 取消 | `ASWebAuthenticationSession` 返回 code=1 → 静默，不报错 |
| 微信 URL 未配置 | `lastAuthError = "未配置 VILSAY_WECHAT_OAUTH_URL"` |
| 无网络 | `NetworkMonitor` → `AppState.networkOfflineHint` 菜单 + 诊断区 |

---

## 六、架构符合性 · 已知偏离（本周确认）

| 编号 | 偏离项 | 规约出处 | 偏离内容 | 决策 |
|------|--------|----------|----------|------|
| D-W4-01 | `free_monthly_quota = 500` | TECH_SPEC_SUPPLEMENT §3.2：200+50 | 服务端默认 500（统一额度） | **待产品确认**；上线前需对齐，或拆分 `polish_quota`/`select_speak_quota` |
| D-W4-02 | `AppError` enum 未落地 | TECH_SPEC_SUPPLEMENT §6.1 | 代码使用 `UserFacingError` 字符串 + `AppState` 多字段 | **有意简化**；当前可感知效果等同；W6 打磨期统一 |
| D-W4-03 | `POST /auth/logout` 未实现 | TECH_ARCH §6.2 API 列表 | 纯客户端清 Token；无服务端 blacklist | **可接受（Phase 1）**；上线前若需 JWT 吊销须加 Redis；记入 W6 |
| D-W4-04 | Google/微信服务端为 `oauth_dev_email` 占位 | TECH_SPEC_SUPPLEMENT §2.1 | 服务端未真实换 token | **已知，非生产**；Cursor 任务 W4-SERVER-02/03 补全 |
| D-W4-05 | 邮件验证无 SMTP | TECH_SPEC_SUPPLEMENT §2.1 | 服务端存 `verification_token` 但不发信 | **已知**；Cursor 任务 W4-SERVER-01 补全；开发阶段用 `dev_expose_verification_token` |
| D-W4-06 | `dev_expose_verification_token = True` | — | 生产不可开启 | **必须在上线前改为 False**；标入发版检查清单 |
| D-W4-07 | `jwt_secret` 为硬编码 dev 值 | 安全基线 | `server/app/config.py` 默认字符串 | **必须通过环境变量覆盖再部署**；标入发版检查清单 |
| D-W4-08 | 自建润色代理 `/api/v1/polish` 未实现 | TECH_SPEC_SUPPLEMENT §4.2 | 客户端仍直连 DashScope | **Phase 1 可接受**；W7+ 后端前移时实现 |

---

## 七、Week 4 剩余任务清单（给 Cursor）

详见 `docs/status/WEEK4_CURSOR_TASKS.md`（本次新建）。

---

## 八、验收步骤

```bash
# 1. 启动后端（SQLite dev）
cd /path/to/Vilsay/server
source .venv/bin/activate
DATABASE_URL=sqlite:///./vilsay.db \
  JWT_SECRET=test-secret-32chars-xxxxxxxxxxx \
  uvicorn app.main:app --reload

# 2. 后端健康检查
curl http://127.0.0.1:8000/health
# 期望: {"status": "ok"}

# 3. 邮箱注册
curl -X POST http://127.0.0.1:8000/api/v1/auth/register \
  -H 'Content-Type: application/json' \
  -d '{"email":"test@example.com","password":"testpass123"}'
# 期望: {"message":"registered","verification_token":"<tok>"}

# 4. 邮箱登录（开发：未验证也可登录，视服务端策略）
curl -X POST http://127.0.0.1:8000/api/v1/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"email":"test@example.com","password":"testpass123"}'
# 期望: {"access_token":"...","refresh_token":"..."}

# 5. 用量查询
curl http://127.0.0.1:8000/api/v1/usage/current \
  -H 'Authorization: Bearer <access_token>'

# 6. App 端集成验收
# a. 设置环境变量 VILSAY_API_BASE=http://127.0.0.1:8000 后运行 App
# b. 打开设置 → 账号页 → 邮箱注册 → 验证 → 登录 → 设置页显示邮箱与用量
# c. 说一句话润色 → 设置页用量 +1
# d. 设置 → 诊断 → 权限区、试录、热键自测、AI 各段可独立测试
# e. 菜单栏「最近问题」显示 polishAttentionMessage
```

---

# 文档结束
