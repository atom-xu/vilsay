import Link from "next/link";

type Props = { href?: string; className?: string; children?: React.ReactNode };

export function DownloadMacButton({
  href = "/#download",
  className = "",
  children = "免费下载",
}: Props) {
  return (
    <Link
      href={href}
      className={`rounded-full bg-brand-gradient px-5 py-2 text-sm font-semibold text-white shadow-lg hover:opacity-90 transition-opacity ${className}`}
    >
      {children}
    </Link>
  );
}
