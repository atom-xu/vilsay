import { PricingCard } from "@/components/PricingCard";

const freeItems = [
  { ok: true,  text: "每日 20 次语音润色" },
  { ok: true,  text: "本地 WhisperKit 离线识别" },
  { ok: true,  text: "基础 AI 润色" },
  { ok: true,  text: "自定义词典（20 条）" },
  { ok: false, text: "云端高速 ASR" },
  { ok: false, text: "AI3 个性化学习" },
  { ok: false, text: "无限次使用" },
];

const proItems = [
  { ok: true, text: "无限次语音润色" },
  { ok: true, text: "云端高速 ASR（更准确）" },
  { ok: true, text: "AI3 个性化学习" },
  { ok: true, text: "自定义词典（无限）" },
  { ok: true, text: "本地 WhisperKit 离线备用" },
  { ok: true, text: "优先技术支持" },
];

export default function PricingPage() {
  return (
    <main className="bg-vilsay-light-base min-h-screen">
      <div className="mx-auto max-w-5xl px-6 py-20">
        <div className="text-center mb-14">
          <h1 className="text-4xl font-extrabold tracking-tight text-vilsay-text-primary">
            简单透明的<span className="brand-text">定价</span>
          </h1>
          <p className="mt-4 text-vilsay-text-secondary max-w-md mx-auto">
            免费开始，按需升级。也支持自带 API Key（BYOK）。
          </p>
        </div>

        <div className="grid gap-6 md:grid-cols-2 items-start">
          <PricingCard
            name="Free"
            price="¥0"
            period="/月"
            items={freeItems}
            cta="立即下载"
            href="/#download"
          />
          <PricingCard
            name="Pro"
            price="¥28"
            period="/月"
            sub="按年付 ¥268/年，省 68 元"
            highlight
            items={proItems}
            cta="升级 Pro"
            href="/#download"
          />
        </div>

        <div className="mt-12 rounded-2xl border border-vilsay-text-primary/8 bg-vilsay-light-card p-7">
          <h3 className="font-semibold text-vilsay-text-primary mb-2">自带 API Key（BYOK）</h3>
          <p className="text-sm text-vilsay-text-secondary leading-relaxed">
            已有阿里云 DashScope Key？在 Vilsay 设置中填入即可享受 Pro 级云端 ASR 与润色能力，
            按供应商实际用量计费，适合用量较大的专业用户。
          </p>
        </div>
      </div>
    </main>
  );
}
