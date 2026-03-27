import Link from "next/link";
import { WaveformLogo } from "@/components/WaveformLogo";

export function Navbar() {
  return (
    <header className="sticky top-0 z-50 border-b border-white/10 bg-vilsay-dark-base/90 backdrop-blur-md">
      <div className="mx-auto flex max-w-6xl items-center justify-between px-6 py-4">
        <Link href="/" className="flex items-center gap-2.5">
          <WaveformLogo size={24} />
          <span className="text-lg font-bold tracking-tight text-vilsay-text-inverse">
            Vilsay
          </span>
        </Link>

        <nav className="hidden items-center gap-7 text-sm font-medium text-vilsay-text-inv-sec sm:flex">
          <Link href="/#features" className="hover:text-vilsay-text-inverse transition-colors">功能</Link>
          <Link href="/#how"      className="hover:text-vilsay-text-inverse transition-colors">使用方式</Link>
          <Link href="/pricing"   className="hover:text-vilsay-text-inverse transition-colors">定价</Link>
          <Link href="/docs"      className="hover:text-vilsay-text-inverse transition-colors">文档</Link>
        </nav>

        <a
          href="/#download"
          className="rounded-full bg-brand-gradient px-5 py-2 text-sm font-semibold text-white shadow-lg hover:opacity-90 transition-opacity"
        >
          免费下载
        </a>
      </div>
    </header>
  );
}
