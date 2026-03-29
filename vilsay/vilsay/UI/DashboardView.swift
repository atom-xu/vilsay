//
//  DashboardView.swift
//  vilsay
//

import SwiftUI

/// 主窗口仪表盘（对标 Typeless 首页布局）。
struct DashboardView: View {
    @StateObject private var data = DashboardDataProvider()
    @ObservedObject private var auth = AuthService.shared
    @ObservedObject private var state = AppState.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VSpacing.cardGap) {
                // Hero 区域
                heroSection

                // 累计数据卡片网格（5 项）
                cumulativeStatsGrid

                // 反馈入口
                feedbackSection
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(VSpacing.pageInset)
        }
        .background(VSettingsBackground())
        .groupBoxStyle(VCardStyle())
        .task { await data.refresh() }
    }

    // MARK: - Hero

    private var heroSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: VSpacing.md) {
                HStack(spacing: VSpacing.sm) {
                    VilsayMarkCard()
                    VStack(alignment: .leading, spacing: 2) {
                        Text(greetingText)
                            .font(.title2.weight(.bold))
                        Text("按住快捷键开始语音输入，Vilsay 帮你润色。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                // 今日概览行
                HStack(spacing: VSpacing.lg) {
                    todayBadge(label: "今日口述", value: "\(data.todayCount) 次", icon: "mic.fill")
                    todayBadge(label: "今日时长", value: formatDuration(data.todayDurationMs), icon: "timer")
                    if let conf = data.todayAvgConfidence {
                        todayBadge(label: "识别准确率", value: String(format: "%.0f%%", conf * 100), icon: "checkmark.seal.fill")
                    }
                    Spacer()
                }
            }
        } label: {
            EmptyView()
        }
    }

    private func todayBadge(label: String, value: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(VColor.accent.opacity(0.7))
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.callout.weight(.semibold))
            }
        }
    }

    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 12 { return "早上好" }
        if hour < 18 { return "下午好" }
        return "晚上好"
    }

    // MARK: - 累计数据卡片

    private var cumulativeStatsGrid: some View {
        VStack(alignment: .leading, spacing: VSpacing.sm) {
            Text("累计数据")
                .font(.headline.weight(.bold))

            // 上排 3 张
            HStack(spacing: VSpacing.cardGap) {
                cumulativeCard(
                    title: "总口述时间",
                    value: formatDurationLong(data.totalDurationMs),
                    subtitle: "\(data.totalSessions) 次口述",
                    icon: "clock.fill",
                    color: VColor.accent
                )
                cumulativeCard(
                    title: "口述字数",
                    value: formatCount(data.totalWordCount),
                    subtitle: "累计输入",
                    icon: "character.cursor.ibeam",
                    color: VColor.ok
                )
                cumulativeCard(
                    title: "节省时间",
                    value: formatDurationLong(data.timeSavedMs),
                    subtitle: "相比手动打字",
                    icon: "bolt.fill",
                    color: .orange
                )
            }

            // 下排 2 张
            HStack(spacing: VSpacing.cardGap) {
                cumulativeCard(
                    title: "平均口述速度",
                    value: data.avgWordsPerMinute > 0 ? "\(Int(data.avgWordsPerMinute))" : "--",
                    subtitle: "字/分钟",
                    icon: "gauge.with.dots.needle.50percent",
                    color: .purple
                )
                Button {
                    AppState.shared.selectedNavItem = .profile
                } label: {
                    cumulativeCard(
                        title: "个性化",
                        value: data.archetype?.label ?? "\(data.personalizationScore)%",
                        subtitle: data.archetype != nil ? "\(data.archetype!.englishLabel) · 适应度 \(data.personalizationScore)% →" : "AI 润色适应度 →",
                        icon: data.archetype?.icon ?? "brain.head.profile",
                        color: .pink
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func cumulativeCard(title: String, value: String, subtitle: String, icon: String, color: Color) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: VSpacing.sm) {
                HStack {
                    Image(systemName: icon)
                        .font(.system(size: 18))
                        .foregroundStyle(color.opacity(0.8))
                    Spacer()
                }
                Text(value)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        } label: {
            Text(title)
        }
    }


    // MARK: - 反馈

    private var feedbackSection: some View {
        GroupBox {
            HStack(spacing: VSpacing.md) {
                Image(systemName: "hand.thumbsup.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(VColor.accent.opacity(0.7))
                VStack(alignment: .leading, spacing: 2) {
                    Text("帮助我们做得更好")
                        .font(.callout.weight(.medium))
                    Text("如果你在使用中遇到识别不准或润色不满意的情况，可以在历史记录中标记反馈。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("前往历史") {
                    AppState.shared.selectedNavItem = .history
                }
                .buttonStyle(VSecondaryButtonStyle())
                .controlSize(.small)
            }
        } label: {
            EmptyView()
        }
    }

    // MARK: - 格式化

    private func formatDuration(_ ms: Int) -> String {
        let s = ms / 1000
        if s < 60 { return "\(s)s" }
        return "\(s / 60)m \(s % 60)s"
    }

    private func formatDurationLong(_ ms: Int) -> String {
        let totalSeconds = ms / 1000
        if totalSeconds < 60 { return "\(totalSeconds) 秒" }
        let minutes = totalSeconds / 60
        if minutes < 60 { return "\(minutes) 分钟" }
        let hours = minutes / 60
        let remainMin = minutes % 60
        if remainMin == 0 { return "\(hours) 小时" }
        return "\(hours) 小时 \(remainMin) 分"
    }

    private func formatCount(_ count: Int) -> String {
        if count < 1000 { return "\(count)" }
        if count < 10000 { return String(format: "%.1fk", Double(count) / 1000) }
        return String(format: "%.1f 万", Double(count) / 10000)
    }

}
