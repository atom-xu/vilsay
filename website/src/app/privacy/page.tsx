export const metadata = {
  title: "隐私政策 - Vilsay",
  description: "Vilsay 隐私政策：了解我们如何收集、使用和保护您的数据。",
};

export default function PrivacyPage() {
  return (
    <main className="mx-auto max-w-3xl px-4 py-16">
      <h1 className="text-3xl font-bold">Vilsay 隐私政策</h1>
      <p className="mt-2 text-sm text-vilsay-text-secondary">
        最后更新：2026-03-27 &middot; 生效日期：2026-03-27
      </p>

      <p className="mt-6 text-vilsay-text-secondary">
        Vilsay（以下简称"我们"）重视您的隐私。本政策说明 Vilsay macOS
        应用程序及相关在线服务在运行过程中如何收集、使用、存储和保护您的信息。使用本产品即表示您同意本政策的内容。
      </p>

      {/* 1 */}
      <h2 className="mt-10 text-xl font-semibold">1. 我们收集的信息</h2>

      <h3 className="mt-6 text-lg font-medium">1.1 账号信息</h3>
      <p className="mt-2 text-vilsay-text-secondary">
        当您注册 Vilsay 账号或通过第三方（Apple、Google、微信）登录时，我们会收集您的<strong>电子邮箱地址</strong>（或第三方平台提供的唯一标识符）。该信息仅用于身份验证与账号管理。
      </p>

      <h3 className="mt-6 text-lg font-medium">1.2 使用统计</h3>
      <p className="mt-2 text-vilsay-text-secondary">
        我们记录润色请求的<strong>次数、时长</strong>及调用时间戳，用于免费配额计算和服务质量监控。这些数据与您的账号关联，但不包含语音或文本内容本身。
      </p>

      <h3 className="mt-6 text-lg font-medium">1.3 设备与崩溃信息</h3>
      <p className="mt-2 text-vilsay-text-secondary">
        我们可能通过 Apple 提供的框架收集匿名崩溃日志和基础设备信息（操作系统版本、设备型号），以改进应用稳定性。
      </p>

      {/* 2 */}
      <h2 className="mt-10 text-xl font-semibold">2. 我们不收集的信息</h2>
      <ul className="mt-4 list-disc space-y-2 pl-5 text-vilsay-text-secondary">
        <li>
          <strong>录音音频文件</strong> —
          语音录制和本地语音识别（Whisper）完全在您的设备上完成，音频不会上传到我们的服务器。
        </li>
        <li>
          <strong>识别后的原始文本</strong> —
          当您使用 Vilsay 提供的云端润色服务（Pro）时，文本会经由我们的代理服务器转发至阿里云 DashScope
          进行 AI 处理，但我们不持久化存储该文本内容。
        </li>
        <li>
          <strong>剪贴板内容</strong> — 我们不读取或存储您的系统剪贴板。
        </li>
        <li>
          <strong>键盘输入</strong> —
          热键监听仅捕获特定功能键（Fn/🌐、右 Option）的按下与松开事件，不记录任何字符输入。
        </li>
      </ul>

      {/* 3 */}
      <h2 className="mt-10 text-xl font-semibold">3. 本地数据</h2>
      <p className="mt-4 text-vilsay-text-secondary">
        Vilsay 在您的设备上使用 SQLite
        数据库存储以下本地数据：润色历史记录、洞察引擎（AI3）用户画像和个性化词典。这些数据不会同步到云端，您可以随时在设置中清除。
      </p>

      {/* 4 */}
      <h2 className="mt-10 text-xl font-semibold">4. 第三方服务</h2>
      <ul className="mt-4 list-disc space-y-2 pl-5 text-vilsay-text-secondary">
        <li>
          <strong>阿里云 DashScope</strong> —
          用于文本润色（Qwen 系列模型）和云端语音识别（Paraformer）。当您使用自备
          API Key 时，数据直接发送至 DashScope；使用 Pro
          服务时，数据经由 Vilsay 代理转发。请参阅{" "}
          <a
            href="https://help.aliyun.com/zh/model-studio/developer-reference/privacy-policy"
            target="_blank"
            rel="noopener noreferrer"
            className="underline"
          >
            阿里云隐私政策
          </a>
          。
        </li>
        <li>
          <strong>Apple Sign in / Google OAuth / 微信登录</strong> —
          仅用于身份验证，我们只获取您的邮箱或唯一标识符。
        </li>
        <li>
          <strong>WhisperKit</strong> —
          语音识别完全在本地运行，不涉及网络传输。
        </li>
      </ul>

      {/* 5 */}
      <h2 className="mt-10 text-xl font-semibold">5. 数据安全</h2>
      <p className="mt-4 text-vilsay-text-secondary">
        所有网络通信均通过 HTTPS/TLS 加密传输。账号密码使用 bcrypt
        单向哈希存储。访问令牌（JWT）存储在 macOS Keychain 中，受系统级安全保护。
      </p>

      {/* 6 */}
      <h2 className="mt-10 text-xl font-semibold">6. 数据保留与删除</h2>
      <p className="mt-4 text-vilsay-text-secondary">
        使用统计数据保留至当前计费周期结束后 90
        天。您可以通过联系我们申请删除账号及所有关联数据。本地数据可随时在应用设置中清除。
      </p>

      {/* 7 */}
      <h2 className="mt-10 text-xl font-semibold">7. 儿童隐私</h2>
      <p className="mt-4 text-vilsay-text-secondary">
        Vilsay 不面向 13 岁以下的儿童。我们不会故意收集儿童的个人信息。
      </p>

      {/* 8 */}
      <h2 className="mt-10 text-xl font-semibold">8. 政策更新</h2>
      <p className="mt-4 text-vilsay-text-secondary">
        我们可能不时更新本隐私政策。重大变更将通过应用内通知或网站公告告知您。继续使用本产品即表示您接受更新后的政策。
      </p>

      {/* 9 */}
      <h2 className="mt-10 text-xl font-semibold">9. 联系我们</h2>
      <p className="mt-4 text-vilsay-text-secondary">
        如果您对本隐私政策有任何疑问或需要行使您的数据权利，请通过以下方式联系我们：
      </p>
      <p className="mt-2 text-vilsay-text-secondary">
        邮箱：
        <a href="mailto:privacy@vilsay.com" className="underline">
          privacy@vilsay.com
        </a>
      </p>
    </main>
  );
}
