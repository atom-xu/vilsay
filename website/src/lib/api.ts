/** 与 `server/` FastAPI 的 `APIRouter(prefix="/api/v1")` 对齐。环境变量可只写 origin，会自动补 `/api/v1`。 */
function apiV1Base(): string {
  const raw = (
    process.env.NEXT_PUBLIC_API_BASE || "https://api.vilsay.com"
  ).replace(/\/$/, "");
  if (raw.endsWith("/api/v1")) return raw;
  return `${raw}/api/v1`;
}

const API_BASE = apiV1Base();

export async function getUsage(token: string) {
  const res = await fetch(`${API_BASE}/usage/current`, {
    headers: { Authorization: `Bearer ${token}` },
    cache: "no-store",
  });
  if (!res.ok) throw new Error("usage fetch failed");
  const j = (await res.json()) as {
    used: number;
    quota: number;
    year_month: string;
  };
  return {
    used: j.used,
    quota: j.quota,
    resetDate: j.year_month,
    history: [] as { date: string; count: number }[],
  };
}

export async function getProfile(token: string) {
  const res = await fetch(`${API_BASE}/auth/profile`, {
    headers: { Authorization: `Bearer ${token}` },
    cache: "no-store",
  });
  if (!res.ok) throw new Error("profile fetch failed");
  const j = (await res.json()) as { email: string };
  return {
    email: j.email,
    plan: "Free",
    createdAt: "",
  };
}

/** Mock 用量（后端未就绪时使用） */
export function mockUsage() {
  return {
    used: 156,
    quota: 500,
    resetDate: "2026-04-01",
    history: Array.from({ length: 30 }, (_, i) => ({
      date: `Day ${i + 1}`,
      count: Math.floor(3 + Math.random() * 8),
    })),
  };
}
