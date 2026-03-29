export function VilsayLogo({ size = 36 }: { size?: number }) {
  const scale = size / 128;
  return (
    <svg
      width={128 * scale}
      height={128 * scale}
      viewBox="0 0 128 128"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
    >
      <style>{
        `
        @keyframes blink { 0%,49%{opacity:.9} 50%,100%{opacity:0} }
        @keyframes wb_nav_0 { 0%,100%{transform:scaleY(1)} 50%{transform:scaleY(1.3)} }
        @keyframes wb_nav_1 { 0%,100%{transform:scaleY(1)} 50%{transform:scaleY(0.65)} }
        @keyframes wb_nav_2 { 0%,100%{transform:scaleY(1)} 50%{transform:scaleY(1.45)} }
        @keyframes wb_nav_3 { 0%,100%{transform:scaleY(1)} 50%{transform:scaleY(0.8)} }
        `
      }</style>
      <defs>
        <linearGradient id="bars_nav" x1="0" y1="64" x2="73" y2="64" gradientUnits="userSpaceOnUse">
          <stop offset="0%" stopColor="#fb923c"/>
          <stop offset="50%" stopColor="#f472b6"/>
          <stop offset="100%" stopColor="#c084fc"/>
        </linearGradient>
        <linearGradient id="fade_nav" x1="83" y1="37" x2="118" y2="91" gradientUnits="userSpaceOnUse">
          <stop offset="0%" stopColor="#c084fc" stopOpacity="0.65"/>
          <stop offset="100%" stopColor="#c084fc" stopOpacity="0.06"/>
        </linearGradient>
      </defs>
      
      {/* 4根动态音波柱 */}
      <rect x="15" y="40" width="9" height="48" rx="4.7" fill="url(#bars_nav)" 
        style={{transformOrigin:"19.5px 64px", animation:"wb_nav_0 1.4s ease-in-out 0s infinite alternate"}}/>
      <rect x="27" y="29" width="9" height="69" rx="4.7" fill="url(#bars_nav)" opacity="0.9"
        style={{transformOrigin:"31.5px 63.5px", animation:"wb_nav_1 1s ease-in-out 0.15s infinite alternate"}}/>
      <rect x="39" y="37" width="9" height="53" rx="4.7" fill="url(#bars_nav)" opacity="0.75"
        style={{transformOrigin:"43.5px 63.5px", animation:"wb_nav_2 1.6s ease-in-out 0.3s infinite alternate"}}/>
      <rect x="52" y="48" width="9" height="32" rx="4.7" fill="url(#bars_nav)" opacity="0.5"
        style={{transformOrigin:"56.5px 64px", animation:"wb_nav_3 1.2s ease-in-out 0.1s infinite alternate"}}/>
      
      {/* 分隔线 */}
      <line x1="76" y1="32" x2="76" y2="96" stroke="rgba(192,132,252,0.12)" strokeWidth="1"/>
      
      {/* 输入光标（闪烁） */}
      <rect x="80" y="51" width="4" height="27" rx="2" fill="#c084fc" opacity="0.9"
        style={{animation:"blink 1.1s step-end infinite"}}/>
      
      {/* 4根横向输出线 */}
      <rect x="89" y="52" width="27" height="4" rx="2" fill="url(#fade_nav)" opacity="0.65"/>
      <rect x="89" y="63" width="20" height="4" rx="2" fill="url(#fade_nav)" opacity="0.38"/>
      <rect x="89" y="73" width="24" height="4" rx="2" fill="url(#fade_nav)" opacity="0.2"/>
      <rect x="89" y="84" width="15" height="4" rx="2" fill="url(#fade_nav)" opacity="0.09"/>
      
      {/* 小圆点 */}
      <circle cx="29" cy="20" r="2" fill="white" opacity="0.35"
        style={{animation:"blink 2.4s ease-in-out infinite"}}/>
    </svg>
  );
}
