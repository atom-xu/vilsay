import Link from "next/link";
import { UsageChart } from "./UsageChart";
import { mockUsage } from "@/lib/api";

export default function DashboardPage() {
  const data = mockUsage();

  return (
    <main className="mx-auto max-w-3xl px-4 py-16">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-bold">我的账号</h1>
        <button
          type="button"
          className="text-sm text-vilsay-text-secondary"
          disabled
        >
          登出（对接后端后启用）
        </button>
      </div>
      <p className="mt-4 rounded-lg bg-amber-50 p-4 text-sm text-amber-900">
        网页端登录需独立 OAuth / Session；当前为占位面板，数据为 mock。
      </p>

      <section className="mt-10">
        <h2 className="font-semibold">本月使用量</h2>
        <div className="mt-4 rounded-xl border border-gray-200 bg-white p-6">
          <p className="text-lg">
            已用 {data.used} / {data.quota} 次
          </p>
          <div className="mt-2 h-3 w-full overflow-hidden rounded-full bg-gray-100">
            <div
              className="h-full bg-vilsay-accent"
              style={{ width: `${Math.min(100, (data.used / data.quota) * 100)}%` }}
            />
          </div>
          <p className="mt-2 text-sm text-vilsay-text-secondary">
            重置日期：{data.resetDate}
          </p>
        </div>
      </section>

      <section className="mt-10">
        <h2 className="font-semibold">近 30 天趋势</h2>
        <div className="mt-4 h-64 rounded-xl border border-gray-200 bg-white p-4">
          <UsageChart data={data.history} />
        </div>
      </section>

      <section className="mt-10">
        <h2 className="font-semibold">订阅</h2>
        <p className="mt-2 text-vilsay-text-secondary">当前：Free（mock）</p>
        <Link
          href="/pricing"
          className="mt-4 inline-block rounded-xl bg-vilsay-accent px-6 py-2 font-medium text-white"
        >
          升级到 Pro
        </Link>
      </section>
    </main>
  );
}
