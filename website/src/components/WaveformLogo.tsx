export function WaveformLogo({ size = 32, height }: { size?: number; height?: number }) {
  const finalSize = height || size;
  // 左侧5根音波柱高度
  const leftBars = [
    { h: 18, color: "#fb923c" },   // 橙
    { h: 24, color: "#f472b6" },   // 粉
    { h: 30, color: "#c084fc" },   // 紫
    { h: 20, color: "#a855f7" },   // 紫
    { h: 26, color: "#8b5cf6" },   // 紫
  ];
  
  // 右侧3根横向文字线
  const rightLines = [
    { w: 28, y: 8 },
    { w: 36, y: 16 },
    { w: 24, y: 24 },
  ];

  const barWidth = 4;
  const gap = 3;
  const leftWidth = leftBars.length * (barWidth + gap) - gap;
  const dividerX = leftWidth + 6;
  const totalWidth = dividerX + 44;
  const scale = finalSize / 32;

  return (
    <svg
      width={totalWidth * scale}
      height={32 * scale}
      viewBox={`0 0 ${totalWidth} 32`}
      fill="none"
      aria-hidden="true"
    >
      {/* 左侧音波柱 */}
      {leftBars.map((bar, i) => (
        <rect
          key={`left-${i}`}
          x={i * (barWidth + gap)}
          y={(32 - bar.h) / 2}
          width={barWidth}
          height={bar.h}
          rx={2}
          fill={bar.color}
        />
      ))}
      
      {/* 分隔线 - 半透明紫 */}
      <line
        x1={dividerX - 2}
        y1={4}
        x2={dividerX - 2}
        y2={28}
        stroke="#c084fc"
        strokeWidth={1}
        opacity={0.4}
      />
      
      {/* 右侧横向文字线 - 粉紫色 */}
      {rightLines.map((line, i) => (
        <rect
          key={`right-${i}`}
          x={dividerX + 4}
          y={line.y - 2}
          width={line.w}
          height={4}
          rx={2}
          fill="#e879f9"
          opacity={0.9 - i * 0.15}
        />
      ))}
    </svg>
  );
}
