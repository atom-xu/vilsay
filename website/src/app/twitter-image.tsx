import { ImageResponse } from "next/og";

export const runtime = "edge";
export const alt = "Vilsay - macOS 语音润色应用";
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";

export default function TwitterImage() {
  return new ImageResponse(
    (
      <div
        style={{
          height: "100%",
          width: "100%",
          display: "flex",
          flexDirection: "column",
          alignItems: "flex-start",
          justifyContent: "center",
          background:
            "linear-gradient(135deg, #121015 0%, #1e1620 45%, #2a1c2e 100%)",
          padding: 72,
        }}
      >
        <div
          style={{
            display: "flex",
            alignItems: "center",
            gap: 20,
          }}
        >
          <div
            style={{
              width: 64,
              height: 64,
              borderRadius: 16,
              background:
                "linear-gradient(135deg, #fb923c, #f472b6, #c084fc)",
            }}
          />
          <span
            style={{
              fontSize: 56,
              fontWeight: 700,
              color: "#f4f4f5",
              letterSpacing: "-0.03em",
            }}
          >
            Vilsay
          </span>
        </div>
        <p
          style={{
            marginTop: 28,
            fontSize: 32,
            color: "rgba(244,244,245,0.88)",
            maxWidth: 920,
            lineHeight: 1.3,
          }}
        >
          macOS 原生语音润色 · 按住说话，松开即得流畅文字
        </p>
      </div>
    ),
    { ...size },
  );
}
