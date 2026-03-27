# Week 4 任务拆解（架构师细化版）

**架构师**：AI Architect  
**日期**：2026-03-23  
**目标**：将 Week 4 的宏观需求拆解成可在 1-2 周内完成的小任务

---

## 🎯 Week 4 原始需求回顾

根据任务书，Week 4 的核心需求：
1. **流式 ASR + 800ms 文本 VAD**（W4-01）
2. **账号体系**（邮箱验证、忘记密码、OAuth）
3. **计费与用量**（套餐、限额）

**架构师评估**：这些需求工作量至少 **10-12 周**，不可能在 Week 4 完成。

---

## 📊 决策：分阶段交付（MVP 优先）

### 阶段 1：Week 4-5（2 周）- 基础可用
**目标**：快速上线基础版本，验证核心流程

### 阶段 2：Week 6-8（3 周）- 功能完善
**目标**：补齐高级特性

### 阶段 3：Week 9-10（2 周）- 优化与上线
**目标**：性能优化、安全加固

---

## 🔥 阶段 1：Week 4-5 任务拆解

### Sprint 1.1：账号体系基础（5 天）

#### Task 1.1.1：后端 - 邮箱注册（2 天）
**负责人**：后端开发  
**优先级**：P0

**子任务**：
- [ ] 数据库 Schema 设计（`users` 表）
  ```sql
  CREATE TABLE users (
      id SERIAL PRIMARY KEY,
      email VARCHAR(255) UNIQUE NOT NULL,
      password_hash VARCHAR(255) NOT NULL,
      is_verified BOOLEAN DEFAULT FALSE,
      verification_token VARCHAR(255),
      created_at TIMESTAMP DEFAULT NOW()
  );
  ```

- [ ] `POST /auth/register` API 实现
  ```python
  @app.post("/auth/register")
  async def register(user: UserCreate):
      # 1. 检查邮箱是否已存在
      # 2. bcrypt 加密密码
      # 3. 生成验证 Token（UUID）
      # 4. 保存到数据库
      # 5. 返回成功（暂不发邮件）
      return {"message": "注册成功，请验证邮箱"}
  ```

- [ ] `POST /auth/login` API 实现
  ```python
  @app.post("/auth/login")
  async def login(credentials: LoginRequest):
      # 1. 查询用户
      # 2. 验证密码（bcrypt.checkpw）
      # 3. 生成 JWT
      # 4. 返回 Token
      return {"access_token": jwt_token}
  ```

- [ ] 单元测试（Pytest）

**验收标准**：
- ✅ 可以注册用户
- ✅ 可以登录获取 Token
- ✅ 密码已加密存储

---

#### Task 1.1.2：客户端 - 登录界面（2 天）
**负责人**：客户端开发  
**优先级**：P0

**子任务**：
- [ ] 创建 `LoginView.swift`
  ```swift
  struct LoginView: View {
      @State private var email = ""
      @State private var password = ""
      @State private var isLoading = false
      @State private var errorMessage: String?
      
      var body: some View {
          VStack(spacing: 20) {
              TextField("邮箱", text: $email)
                  .textContentType(.emailAddress)
              
              SecureField("密码", text: $password)
                  .textContentType(.password)
              
              Button("登录") {
                  Task { await login() }
              }
              
              Button("注册") {
                  // TODO: 打开注册页面
              }
          }
      }
      
      func login() async {
          // 调用后端 API
      }
  }
  ```

- [ ] 创建 `APIClient.swift`（网络请求封装）
  ```swift
  struct APIClient {
      static let baseURL = ProcessInfo.processInfo.environment["VILSAY_API_BASE"] ?? "http://localhost:8000"
      
      static func login(email: String, password: String) async throws -> String {
          // POST /auth/login
          // 返回 JWT Token
      }
  }
  ```

- [ ] Token 存储（Keychain）
  ```swift
  struct KeychainHelper {
      static func saveToken(_ token: String) {
          // 使用 Keychain Services API
      }
      
      static func loadToken() -> String? {
          // 从 Keychain 读取
      }
  }
  ```

**验收标准**：
- ✅ 可以输入邮箱密码登录
- ✅ Token 安全存储在 Keychain
- ✅ 错误提示友好

---

#### Task 1.1.3：集成测试（1 天）
**负责人**：测试 + 开发  
**优先级**：P0

**测试用例**：
- [ ] 注册新用户 → 登录 → 获取 Token
- [ ] 登录失败（错误密码）
- [ ] 重复注册（邮箱已存在）
- [ ] Token 过期处理

---

### Sprint 1.2：计费基础（3 天）

#### Task 1.2.1：后端 - 免费额度限制（2 天）
**负责人**：后端开发  
**优先级**：P1

**子任务**：
- [ ] 数据库 Schema 更新
  ```sql
  ALTER TABLE users ADD COLUMN free_monthly_quota INT DEFAULT 100;
  ALTER TABLE users ADD COLUMN used_quota INT DEFAULT 0;
  ALTER TABLE users ADD COLUMN quota_reset_at TIMESTAMP;
  ```

- [ ] 中间件：额度检查
  ```python
  async def check_quota(user: User):
      if user.used_quota >= user.free_monthly_quota:
          raise HTTPException(status_code=402, detail="额度已用完")
  ```

- [ ] `POST /polish` 增加计数逻辑
  ```python
  @app.post("/polish")
  async def polish(request: PolishRequest, user: User = Depends(get_current_user)):
      # 1. 检查额度
      await check_quota(user)
      
      # 2. 调用润色服务
      result = await polish_service(request.text)
      
      # 3. 增加使用次数
      user.used_quota += 1
      await db.commit()
      
      return {"polished_text": result}
  ```

**验收标准**：
- ✅ 超额时返回 402 状态码
- ✅ 每次润色正确计数

---

#### Task 1.2.2：客户端 - 额度显示（1 天）
**负责人**：客户端开发  
**优先级**：P1

**子任务**：
- [ ] 在设置界面显示剩余次数
  ```swift
  struct QuotaView: View {
      @State private var usedQuota = 0
      @State private var totalQuota = 100
      
      var body: some View {
          VStack {
              Text("本月已用：\(usedQuota) / \(totalQuota)")
              ProgressView(value: Double(usedQuota), total: Double(totalQuota))
          }
      }
  }
  ```

- [ ] 处理 402 响应
  ```swift
  if response.statusCode == 402 {
      AppState.shared.showUpgradePrompt = true
  }
  ```

**验收标准**：
- ✅ 可以查看剩余次数
- ✅ 超额时有明确提示

---

### Sprint 1.3：流式 ASR 基础（5 天）

#### Task 1.3.1：WebSocket 客户端（3 天）
**负责人**：客户端开发  
**优先级**：P0

**子任务**：
- [ ] 创建 `StreamingASRClient.swift`（参考 `STREAMING_ASR_DESIGN.md`）
  ```swift
  @MainActor
  final class StreamingASRClient {
      private var webSocketTask: URLSessionWebSocketTask?
      
      func connect() async throws {
          // WebSocket 连接
      }
      
      func sendAudioFrame(_ data: Data) async throws {
          // 发送音频帧
      }
      
      func disconnect() {
          // 关闭连接
      }
  }
  ```

- [ ] Mock 服务器测试（本地 WebSocket Server）
  ```python
  # test_ws_server.py
  import asyncio
  import websockets
  
  async def echo(websocket):
      async for message in websocket:
          # 返回 Mock 识别结果
          await websocket.send('{"text": "测试文本"}')
  
  asyncio.run(websockets.serve(echo, "localhost", 8765))
  ```

- [ ] 单元测试

**验收标准**：
- ✅ 可以连接 Mock 服务器
- ✅ 可以发送音频帧
- ✅ 可以接收识别结果

---

#### Task 1.3.2：DashScope 接入（2 天）
**负责人**：客户端开发  
**优先级**：P1

**子任务**：
- [ ] 申请 DashScope API Key
- [ ] 实现鉴权逻辑（Token 生成）
- [ ] 替换 Mock 服务器为真实端点
- [ ] 错误处理（网络超时、连接断开）

**验收标准**：
- ✅ 可以连接 DashScope
- ✅ 可以接收真实识别结果
- ✅ 错误有明确日志

---

### Sprint 1.4：基础集成（2 天）

#### Task 1.4.1：登录 + 润色联调（1 天）
**负责人**：全栈  
**优先级**：P0

**测试流程**：
1. 注册用户 → 登录
2. 触发热键 → 录音 → 润色
3. 检查额度是否扣减
4. 超额后是否拒绝

---

#### Task 1.4.2：流式 ASR 初步测试（1 天）
**负责人**：客户端  
**优先级**：P1

**测试流程**：
1. 开启流式模式（设置）
2. 按住热键说话
3. 观察实时文本输出（日志）
4. 验证延迟是否 < 1 秒

---

## 🎯 阶段 1 总结（Week 4-5）

**完成内容**：
- ✅ 基础账号（注册、登录）
- ✅ 免费额度限制（100 次/月）
- ✅ 流式 ASR 雏形（可接收实时文本）

**未完成（留待 Week 6+）**：
- ⏸️ 邮箱验证（不影响基础使用）
- ⏸️ 忘记密码（可手动重置数据库）
- ⏸️ OAuth（Sign in with Apple / Google）
- ⏸️ 800ms VAD（先用整段识别）
- ⏸️ 付费升级（暂时只有免费版）

---

## 📊 阶段 2-3 任务概览（Week 6-10）

### Week 6-7：完善账号体系
- [ ] 邮箱验证（SendGrid）
- [ ] 忘记密码
- [ ] Sign in with Apple

### Week 8：流式 ASR 完整版
- [ ] 800ms 文本 VAD
- [ ] 流式润色
- [ ] 性能优化

### Week 9：付费与计费
- [ ] Stripe 支付集成
- [ ] Pro 套餐
- [ ] 用量统计

### Week 10：测试与上线
- [ ] 安全审计
- [ ] 性能测试
- [ ] 生产环境部署

---

## 🚀 开发建议

### 1. 每日站会（15 分钟）
- 昨天完成了什么
- 今天计划做什么
- 遇到了什么阻碍

### 2. 代码审查（必须）
- 每个 PR 至少 1 人 Review
- 关键功能（账号、支付）需要 2 人 Review

### 3. 持续集成
- 每次提交自动运行测试
- 测试覆盖率 > 70%

### 4. 文档同步
- API 变更立即更新文档
- 每周五更新 `VILSAY_DEV_TASKS.md`

---

## 📝 风险管理

| 风险 | 概率 | 影响 | 缓解措施 |
|------|------|------|---------|
| DashScope API 不稳定 | 中 | 高 | 提前准备本地 Whisper 备用 |
| 后端开发进度慢 | 中 | 中 | 客户端先用 Mock API |
| 流式 ASR 延迟高 | 低 | 中 | 优化音频帧大小 |
| 账号系统安全漏洞 | 低 | 高 | 提前进行安全审计 |

---

## ✅ Week 4-5 验收标准

**功能完整性**：
- [ ] 可以注册、登录
- [ ] 润色功能需要登录
- [ ] 免费额度 100 次/月
- [ ] 流式 ASR 可接收实时文本

**性能**：
- [ ] 登录响应 < 1 秒
- [ ] 流式 ASR 首字延迟 < 1 秒

**用户体验**：
- [ ] 错误提示清晰
- [ ] 界面无闪烁

**代码质量**：
- [ ] 测试覆盖率 > 70%
- [ ] 无 Critical Bug

---

**批准**：架构师  
**日期**：2026-03-23  
**下一步**：开发团队按此计划执行，每日更新进度
