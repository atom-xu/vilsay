# Week 4 · Cursor 开发任务（剩余）

**版本**: 1.3 | **日期**: 2026-03-25  
**前置阅读**: `docs/spec/VILSAY_TECH_ARCH.md`、`docs/VILSAY_TECH_SPEC_SUPPLEMENT.md`、`docs/status/micro-arch/Week4_MICRO_ARCH.md`

> **已完成（本文件不再重复）**：W4-P01～P05（设置内诊断）、W4-02（后端框架）、W4-03 客户端登录 UI、W4-04 Apple ID 客户端、W4-06 Google 客户端 OAuth、邮箱注册/登录主链路骨架。

> **客户端 W4-CLIENT-01～04（2026-03-25 已落地）**：`Info.plist` + `AppDelegate` 深链已具备；设置页已增加「刷新用量」；`AuthService` 已支持 `isQuotaExceeded` / `incrementLocalUsage` / `decrementLocalUsage` 与用量上报写回；`Pipeline.beginRecordingSession` 已做配额拦截；`UsageStatsView` 已接真实用量、超额橙色、`https://vilsay.com/pricing` 升级入口。

> **服务端 W4-SERVER-01～06（2026-03-25 已落地）**：`email_service.py`（验证/重置邮件）、`config` SMTP 与 OAuth 字段、`oauth_util` Google/微信换 token；`main.py`：`/auth/logout`、`GET /usage/history`（`month` + 分页）、`POST /auth/forgot-password` / `reset-password`、`POST /usage/record` 写入 `duration_ms`；SQLite `_migrate_sqlite` 补列；`requirements.txt` 含 `google-auth`、`requests`、`python-multipart`。

---

## 任务总览（10 个可执行任务 + 生产清单）

| 类型 | ID | 摘要 |
|------|-----|------|
| **客户端** | W4-CLIENT-01 | URL Scheme / Deep Link → `AuthService.handleDeepLink` |
| **客户端** | W4-CLIENT-02 | 设置页账号区接真实 `AuthService` |
| **客户端** | W4-CLIENT-03 | 本地用量软限制（`Pipeline` 前拦截 + `incrementLocalUsage`） |
| **客户端** | W4-CLIENT-04 | `UsageStatsView` 真实用量数据 |
| **服务端** | W4-SERVER-01 | SMTP 发验证邮件 |
| **服务端** | W4-SERVER-02 | Google OAuth 服务端换 Token |
| **服务端** | W4-SERVER-03 | 微信 OAuth 服务端换 Token |
| **服务端** | W4-SERVER-04 | `POST /auth/logout` |
| **服务端** | W4-SERVER-05 | `GET /usage/history` |
| **服务端** | W4-SERVER-06 | `forgot-password` / `reset-password` |
| **上线** | W4-PROD-01 | **生产上线检查清单**（JWT、SMTP 暴露、DB、客户端域名与 Scheme 等） |

---

## W4-CLIENT-01 · 补全：URL Scheme 与 Deep Link 接入

```
目标文件：vilsay/vilsay/Info.plist、vilsay/vilsay/App/AppDelegate.swift

1. Info.plist 注册 URL Scheme（若未注册）：
   CFBundleURLTypes → CFBundleURLSchemes = ["vilsay"]

2. AppDelegate 确认存在：
   func application(_ application: NSApplication, open urls: [URL]) {
       for url in urls { AuthService.shared.handleDeepLink(url) }
   }
   （AuthService.handleDeepLink 已实现；仅需确认 AppDelegate 转发）

3. 验收：
   □ 终端运行 open "vilsay://auth/verify?token=test" → App 不崩溃、
     AppDelegate 路由调用 AuthService.handleDeepLink
   □ 终端运行 open "vilsay://auth/callback?code=xxx&state=google" → 同上
```

---

## W4-CLIENT-02 · 补全：设置页账号区接入 AuthService

```
目标文件：vilsay/vilsay/UI/SettingsRootView.swift

当前状态：设置页有账号信息「占位」（W2-06），需接真实 AuthService 数据。

需实现：
1. 账号 Section 根据 AuthService.shared.isAuthenticated 切换：
   - 未登录：「登录 / 注册」按钮 → 打开 LoginView
   - 已登录：
     * 显示 auth.userEmail
     * 显示「本月用量：X / Y 次」（auth.usageUsed / auth.usageQuota）
     * 「刷新用量」按钮 → Task { await auth.refreshUsage() }
     * 「退出登录」按钮 → auth.logout()
2. 若 auth.lastAuthError 非空 → 橙色文字显示在账号 Section 下方

验收：
□ 登录后设置页显示邮箱与用量数字
□ 完成一轮润色后点「刷新用量」，数字 +1
□ 退出登录后显示「登录」按钮
□ 服务端返回 lastAuthError 时设置页内有橙色提示
```

---

## W4-CLIENT-03 · 补全：本地用量软限制（客户端先行拦截）

```
目标文件：vilsay/vilsay/Auth/AuthService.swift、Core/Pipeline.swift

规约（TECH_SPEC_SUPPLEMENT §3.3）：
  App 启动时拉取当月用量；每次使用后本地 +1；
  本地计数 >= quota 时，触发前弹出升级提示，不等服务端 402。

需实现：
1. AuthService 新增：
   func incrementLocalUsage() → usageUsed += 1（仅本地，非上报）
   var isQuotaExceeded: Bool { usageUsed >= usageQuota }

2. Pipeline 在「开始录音」入口（热键按下 / 悬浮球按下 之前）：
   if AuthService.shared.isAuthenticated && AuthService.shared.isQuotaExceeded {
       AppState.shared.lastPipelineError = "本月免费次数已用完，请升级继续使用。"
       AppState.shared.status = .attention
       return   // 不启动录音
   }

3. recordUsageAfterFirstPolishToken 成功后调用 incrementLocalUsage()
   （已有 refreshUsage() 会从服务端同步真实值，incrementLocalUsage 仅防并发延迟）

验收：
□ 后端 free_monthly_quota 改为 2，说 2 句后第 3 次按热键即被拦截
□ 菜单栏或设置内有可见提示
□ 重启 App 后 refreshUsage() 从服务端拉取真实值，若未超则可正常使用
```

---

## W4-CLIENT-04 · 补全：UsageStatsView 接入真实数据

```
目标文件：vilsay/vilsay/UI/UsageStatsView.swift

当前状态：假数据展示（W2-08）。

需实现：
1. 读取 AuthService.shared.usageUsed / usageQuota
2. 进度条 = Double(usageUsed) / Double(max(1, usageQuota))
3. 文字「本月已使用 X / Y 次」
4. 已登录时「升级」按钮可跳转（占位 URL 或 NSWorkspace.open）；
   未登录时显示「请先登录」

验收：
□ 登录后 UsageStatsView 进度条与数字与 SettingsRootView 账号区一致
□ 超过 quota 时进度条满格 + 橙色
```

---

## W4-SERVER-01 · 补全：SMTP 发送验证邮件

```
目标文件：server/app/main.py、server/app/email_service.py（新建）

规约（TECH_SPEC_SUPPLEMENT §2.1）：
  注册后后端发送验证邮件；用户点链接跳 vilsay://auth/verify?token=xxx

需实现：
1. 新建 server/app/email_service.py：
   - 读取 settings.smtp_host / smtp_port / smtp_user / smtp_password
   - 使用 Python 标准库 smtplib + email.mime 发送 HTML 邮件
   - 邮件内容包含：
     vilsay://auth/verify?token={verification_token}
   - 接口：async def send_verification_email(to: str, token: str)

2. server/app/config.py 添加字段：
   smtp_host: str | None = None
   smtp_port: int = 587
   smtp_user: str | None = None
   smtp_password: str | None = None
   smtp_from: str = "noreply@vilsay.com"

3. server/app/main.py：
   - register() 成功后调用 send_verification_email()
   - 若 smtp_host 为 None：不发信（兜底：dev_expose_verification_token 回填 token）
   - 发信失败：记录日志，不影响注册响应（静默失败，token 已存库）

验收：
□ 配置 SMTP_HOST 后注册，收件箱收到验证邮件
□ 未配置 SMTP_HOST 时注册，返回 verification_token（dev_expose_verification_token=True）
□ 发信失败（SMTP 凭证错误）不影响 HTTP 200 注册响应
```

---

## W4-SERVER-02 · 补全：Google OAuth 服务端真实换 Token

```
目标文件：server/app/main.py、server/app/oauth_util.py

规约（TECH_SPEC_SUPPLEMENT §2.1）：
  POST /auth/google { code } → 后端向 Google 换取 id_token，验证后建账号

需实现（auth_google 端点）：
1. 读取 settings.google_client_id / google_client_secret
2. 使用 google-auth 库验证 code：
   - requests.post("https://oauth2.googleapis.com/token", data={
       "code": code, "client_id": ..., "client_secret": ...,
       "redirect_uri": "vilsay://auth/callback", "grant_type": "authorization_code"
     })
   - 解析返回的 id_token → 获取 email
3. 用 email 查/建 User，返回 TokenResponse
4. 若 google_client_id / google_client_secret 未配置：
   返回 400 {"error":"oauth_not_configured","message":"Google 登录未配置"}

server/app/config.py 添加：
  google_client_id: str | None = None
  google_client_secret: str | None = None

requirements.txt 添加：
  google-auth>=2.0
  requests>=2.28

验收：
□ 配置真实 Google Client ID/Secret，App 授权后 Google 账号登录成功
□ 未配置时 POST /auth/google 返回 400 + 明确错误信息（不是 500）
```

---

## W4-SERVER-03 · 补全：微信 OAuth 服务端真实换 Token

```
目标文件：server/app/main.py、server/app/oauth_util.py

规约（TECH_SPEC_SUPPLEMENT §2.1）：
  POST /auth/wechat { code } → 后端向微信换取 access_token + openid，建账号

需实现（auth_wechat 端点）：
1. 读取 settings.wechat_app_id / wechat_app_secret
2. 调用微信 API：
   GET https://api.weixin.qq.com/sns/oauth2/access_token
   ?appid=...&secret=...&code=...&grant_type=authorization_code
   → 解析 openid
3. 以 openid 为账号标识（无邮箱时用 wechat_{openid}@oauth.vilsay.local）
4. 若 wechat_app_id 未配置：返回 400 + 明确错误信息

server/app/config.py 添加：
  wechat_app_id: str | None = None
  wechat_app_secret: str | None = None

注意（TECH_ARCH §11 已知隐患）：
  微信开放平台审核周期长，可能晚于其他登录方式上线；
  服务端实现可先到位，客户端 startWeChatOAuth() 依赖 VILSAY_WECHAT_OAUTH_URL 配置。

验收：
□ 配置真实微信 AppID/Secret，微信授权后登录成功
□ 未配置时返回 400 + 明确错误（不 500）
```

---

## W4-SERVER-04 · 补全：POST /auth/logout（token 记录清除）

```
目标文件：server/app/main.py

说明（micro-arch D-W4-03）：
  Phase 1 不要求 JWT 黑名单（Redis）；仅实现端点使接口列表完整，
  客户端 logout 已清除本地 Token，服务端响应 200 即可。

实现：
@api.post("/auth/logout")
def logout(user: User = Depends(get_current_user)) -> MessageResponse:
    return MessageResponse(message="logged_out")

未来（W6/W7）：若需 JWT 吊销，扩展此端点写入 Redis blacklist。

验收：
□ curl -X POST /auth/logout -H "Authorization: Bearer <token>" → 200 {"message":"logged_out"}
□ curl -X POST /auth/logout （无 token）→ 401
```

---

## W4-SERVER-05 · 补全：GET /usage/history

```
目标文件：server/app/main.py、server/app/schemas.py

规约（TECH_SPEC_SUPPLEMENT §5.4）：
  GET /api/v1/usage/history?page=1&per_page=20&month=2026-03

schemas.py 新增：
  class UsageHistoryItem(BaseModel):
      id: int
      type: str
      created_at: str  # ISO8601
      duration_ms: int | None = None

  class UsageHistoryResponse(BaseModel):
      data: list[UsageHistoryItem]
      pagination: dict   # page, per_page, total, total_pages

main.py 实现：
  @api.get("/usage/history", response_model=UsageHistoryResponse)
  def usage_history(page: int = 1, per_page: int = 20, month: str | None = None,
                    user: User = Depends(get_current_user), db: Session = Depends(get_db)):
      # 按 month 过滤（YYYY-MM），分页查询 UsageEvent
      ...

验收：
□ 说 5 句后 GET /usage/history → data 含 5 条
□ month=2026-03 过滤正确
□ 分页字段存在
```

---

## W4-SERVER-06 · 补全：POST /auth/forgot-password + reset-password

```
目标文件：server/app/main.py、server/app/models.py、server/app/email_service.py

规约（TECH_ARCH §6.2 API 列表）：
  POST /auth/forgot-password   → 发重置邮件
  POST /auth/reset-password    → 用 token 设新密码

models.py 在 User 上添加（SQLite 迁移用 ALTER TABLE 同现有 _migrate_sqlite 模式）：
  reset_token: Mapped[str | None] = mapped_column(String(128), nullable=True, index=True)
  reset_token_expires_at: Mapped[datetime | None]

forgot-password：
  - 查 user by email → 生成 secrets.token_urlsafe(32) → 存 reset_token + 设 1 小时过期
  - 调用 email_service.send_reset_email(email, token)（若 smtp_host 为 None 则 dev 暴露 token）
  - 返回 {"message":"if_account_exists_email_sent"}（勿泄露账号是否存在）

reset-password：
  - 查 user by reset_token → 验证未过期 → hash_password(new_password) → 清除 reset_token

验收：
□ POST /auth/forgot-password {email} → 200（账号存在或不存在响应相同）
□ 用正确 token 重置密码后可登录新密码
□ token 过期（手动把 reset_token_expires_at 设为过去）→ 400 "invalid or expired token"
```

---

## W4-PROD-01 · 生产上线检查清单（开发完成后验证）

```
服务端必须修改（发版前）：
□ JWT_SECRET 改为真实随机值（openssl rand -hex 32），通过环境变量注入
□ dev_expose_verification_token 改为 False（生产 .env 中 DEV_EXPOSE_VERIFICATION_TOKEN=false）
□ DATABASE_URL 改为 PostgreSQL 连接字符串
□ free_monthly_quota 与产品确认后对齐（当前 500，规约示例 200）

客户端必须确认（发版前）：
□ AppConfig.backendAPIBaseURL 生产值指向部署域名（非 localhost）
□ vilsay:// URL Scheme 已在 Info.plist 注册
□ VILSAY_GOOGLE_CLIENT_ID 填写真实值
□ DashScope API Key 非客户端直连（上线前移到自建代理）
```

---

# 文档结束
