import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  reactStrictMode: true,
  output: "export",   // 静态导出，兼容 Cloudflare Pages / 阿里云 OSS
  trailingSlash: true,
  images: { unoptimized: true },
};

export default nextConfig;
