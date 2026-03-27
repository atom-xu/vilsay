"use client";
import { useState } from "react";

const scenarios = [
  {
    label: "工作汇报",
    input:  "这个项目呢就是，然后我们团队上周就是完成了主要的那个功能开发，然后就是这周在做测试，然后大概下周能上线吧。",
    output: "上周，团队完成了核心功能开发；本周进入测试阶段，预计下周上线。",
    app: "邮件 / 飞书",
  },
  {
    label: "即时通讯",
    input:  "好的好的，那个事情我知道了，然后我回头跟他们沟通一下，然后有结果了我跟你说。",
    output: "好的，我来跟进一下，有结果第一时间通知你。",
    app: "微信 / 钉钉",
  },
  {
    label: "会议纪要",
    input:  "然后关于那个预算问题，大家的意见就是说，先按原来的计划走，然后如果有变化的话再说。",
    output: "预算方面，会议决定维持原计划，如有变动另行沟通。",
    app: "Notion / 备忘录",
  },
  {
    label: "代码注释",
    input:  "这个函数就是，把用户输入的那个文本进行处理，然后返回一个清理过的字符串。",
    output: "处理用户输入文本，返回经过清洗的标准化字符串。",
    app: "VS Code / Xcode",
  },
];

export function ScenarioDemo() {
  const [active, setActive] = useState(0);
  const s = scenarios[active];

  return (
    <section className="bg-vilsay-light-base py-24">
      <div className="mx-auto max-w-5xl px-6">
        <div className="text-center mb-12">
          <h2 className="text-3xl font-bold tracking-tight text-vilsay-text-primary md:text-4xl">
            在你每天用的<span className="brand-text">任意场景</span>里
          </h2>
          <p className="mt-4 text-vilsay-text-secondary">
            口语转文字，Vilsay 自动去掉废话、理顺逻辑。
          </p>
        </div>

        {/* Tabs */}
        <div className="flex flex-wrap justify-center gap-2 mb-8">
          {scenarios.map((sc, i) => (
            <button
              key={sc.label}
              onClick={() => setActive(i)}
              className={`rounded-full px-5 py-2 text-sm font-medium transition-all ${
                active === i
                  ? "bg-vilsay-dark-base text-white shadow-md"
                  : "bg-vilsay-text-primary/5 text-vilsay-text-secondary hover:bg-vilsay-text-primary/10"
              }`}
            >
              {sc.label}
            </button>
          ))}
        </div>

        {/* Demo card */}
        <div className="rounded-2xl border border-vilsay-text-primary/8 bg-vilsay-light-card p-8 shadow-sm">
          <div className="grid gap-6 md:grid-cols-2">
            <div>
              <div className="mb-3 flex items-center gap-2 text-xs font-semibold uppercase tracking-wider text-vilsay-text-tertiary">
                <span className="h-2 w-2 rounded-full bg-vilsay-orange" /> 你说的
              </div>
              <p className="rounded-xl bg-vilsay-light-base p-4 text-sm text-vilsay-text-secondary leading-relaxed border border-dashed border-vilsay-text-primary/10">
                &ldquo;{s.input}&rdquo;
              </p>
            </div>
            <div>
              <div className="mb-3 flex items-center gap-2 text-xs font-semibold uppercase tracking-wider text-vilsay-text-tertiary">
                <span className="h-2 w-2 rounded-full bg-vilsay-purple" /> Vilsay 输出
              </div>
              <p className="rounded-xl bg-gradient-to-br from-vilsay-purple/5 to-vilsay-pink/5 p-4 text-sm text-vilsay-text-primary leading-relaxed border border-vilsay-purple/15 font-medium">
                {s.output}
              </p>
            </div>
          </div>
          <div className="mt-5 flex items-center gap-2 text-xs text-vilsay-text-tertiary">
            <svg className="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2" />
            </svg>
            直接注入：{s.app}
          </div>
        </div>
      </div>
    </section>
  );
}
