const features = [
  {
    icon: "⚡",
    title: "< 1.5 秒全程响应",
    desc: "从说完最后一个字，到文字出现在光标位置，端到端延迟不超过 1.5 秒。",
    accent: "from-vilsay-orange/10 to-vilsay-pink/5",
    iconBg: "bg-vilsay-orange/15",
  },
  {
    icon: "✨",
    title: "AI3 智能润色",
    desc: "自动纠正识别错误、理顺表达逻辑、补全标点——输出即可直接发送。",
    accent: "from-vilsay-pink/10 to-vilsay-purple/5",
    iconBg: "bg-vilsay-pink/15",
  },
  {
    icon: "🧠",
    title: "洞察引擎",
    desc: "洞察引擎在后台学习你的口头禅、专业术语和表达风格，悄悄提升每次润色质量。",
    accent: "from-vilsay-purple/10 to-vilsay-indigo/5",
    iconBg: "bg-vilsay-purple/15",
  },
  {
    icon: "🔒",
    title: "音频本地处理",
    desc: "录音全程在你的 Mac 上处理，只有文字会传输到云端模型，声音从不上传。",
    accent: "from-vilsay-indigo/10 to-vilsay-purple/5",
    iconBg: "bg-vilsay-indigo/15",
  },
  {
    icon: "⌨️",
    title: "任意应用，光标在哪输在哪",
    desc: "微信、邮件、Notion、Terminal——只要有光标，Vilsay 就能输入，无需切换。",
    accent: "from-vilsay-orange/10 to-vilsay-pink/5",
    iconBg: "bg-vilsay-orange/15",
  },
  {
    icon: "📚",
    title: "自定义词典",
    desc: "一键收录专有名词、品牌术语，AI3 也会主动推荐你常说的词条。",
    accent: "from-vilsay-pink/10 to-vilsay-purple/5",
    iconBg: "bg-vilsay-pink/15",
  },
];

export function FeatureGrid() {
  return (
    <section id="features" className="bg-vilsay-light-base py-24">
      <div className="mx-auto max-w-6xl px-6">
        <div className="text-center mb-14">
          <h2 className="text-3xl font-bold tracking-tight text-vilsay-text-primary md:text-4xl">
            语音输入，<span className="brand-text">重新定义</span>
          </h2>
          <p className="mt-4 text-vilsay-text-secondary max-w-xl mx-auto">
            不是普通的听写工具——Vilsay 是一个懂你的语言助手。
          </p>
        </div>
        <div className="grid gap-5 sm:grid-cols-2 lg:grid-cols-3">
          {features.map((f) => (
            <div
              key={f.title}
              className={`rounded-2xl bg-gradient-to-br ${f.accent} border border-vilsay-text-primary/5 p-6 hover:border-vilsay-text-primary/10 transition-colors`}
            >
              <div className={`inline-flex items-center justify-center w-11 h-11 rounded-xl ${f.iconBg} text-2xl mb-4`}>
                {f.icon}
              </div>
              <h3 className="font-semibold text-vilsay-text-primary mb-2">{f.title}</h3>
              <p className="text-sm text-vilsay-text-secondary leading-relaxed">{f.desc}</p>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}
