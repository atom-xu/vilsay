//
//  DictionaryView.swift
//  W2-07 / W5-03 / W5-07
//

import SwiftUI

struct DictionaryView: View {
    @StateObject private var repo = DictionaryRepository()
    @StateObject private var candidateRepo = CandidateRepository()
    @ObservedObject private var appState = AppState.shared

    @State private var selectedTab = 0
    @State private var showAddSheet = false
    @State private var newTerm = ""
    @State private var newKind = "用语"
    /// 与历史页一致：`searchable(placement: .toolbar)` 参与统一工具栏，避免详情列单独一条「标题+横线」的割裂感。
    @State private var dictionarySearchText = ""

    private var filteredDictionaryEntries: [DictionaryRecord] {
        let q = dictionarySearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return repo.entries }
        return repo.entries.filter { $0.word.localizedCaseInsensitiveContains(q) }
    }

    private var filteredCandidates: [ProfileService.DictionaryCandidate] {
        let q = dictionarySearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return candidateRepo.candidates }
        return candidateRepo.candidates.filter {
            $0.word.localizedCaseInsensitiveContains(q)
                || ($0.context?.localizedCaseInsensitiveContains(q) ?? false)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Tab 切换器（搜索已移至 toolbar，与系统搜索风格一致）
            HStack(spacing: VSpacing.sm) {
                tabButton("我的词典", tag: 0)
                tabButton("智能推荐（\(appState.candidatesCount)）", tag: 1)
                Spacer()
            }
            .padding(.horizontal, VSpacing.pageInset)
            .padding(.vertical, VSpacing.md)

            Group {
                if selectedTab == 0 {
                    myDictionaryTab
                } else {
                    recommendationTab
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(VSettingsBackground())
        // 系统风格搜索框，放在 toolbar 右侧，与 macOS 搜索交互一致
        .searchable(text: $dictionarySearchText, placement: .toolbar, prompt: "搜索词汇…")
        .onAppear {
            repo.load()
            candidateRepo.load()
        }
        .sheet(isPresented: $showAddSheet) {
            addSheet
        }
    }

    // MARK: - Tab 按钮

    private func tabButton(_ title: String, tag: Int) -> some View {
        let selected = selectedTab == tag
        return Button(title) { selectedTab = tag }
            .font(.subheadline.weight(selected ? .semibold : .regular))
            .foregroundStyle(selected ? .white : .secondary)
            .padding(.horizontal, VSpacing.md)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(selected ? VColor.accent : Color.primary.opacity(0.06))
            )
            .buttonStyle(.plain)
            .animation(.easeInOut(duration: 0.15), value: selectedTab)
    }

    // MARK: - 我的词典

    private var myDictionaryTab: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 顶部操作栏
            HStack {
                Text(
                    dictionarySearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? "共 \(repo.entries.count) 个词汇"
                        : "共 \(filteredDictionaryEntries.count) 个词汇"
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    showAddSheet = true
                } label: {
                    Label("添加", systemImage: "plus.circle.fill")
                        .font(.subheadline.weight(.medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(VColor.accent)
            }
            .padding(.horizontal, VSpacing.pageInset)
            .padding(.vertical, VSpacing.sm)

            if repo.entries.isEmpty {
                emptyState(
                    icon: "text.book.closed",
                    message: "还没有词汇\n点击右上角「添加」开始"
                )
            } else if filteredDictionaryEntries.isEmpty {
                emptyState(
                    icon: "magnifyingglass",
                    message: "没有匹配的词汇\n试试其它关键词"
                )
            } else {
                // Tag chip 流式布局
                ScrollView {
                    WordChipGrid(entries: filteredDictionaryEntries) { id in
                        repo.delete(id: id)
                    }
                    .padding(VSpacing.pageInset)
                }
            }
        }
    }

    // MARK: - 智能推荐

    private var recommendationTab: some View {
        Group {
            if candidateRepo.candidates.isEmpty {
                emptyState(
                    icon: "sparkles",
                    message: "继续使用，Vilsay 会自动\n发现你的常用词汇"
                )
            } else if filteredCandidates.isEmpty {
                emptyState(
                    icon: "magnifyingglass",
                    message: "没有匹配的推荐\n试试其它关键词"
                )
            } else {
                List {
                    Section {
                        Text("词典中的词汇会帮助语音润色更准确地识别这些词。请只添加正确的词汇，忽略 ASR 识别错误。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                    ForEach(filteredCandidates) { c in
                        VStack(alignment: .leading, spacing: VSpacing.sm) {
                            HStack {
                                Text(c.word)
                                    .font(.body.weight(.medium))
                                Spacer()
                                Text("\(Int(c.score * 100))%")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(VColor.accent)
                            }
                            if let ctx = c.context, !ctx.isEmpty {
                                Text(ctx)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            ProgressView(value: c.score)
                                .tint(VColor.accent)
                            HStack(spacing: VSpacing.sm) {
                                Button("加入词典") {
                                    candidateRepo.approve(id: c.id)
                                    repo.load()
                                }
                                .buttonStyle(VPrimaryButtonStyle())
                                .controlSize(.small)
                                .frame(maxWidth: 100)
                                Button("忽略") {
                                    candidateRepo.dismiss(id: c.id)
                                }
                                .buttonStyle(VSecondaryButtonStyle())
                                .controlSize(.small)
                                .frame(maxWidth: 80)
                            }
                        }
                        .padding(.vertical, VSpacing.xs)
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 空状态

    private func emptyState(icon: String, message: String) -> some View {
        VStack(spacing: VSpacing.md) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.tertiary)
            Text(message)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 添加词汇 Sheet

    private var addSheet: some View {
        VStack(alignment: .leading, spacing: VSpacing.lg) {
            HStack {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(VColor.accent)
                Text("添加词汇")
                    .font(.title3.weight(.semibold))
            }

            VStack(alignment: .leading, spacing: VSpacing.xs) {
                Text("词条").font(.subheadline.weight(.medium))
                TextField("输入词汇…", text: $newTerm)
                    .textFieldStyle(.roundedBorder)
            }

            HStack(spacing: 0) {
                Text("类型")
                    .font(.subheadline.weight(.medium))
                Spacer()
                HStack(spacing: 8) {
                    ForEach(["用语", "专有名词"], id: \.self) { kind in
                        let selected = newKind == kind
                        Button(kind) { newKind = kind }
                            .font(.subheadline.weight(selected ? .semibold : .regular))
                            .foregroundStyle(selected ? .white : .secondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(selected ? VColor.accent : Color.primary.opacity(0.07)))
                            .buttonStyle(.plain)
                            .animation(.easeInOut(duration: 0.15), value: newKind)
                    }
                }
            }

            HStack(spacing: VSpacing.sm) {
                Button("取消") { showAddSheet = false }
                    .buttonStyle(VSecondaryButtonStyle())
                Button("添加") {
                    let t = newTerm.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !t.isEmpty else { return }
                    repo.add(word: t, context: newKind)
                    newTerm = ""
                    showAddSheet = false
                }
                .buttonStyle(VPrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(newTerm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(VSpacing.xl)
        .background(VSettingsBackground())
        .frame(minWidth: 340, minHeight: 280)
    }
}

// MARK: - 词汇 Chip 流式网格

/// 流式布局词汇标签，每个 chip 按自身内容宽度排列，一行放不下自动换行。
private struct WordChipGrid: View {
    let entries: [DictionaryRecord]
    let onDelete: (Int64) -> Void

    var body: some View {
        FlowLayout(spacing: 8, lineSpacing: 10) {
            ForEach(entries, id: \.word) { item in
                wordChip(item)
            }
        }
    }

    private func wordChip(_ item: DictionaryRecord) -> some View {
        HStack(spacing: 4) {
            // AI 推荐标记
            if item.source == "ai" {
                Image(systemName: "sparkle")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(VColor.accent)
            }

            Text(item.word)
                .font(.subheadline.weight(.medium))
                // 不限行数，词条完整显示

            if let id = item.id {
                Button {
                    onDelete(id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("删除「\(item.word)」")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: VRadius.sm, style: .continuous)
                .fill(Color.primary.opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: VRadius.sm, style: .continuous)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
                )
        )
    }
}
