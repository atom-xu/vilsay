//
//  ProfileView.swift
//  vilsay — AI3 语言画像可视化：展示用户语言特征，AI3 持续学习更新。
//

import Combine
import SwiftUI
import GRDB

// MARK: - Data Provider

@MainActor
final class ProfileDataProvider: ObservableObject {
    @Published var habitualWords: [HabitualWord] = []
    @Published var thinkingStyle: ThinkingStyle?
    @Published var tone: ToneProfile?
    @Published var dictionaryCount: Int = 0
    @Published var correctionGaps: [CorrectionGap] = []
    @Published var totalAnalyzedCount: Int = 0
    @Published var lastAnalysisDate: String?
    @Published var portrait: String = ""
    @Published var dimensions: StyleDimensions?
    @Published var isLoaded = false

    struct CorrectionGap: Identifiable {
        let id = UUID()
        var asrFragment: String
        var polishedFragment: String
        var expected: String
        var gapType: String
        var confidence: Double
    }

    func refresh() async {
        guard let pool = try? AppDatabase.shared.dbPool else { return }
        do {
            let result = try await pool.read { db -> (
                [HabitualWord], ThinkingStyle?, ToneProfile?, Int, [CorrectionGap], Int, String?, String, StyleDimensions?
            ) in
                var hw: [HabitualWord] = []
                if let row = try UserProfileRecord
                    .filter(Column("key") == "habitual_words" && Column("output_mode") == "__global__")
                    .fetchOne(db),
                   let jsonData = row.value.data(using: .utf8),
                   let arr = try? JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]] {
                    hw = arr.compactMap { item in
                        guard let word = item["word"] as? String else { return nil }
                        return HabitualWord(
                            word: word,
                            action: item["action"] as? String ?? "keep",
                            confidence: item["confidence"] as? Double ?? 0
                        )
                    }
                }

                var ts: ThinkingStyle?
                if let row = try UserProfileRecord
                    .filter(Column("key") == "thinking_style" && Column("output_mode") == "__global__")
                    .fetchOne(db),
                   let jsonData = row.value.data(using: .utf8),
                   let obj = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                    ts = ThinkingStyle(
                        expand: obj["expand"] as? String ?? "",
                        topicSwitchSignals: obj["topic_switch_signals"] as? [String] ?? [],
                        closeSignals: obj["close_signals"] as? [String] ?? [],
                        confidence: row.confidence
                    )
                }

                var toneVal: ToneProfile?
                if let row = try UserProfileRecord
                    .filter(Column("key") == "tone" && Column("output_mode") == "__global__")
                    .fetchOne(db),
                   let jsonData = row.value.data(using: .utf8),
                   let obj = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                    toneVal = ToneProfile(
                        overall: obj["overall"] as? String ?? "",
                        sentenceLength: obj["sentence_length"] as? String ?? "medium",
                        mixedLang: obj["mixed_lang"] as? String ?? "",
                        confidence: row.confidence
                    )
                }

                let dictCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM dictionary") ?? 0

                var gaps: [CorrectionGap] = []
                if let row = try UserProfileRecord
                    .filter(Column("key") == "correction_gaps" && Column("output_mode") == "__global__")
                    .fetchOne(db),
                   let jsonData = row.value.data(using: .utf8),
                   let arr = try? JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]] {
                    gaps = arr.compactMap { item in
                        CorrectionGap(
                            asrFragment: item["asr_fragment"] as? String ?? "",
                            polishedFragment: item["polished_fragment"] as? String ?? "",
                            expected: item["expected"] as? String ?? "",
                            gapType: item["gap_type"] as? String ?? "",
                            confidence: item["confidence"] as? Double ?? 0
                        )
                    }
                }

                // AI3 认知画像
                let portraitValue = try UserProfileRecord
                    .filter(Column("key") == "ai3_portrait" && Column("output_mode") == "__global__")
                    .fetchOne(db)?.value ?? ""

                // 双轴维度
                var dims: StyleDimensions?
                if let row = try UserProfileRecord
                    .filter(Column("key") == "ai3_dimensions" && Column("output_mode") == "__global__")
                    .fetchOne(db),
                   let jsonData = row.value.data(using: .utf8),
                   let obj = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                    dims = StyleDimensions(
                        warmth: obj["warmth"] as? Double ?? 0.5,
                        directness: obj["directness"] as? Double ?? 0.5,
                        confidence: obj["confidence"] as? Double ?? 0,
                        sampleCount: obj["sample_count"] as? Int ?? 0
                    )
                }

                let state = try AnalyzerStateRecord.fetchOne(db)
                let analyzed = state?.totalLoggedCount ?? 0
                let lastRun = state?.lastRunAt

                return (hw, ts, toneVal, dictCount, gaps, analyzed, lastRun, portraitValue, dims)
            }
            habitualWords = result.0
            thinkingStyle = result.1
            tone = result.2
            dictionaryCount = result.3
            correctionGaps = result.4
            totalAnalyzedCount = result.5
            lastAnalysisDate = result.6
            portrait = result.7
            dimensions = result.8
            isLoaded = true
        } catch {
            print("⚠️ ProfileDataProvider refresh error: \(error)")
        }
    }

    var personalizationScore: Int {
        var score = 0
        if !habitualWords.isEmpty { score += 25 }
        if thinkingStyle != nil { score += 25 }
        if tone != nil { score += 25 }
        if dictionaryCount > 0 { score += 15 }
        if !correctionGaps.isEmpty { score += 10 }
        return min(100, score)
    }

    /// 已学习的维度数量。
    var learnedDimensions: Int {
        var n = 0
        if !habitualWords.isEmpty { n += 1 }
        if thinkingStyle != nil { n += 1 }
        if tone != nil { n += 1 }
        if dictionaryCount > 0 { n += 1 }
        return n
    }
}

// MARK: - View

struct ProfileView: View {
    @StateObject private var data = ProfileDataProvider()
    @State private var animateScore = false
    @State private var expandedSection: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VSpacing.cardGap) {
                heroCard
                archetypeCard
                portraitCard
                learningStatusBar
                sectionCard(
                    id: "tone",
                    icon: "waveform",
                    title: "说话风格",
                    color: .purple,
                    filled: data.tone != nil
                ) { toneContent }
                sectionCard(
                    id: "habitual",
                    icon: "text.quote",
                    title: "口头禅",
                    color: .blue,
                    filled: !data.habitualWords.isEmpty,
                    badge: data.habitualWords.isEmpty ? nil : "\(data.habitualWords.count)"
                ) { habitualWordsContent }
                sectionCard(
                    id: "thinking",
                    icon: "point.3.connected.trianglepath.dotted",
                    title: "思维结构",
                    color: .teal,
                    filled: data.thinkingStyle != nil
                ) { thinkingStyleContent }
                sectionCard(
                    id: "gaps",
                    icon: "stethoscope",
                    title: "润色质量追踪",
                    color: .orange,
                    filled: !data.correctionGaps.isEmpty,
                    badge: data.correctionGaps.isEmpty ? nil : "\(data.correctionGaps.count)"
                ) { correctionGapsContent }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(VSpacing.pageInset)
        }
        .background(VSettingsBackground())
        .groupBoxStyle(VCardStyle())
        .task {
            await data.refresh()
            withAnimation(.easeOut(duration: 0.8)) {
                animateScore = true
            }
        }
    }

    // MARK: - Hero Card

    private var heroCard: some View {
        GroupBox {
            HStack(spacing: VSpacing.lg) {
                // 圆环进度
                ZStack {
                    Circle()
                        .stroke(Color.pink.opacity(0.15), lineWidth: 8)
                    Circle()
                        .trim(from: 0, to: animateScore ? Double(data.personalizationScore) / 100.0 : 0)
                        .stroke(Color.pink, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Text("\(animateScore ? data.personalizationScore : 0)")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(.pink)
                            .contentTransition(.numericText())
                        Text("适应度")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 90, height: 90)

                VStack(alignment: .leading, spacing: VSpacing.sm) {
                    Text("AI 正在学习你的表达方式")
                        .font(.title3.weight(.bold))
                    Text(heroSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    // 维度进度点
                    HStack(spacing: 12) {
                        dimensionDot("风格", filled: data.tone != nil, color: .purple)
                        dimensionDot("口头禅", filled: !data.habitualWords.isEmpty, color: .blue)
                        dimensionDot("思维", filled: data.thinkingStyle != nil, color: .teal)
                        dimensionDot("词典", filled: data.dictionaryCount > 0, color: .green)
                    }
                    .padding(.top, 4)
                }
                Spacer()
            }
        } label: {
            EmptyView()
        }
    }

    private var heroSubtitle: String {
        if !data.isLoaded { return "加载中..." }
        let n = data.learnedDimensions
        if n == 0 { return "继续使用 Vilsay，AI 会自动分析你的语言习惯。每 20 次口述触发一轮学习。" }
        if n < 4 { return "已学习 \(n) 个维度。已分析 \(data.totalAnalyzedCount) 次口述，每次使用都在让润色更懂你。" }
        return "4 个维度全部就绪！已从 \(data.totalAnalyzedCount) 次口述中学习，润色已完全适配你的风格。"
    }

    private func dimensionDot(_ label: String, filled: Bool, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(filled ? color : color.opacity(0.2))
                .frame(width: 8, height: 8)
                .overlay(
                    Circle()
                        .stroke(color.opacity(0.4), lineWidth: filled ? 0 : 1)
                )
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(filled ? .primary : .tertiary)
        }
    }

    // MARK: - 语言人格（Social Style Model）

    @ViewBuilder
    private var archetypeCard: some View {
        if let dims = data.dimensions {
            let arch = dims.archetype
            GroupBox {
                VStack(alignment: .leading, spacing: VSpacing.md) {
                    // 人格标签
                    HStack(spacing: VSpacing.md) {
                        // 图标
                        ZStack {
                            Circle()
                                .fill(archetypeColor(arch).opacity(0.12))
                            Image(systemName: arch.icon)
                                .font(.system(size: 22))
                                .foregroundStyle(archetypeColor(arch))
                        }
                        .frame(width: 52, height: 52)

                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(arch.label)
                                    .font(.title2.weight(.bold))
                                Text(arch.englishLabel)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Text(arch.tagline)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                    }

                    // 双轴条形图
                    VStack(spacing: 10) {
                        axisBar(
                            leftLabel: "理性",
                            rightLabel: "感性",
                            value: dims.warmth,
                            color: archetypeColor(arch)
                        )
                        axisBar(
                            leftLabel: "铺垫",
                            rightLabel: "直接",
                            value: dims.directness,
                            color: archetypeColor(arch)
                        )
                    }

                    // 底部信息
                    HStack {
                        Text("基于 \(dims.sampleCount) 次语音分析")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Spacer()
                        Text("置信度 \(Int(dims.confidence * 100))%")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text("Social Style Model · Merrill & Reid")
                            .font(.system(size: 8))
                            .foregroundStyle(.quaternary)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "person.crop.circle.badge.checkmark")
                        .foregroundStyle(archetypeColor(arch))
                    Text("你的语言人格")
                        .font(.subheadline.weight(.semibold))
                }
            }
        } else if data.isLoaded {
            GroupBox {
                HStack(spacing: VSpacing.sm) {
                    ProgressView()
                        .controlSize(.small)
                    Text("AI3 正在学习你的语言人格，需要至少一轮分析...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, VSpacing.xs)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "person.crop.circle.badge.questionmark")
                        .foregroundStyle(.secondary)
                    Text("你的语言人格")
                        .font(.subheadline.weight(.semibold))
                }
            }
        }
    }

    private func axisBar(leftLabel: String, rightLabel: String, value: Double, color: Color) -> some View {
        HStack(spacing: 8) {
            Text(leftLabel)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .trailing)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(color.opacity(0.1))
                    // 指示点
                    Circle()
                        .fill(color)
                        .frame(width: 10, height: 10)
                        .offset(x: max(0, min(geo.size.width - 10, geo.size.width * (animateScore ? value : 0.5) - 5)))
                        .animation(.spring(response: 0.6, dampingFraction: 0.7), value: animateScore)
                }
            }
            .frame(height: 10)
            Text(rightLabel)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .leading)
        }
    }

    private func archetypeColor(_ arch: SpeechArchetype) -> Color {
        switch arch {
        case .executor: return .blue
        case .inspirer: return .orange
        case .analyst:  return .purple
        case .narrator: return .pink
        }
    }

    // MARK: - AI3 认知画像

    private var portraitCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: VSpacing.sm) {
                HStack(spacing: VSpacing.sm) {
                    Image(systemName: "person.text.rectangle")
                        .font(.system(size: 14))
                        .foregroundStyle(.pink)
                    Text("AI3 对你的认知")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    if !data.portrait.isEmpty {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                        Text("每轮分析自动更新")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                if data.portrait.isEmpty {
                    HStack(spacing: VSpacing.sm) {
                        ProgressView()
                            .controlSize(.small)
                        Text("AI3 还在学习中，使用几次后就会形成对你的认知画像...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, VSpacing.sm)
                } else {
                    Text(data.portrait)
                        .font(.callout)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, VSpacing.xs)
                        .textSelection(.enabled)
                }
            }
        } label: {
            EmptyView()
        }
    }

    // MARK: - Learning Status Bar

    private var learningStatusBar: some View {
        HStack(spacing: VSpacing.sm) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.caption)
                .foregroundStyle(VColor.accent)
                .rotationEffect(.degrees(animateScore ? 360 : 0))
                .animation(.linear(duration: 2).repeatCount(1), value: animateScore)

            if let lastDate = data.lastAnalysisDate {
                Text("上次学习：\(formatISO8601(lastDate))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("等待首次分析...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("已分析 \(data.totalAnalyzedCount) 次口述")
                .font(.caption)
                .foregroundStyle(.tertiary)

            // 手动触发按钮
            Button {
                Task {
                    await AI3Analyzer.shared.analyze()
                    await data.refresh()
                    // 重新触发动画
                    animateScore = false
                    withAnimation(.easeOut(duration: 0.8)) {
                        animateScore = true
                    }
                }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10, weight: .semibold))
                    Text("立即学习")
                        .font(.caption.weight(.medium))
                }
                .foregroundStyle(VColor.accent)
            }
            .buttonStyle(.plain)
            .help("手动触发 AI3 分析")
        }
        .padding(.horizontal, VSpacing.sm)
        .padding(.vertical, VSpacing.xs)
        .background(
            RoundedRectangle(cornerRadius: VRadius.sm, style: .continuous)
                .fill(Color.primary.opacity(0.03))
        )
    }

    // MARK: - Expandable Section Card

    private func sectionCard<Content: View>(
        id: String,
        icon: String,
        title: String,
        color: Color,
        filled: Bool,
        badge: String? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        let isExpanded = expandedSection == id
        return GroupBox {
            VStack(alignment: .leading, spacing: 0) {
                // Header — 点击展开/收起
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        expandedSection = isExpanded ? nil : id
                    }
                } label: {
                    HStack(spacing: VSpacing.sm) {
                        Image(systemName: icon)
                            .font(.system(size: 14))
                            .foregroundStyle(color)
                            .frame(width: 20)
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                        if let badge = badge {
                            Text(badge)
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(color.opacity(0.7)))
                        }
                        Spacer()
                        if !filled {
                            Text("学习中")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.secondary.opacity(0.1)))
                        }
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if isExpanded {
                    Divider()
                        .padding(.vertical, VSpacing.sm)
                    content()
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        } label: {
            EmptyView()
        }
    }

    // MARK: - 说话风格

    @ViewBuilder
    private var toneContent: some View {
        if let tone = data.tone {
            VStack(alignment: .leading, spacing: VSpacing.md) {
                // 风格标签
                HStack(spacing: 8) {
                    stylePill(tone.overall, color: .purple)
                    stylePill(sentenceLengthLabel(tone.sentenceLength), color: .indigo)
                    if !tone.mixedLang.isEmpty {
                        stylePill(tone.mixedLang, color: .cyan)
                    }
                }

                confidenceBar(tone.confidence, color: .purple)
            }
        } else {
            emptyHint("继续使用，AI 会分析你的语气、句式和语言切换习惯。")
        }
    }

    private func stylePill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: VRadius.sm, style: .continuous)
                    .fill(color.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: VRadius.sm, style: .continuous)
                            .stroke(color.opacity(0.2), lineWidth: 0.5)
                    )
            )
    }

    // MARK: - 口头禅

    @ViewBuilder
    private var habitualWordsContent: some View {
        if data.habitualWords.isEmpty {
            emptyHint("AI 会自动识别你的口头禅和习惯用语。")
        } else {
            VStack(alignment: .leading, spacing: VSpacing.sm) {
                Text("标记为「保留」的词在润色时不会被删除。AI3 每轮分析后自动更新。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                FlowLayout(spacing: 8, lineSpacing: 8) {
                    ForEach(data.habitualWords, id: \.word) { hw in
                        habitualWordChip(hw)
                    }
                }
            }
        }
    }

    private func habitualWordChip(_ hw: HabitualWord) -> some View {
        let actionColor: Color
        let actionIcon: String
        switch hw.action {
        case "keep":     actionColor = .green;  actionIcon = "checkmark"
        case "simplify": actionColor = .orange; actionIcon = "arrow.right.arrow.left"
        case "remove":   actionColor = .red;    actionIcon = "xmark"
        default:         actionColor = .secondary; actionIcon = "questionmark"
        }
        return HStack(spacing: 5) {
            Text(hw.word)
                .font(.subheadline.weight(.medium))
            Image(systemName: actionIcon)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 14, height: 14)
                .background(Circle().fill(actionColor.opacity(0.7)))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: VRadius.sm, style: .continuous)
                .fill(actionColor.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: VRadius.sm, style: .continuous)
                        .stroke(actionColor.opacity(0.2), lineWidth: 0.5)
                )
        )
    }

    // MARK: - 思维结构

    @ViewBuilder
    private var thinkingStyleContent: some View {
        if let ts = data.thinkingStyle {
            VStack(alignment: .leading, spacing: VSpacing.md) {
                if !ts.expand.isEmpty {
                    insightRow(icon: "text.alignleft", label: "表达展开", value: ts.expand, color: .teal)
                }
                if !ts.topicSwitchSignals.isEmpty {
                    insightRow(icon: "arrow.triangle.branch", label: "话题切换", value: ts.topicSwitchSignals.joined(separator: "、"), color: .teal)
                }
                if !ts.closeSignals.isEmpty {
                    insightRow(icon: "checkmark.circle", label: "收尾信号", value: ts.closeSignals.joined(separator: "、"), color: .teal)
                }
                confidenceBar(ts.confidence, color: .teal)
            }
        } else {
            emptyHint("AI 会分析你的论述方式、话题切换和收尾习惯。")
        }
    }

    private func insightRow(icon: String, label: String, value: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: VSpacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(color)
                .frame(width: 16, alignment: .center)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - 润色质量追踪

    @ViewBuilder
    private var correctionGapsContent: some View {
        if data.correctionGaps.isEmpty {
            emptyHint("暂未发现润色漏洞，这是好事！")
        } else {
            VStack(alignment: .leading, spacing: VSpacing.sm) {
                Text("AI3 发现以下润色遗漏，已自动反馈给润色引擎，下次会更准。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(data.correctionGaps) { gap in
                    HStack(spacing: 8) {
                        gapTypeBadge(gap.gapType)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Text(gap.asrFragment)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .strikethrough()
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 8))
                                    .foregroundStyle(.tertiary)
                                Text(gap.expected)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(VColor.accent)
                            }
                            if !gap.polishedFragment.isEmpty && gap.polishedFragment != gap.asrFragment {
                                Text("润色写了「\(gap.polishedFragment)」")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.orange.opacity(0.04))
                    )
                }
            }
        }
    }

    private func gapTypeBadge(_ type: String) -> some View {
        let label: String
        let color: Color
        switch type {
        case "missed_typo":      label = "漏纠";   color = .orange
        case "missed_pinyin":    label = "同音漏纠"; color = .orange
        case "over_delete":      label = "过删";    color = .red
        case "under_delete":     label = "欠删";    color = .yellow
        case "wrong_correction": label = "错改";    color = .red
        default:                 label = type;      color = .secondary
        }
        return Text(label)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.75)))
    }

    // MARK: - Shared Helpers

    private func confidenceBar(_ confidence: Double, color: Color) -> some View {
        HStack(spacing: 6) {
            Text("学习置信度")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(color.opacity(0.12))
                    Capsule()
                        .fill(color)
                        .frame(width: geo.size.width * (animateScore ? confidence : 0))
                }
            }
            .frame(width: 80, height: 4)
            Text(String(format: "%.0f%%", confidence * 100))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
        }
    }

    private func emptyHint(_ message: String) -> some View {
        HStack(spacing: VSpacing.sm) {
            ProgressView()
                .controlSize(.small)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, VSpacing.xs)
    }

    private func sentenceLengthLabel(_ raw: String) -> String {
        switch raw {
        case "short": return "偏短句"
        case "long": return "偏长句"
        default: return "中等句式"
        }
    }

    private func formatISO8601(_ iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: iso) else { return iso }
        let display = DateFormatter()
        display.dateFormat = "M/d HH:mm"
        return display.string(from: date)
    }
}
