export default function PrivacyPage() {
  return (
    <main className="mx-auto max-w-3xl px-4 py-16">
      <h1 className="text-3xl font-bold">Vilsay 隐私政策</h1>
      <p className="mt-2 text-sm text-vilsay-text-secondary">最后更新：2026-03-25（开发占位，上架前须法务审核）</p>

      <h2 className="mt-10 text-xl font-semibold">我们收集的信息</h2>
      <ul className="mt-4 list-disc space-y-2 pl-5 text-vilsay-text-secondary">
        <li>账号信息：邮箱地址（注册时）</li>
        <li>使用数据：润色次数、使用频率（统计）</li>
        <li>语音数据：仅在设备本地处理，从不上传录音文件</li>
      </ul>

      <h2 className="mt-10 text-xl font-semibold">我们不收集的信息</h2>
      <ul className="mt-4 list-disc space-y-2 pl-5 text-vilsay-text-secondary">
        <li>录音音频文件</li>
        <li>剪贴板内容</li>
      </ul>

      <h2 className="mt-10 text-xl font-semibold">AI3 个性化数据</h2>
      <p className="mt-4 text-vilsay-text-secondary">
        用户画像数据存储在设备本地 SQLite；不同步到云端；可在设置中清除。
      </p>

      <h2 className="mt-10 text-xl font-semibold">第三方服务</h2>
      <p className="mt-4 text-vilsay-text-secondary">
        DashScope（阿里云）：仅传输文字进行润色；Apple / Google OAuth 仅用于身份验证。
      </p>

      <h2 className="mt-10 text-xl font-semibold">联系我们</h2>
      <p className="mt-4 text-vilsay-text-secondary">privacy@vilsay.com</p>
    </main>
  );
}
