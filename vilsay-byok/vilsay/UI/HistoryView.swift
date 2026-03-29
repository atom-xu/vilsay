//
//  HistoryView.swift
//  vilsay
//

import SwiftUI
import Combine

/// 历史记录：单列列表 + 点击行内展开详情（accordion）。
/// 搜索和筛选放在 toolbar；行间用间距分隔，不使用 Divider 横线。
struct HistoryView: View {
    @StateObject private var repo = RawLogRepository()

    @State private var searchText = ""
    @State private var dateFilter: HistoryDateFilter = .all
    @State private var flaggedOnly = false
    @State private var expandedId: Int64?
    @State private var pipelineCancellable: AnyCancellable?

    var body: some View {
        Group {
            if repo.records.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(repo.records, id: \.id) { record in
                            rowWithDetail(record)
                        }
                    }
                    .padding(.vertical, VSpacing.sm)
                }
            }
        }
        .background(VSettingsBackground())
        // 搜索放 toolbar
        .searchable(text: $searchText, placement: .toolbar, prompt: "搜索内容…")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Picker("", selection: $dateFilter) {
                    ForEach(HistoryDateFilter.allCases) { f in
                        Text(f.rawValue).tag(f)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
                .frame(width: 70)
            }
            ToolbarItem(placement: .automatic) {
                Toggle(isOn: $flaggedOnly) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                }
                .toggleStyle(.button)
                .controlSize(.small)
                .tint(VColor.warn)
                .help("仅显示已标记有误的记录")
            }
        }
        .onAppear {
            refreshList()
            pipelineCancellable = NotificationCenter.default
                .publisher(for: .init("VilsayPipelineDidComplete"))
                .debounce(for: .seconds(0.3), scheduler: RunLoop.main)
                .sink { _ in refreshList() }
        }
        .onDisappear {
            pipelineCancellable = nil
        }
        .onChange(of: searchText) { _, _ in refreshList() }
        .onChange(of: dateFilter) { _, _ in refreshList() }
        .onChange(of: flaggedOnly) { _, _ in refreshList() }
    }

    // MARK: - 行 + 行内展开

    @ViewBuilder
    private func rowWithDetail(_ record: RawLogRecord) -> some View {
        let isExpanded = expandedId == record.id

        VStack(alignment: .leading, spacing: 0) {
            // 主行
            HStack(alignment: .top, spacing: VSpacing.sm) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(record.polishedText.isEmpty ? record.asrText : record.polishedText)
                        .font(.callout)
                        .lineLimit(isExpanded ? nil : 2)
                        .foregroundStyle(.primary)

                    HStack(spacing: 6) {
                        Text(formatDateTime(record.createdAt))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        if let ms = record.durationMs, ms > 0 {
                            Text("·").foregroundStyle(.quaternary)
                            Text(formatDuration(ms))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        if let provider = record.asrProvider {
                            Text("·").foregroundStyle(.quaternary)
                            Text(provider)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                Spacer()

                HStack(spacing: VSpacing.sm) {
                    if record.userFlaggedError {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(VColor.warn)
                    }
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, VSpacing.pageInset)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    expandedId = isExpanded ? nil : record.id
                }
            }

            // 展开的详情区
            if isExpanded {
                inlineDetail(record)
                    .padding(.horizontal, VSpacing.pageInset)
                    .padding(.bottom, 16)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

        }
    }

    // MARK: - 行内详情

    private func inlineDetail(_ record: RawLogRecord) -> some View {
        VStack(alignment: .leading, spacing: VSpacing.md) {
            // 原文 vs 润色对比（只在不同时显示原文）
            if !record.asrText.isEmpty && record.asrText != record.polishedText {
                VStack(alignment: .leading, spacing: 4) {
                    Text("语音原文")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text(record.asrText)
                        .font(.callout)
                        .foregroundStyle(.primary.opacity(0.75))
                        .textSelection(.enabled)
                }
            }

            if !record.polishedText.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("润色结果")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    HStack(alignment: .top) {
                        Text(record.polishedText)
                            .font(.callout)
                            .textSelection(.enabled)
                        Spacer()
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(record.polishedText, forType: .string)
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("复制润色结果")
                    }
                }
            }

            // Review 结果（后台二次校验）
            if let reviewText = record.reviewText, !reviewText.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Text("Review 结果")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        if let ms = record.reviewMs {
                            Text("(\(ms)ms)")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        if reviewText != record.polishedText {
                            Text("有修正")
                                .font(.caption2)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(VColor.warn.opacity(0.15), in: Capsule())
                                .foregroundStyle(VColor.warn)
                        } else {
                            Text("无变化")
                                .font(.caption2)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.green.opacity(0.15), in: Capsule())
                                .foregroundStyle(.green)
                        }
                    }
                    Text(reviewText)
                        .font(.callout)
                        .foregroundStyle(.primary.opacity(0.75))
                        .textSelection(.enabled)
                }
            }

            // 元数据 + 操作一行
            HStack(spacing: VSpacing.md) {
                if let conf = record.asrConfidence {
                    metaChip(label: "置信度", value: String(format: "%.0f%%", conf * 100))
                }
                if let appId = record.targetAppId, !appId.isEmpty {
                    metaChip(label: "应用", value: shortAppId(appId))
                }
                Spacer()
                Button {
                    if let id = record.id {
                        repo.toggleFlaggedError(id: id)
                        refreshList()
                    }
                } label: {
                    Label(
                        record.userFlaggedError ? "取消标记" : "标记有误",
                        systemImage: record.userFlaggedError ? "checkmark.circle" : "exclamationmark.triangle"
                    )
                    .font(.caption)
                    .foregroundStyle(record.userFlaggedError ? VColor.ok : VColor.warn)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(VSpacing.md)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: VRadius.md, style: .continuous))
    }

    private func metaChip(label: String, value: String) -> some View {
        HStack(spacing: 3) {
            Text(label).foregroundStyle(.tertiary)
            Text(value).foregroundStyle(.secondary)
        }
        .font(.caption2)
    }

    // MARK: - 空状态

    private var emptyState: some View {
        VStack(spacing: VSpacing.md) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            Text(searchText.isEmpty && dateFilter == .all && !flaggedOnly
                 ? "还没有语音记录"
                 : "没有匹配的记录")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 工具

    private func refreshList() {
        repo.fetchFiltered(search: searchText, dateRange: dateFilter, flaggedOnly: flaggedOnly)
    }

    private func formatDateTime(_ iso: String) -> String {
        let fmt = ISO8601DateFormatter()
        guard let date = fmt.date(from: iso) else { return iso }
        let df = DateFormatter()
        df.dateFormat = "MM-dd HH:mm"
        return df.string(from: date)
    }

    private func formatDuration(_ ms: Int) -> String {
        let s = ms / 1000
        if s < 60 { return "\(s)s" }
        return "\(s / 60)m\(s % 60)s"
    }

    private func shortAppId(_ bundleId: String) -> String {
        bundleId.components(separatedBy: ".").last ?? bundleId
    }
}
