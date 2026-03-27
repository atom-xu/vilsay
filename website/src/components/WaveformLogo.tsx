export function WaveformLogo({ size = 22 }: { size?: number }) {
  const bars = [
    { color: "#fb923c", h: 10 },
    { color: "#f472b6", h: 17 },
    { color: "#c084fc", h: 13 },
    { color: "#818cf8", h: 7  },
  ];
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 22 22"
      fill="none"
      aria-hidden="true"
    >
      {bars.map((b, i) => (
        <rect
          key={i}
          x={i * 5 + 1}
          y={(22 - b.h) / 2}
          width={3.5}
          height={b.h}
          rx={1.75}
          fill={b.color}
        />
      ))}
    </svg>
  );
}
