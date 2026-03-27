//
//  FloatingButtonView.swift
//  Vilsay — 单行长条 bar，品牌暖色调
//

import SwiftUI

struct FloatingButtonView: View {
    @ObservedObject private var state = AppState.shared

    @State private var waveLevels: [CGFloat] = Array(repeating: 0.12, count: 8)
    @State private var dotPulse = false
    /// W6-01：预览条上「有误」→「已记录」后短时关闭 pill。
    @State private var feedbackRecorded = false

    private var isRecordingActive: Bool {
        state.status == .recording || state.status == .editMode
            || (state.triggerMode == .push && state.isPushPressed)
    }
    private var isProcessing: Bool {
        state.status == .processing || state.status == .injecting
    }
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.15)) { timeline in
            let hasText = !state.lastPipelinePolishedText
                .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let previewOn = (state.floatingPreviewDismissAt.map { $0 > timeline.date } ?? false)
                && hasText

            ZStack {
                if let errMsg = state.transientErrorFlash {
                    errorFlashBar(errMsg)
                } else if previewOn { toastBar }
                else if isRecordingActive { recordingBar(editMode: state.status == .editMode) }
                else if isProcessing { thinkingBar }
            }
        }
        .onChange(of: state.floatingAudioLevel) { _, v in
            waveLevels.removeFirst()
            waveLevels.append(max(0.08, min(1.0, CGFloat(v) * 1.3)))
        }
        .onChange(of: state.lastPipelinePolishedText) { _, _ in
            feedbackRecorded = false
        }
    }

    // MARK: - 通用 bar 背景

    private func barBackground(borderColor: Color) -> some View {
        Capsule()
            .fill(LinearGradient(
                colors: [VColor.floatBarStart, VColor.floatBarEnd],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ))
            .overlay(Capsule().stroke(borderColor, lineWidth: VBorder.regular))
            .shadow(color: .black.opacity(0.45), radius: 10, x: 0, y: 0)
    }

    // MARK: - 录音 bar（普通 / 改词）

    private func recordingBar(editMode: Bool) -> some View {
        let accent = editMode ? VColor.brandIndigo : VColor.brandOrange
        let border = editMode ? accent.opacity(0.35) : VColor.brandOrange.opacity(0.25)

        return HStack(spacing: 10) {
            HStack(spacing: 5) {
                Circle()
                    .fill(accent)
                    .frame(width: 5, height: 5)
                    .shadow(color: accent, radius: dotPulse ? 5 : 2)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) {
                            dotPulse = true
                        }
                    }
                if editMode {
                    Text("听指令…")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(accent.opacity(0.9))
                } else {
                    Text("VILSAY")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(VColor.brandOrange.opacity(0.80))
                        .tracking(1.0)
                }
            }

            HStack(alignment: .center, spacing: 2.5) {
                ForEach(0 ..< 8, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(barGradient(index: i, editMode: editMode))
                        .frame(width: 3, height: max(3, waveLevels[i] * 20))
                        .animation(.easeOut(duration: 0.10), value: waveLevels[i])
                }
            }
            .frame(height: 22)

            Button {
                Task { @MainActor in await Pipeline.shared.cancel() }
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.07))
                        .frame(width: 16, height: 16)
                    Image(systemName: "xmark")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(Color(white: 0.45))
                }
            }
            .buttonStyle(.plain)
            .help("取消录音（与 ESC 相同）")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(barBackground(borderColor: border))
        .clipShape(Capsule())
    }

    // MARK: - 错误提示 bar（录音太短 / 未识别到语音）

    private func errorFlashBar(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(VColor.warn.opacity(0.85))
            Text(message)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(VColor.floatText)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(barBackground(borderColor: VColor.warn.opacity(0.25)))
        .clipShape(Capsule())
    }

    // MARK: - 处理中 bar
    // [···  处理中]

    private var thinkingBar: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.85)
            Text("思考中…")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(VColor.floatText)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(barBackground(borderColor: VColor.brandPurple.opacity(0.22)))
        .clipShape(Capsule())
    }

    // MARK: - 完成 toast bar
    // [✓ 润色完成  预览文字…  有误]

    private var toastBar: some View {
        let raw = state.lastPipelinePolishedText
        let maxC = Constants.floatingPillPreviewMaxChars
        let preview = raw.count <= maxC ? raw : String(raw.prefix(maxC)) + "…"
        let polishFailed = !state.lastPolishDidWork
        return HStack(spacing: 8) {
            Image(systemName: polishFailed ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(polishFailed ? VColor.warn.opacity(0.85) : VColor.okVivid.opacity(0.85))

            VStack(alignment: .leading, spacing: 1) {
                Text(preview)
                    .font(.system(size: 11, weight: .light))
                    .foregroundStyle(VColor.floatText)
                    .lineLimit(1)
                    .frame(maxWidth: 160, alignment: .leading)
                if polishFailed, let reason = state.lastPolishFailReason {
                    Text(reason)
                        .font(.system(size: 9))
                        .foregroundStyle(VColor.warn)
                        .lineLimit(1)
                }
            }

            if feedbackRecorded {
                Label("已记录", systemImage: "checkmark.circle")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(VColor.okVivid.opacity(0.9))
            } else {
                Button {
                    ErrorFeedbackService.flagLatestError()
                    withAnimation(.easeInOut(duration: 0.2)) { feedbackRecorded = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        AppState.shared.floatingPreviewDismissAt = Date()
                    }
                } label: {
                    Label("有误", systemImage: "exclamationmark.triangle")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(VColor.warn)
                }
                .buttonStyle(.plain)
                .help("标记最近一条润色结果供改进学习")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(barBackground(borderColor: VColor.okVivid.opacity(0.22)))
        .clipShape(Capsule())
        .onHover { inside in if inside { state.extendFloatingPreviewOnHover() } }
    }

    // MARK: - 波形渐变

    private func barGradient(index: Int, editMode: Bool = false) -> LinearGradient {
        if editMode {
            let t = CGFloat(index) / 7.0
            let color = blend(VColor.brandIndigo, VColor.brandPurple, t: t)
            return LinearGradient(
                colors: [color.opacity(0.92), color.opacity(0.5)],
                startPoint: .top, endPoint: .bottom
            )
        }
        let t = CGFloat(index) / 7.0
        let color = t < 0.5
            ? blend(VColor.brandOrange, VColor.brandPink, t: t * 2)
            : blend(VColor.brandPink, VColor.brandPurple, t: (t - 0.5) * 2)
        return LinearGradient(
            colors: [color.opacity(0.92), color.opacity(0.50)],
            startPoint: .top, endPoint: .bottom
        )
    }

    private func blend(_ a: Color, _ b: Color, t: CGFloat) -> Color {
        let ca = NSColor(a).usingColorSpace(.sRGB) ?? NSColor(a)
        let cb = NSColor(b).usingColorSpace(.sRGB) ?? NSColor(b)
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        ca.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        cb.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return Color(red: r1 + (r2 - r1) * t,
                     green: g1 + (g2 - g1) * t,
                     blue: b1 + (b2 - b1) * t)
    }
}
