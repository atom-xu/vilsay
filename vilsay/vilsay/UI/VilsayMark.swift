import SwiftUI

// ─────────────────────────────────────────
// MARK: - Shared gradient
// ─────────────────────────────────────────

private let brandGradient = LinearGradient(
    stops: [
        .init(color: Color(hex: "fb923c"), location: 0.0),
        .init(color: Color(hex: "f472b6"), location: 0.5),
        .init(color: Color(hex: "c084fc"), location: 1.0),
    ],
    startPoint: .leading,
    endPoint: .trailing
)

// ─────────────────────────────────────────
// MARK: - WaveformBars (shared shape logic)
// ─────────────────────────────────────────

/// Animated waveform bars. Scale controls overall size.
struct WaveformBars: View {
    let barWidth: CGFloat
    let spacing: CGFloat
    let heights: [CGFloat]        // relative heights, will be scaled
    let cornerRadius: CGFloat
    let showCursor: Bool

    @State private var phase = false

    // Each bar has its own animation timing
    private let durations: [Double] = [1.4, 1.0, 1.6, 1.2]
    private let delays:    [Double] = [0.0, 0.15, 0.3, 0.1]
    private let scales:    [CGFloat] = [1.3, 0.65, 1.45, 0.8]

    var body: some View {
        HStack(alignment: .center, spacing: spacing) {
            ForEach(0..<heights.count, id: \.self) { i in
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(brandGradient)
                    .frame(width: barWidth, height: heights[i])
                    .scaleEffect(y: phase ? scales[i] : 1.0, anchor: .center)
                    .animation(
                        .easeInOut(duration: durations[i])
                            .repeatForever(autoreverses: true)
                            .delay(delays[i]),
                        value: phase
                    )
                    .opacity(1.0 - Double(i) * 0.15)
            }

            if showCursor {
                CursorBar(width: barWidth * 0.7, height: heights.last ?? 12, cornerRadius: cornerRadius * 0.6)
            }
        }
        .onAppear { phase = true }
    }
}

// ─────────────────────────────────────────
// MARK: - Cursor bar (blinking)
// ─────────────────────────────────────────

private struct CursorBar: View {
    let width: CGFloat
    let height: CGFloat
    let cornerRadius: CGFloat

    @State private var visible = true

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color(hex: "c084fc"))
            .frame(width: width, height: height)
            .opacity(visible ? 0.85 : 0)
            .animation(.easeInOut(duration: 0.0).repeatForever(), value: visible)
            .onAppear {
                withAnimation(.linear(duration: 1.1).repeatForever()) {
                    visible.toggle()
                }
            }
    }
}

// ─────────────────────────────────────────
// MARK: - 1. Sidebar logo mark
//   Usage: replace Image("AppIcon") in sidebar header
// ─────────────────────────────────────────

struct VilsayMarkSidebar: View {
    var body: some View {
        WaveformBars(
            barWidth:     3,
            spacing:      3,
            heights:      [8, 14, 10, 5],
            cornerRadius: 1.5,
            showCursor:   false          // sidebar is too small for cursor
        )
        .frame(width: 22, height: 22)
    }
}

// ─────────────────────────────────────────
// MARK: - 2. Welcome card mark  (with soft glow)
//   Usage: replace Image("AppIcon") in welcome card header
// ─────────────────────────────────────────

struct VilsayMarkCard: View {
    var body: some View {
        WaveformBars(
            barWidth:     5.5,
            spacing:      5,
            heights:      [12, 20, 16, 12],
            cornerRadius: 2.75,
            showCursor:   false
        )
        .frame(width: 34, height: 34)
    }
}

// ─────────────────────────────────────────
// MARK: - Preview
// ─────────────────────────────────────────

#Preview {
    VStack(spacing: 40) {
        // Sidebar context
        HStack(spacing: 9) {
            VilsayMarkSidebar()
            Text("Vilsay")
                .font(.system(size: 15, weight: .semibold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(8)

        // Card context
        HStack(spacing: 14) {
            VilsayMarkCard()
            VStack(alignment: .leading, spacing: 3) {
                Text("晚上好")
                    .font(.system(size: 17, weight: .semibold))
                Text("按住快捷键开始语音输入，Vilsay 帮你润色。")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
        .padding(20)
        .background(Color.white)
        .cornerRadius(14)
        .shadow(color: .black.opacity(0.07), radius: 4)
    }
    .padding(32)
    .background(Color(hex: "f5f3f0"))
}

// ─────────────────────────────────────────
// MARK: - Color hex helper
// ─────────────────────────────────────────

extension Color {
    init(hex: String) {
        let h = hex.trimmingCharacters(in: .init(charactersIn: "#"))
        var val: UInt64 = 0
        Scanner(string: h).scanHexInt64(&val)
        self.init(
            red:   Double((val >> 16) & 0xff) / 255,
            green: Double((val >> 8)  & 0xff) / 255,
            blue:  Double( val        & 0xff) / 255
        )
    }
}
