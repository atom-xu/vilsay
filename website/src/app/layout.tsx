import type { Metadata } from "next";
import { Footer } from "@/components/Footer";
import { Navbar } from "@/components/Navbar";
import "./globals.css";

export const metadata: Metadata = {
  title: "Vilsay · 说话，比打字更快",
  description: "macOS 原生语音润色应用。按住 Fn 说话，AI 自动纠错润色，越用越懂你。",
  openGraph: {
    title: "Vilsay · 说话，比打字更快",
    description: "macOS 原生语音润色。按住说话，松开即得流畅文字。",
    url: "https://vilsay.com",
    siteName: "Vilsay",
    locale: "zh_CN",
    type: "website",
  },
  twitter: {
    card: "summary_large_image",
    title: "Vilsay · 说话，比打字更快",
    description: "macOS 原生语音润色，AI 纠错 + 个性化学习",
  },
  robots: { index: true, follow: true },
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="zh-CN">
      <body className="min-h-screen">
        <Navbar />
        {children}
        <Footer />
      </body>
    </html>
  );
}
