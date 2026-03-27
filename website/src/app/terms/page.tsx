export default function TermsPage() {
  return (
    <main className="mx-auto max-w-3xl px-4 py-16">
      <h1 className="text-3xl font-bold">Vilsay 服务条款</h1>
      <p className="mt-2 text-sm text-vilsay-text-secondary">最后更新：2026-03-25（开发占位，上架前须法务审核）</p>

      <h2 className="mt-10 text-xl font-semibold">服务说明</h2>
      <p className="mt-4 text-vilsay-text-secondary">
        Vilsay 是 macOS 语音润色工具，提供语音识别、AI 润色与文字注入等功能。
      </p>

      <h2 className="mt-10 text-xl font-semibold">使用限制</h2>
      <ul className="mt-4 list-disc space-y-2 pl-5 text-vilsay-text-secondary">
        <li>免费版每日使用次数有限</li>
        <li>禁止滥用 API 接口</li>
        <li>禁止逆向工程</li>
      </ul>

      <h2 className="mt-10 text-xl font-semibold">付费服务</h2>
      <p className="mt-4 text-vilsay-text-secondary">
        Pro 订阅按月计费；可随时取消，当月仍可使用至到期。
      </p>

      <h2 className="mt-10 text-xl font-semibold">免责声明</h2>
      <p className="mt-4 text-vilsay-text-secondary">
        AI 润色结果仅供参考，不保证 100% 准确。
      </p>
    </main>
  );
}
