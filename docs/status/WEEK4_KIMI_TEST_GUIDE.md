# Week 4 · Kimi 测试指南

**版本**: 1.0 | **日期**: 2026-03-25
**测试范围**: 账号体系、用量统计、设置内诊断、错误显性化
**前置**: `docs/status/micro-arch/Week4_MICRO_ARCH.md`、`docs/DASHSCOPE_SMOKE_TEST.md`

---

## 一、环境准备

### 1.1 启动后端服务

```bash
cd Vilsay/server
source .venv/bin/activate
# 使用 SQLite（开发）
DATABASE_URL=sqlite:///./vilsay.db \
  JWT_SECRET=test-secret-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx \
  DEV_EXPOSE_VERIFICATION_TOKEN=true \
  uvicorn app.main:app --reload --port 8000

# 健康检查
curl http://127.0.0.1:8000/health
# 期望: {"status":"ok"}
```

### 1.2 App 环境变量

Xcode Scheme → Edit Scheme → Arguments → Environment Variables:

```
VILSAY_API_BASE = http://127.0.0.1:8000
DASHSCOPE_API_KEY = <你的百炼 Key>
```

### 1.3 重置测试账号

```bash
# 删除 SQLite 数据库重置（服务重启后自动重建）
rm Vilsay/server/vilsay.db
```

---

## 二、A 类：账号注册与登录（邮箱）

### T-W4-A01 · 正常注册流程

```
前置：后端运行，App 设置 VILSAY_API_BASE

步骤：
1. 打开设置 → 账号 → 「登录 / 注册」
2. 切换到「注册」，输入 test1@example.com / TestPass123
3. 点「注册」

期望：
□ 弹出「请查收验证邮件」对话框
□ 开发环境对话框内展示 verification_token
□ 服务端 GET /api/v1/auth/verify-status?email=test1@example.com 返回 verified:false

验证验证链路（从对话框取 token）：
4. 取出 verification_token，在 App 内或终端执行：
   open "vilsay://auth/verify?token=<token>"

期望：
□ App 自动完成登录（isAuthenticated = true）
□ 设置页显示 test1@example.com 与用量数字（0 / N）
□ Onboarding Step 4（如未完成）进入已登录状态
```

### T-W4-A02 · 重复注册（错误路径）

```
步骤：
1. 用已注册邮箱 test1@example.com 再次注册

期望：
□ LoginView 显示错误文字（如「该邮箱已注册」或服务端 400 detail）
□ 不崩溃，不弹系统弹窗
□ 邮箱/密码字段仍可继续编辑
```

### T-W4-A03 · 正常登录

```
步骤：
1. 账号页切换「登录」
2. 输入 test1@example.com / TestPass123，点「登录」

期望：
□ 登录成功 → 窗口关闭或跳转
□ 设置页显示邮箱和用量
□ AppState.shared.isAuthenticated（可在 Xcode 调试确认）
```

### T-W4-A04 · 密码错误（错误路径）

```
步骤：
1. 输入正确邮箱 + 错误密码

期望：
□ 显示「邮箱或密码错误」类错误（不可分别提示哪个错误）
□ 不崩溃、不清空邮箱字段
```

### T-W4-A05 · 退出登录

```
步骤：
1. 已登录状态 → 设置 → 「退出登录」

期望：
□ 设置页切回「登录」按钮
□ Keychain 清除（重启 App 后不自动登录）
□ usageUsed 归零（不显示历史数字）
```

---

## 三、B 类：Apple ID 登录

### T-W4-B01 · Apple ID 正常登录

```
前置：已配置后端；App 有 Apple Developer 账号 provisioning

步骤：
1. 账号页 → 「Sign in with Apple」

期望：
□ 系统弹出 Apple 授权界面
□ 授权后登录成功（设置页显示 Apple 关联邮箱或 apple_xxx@oauth.vilsay.local）
□ Keychain 存有 accessToken
□ 重启 App → 自动恢复登录状态
```

### T-W4-B02 · 取消 Apple 登录

```
步骤：
1. 触发 Apple 登录 → 系统弹窗 → 点「取消」

期望：
□ App 不报错、不进入错误状态
□ LoginView 仍显示，按钮可再次点击
```

---

## 四、C 类：Google OAuth 登录（需配置 VILSAY_GOOGLE_CLIENT_ID）

### T-W4-C01 · Google 正常登录

```
前置：VILSAY_GOOGLE_CLIENT_ID 设置，服务端 GOOGLE_CLIENT_ID + GOOGLE_CLIENT_SECRET 设置

步骤：
1. 账号页 → 「Google 登录」
2. 系统打开 ASWebAuthenticationSession（内嵌浏览器）
3. 完成 Google 授权

期望：
□ 授权后回调 vilsay://auth/callback?code=xxx&state=google
□ App 自动完成登录，设置页显示 Google 邮箱
```

### T-W4-C02 · 未配置 Google Client ID

```
步骤：
1. 不设置 VILSAY_GOOGLE_CLIENT_ID
2. 点「Google 登录」

期望：
□ 显示明确提示「未配置 VILSAY_GOOGLE_CLIENT_ID」
□ 不崩溃、不打开空浏览器
```

### T-W4-C03 · 取消 Google 登录

```
步骤：
1. 触发 Google 登录 → 浏览器弹出 → 关闭/取消

期望：
□ App 不报错（静默处理 ASWebAuthenticationSession code=1 cancellation）
□ LoginView 正常可继续操作
```

---

## 五、D 类：用量统计

### T-W4-D01 · 用量正常计数

```
前置：已登录，DASHSCOPE_API_KEY 配置

步骤：
1. 记录当前 usageUsed（设置页查看）
2. 按热键说一句话，完成润色注入
3. 设置 → 账号区 → 「刷新用量」

期望：
□ 用量数字 +1
□ 后端 GET /usage/current → used +1（curl 验证）
□ 取消（ESC）的录音不计数
```

### T-W4-D02 · 用量上报不阻塞主链路

```
步骤：
1. 断开后端（停止 uvicorn）
2. 说一句话，完成润色注入

期望：
□ 润色与注入正常完成（<1.5s）
□ 菜单栏/设置出现「用量上报失败」类错误提示（非崩溃）
□ 主链路时延不受影响（性能日志确认）
```

### T-W4-D03 · 超额拦截（软限制）

```
前置：服务端 FREE_MONTHLY_QUOTA 改为 2（临时测试）

步骤：
1. 说 2 句（到达额度）
2. 按热键触发第 3 次

期望：
□ 第 3 次按热键 → 不启动录音
□ 菜单栏或设置内有「本月免费次数已用完」提示
□ 悬浮按钮不进入录音状态
```

### T-W4-D04 · 服务端超额返回 402

```
前置：用量已超 free_monthly_quota（直接 DB 插入 usage_events 造满）

步骤：
1. 说一句话润色（此次上报会触发服务端 402）

期望：
□ AppState.lastPipelineError 含 quotaExceeded 文案
□ 菜单栏橙色图标 + 点击可见错误文字
□ 润色文字已注入（规约：超额在当次后才拦截，不在说话中途打断）
```

---

## 六、E 类：设置内诊断（W4-P01～P05）

### T-W4-E01 · 权限中心（W4-P01）

```
步骤：
1. 设置 → 诊断区 → 权限 Section

期望：
□ 麦克风权限状态正确（授权 / 未授权）
□ 辅助功能权限状态正确
□ 「打开系统设置」按钮点击 → 跳转正确的隐私设置页（Privacy_Microphone / Privacy_Accessibility）
□ 在系统设置中切换权限后回到 App → 状态自动刷新（无需重启）
```

### T-W4-E02 · 麦克风试录（W4-P02）

```
步骤：
1. 设置 → 诊断 → 「开始试录」→ 说几个字 → 「停止」
2. 点「播放」

期望：
□ 停止后显示录音时长（秒）
□ 播放可听到声音
□ 「删除临时文件」后临时目录无残留文件
□ 录音过短（< 0.2s）时显示提示文字，不崩溃
□ 麦克风权限被拒时显示具体错误 + 「打开麦克风隐私设置」按钮
```

### T-W4-E03 · 热键自测（W4-P03）

```
步骤：
1. 设置 → 诊断 → 「开始监听热键」
2. 按当前绑定热键（FN 或右 Option）

期望：
□ 显示「热键检测成功」类绿色提示
□ 测试 ESC：「开始监听」→ 按 ESC → 提示成功
□ 无辅助功能时：红色提示「热键监听未就绪」+「打开辅助功能设置」按钮

异常路径：
□ 辅助功能关闭时点「开始监听」→ 明确提示无权限（不静默）
```

### T-W4-E04 · AI 分段诊断（W4-P04）

```
前置：已完成麦克风试录（有 lastURL）、配置 DASHSCOPE_API_KEY

步骤：
1. 「运行本地转写」→ 显示 Whisper 结果 + 耗时
2. 「请求云端（样例 URL）」→ 若配置 Key → 显示 Paraformer 结果或明确提示
3. 「运行润色诊断」→ 显示 AI2 润色结果 + 耗时

期望：
□ 各按钮独立，互不阻塞
□ 本地 Whisper 未就绪时显示「本地模型仍在加载」（非空白）
□ 无 API Key 时润色诊断显示「未配置 API Key，输出为降级原文」
□ 无网络时云端 ASR 显示「当前无网络」
□ 每种异常均有独立说明行（非仅 Logger）
```

### T-W4-E05 · 最近问题摘要（W4-P05）

```
步骤：
1. 触发一个可见错误（如关闭后端后录音）
2. 设置 → 诊断 → 「最近问题」Section

期望：
□ 错误文字可见（lastPipelineError / polishAttentionMessage）
□ 「复制全部摘要」→ 粘贴后包含错误文字
□ 「清除摘要显示」→ 文字消失（不写磁盘）
□ 无错误时显示「暂无最近问题」
```

---

## 七、F 类：错误显性化与弱网

### T-W4-F01 · 后端断开时登录操作

```
步骤：
1. 停止后端服务
2. 尝试邮箱登录

期望：
□ LoginView 出现错误文字（连接失败或超时）
□ 不崩溃、不卡死（有 URLSession timeout）
□ 重启后端后可再次正常登录
```

### T-W4-F02 · 弱网 / 无网提示

```
步骤：
1. 断开 Wi-Fi / 以太网
2. 触发热键录音

期望：
□ AppState.networkOfflineHint 被设置 → 菜单栏或诊断区可见「当前无网络」
□ 自动切本地 Whisper（不闪退）
□ 润色无 API Key 时返回原文（降级行为符合规约）
□ 重连网络后 networkOfflineHint 清除
```

### T-W4-F03 · Token 过期处理

```
步骤（模拟方式：修改服务端 jwt_access_days=0 后重登、再等几分钟）：
1. 登录后等 access token 过期
2. 执行任意需要鉴权的操作（用量刷新）

期望：
□ App 自动尝试 refreshToken 续期（refreshTokensIfNeeded）
□ 若 refresh 也过期 → 自动登出，设置页切回「登录」按钮
□ 有可见提示「登录已过期」或 lastAuthError
```

---

## 八、G 类：Week 4 里程碑（最终验收）

```
以下全部通过方可将 Week 4 标为完成：

账号与认证：
□ G01 邮箱注册 → 验证 → 登录 全流程正常
□ G02 Apple ID 登录正常
□ G03 Google OAuth 正常（若 Client ID 已配置）
□ G04 登出后 Token 清除，重启不自动登录

用量：
□ G05 说 3 句，用量 +3（服务端确认）
□ G06 超额后热键被软拦截（客户端先行判断）

诊断与错误：
□ G07 W4-P01～P05 各诊断区无报错、信息准确
□ G08 断后端 → 登录失败提示可见
□ G09 无网络 → 自动降级本地 Whisper，菜单有提示

代码质量（架构合规）：
□ G10 build 无 ERROR（Warning 可有）
□ G11 xcodebuild test -only-testing:vilsayTests 全绿
□ G12 vilsay:// URL Scheme 注册确认（Info.plist 中存在）
```

---

## 九、已知可跳过项（本阶段不作门禁）

| 项目 | 原因 |
|------|------|
| 微信登录真实验证 | 开放平台审核周期；服务端占位；客户端入口已有 |
| `GET /usage/history` UI 集成 | 仅后端补全即可；前端 UsageStatsView 折线图用假数据过渡 |
| `POST /auth/forgot-password` | SMTP 需先完成；可在 SMTP 任务后联测 |
| 自建润色代理 | W7+ 后端前移；当前客户端直连 |

---

# 文档结束
