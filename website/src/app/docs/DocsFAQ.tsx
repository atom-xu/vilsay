"use client";

import { useState } from "react";

const faqs = [
  {
    q: "录音会上传到服务器吗？",
    a: "不会。音频仅在本地处理；润色仅传输文字到云端模型（如 DashScope）。",
  },
  {
    q: "支持哪些语言？",
    a: "目前以中文普通话为主；英文等以实际模型能力为准。",
  },
  {
    q: "Pro 和 BYOK 有什么区别？",
    a: "Pro 为订阅套餐；BYOK 为在设置中填入自有 API Key，按供应商计费。",
  },
  {
    q: "如何重置 AI 学习数据？",
    a: "在 App：设置 → 数据 → 清除 AI 学习数据。",
  },
  {
    q: "macOS 版本要求？",
    a: "macOS 14 (Sonoma) 及以上。",
  },
  {
    q: "辅助功能权限是否安全？",
    a: "仅用于向当前应用注入文字，不读取屏幕内容。",
  },
];

export function DocsFAQ() {
  const [open, setOpen] = useState<number | null>(0);

  return (
    <div className="not-prose mt-6 space-y-2">
      {faqs.map((item, i) => (
        <div key={item.q} className="rounded-lg border border-gray-200 bg-white">
          <button
            type="button"
            className="flex w-full items-center justify-between px-4 py-3 text-left font-medium text-vilsay-text-primary"
            onClick={() => setOpen(open === i ? null : i)}
          >
            {item.q}
            <span className="text-vilsay-text-tertiary">{open === i ? "−" : "+"}</span>
          </button>
          {open === i && (
            <p className="border-t border-gray-100 px-4 py-3 text-sm text-vilsay-text-secondary">
              {item.a}
            </p>
          )}
        </div>
      ))}
    </div>
  );
}
