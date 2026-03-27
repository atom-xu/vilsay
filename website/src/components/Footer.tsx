import Link from "next/link";
import { WaveformLogo } from "@/components/WaveformLogo";

export function Footer() {
  return (
    <footer className="bg-vilsay-dark-base border-t border-white/5">
      <div className="mx-auto max-w-6xl px-6 py-12">
        <div className="flex flex-col gap-8 sm:flex-row sm:items-start sm:justify-between">
          <div>
            <div className="flex items-center gap-2.5 mb-3">
              <WaveformLogo size={20} />
              <span className="font-bold text-vilsay-text-inverse">Vilsay</span>
            </div>
            <p className="text-sm text-vilsay-text-inv-sec max-w-xs leading-relaxed">
              macOS 原生语音润色应用。说话，比打字更快，而且越用越懂你。
            </p>
          </div>

          <div className="flex gap-12 text-sm">
            <div>
              <p className="font-medium text-vilsay-text-inverse mb-3">产品</p>
              <ul className="space-y-2 text-vilsay-text-inv-sec">
                <li><Link href="/#features" className="hover:text-vilsay-text-inverse transition-colors">功能</Link></li>
                <li><Link href="/pricing"   className="hover:text-vilsay-text-inverse transition-colors">定价</Link></li>
                <li><Link href="/docs"      className="hover:text-vilsay-text-inverse transition-colors">文档</Link></li>
              </ul>
            </div>
            <div>
              <p className="font-medium text-vilsay-text-inverse mb-3">法律</p>
              <ul className="space-y-2 text-vilsay-text-inv-sec">
                <li><Link href="/privacy" className="hover:text-vilsay-text-inverse transition-colors">隐私政策</Link></li>
                <li><Link href="/terms"   className="hover:text-vilsay-text-inverse transition-colors">服务条款</Link></li>
              </ul>
            </div>
          </div>
        </div>

        <div className="mt-10 border-t border-white/5 pt-6 flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3 text-xs text-vilsay-text-inv-sec">
          <span>© {new Date().getFullYear()} Vilsay. 保留所有权利。</span>
          <span>仅限 macOS 14（Sonoma）及以上</span>
        </div>
      </div>
    </footer>
  );
}
