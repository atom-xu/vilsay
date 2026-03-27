//
//  HistoryDetailView.swift
//  vilsay
//

import SwiftUI

/// 历史记录详情：ASR 原文 vs 润色文本对比 + 元数据。
struct HistoryDetailView: View {
    let record: RawLogRecord
    let onToggleFlag: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VSpacing.cardGap) {
                // ASR 原文
                textSection(
                    title: "语音识别原文",
                    icon: "waveform",
                    text: record.asrText,
                    isEmpty: record.asrText.isEmpty
                )

                // 润色结果
                textSection(
                    title: "润色结果",
                    icon: "text.badge.checkmark",
                    text: record.polishedText,
                    isEmpty: record.polishedText.isEmpty
                )

                // 元数据
                metadataSection

                // 操作
                actionsSection
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(VSpacing.pageInset)
        }
        // 不设自己的背景——父视图 HistoryView 已设 VSettingsBackground
        .groupBoxStyle(VCardStyle())
    }

    // MARK: - 文本段落

    private func textSection(title: String, icon: String, text: String, isEmpty: Bool) -> some View {
        GroupBox {
            if isEmpty {
                Text("（空）")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
            } else {
                HStack(alignment: .top) {
                    Text(text)
                        .font(.body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .help("复制到剪贴板")
                }
            }
        } label: {
            Label(title, systemImage: icon)
        }
    }

    // MARK: - 元数据

    private var metadataSection: some View {
        GroupBox {
            VStack(spacing: VSpacing.sm) {
                metaRow("时间", value: formatFullTime(record.createdAt))

                if let ms = record.durationMs {
                    metaRow("时长", value: formatDuration(ms))
                }

                if let provider = record.asrProvider {
                    metaRow("ASR 引擎", value: provider)
                }

                if let conf = record.asrConfidence {
                    metaRow("置信度", value: String(format: "%.1f%%", conf * 100))
                }

                if let appId = record.targetAppId, !appId.isEmpty {
                    metaRow("目标应用", value: appId)
                }

                if let sid = record.sessionId {
                    metaRow("会话 ID", value: sid)
                }
            }
        } label: {
            Label("详细信息", systemImage: "info.circle")
        }
    }

    private func metaRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
            Text(value)
                .font(.callout)
                .textSelection(.enabled)
            Spacer()
        }
    }

    // MARK: - 操作

    private var actionsSection: some View {
        HStack(spacing: VSpacing.sm) {
            Button {
                onToggleFlag()
            } label: {
                Label(
                    record.userFlaggedError ? "取消标记" : "标记有误",
                    systemImage: record.userFlaggedError ? "checkmark.circle" : "exclamationmark.triangle"
                )
                .foregroundStyle(record.userFlaggedError ? VColor.ok : VColor.warn)
            }
            .buttonStyle(VSecondaryButtonStyle())
            .controlSize(.small)
            .frame(maxWidth: 140)

            Spacer()
        }
    }

    // MARK: - 格式化

    private func formatFullTime(_ iso: String) -> String {
        let fmt = ISO8601DateFormatter()
        guard let date = fmt.date(from: iso) else { return iso }
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return df.string(from: date)
    }

    private func formatDuration(_ ms: Int) -> String {
        let s = ms / 1000
        if s < 60 { return "\(s) 秒" }
        return "\(s / 60) 分 \(s % 60) 秒"
    }
}
