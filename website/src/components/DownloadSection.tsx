import { WaveformLogo } from "@/components/WaveformLogo";

export function DownloadSection() {
  return (
    <section id="download" className="bg-vilsay-dark-base py-24">
      <div className="mx-auto max-w-3xl px-6 text-center">
        <div className="inline-flex items-center justify-center w-16 h-16 rounded-2xl bg-vilsay-dark-card border border-white/10 mb-6">
          <WaveformLogo size={36} />
        </div>
        <h2 className="text-3xl font-bold text-vilsay-text-inverse md:text-4xl mb-4">
          现在就开始说话
        </h2>
        <p className="text-vilsay-text-inv-sec mb-10 max-w-md mx-auto">
          免费下载，安装后 30 秒即可完成引导。每天节省大量打字时间。
        </p>
        <div className="flex flex-wrap justify-center gap-4">
          <a
            href="/#"
            className="inline-flex items-center gap-3 rounded-full bg-brand-gradient px-8 py-4 font-semibold text-white shadow-2xl shadow-vilsay-purple/20 hover:opacity-90 transition-opacity"
          >
            <svg className="w-5 h-5" viewBox="0 0 24 24" fill="currentColor">
              <path d="M18.71 19.5C17.88 20.74 17 21.95 15.66 21.97C14.32 22 13.89 21.18 12.37 21.18C10.84 21.18 10.37 21.95 9.1 22C7.78 22.05 6.8 20.68 5.96 19.47C4.25 17 2.94 12.45 4.7 9.39C5.57 7.87 7.13 6.91 8.82 6.88C10.1 6.86 11.32 7.75 12.11 7.75C12.89 7.75 14.37 6.68 15.92 6.84C16.57 6.87 18.39 7.1 19.56 8.82C19.47 8.88 17.39 10.1 17.41 12.63C17.44 15.65 20.06 16.66 20.09 16.67C20.06 16.74 19.67 18.11 18.71 19.5ZM13 3.5C13.73 2.67 14.94 2.04 15.94 2C16.07 3.17 15.6 4.35 14.9 5.19C14.21 6.04 13.07 6.7 11.95 6.61C11.8 5.46 12.36 4.26 13 3.5Z"/>
            </svg>
            下载 for macOS
          </a>
        </div>
        <p className="mt-6 text-xs text-vilsay-text-inv-sec">
          要求 macOS 14（Sonoma）及以上 · Apple Silicon 和 Intel 均支持
        </p>
      </div>
    </section>
  );
}
