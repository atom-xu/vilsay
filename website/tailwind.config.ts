import type { Config } from "tailwindcss";

const config: Config = {
  content: ["./src/**/*.{js,ts,jsx,tsx,mdx}"],
  theme: {
    extend: {
      colors: {
        vilsay: {
          orange: "#fb923c",
          pink:   "#f472b6",
          purple: "#c084fc",
          indigo: "#818cf8",
          "dark-base":     "#0c0907",
          "dark-card":     "#1c130d",
          "dark-elevated": "#26190f",
          "light-base":    "#faf8f5",
          "light-card":    "#ffffff",
          text: {
            primary:   "#1a1210",
            secondary: "#6b5c52",
            tertiary:  "#9c8880",
            inverse:   "#f5f0eb",
            "inv-sec": "#9c8070",
          },
          ok:   "#4ade80",
          warn: "#fb923c",
          fail: "#f87171",
        },
      },
      backgroundImage: {
        "brand-gradient":   "linear-gradient(135deg,#fb923c,#f472b6,#c084fc)",
        "brand-gradient-h": "linear-gradient(90deg,#fb923c,#f472b6,#c084fc)",
        "hero-noise":
          "radial-gradient(ellipse 80% 50% at 15% 5%,rgba(251,146,60,.10) 0%,transparent 55%)," +
          "radial-gradient(ellipse 60% 60% at 85% 95%,rgba(192,132,252,.09) 0%,transparent 55%)",
      },
      animation: {
        "bar1":     "bar 1.4s ease-in-out infinite alternate",
        "bar2":     "bar 1.0s ease-in-out .15s infinite alternate",
        "bar3":     "bar 1.6s ease-in-out .3s  infinite alternate",
        "bar4":     "bar 1.2s ease-in-out .1s  infinite alternate",
        "fade-up":  "fadeUp .55s ease both",
        "fade-up-d1":"fadeUp .55s .10s ease both",
        "fade-up-d2":"fadeUp .55s .20s ease both",
        "fade-up-d3":"fadeUp .55s .30s ease both",
      },
      keyframes: {
        bar: {
          "0%":   { transform: "scaleY(.55)" },
          "100%": { transform: "scaleY(1.0)"  },
        },
        fadeUp: {
          "0%":   { opacity: "0", transform: "translateY(18px)" },
          "100%": { opacity: "1", transform: "translateY(0)"     },
        },
      },
    },
  },
  plugins: [],
};

export default config;
