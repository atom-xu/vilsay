//
//  UsageStatsView.swift
//  vilsay
//

import AppKit
import SwiftUI

/// W2-08：用量统计（登录后对接后端）。
struct UsageStatsView: View {
    @ObservedObject private var auth = AuthService.shared

    private let last7Days: [CGFloat] = [12, 20, 15, 30, 22, 18, 25]

    private var ratio: Double {
        guard auth.usageQuota > 0 else { return 0 }
        return min(1, Double(auth.usageUsed) / Double(auth.usageQuota))
    }

    private var quotaExceeded: Bool {
        auth.isAuthenticated && auth.isQuotaExceeded
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VSpacing.cardGap) {
                usageCard
                trendCard
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(VSpacing.pageInset)
        }
        .background(VSettingsBackground())
        .groupBoxStyle(VCardStyle())
    }

    // MARK: - 用量卡片

    private var usageCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: VSpacing.md) {
                // 用量进度
                VStack(alignment: .leading, spacing: VSpacing.sm) {
                    HStack {
                        Text(auth.isAuthenticated
                             ? "本月已使用"
                             : "请先在「设置」中登录")
                            .foregroundStyle(.secondary)
                        Spacer()
                        if auth.isAuthenticated {
                            Text("\(auth.usageUsed) / \(auth.usageQuota) 次")
                                .font(.subheadline.weight(.semibold))
                        }
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.secondary.opacity(0.15))
                            Capsule()
                                .fill(quotaExceeded ? VColor.warn : VColor.accent)
                                .frame(width: geo.size.width * ratio)
                                .animation(.easeInOut(duration: 0.5), value: ratio)
                        }
                    }
                    .frame(height: 8)

                    HStack {
                        Text("\(Int((min(ratio, 1) * 100).rounded()))%")
                            .font(.caption)
                            .foregroundStyle(quotaExceeded ? VColor.warn : .secondary)
                        Spacer()
                        if quotaExceeded {
                            Label("已超额", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(VColor.warn)
                        }
                    }
                }

                Divider()

                // 套餐行
                HStack {
                    Label("免费版", systemImage: "creditcard")
                        .foregroundStyle(.secondary)
                    Spacer()
                    if auth.isAuthenticated {
                        Button("升级 Pro") {
                            NSWorkspace.shared.open(WebsiteURL.pricing)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    } else {
                        Button("升级 Pro") {}
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(true)
                            .help("请先登录")
                    }
                }
            }
        } label: {
            Label("本月用量", systemImage: "chart.bar.fill")
        }
    }

    // MARK: - 趋势卡片

    private var trendCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: VSpacing.md) {
                UsageLineChart(values: last7Days)
                    .frame(height: 120)

                HStack {
                    ForEach(["一", "二", "三", "四", "五", "六", "日"], id: \.self) { d in
                        Text(d)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity)
                    }
                }

                Divider()

                Text("详细记录（Week 4 接入后端后展示）")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        } label: {
            Label("最近 7 天", systemImage: "calendar")
        }
    }
}

// MARK: - 折线图

struct UsageLineChart: View {
    let values: [CGFloat]

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let maxV = max(values.max() ?? 1, 1)
            let stepX = values.count > 1 ? w / CGFloat(values.count - 1) : w
            let plotH = h - 8

            ZStack(alignment: .topLeading) {
                // 填充区域
                Path { path in
                    guard let first = values.first else { return }
                    path.move(to: CGPoint(x: 0, y: plotH))
                    path.addLine(to: CGPoint(x: 0, y: plotH - (first / maxV) * plotH))
                    for i in 1..<values.count {
                        let x = CGFloat(i) * stepX
                        let y = plotH - (values[i] / maxV) * plotH
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                    path.addLine(to: CGPoint(x: CGFloat(values.count - 1) * stepX, y: plotH))
                    path.closeSubpath()
                }
                .fill(LinearGradient(
                    colors: [VColor.accent.opacity(0.25), VColor.accent.opacity(0.02)],
                    startPoint: .top,
                    endPoint: .bottom
                ))

                // 折线
                Path { path in
                    guard let first = values.first else { return }
                    path.move(to: CGPoint(x: 0, y: plotH - (first / maxV) * plotH))
                    for i in 1..<values.count {
                        let x = CGFloat(i) * stepX
                        let y = plotH - (values[i] / maxV) * plotH
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
                .stroke(VColor.accent, style: StrokeStyle(lineWidth: 2, lineJoin: .round))

                // 数据点
                ForEach(0..<values.count, id: \.self) { i in
                    let x = CGFloat(i) * stepX
                    let y = plotH - (values[i] / maxV) * plotH
                    Circle()
                        .fill(VColor.accent)
                        .frame(width: 6, height: 6)
                        .position(x: x, y: y)
                }
            }
        }
    }
}
