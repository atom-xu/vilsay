import Link from "next/link";

type Item = { ok: boolean; text: string };
type Props = {
  name: string;
  price: string;
  period?: string;
  sub?: string;
  highlight?: boolean;
  items: Item[];
  cta: string;
  href: string;
};

export function PricingCard({ name, price, period, sub, highlight, items, cta, href }: Props) {
  return (
    <div className={`relative flex flex-col rounded-2xl p-8 ${
      highlight
        ? "bg-vilsay-dark-card border border-vilsay-purple/30 shadow-xl shadow-vilsay-purple/10"
        : "bg-vilsay-light-card border border-vilsay-text-primary/8"
    }`}>
      {highlight && (
        <span className="absolute -top-3 left-1/2 -translate-x-1/2 rounded-full bg-brand-gradient px-4 py-0.5 text-xs font-semibold text-white shadow">
          推荐
        </span>
      )}
      <div>
        <h3 className={`text-sm font-semibold uppercase tracking-wider ${highlight ? "text-vilsay-purple" : "text-vilsay-text-secondary"}`}>
          {name}
        </h3>
        <div className="mt-3 flex items-end gap-1">
          <span className={`text-4xl font-extrabold ${highlight ? "text-vilsay-text-inverse" : "text-vilsay-text-primary"}`}>
            {price}
          </span>
          {period && (
            <span className={`mb-1 text-sm ${highlight ? "text-vilsay-text-inv-sec" : "text-vilsay-text-secondary"}`}>
              {period}
            </span>
          )}
        </div>
        {sub && <p className={`mt-1 text-xs ${highlight ? "text-vilsay-text-inv-sec" : "text-vilsay-text-secondary"}`}>{sub}</p>}
      </div>

      <ul className="mt-7 flex-1 space-y-3">
        {items.map((it) => (
          <li key={it.text} className="flex gap-3 text-sm">
            <span className={it.ok ? "text-vilsay-ok" : (highlight ? "text-white/20" : "text-vilsay-text-primary/20")}>
              {it.ok ? "✓" : "✗"}
            </span>
            <span className={it.ok ? (highlight ? "text-vilsay-text-inverse" : "text-vilsay-text-primary") : (highlight ? "text-white/30" : "text-vilsay-text-tertiary")}>
              {it.text}
            </span>
          </li>
        ))}
      </ul>

      <Link
        href={href}
        className={`mt-8 block rounded-full py-3 text-center text-sm font-semibold transition-opacity ${
          highlight
            ? "bg-brand-gradient text-white hover:opacity-90"
            : "border border-vilsay-text-primary/15 text-vilsay-text-primary hover:bg-vilsay-text-primary/5"
        }`}
      >
        {cta}
      </Link>
    </div>
  );
}
