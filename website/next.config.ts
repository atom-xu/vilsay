import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  reactStrictMode: true,
  output: "export",
  distDir: 'dist',
  trailingSlash: true,
  images: { unoptimized: true },
};

export default nextConfig;
