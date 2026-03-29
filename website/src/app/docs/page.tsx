import { DocsFAQ } from "./DocsFAQ";

const sections = [
  { id: "start",   title: "快速开始" },
  { id: "hotkey",  title: "热键与录音" },
  { id: "polish",  title: "AI 润色" },
  { id: "insight",  title: "洞察引擎" },
  { id: "dict",    title: "自定义词典" },
  { id: "byok",    title: "自带 API Key" },
  { id: "privacy", title: "隐私与权限" },
  { id: "faq",     title: "常见问题" },
];

export default function DocsPage() {
  return (
    <main className="bg-vilsay-light-base min-h-screen">
      <div className="mx-auto flex max-w-6xl flex-col gap-12 px-6 py-16 lg:flex-row">
        {/* Sidebar nav */}
        <nav className="lg:w-52 lg:shrink-0">
          <p className="text-xs font-semibold uppercase tracking-wider text-vilsay-text-tertiary mb-4">目录</p>
          <ul className="space-y-1 text-sm">
            {sections.map((s) => (
              <li key={s.id}>
                <a
                  href={`#${s.id}`}
                  className="block rounded-lg px-3 py-2 text-vilsay-text-secondary hover:bg-vilsay-text-primary/5 hover:text-vilsay-text-primary transition-colors"
                >
                  {s.title}
                </a>
              </li>
            ))}
          </ul>
        </nav>

        {/* Content */}
        <article className="flex-1 max-w-none prose prose-gray">
          <h1 className="text-3xl font-extrabold text-vilsay-text-primary">文档</h1>

          <h2 id="start" className="mt-10 text-xl font-bold text-vilsay-text-primary">快速开始</h2>
          <ol className="mt-3 space-y-2 text-sm text-vilsay-text-secondary pl-5 list-decimal">
            <li>下载安装 Vilsay（要求 macOS 14+）</li>
            <li>启动后按引导完成权限授权（麦克风 + 辅助功能）</li>
            <li>将光标放在任意文本框</li>
            <li>按住 <code className="rounded bg-vilsay-text-primary/8 px-1.5 py-0.5 font-mono text-xs">Fn</code> 说话，松开后文字自动注入</li>
          </ol>

          <h2 id="hotkey" className="mt-10 text-xl font-bold text-vilsay-text-primary">热键与录音</h2>
          <ul className="mt-3 space-y-2 text-sm text-vilsay-text-secondary pl-5 list-disc">
            <li><strong>默认热键</strong>：<code className="rounded bg-vilsay-text-primary/8 px-1.5 py-0.5 font-mono text-xs">Fn</code> 长按录音，松开结束</li>
            <li><strong>自定义热键</strong>：设置 → 热键，可改为任意组合键</li>
            <li><strong>悬浮按钮</strong>：可拖动到屏幕任意位置，点按等同热键</li>
            <li><strong>取消录音</strong>：录音中按 <code className="rounded bg-vilsay-text-primary/8 px-1.5 py-0.5 font-mono text-xs">ESC</code> 或点击 ✕</li>
            <li><strong>Push-to-Talk</strong>：按住说、松开输出；支持切换为点击开关模式</li>
          </ul>

          <h2 id="polish" className="mt-10 text-xl font-bold text-vilsay-text-primary">AI 润色</h2>
          <ul className="mt-3 space-y-2 text-sm text-vilsay-text-secondary pl-5 list-disc">
            <li>自动纠正语音识别错误和同音字</li>
            <li>去除口头禅（"然后"、"就是"、"那个"）</li>
            <li>理顺表达逻辑，补全标点</li>
            <li>根据目标应用（邮件/聊天/文档）自动调整语气</li>
          </ul>

          <h2 id="insight" className="mt-10 text-xl font-bold text-vilsay-text-primary">洞察引擎</h2>
          <ul className="mt-3 space-y-2 text-sm text-vilsay-text-secondary pl-5 list-disc">
            <li>洞察引擎在后台分析你的语音模式，持续优化润色质量</li>
            <li>自动识别高频口头禅和专业术语</li>
            <li>学习数据仅存储在本地，不上传</li>
            <li>可在设置 → 数据中查看或清除学习记录</li>
          </ul>

          <h2 id="dict" className="mt-10 text-xl font-bold text-vilsay-text-primary">自定义词典</h2>
          <ul className="mt-3 space-y-2 text-sm text-vilsay-text-secondary pl-5 list-disc">
            <li>手动添加专有名词、品牌名、人名，确保准确识别</li>
            <li>洞察引擎会主动推荐词条，一键确认加入词典</li>
            <li>Free 版最多 20 条；Pro 版无限</li>
          </ul>

          <h2 id="byok" className="mt-10 text-xl font-bold text-vilsay-text-primary">自带 API Key（BYOK）</h2>
          <ul className="mt-3 space-y-2 text-sm text-vilsay-text-secondary pl-5 list-disc">
            <li>在设置 → API Key 中填入阿里云 DashScope Key</li>
            <li>填入后自动启用云端高速 ASR 与润色</li>
            <li>按 DashScope 实际用量计费，适合用量较大的用户</li>
          </ul>

          <h2 id="privacy" className="mt-10 text-xl font-bold text-vilsay-text-primary">隐私与权限</h2>
          <ul className="mt-3 space-y-2 text-sm text-vilsay-text-secondary pl-5 list-disc">
            <li><strong>麦克风权限</strong>：仅用于录制你主动触发的语音，不后台监听</li>
            <li><strong>辅助功能权限</strong>：仅用于将文字注入当前应用的光标位置，不读取屏幕内容</li>
            <li><strong>录音文件</strong>：音频仅在本地处理，不上传任何录音</li>
            <li><strong>文字传输</strong>：润色时仅将识别出的文字发送至云端模型</li>
          </ul>

          <h2 id="faq" className="mt-10 text-xl font-bold text-vilsay-text-primary">常见问题</h2>
          <DocsFAQ />
        </article>
      </div>
    </main>
  );
}
