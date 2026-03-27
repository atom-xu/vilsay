const steps = [
  {
    num: "01",
    title: "按住 Fn 开始说话",
    desc: "或按住悬浮按钮。录音在本地实时进行，你说的每个字都会被捕捉。",
    detail: "支持热键自定义 · Push-to-Talk 模式",
    color: "text-vilsay-orange",
    border: "border-vilsay-orange/30",
    bg: "bg-vilsay-orange/10",
  },
  {
    num: "02",
    title: "AI 识别 + 润色",
    desc: "松开按键，Vilsay 立刻将语音转为文字，纠错、润色、适配场景语气。",
    detail: "< 1.5 秒全程完成",
    color: "text-vilsay-pink",
    border: "border-vilsay-pink/30",
    bg: "bg-vilsay-pink/10",
  },
  {
    num: "03",
    title: "文字注入光标位置",
    desc: "流畅文字直接出现在你正在用的应用里，无需切换窗口，无需复制粘贴。",
    detail: "支持任意 macOS 应用",
    color: "text-vilsay-purple",
    border: "border-vilsay-purple/30",
    bg: "bg-vilsay-purple/10",
  },
];

export function HowItWorks() {
  return (
    <section id="how" className="bg-vilsay-dark-base bg-hero-noise py-24">
      <div className="mx-auto max-w-6xl px-6">
        <div className="text-center mb-14">
          <h2 className="text-3xl font-bold tracking-tight text-vilsay-text-inverse md:text-4xl">
            三步完成，<span className="brand-text">快到感觉不像在打字</span>
          </h2>
        </div>
        <div className="grid gap-6 md:grid-cols-3">
          {steps.map((s, i) => (
            <div key={i} className={`rounded-2xl border ${s.border} bg-vilsay-dark-card p-7`}>
              <div className={`text-4xl font-black mb-4 ${s.color} opacity-40`}>{s.num}</div>
              <h3 className={`text-lg font-semibold mb-2 ${s.color}`}>{s.title}</h3>
              <p className="text-sm text-vilsay-text-inv-sec leading-relaxed mb-4">{s.desc}</p>
              <span className={`inline-block rounded-full ${s.bg} ${s.color} px-3 py-1 text-xs font-medium`}>
                {s.detail}
              </span>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}
