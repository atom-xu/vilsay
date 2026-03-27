import { WaveformLogo } from "@/components/WaveformLogo";

export function Hero() {
  return (
    <section className="relative overflow-hidden bg-vilsay-dark-base bg-hero-noise">
      <div className="mx-auto max-w-6xl px-6 py-24 md:py-32 text-center">

        {/* Badge */}
        <div className="inline-flex items-center gap-2 rounded-full border border-vilsay-orange/30 bg-vilsay-orange/10 px-4 py-1.5 text-xs font-medium text-vilsay-orange mb-8">
          <span className="relative flex h-1.5 w-1.5">
            <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-vilsay-orange opacity-75"></span>
            <span className="relative inline-flex rounded-full h-1.5 w-1.5 bg-vilsay-orange"></span>
          </span>
          仅限 macOS 14+（Sonoma）
        </div>

        {/* Headline */}
        <h1 className="animate-fade-up text-5xl font-extrabold leading-tight tracking-tight text-vilsay-text-inverse md:text-7xl">
          说话，比打字更快
          <br />
          <span className="brand-text">而且越用越懂你</span>
        </h1>

        {/* Subheadline */}
        <p className="animate-fade-up-d1 mx-auto mt-6 max-w-xl text-lg text-vilsay-text-inv-sec md:text-xl">
          按住 <kbd className="rounded bg-vilsay-dark-elevated px-2 py-0.5 font-mono text-sm text-vilsay-orange">Fn</kbd> 说话，松开即得流畅文字——
          自动纠错、润色、适配你的表达风格。
        </p>

        {/* CTAs */}
        <div className="animate-fade-up-d2 mt-10 flex flex-wrap justify-center gap-4">
          <a
            id="download"
            href="/#download"
            className="rounded-full bg-brand-gradient px-8 py-3.5 font-semibold text-white shadow-xl hover:opacity-90 transition-opacity"
          >
            免费下载 for macOS
          </a>
          <a
            href="/docs"
            className="rounded-full border border-white/10 bg-white/5 px-8 py-3.5 font-semibold text-vilsay-text-inverse hover:bg-white/10 transition-colors"
          >
            查看文档 →
          </a>
        </div>

        {/* Stats */}
        <div className="animate-fade-up-d3 mt-12 flex flex-wrap justify-center gap-8 text-sm text-vilsay-text-inv-sec">
          {[
            ["< 1.5s", "全程延迟"],
            ["音频本地处理", "录音不上传"],
            ["任意应用", "光标在哪输在哪"],
          ].map(([val, label]) => (
            <div key={label} className="text-center">
              <div className="text-base font-semibold text-vilsay-text-inverse">{val}</div>
              <div className="text-xs mt-0.5">{label}</div>
            </div>
          ))}
        </div>

        {/* App mockup */}
        <div className="animate-fade-up-d3 mx-auto mt-16 max-w-3xl">
          <AppMockup />
        </div>
      </div>
    </section>
  );
}

function AppMockup() {
  return (
    <div className="rounded-2xl border border-white/10 bg-vilsay-dark-card shadow-2xl shadow-black/60 overflow-hidden text-left">
      {/* Title bar */}
      <div className="flex items-center gap-2 bg-vilsay-dark-elevated px-4 py-3 border-b border-white/5">
        <span className="h-3 w-3 rounded-full bg-red-400/80" />
        <span className="h-3 w-3 rounded-full bg-yellow-400/80" />
        <span className="h-3 w-3 rounded-full bg-green-400/80" />
        <div className="mx-auto flex items-center gap-2 text-xs text-white/30">
          <WaveformLogo size={14} />
          Vilsay
        </div>
      </div>

      {/* Window body */}
      <div className="flex h-56 md:h-72">
        {/* Sidebar */}
        <div className="w-40 border-r border-white/5 bg-vilsay-dark-base/60 p-3 flex flex-col gap-1 shrink-0">
          <div className="flex items-center gap-2 rounded-lg bg-white/5 px-2.5 py-1.5 text-xs font-medium text-vilsay-text-inverse">
            <span>🏠</span> 首页
          </div>
          {["历史记录","词典","设置"].map(t => (
            <div key={t} className="flex items-center gap-2 px-2.5 py-1.5 text-xs text-white/25">
              <span>·</span> {t}
            </div>
          ))}
        </div>

        {/* Main content */}
        <div className="flex-1 p-5 relative flex flex-col gap-3">
          {/* Floating recording bar */}
          <div className="absolute top-4 left-1/2 -translate-x-1/2 flex items-center gap-3 rounded-full border border-vilsay-orange/25 bg-[#1c130d] px-4 py-2 shadow-lg shadow-black/40 z-10">
            <span className="relative flex h-2 w-2">
              <span className="animate-ping absolute h-full w-full rounded-full bg-vilsay-orange opacity-60" />
              <span className="relative h-2 w-2 rounded-full bg-vilsay-orange" />
            </span>
            <span className="font-mono text-[9px] font-semibold tracking-widest text-vilsay-orange/80">VILSAY</span>
            {/* Animated wave bars */}
            <div className="flex items-center gap-0.5" style={{height:16}}>
              {[
                {color:"#fb923c", cls:"animate-bar1", base:8},
                {color:"#f472b6", cls:"animate-bar2", base:14},
                {color:"#f472b6", cls:"animate-bar3", base:11},
                {color:"#c084fc", cls:"animate-bar4", base:9},
                {color:"#c084fc", cls:"animate-bar2", base:13},
                {color:"#818cf8", cls:"animate-bar1", base:7},
                {color:"#818cf8", cls:"animate-bar3", base:10},
                {color:"#c084fc", cls:"animate-bar4", base:6},
              ].map((b,i) => (
                <div
                  key={i}
                  className={`rounded-sm ${b.cls}`}
                  style={{width:2.5, height:b.base, background:b.color, transformOrigin:"center"}}
                />
              ))}
            </div>
            <span className="text-white/20 text-xs">✕</span>
          </div>

          {/* Text content preview */}
          <div className="mt-14 space-y-2">
            <div className="h-2 rounded-full bg-white/5 w-full" />
            <div className="h-2 rounded-full bg-white/5 w-5/6" />
            <div className="flex items-center gap-1">
              <div className="h-2 rounded-full bg-vilsay-orange/20 w-2/5" />
              <div className="h-3.5 w-px bg-vilsay-orange animate-pulse" />
            </div>
          </div>

          {/* Completion toast */}
          <div className="mt-4 self-start flex items-center gap-2 rounded-full border border-green-500/20 bg-green-500/5 px-3 py-1.5 text-xs text-green-400/80">
            <span>✓</span>
            <span>好的，我来跟进一下这个需求，明天早上给你回复…</span>
          </div>
        </div>
      </div>
    </div>
  );
}
